//
//  TargetsTests.swift
//  LabelKitTests
//

import Testing
import Foundation
@preconcurrency import Network
@testable import LabelKit

/// Collects everything a loopback peer receives, plus whether it saw end-of-stream.
private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()
    private var complete = false

    func append(_ data: Data) { lock.lock(); bytes.append(data); lock.unlock() }
    func markComplete() { lock.lock(); complete = true; lock.unlock() }
    var received: Data { lock.lock(); defer { lock.unlock() }; return bytes }
    var sawEndOfStream: Bool { lock.lock(); defer { lock.unlock() }; return complete }
}

private func drain(_ conn: NWConnection, into recorder: Recorder) {
    conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
        if let data, !data.isEmpty { recorder.append(data) }
        if isComplete || error != nil {
            recorder.markComplete()
            conn.cancel()
        } else {
            drain(conn, into: recorder)
        }
    }
}

/// Starts a loopback listener that records one connection's bytes, returning its port.
private func startRecordingListener(_ recorder: Recorder) async throws -> (NWListener, UInt16) {
    let listener = try NWListener(using: .tcp, on: .any)
    listener.newConnectionHandler = { conn in
        conn.start(queue: .global())
        drain(conn, into: recorder)
    }
    let port: UInt16 = try await withCheckedThrowingContinuation { cont in
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                listener.stateUpdateHandler = nil
                cont.resume(returning: listener.port?.rawValue ?? 0)
            case .failed(let error):
                listener.stateUpdateHandler = nil
                cont.resume(throwing: error)
            default:
                break
            }
        }
        listener.start(queue: .global())
    }
    return (listener, port)
}

@Suite("Target strict DPI guard")
struct NetworkTargetDPIGuardTests {
    // NetworkTarget checks `strict && dpi != device.nativeDPI` and throws before ever
    // touching the network, so this is exercisable without a live connection or printer.
    // (docs/reviews/PROJECT_REVIEW.md F11 — this guard was previously untested.)

    let device = Device.Preset.ZD620 // nativeDPI == .dpi300

    @Test func strictZPLSendThrowsOnDPIMismatch() async throws {
        let target = NetworkTarget(device: device, host: "203.0.113.1", port: 9100)
        await #expect(throws: PrintError.self) {
            try await target.send(.zpl("^XA^XZ", dpi: .dpi203), strict: true)
        }
    }

    @Test func strictPNGSendThrowsOnDPIMismatch() async throws {
        let target = NetworkTarget(device: device, host: "203.0.113.1", port: 9100)
        await #expect(throws: PrintError.self) {
            try await target.send(.png(Data(), dpi: .dpi600), strict: true)
        }
    }

    // 203.0.113.1 (RFC 5737 TEST-NET-3) is guaranteed non-routable. Depending on the
    // network this runs on, connecting to it either fails fast (.failed) or parks the
    // connection unresolved (.waiting) until the OS's own connect timeout (75s+) —
    // confirmed to be the latter in this environment via a raw `nc` connect that didn't
    // resolve within several seconds. Before the fix, a task-group/continuation deadlock
    // meant the .waiting case could hang for that OS timeout or indefinitely, regardless
    // of the `timeout:` argument below (docs/reviews/code-review_src_2026-07-09.md HIGH
    // #5, GitHub #31); the assertion is bounded well under 75s to catch that regression
    // while staying tolerant of the fail-fast case on networks where that's what happens.
    @Test func sendRawTimesOutInsteadOfHangingOnUnroutableHost() async throws {
        let target = NetworkTarget(device: device, host: "203.0.113.1", port: 9100)

        let start = Date()
        await #expect(throws: (any Error).self) {
            try await target.sendRaw(Data("^XA^XZ".utf8), timeout: 2)
        }
        let elapsed = Date().timeIntervalSince(start)

        #expect(elapsed < 10)
    }
}

@Suite("NetworkTarget delivery")
struct NetworkTargetDeliveryTests {
    let device = Device.Preset.ZD620

    // `sendRaw` used to run on NWConnection and resume as soon as `.contentProcessed`
    // fired — which means only that the connection took the bytes out of our buffer, not
    // that they reached the wire. Neither that nor the `.cancelled` state following
    // `cancel()` is a delivery signal, so a CLI exited with bytes still queued inside
    // Network.framework and print jobs silently vanished. Loopback hid it completely
    // (data lands inline), which is why this can only be pinned down as a contract:
    // by the time `sendRaw` returns, the peer must have the whole payload *and* have
    // seen the half-close, i.e. the bytes are the kernel's problem now, not ours.
    @Test func sendRawDeliversCompletePayloadAndHalfClosesStream() async throws {
        let recorder = Recorder()
        let (listener, port) = try await startRecordingListener(recorder)
        defer { listener.cancel() }

        let payload = Data("^XA^CI28^PW1200^LL978^FO60,100^FDReminders:^FS^XZ".utf8)
        let target = NetworkTarget(device: device, host: "127.0.0.1", port: port)
        try await target.sendRaw(payload, timeout: 5)

        // The peer's receive callback runs on its own queue, so allow it to observe the
        // FIN we sent; the payload itself is guaranteed delivered once sendRaw returns.
        let deadline = Date().addingTimeInterval(2)
        while !recorder.sawEndOfStream && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(recorder.received == payload)
        #expect(recorder.sawEndOfStream)
    }
}

@Suite("FileTarget")
struct FileTargetTests {
    let device = Device.Preset.ZD620

    @Test func writesZPLPayloadToFile() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("labelkit-test-\(UUID().uuidString).zpl")
        defer { try? FileManager.default.removeItem(at: url) }

        let target = FileTarget(url: url, device: device)
        try await target.send(.zpl("^XA^FDHi^FS^XZ", dpi: device.nativeDPI), strict: true)

        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(written == "^XA^FDHi^FS^XZ")
    }

    @Test func writesPNGPayloadToFile() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("labelkit-test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        let target = FileTarget(url: url, device: device)
        try await target.send(.png(bytes, dpi: device.nativeDPI), strict: true)

        let written = try Data(contentsOf: url)
        #expect(written == bytes)
    }
}

@Suite("StdoutTarget and ITerm2Target")
struct ConsoleTargetTests {
    let device = Device.Preset.ZD620

    @Test func stdoutTargetDoesNotThrowForEitherPayloadKind() async throws {
        let target = StdoutTarget(device: device)
        try await target.send(.zpl("^XA^XZ", dpi: device.nativeDPI), strict: true)
        try await target.send(.png(Data([1, 2, 3]), dpi: device.nativeDPI), strict: true)
    }

    @Test func iterm2TargetIgnoresZPLPayload() async throws {
        // `send` guards on `case .png` and silently returns for `.zpl` — this just
        // asserts that path doesn't throw or hang.
        let target = ITerm2Target(device: device)
        try await target.send(.zpl("^XA^XZ", dpi: device.nativeDPI), strict: true)
    }

    @Test func iterm2TargetAcceptsPNGPayload() async throws {
        let target = ITerm2Target(device: device)
        try await target.send(.png(Data([1, 2, 3]), dpi: device.nativeDPI), strict: true)
    }
}
