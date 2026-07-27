//
//  LabelaryTests.swift
//  LabelKitTests
//

import Testing
import Foundation
@testable import LabelKit

/// True when api.labelary.com responds to a quick HEAD request. Gates the end-to-end
/// render tests so they skip cleanly in offline/sandboxed environments instead of failing
/// for an unrelated reason (mirrors zpl2pngHelperIsAvailable() in ZPL2PNGRendererTests.swift).
private func labelaryIsReachable() -> Bool {
    guard let url = URL(string: "https://api.labelary.com/") else { return false }
    var request = URLRequest(url: url)
    request.httpMethod = "HEAD"
    request.timeoutInterval = 5
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var reachable = false
    let task = URLSession.shared.dataTask(with: request) { _, response, _ in
        if let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) {
            reachable = true
        }
        semaphore.signal()
    }
    task.resume()
    _ = semaphore.wait(timeout: .now() + 6)
    return reachable
}

/// Reads pixel width/height from a PNG's IHDR chunk (bytes 16-19 and 20-23, big-endian).
private func pngDimensions(_ data: Data) -> (width: Int, height: Int)? {
    guard data.count >= 24 else { return nil }
    let width = data[16..<20].reduce(0) { ($0 << 8) | UInt32($1) }
    let height = data[20..<24].reduce(0) { ($0 << 8) | UInt32($1) }
    return (Int(width), Int(height))
}

@Suite("LabelaryRenderer")
struct LabelaryRendererTests {

    // dpi=100 -> dpmm = round(100/25.4) = 4, which isn't in Labelary's supported set
    // [6, 8, 12, 24]. This throws before any network call, so it's exercisable
    // without a live connection.
    @Test func invalidDPmmThrowsBeforeNetworkCall() async throws {
        let geometry = RenderGeometry(dpi: 100, widthDots: 200, heightDots: 200)
        let options = ImageRenderOptions(geometry: geometry, timeout: 5)
        let renderer = LabelaryRenderer()

        await #expect(throws: LabelaryError.self) {
            _ = try await renderer.render(from: "^XA^XZ", options: options)
        }
    }

    @Test func defaultInitUsesTheSharedSession() {
        #expect(LabelaryRenderer().session === URLSession.shared)
    }
}

/// Stands in for URLSession's network stack so the request-building and response-handling
/// paths can be exercised without touching api.labelary.com.
private final class StubURLProtocol: URLProtocol {

    /// URLProtocol instances are created and run on URLSession's own queues, so the canned
    /// response and the recorded request are guarded by a lock rather than isolated to an actor.
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var response: (status: Int, body: Data) = (200, Data())
        private var recorded: URLRequest?

        func stub(status: Int, body: Data) {
            lock.lock(); defer { lock.unlock() }
            response = (status, body)
            recorded = nil
        }

        func record(_ request: URLRequest) {
            lock.lock(); defer { lock.unlock() }
            recorded = request
        }

        var lastRequest: URLRequest? {
            lock.lock(); defer { lock.unlock() }
            return recorded
        }

        var stubbed: (status: Int, body: Data) {
            lock.lock(); defer { lock.unlock() }
            return response
        }
    }

    static let state = State()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.state.record(request)
        let (status, body) = StubURLProtocol.state.stubbed
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func stubbedSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: configuration)
}

/// 450 x 600 dots @ 300dpi = 1.5in x 2.0in, dpmm = round(300/25.4) = 12.
private let stubGeometry = RenderGeometry(dpi: 300, widthDots: 450, heightDots: 600)

/// Serialized: the tests share StubURLProtocol.state, which holds one canned response.
@Suite("LabelaryRenderer session injection", .serialized)
struct LabelaryRendererSessionTests {

    // A PNG signature plus enough bytes to look like a body; the renderer only checks
    // status and non-emptiness, so the exact pixels don't matter here.
    private let fakePNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01])

    @Test func injectedSessionHandlesTheRequest() async throws {
        StubURLProtocol.state.stub(status: 200, body: fakePNG)
        let renderer = LabelaryRenderer(session: stubbedSession())
        let options = ImageRenderOptions(geometry: stubGeometry, timeout: 10)

        let data = try await renderer.render(from: "^XA^XZ", options: options)

        // URLSession.shared has no stub registered, so getting these exact bytes back
        // proves the injected session - not the shared one - carried the request.
        #expect(data == fakePNG)
        let request = try #require(StubURLProtocol.state.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.labelary.com/v1/printers/12dpmm/labels/1.500x2.000/0/")
    }

    @Test func requestTimeoutComesFromRenderOptions() async throws {
        StubURLProtocol.state.stub(status: 200, body: fakePNG)
        let renderer = LabelaryRenderer(session: stubbedSession())
        let options = ImageRenderOptions(geometry: stubGeometry, timeout: 3.5)

        _ = try await renderer.render(from: "^XA^XZ", options: options)

        let request = try #require(StubURLProtocol.state.lastRequest)
        #expect(request.timeoutInterval == 3.5)
    }

    @Test func nonSuccessStatusThrowsHTTPError() async throws {
        StubURLProtocol.state.stub(status: 500, body: Data("boom".utf8))
        let renderer = LabelaryRenderer(session: stubbedSession())
        let options = ImageRenderOptions(geometry: stubGeometry, timeout: 10)

        do {
            _ = try await renderer.render(from: "^XA^XZ", options: options)
            Issue.record("expected LabelaryError.httpError")
        } catch let error as LabelaryError {
            guard case .httpError(let status, let body) = error else {
                Issue.record("expected .httpError, got \(error)")
                return
            }
            #expect(status == 500)
            #expect(body == "boom")
        }
    }

    @Test func emptyBodyThrowsEmptyData() async throws {
        StubURLProtocol.state.stub(status: 200, body: Data())
        let renderer = LabelaryRenderer(session: stubbedSession())
        let options = ImageRenderOptions(geometry: stubGeometry, timeout: 10)

        do {
            _ = try await renderer.render(from: "^XA^XZ", options: options)
            Issue.record("expected LabelaryError.emptyData")
        } catch let error as LabelaryError {
            guard case .emptyData = error else {
                Issue.record("expected .emptyData, got \(error)")
                return
            }
        }
    }
}

@Suite("LabelaryRenderer end-to-end", .enabled(if: labelaryIsReachable()))
struct LabelaryRendererRenderTests {

    @Test func rendersPNGDataForWholeInchStock() async throws {
        let device = Device.Preset.ZD620
        let stock = Stock.Preset.label2x1
        let geometry = RenderGeometry(
            dpi: device.nativeDPI.rawValue,
            widthDots: stock.widthDots(at: device.nativeDPI),
            heightDots: stock.heightDots(at: device.nativeDPI)
        )
        let options = ImageRenderOptions(geometry: geometry, timeout: 10)

        let renderer = LabelaryRenderer()
        let data = try await renderer.render(from: "^XA^FO20,20^A0N,30,30^FDHi^FS^XZ", options: options)

        #expect(!data.isEmpty)
        // PNG signature: 0x89 'P' 'N' 'G' \r \n \x1A \n
        #expect(data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
    }

    // The dots-vs-inches arithmetic here is correct - the problems in docs/reviews/
    // code-review_src_2026-07-09.md MEDIUM #10 / GitHub #32 were naming (wInches/hInches,
    // since renamed to wDots/hDots) and configuration (ignored timeout, ignored session),
    // not a rounding-order math bug like the one fixed in zpl2png.swift (GitHub #29).
    // Pin that down: render a
    // non-whole-inch, non-square geometry and confirm the resulting PNG's pixel dimensions
    // match the reference values Labelary itself returns for that size (verified manually
    // against the live API: 1.500x2.000in @ 12dpmm -> 456x608px).
    @Test func nonWholeInchDimensionsProduceCorrectlySizedImage() async throws {
        // 450 x 600 dots @ 300dpi = 1.5in x 2.0in. dpmm = round(300/25.4) = 12.
        let geometry = RenderGeometry(dpi: 300, widthDots: 450, heightDots: 600)
        let options = ImageRenderOptions(geometry: geometry, timeout: 10)

        let renderer = LabelaryRenderer()
        let data = try await renderer.render(from: "^XA^FO10,10^A0N,20,20^FDx^FS^XZ", options: options)

        let dimensions = pngDimensions(data)
        #expect(dimensions?.width == 456)
        #expect(dimensions?.height == 608)
    }
}
