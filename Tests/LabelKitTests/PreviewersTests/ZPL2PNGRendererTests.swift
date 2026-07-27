//
//  ZPL2PNGRendererTests.swift
//  LabelKitTests
//

import Testing
import Foundation
@testable import LabelKit

/// True when a zpl2png helper binary is discoverable via any of ZPL2PNGRenderer's search
/// paths (`$LABELKIT_ZPL2PNG`, `Bundle.main` auxiliary executable, `$PATH`, /usr/local/bin,
/// or the bundled package resource). Gates the end-to-end render test so it skips cleanly on
/// machines/CI where no helper is present, rather than failing for an unrelated reason.
private func zpl2pngHelperIsAvailable() -> Bool {
    (try? ZPL2PNGRenderer()) != nil
}

/// Reads pixel width/height from a PNG's IHDR chunk (bytes 16-19 and 20-23, big-endian).
/// Used to verify runHelper's --width-mm/--height-mm math by checking the actual rendered
/// output size, since the zpl2png binary's output pixel dimensions are width-mm * dpmm.
private func pngDimensions(_ data: Data) -> (width: Int, height: Int)? {
    guard data.count >= 24 else { return nil }
    let width = data[16..<20].reduce(0) { ($0 << 8) | UInt32($1) }
    let height = data[20..<24].reduce(0) { ($0 << 8) | UInt32($1) }
    return (Int(width), Int(height))
}

@Suite("zpl2png free functions")
struct ZPL2PNGHelperLookupTests {

    @Test func lookupInPathFindsAKnownExecutable() {
        // `ls` is present in PATH on every macOS host this package targets.
        let found = lookupInPath(named: "ls")
        #expect(found != nil)
        #expect(found.map { FileManager.default.isExecutableFile(atPath: $0.path) } == true)
    }

    @Test func lookupInPathReturnsNilForUnknownName() {
        let found = lookupInPath(named: "definitely-not-a-real-binary-xyz123")
        #expect(found == nil)
    }

    @Test func lookupInPathSearchesTheSuppliedEnvironment() {
        #expect(lookupInPath(named: "echo", environment: ["PATH": "/bin"])?.path == "/bin/echo")
        #expect(lookupInPath(named: "echo", environment: ["PATH": "/definitely/not/here"]) == nil)
        #expect(lookupInPath(named: "echo", environment: [:]) == nil)
    }

    @Test func bundledZPL2PNGResourceIsPresentAndExecutable() {
        let url = LabelKitResources.zpl2pngURL()
        #expect(url != nil)
        if let url {
            #expect(FileManager.default.isExecutableFile(atPath: url.path))
        }
    }

    @Test func isSandboxedIsFalseUnderSwiftTest() {
        // `swift test` runs as a plain, non-sandboxed process; ZPL2PNGRenderer.init() relies
        // on this to decide whether to require the bundled resource vs. search PATH/fallbacks.
        #expect(isSandboxed() == false)
    }
}

/// Covers where ZPL2PNGRenderer looks for its helper binary. The resolution logic takes the
/// environment and the sandbox flag as parameters precisely so these tests can drive it
/// deterministically instead of mutating the process environment, which would race with the
/// end-to-end suite below (Swift Testing runs suites in parallel).
@Suite("ZPL2PNGRenderer helper resolution")
struct ZPL2PNGHelperResolutionTests {

    /// Creates a regular, non-executable file and returns its URL.
    private func makeNonExecutableFile() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("labelkit-not-executable-\(UUID().uuidString)")
        try Data("not a binary".utf8).write(to: url)
        return url
    }

    @Test func explicitHelperURLIsUsedVerbatim() throws {
        let renderer = try ZPL2PNGRenderer(helperURL: URL(fileURLWithPath: "/bin/echo"))
        #expect(renderer.helperURL.path == "/bin/echo")
    }

    @Test func explicitHelperURLBeatsTheEnvironmentOverride() throws {
        let url = try ZPL2PNGRenderer.resolveHelperURL(
            explicitHelperURL: URL(fileURLWithPath: "/bin/echo"),
            environment: [ZPL2PNGRenderer.helperOverrideEnvironmentVariable: "/bin/ls"],
            sandboxed: false
        )
        #expect(url.path == "/bin/echo")
    }

    @Test func explicitHelperURLThatIsNotExecutableThrows() throws {
        let file = try makeNonExecutableFile()
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(throws: PreviewError.self) {
            _ = try ZPL2PNGRenderer(helperURL: file)
        }
        #expect(throws: PreviewError.self) {
            _ = try ZPL2PNGRenderer(helperURL: URL(fileURLWithPath: "/no/such/zpl2png"))
        }
    }

    @Test func environmentOverrideIsUsedWhenThereIsNoExplicitURL() throws {
        let renderer = try ZPL2PNGRenderer(
            explicitHelperURL: nil,
            environment: [ZPL2PNGRenderer.helperOverrideEnvironmentVariable: "/bin/echo"],
            sandboxed: false
        )
        #expect(renderer.helperURL.path == "/bin/echo")
    }

    @Test func environmentOverrideAlsoAppliesWhenSandboxed() throws {
        // A sandboxed host can only reach what its entitlements allow, but an explicit
        // override is still an explicit instruction and must not be silently discarded.
        let url = try ZPL2PNGRenderer.resolveHelperURL(
            explicitHelperURL: nil,
            environment: [ZPL2PNGRenderer.helperOverrideEnvironmentVariable: "/bin/echo"],
            sandboxed: true
        )
        #expect(url.path == "/bin/echo")
    }

    @Test func environmentOverridePointingAtANonExecutableThrows() throws {
        let file = try makeNonExecutableFile()
        defer { try? FileManager.default.removeItem(at: file) }
        // A typo'd override must be reported, not quietly ignored in favour of some other
        // binary that happens to be installed.
        #expect(throws: PreviewError.self) {
            _ = try ZPL2PNGRenderer.resolveHelperURL(
                explicitHelperURL: nil,
                environment: [ZPL2PNGRenderer.helperOverrideEnvironmentVariable: file.path],
                sandboxed: false
            )
        }
    }

    @Test func emptyEnvironmentOverrideFallsBackToTheSearchPath() throws {
        let url = try ZPL2PNGRenderer.resolveHelperURL(
            explicitHelperURL: nil,
            environment: [ZPL2PNGRenderer.helperOverrideEnvironmentVariable: ""],
            sandboxed: false
        )
        #expect(url.lastPathComponent == "zpl2png")
        #expect(FileManager.default.isExecutableFile(atPath: url.path))
    }

    @Test func environmentOverrideVariableIsTheDocumentedName() {
        #expect(ZPL2PNGRenderer.helperOverrideEnvironmentVariable == "LABELKIT_ZPL2PNG")
    }

    @Test func searchPathIsHonoured() throws {
        // A zpl2png on $PATH is found even when it lives nowhere else on the search list.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("labelkit-path-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = dir.appendingPathComponent("zpl2png")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/echo"), to: fake)

        let url = try ZPL2PNGRenderer.resolveHelperURL(
            explicitHelperURL: nil,
            environment: ["PATH": dir.path],
            sandboxed: false
        )
        #expect(url.path == fake.path)
    }

    // Regression test for the hardcoded personal path that used to sit in the fallback list
    // (`/Users/pete/bin/zpl2png` — docs/reviews/PROJECT_REVIEW.md F12, GitHub #12). With no
    // override and nothing on $PATH, resolution must fall through to machine-independent
    // locations only.
    @Test func searchNeverFallsBackToAPersonalHomeDirectoryPath() throws {
        let url = try ZPL2PNGRenderer.resolveHelperURL(
            explicitHelperURL: nil,
            environment: ["PATH": "/definitely/not/here"],
            sandboxed: false
        )
        #expect(url.path != "/Users/pete/bin/zpl2png")
        #expect(!url.path.hasPrefix(NSHomeDirectory() + "/bin/"))
        #expect(FileManager.default.isExecutableFile(atPath: url.path))
    }

    @Test func sandboxedResolutionIgnoresSystemLocations() throws {
        // A sandboxed process can't execute anything outside its container, so a zpl2png on
        // $PATH must not be selected; the in-bundle copy is used instead.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("labelkit-sandbox-path-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = dir.appendingPathComponent("zpl2png")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/echo"), to: fake)

        let url = try ZPL2PNGRenderer.resolveHelperURL(
            explicitHelperURL: nil,
            environment: ["PATH": dir.path],
            sandboxed: true
        )
        #expect(url.path != fake.path)
        #expect(url == LabelKitResources.zpl2pngURL())
    }
}

@Suite("ZPL2PNGRenderer end-to-end", .enabled(if: zpl2pngHelperIsAvailable()))
struct ZPL2PNGRendererRenderTests {

    // Whole-inch, non-continuous stock (Stock.Preset.label2x1) always has a non-nil
    // heightDots, so this exercises `runHelper`'s width/height math without touching the
    // missing-geometry path covered by continuousStockThrowsInsteadOfCrashing below.
    @Test func rendersPNGDataForWholeInchStock() async throws {
        let device = Device.Preset.ZD620
        let stock = Stock.Preset.label2x1
        let geometry = RenderGeometry(
            dpi: device.nativeDPI.rawValue,
            widthDots: stock.widthDots(at: device.nativeDPI),
            heightDots: stock.heightDots(at: device.nativeDPI)
        )
        let options = ImageRenderOptions(geometry: geometry, timeout: 10)

        let renderer = try ZPL2PNGRenderer()
        let data = try await renderer.render(from: "^XA^FO20,20^A0N,30,30^FDHi^FS^XZ", options: options)

        #expect(!data.isEmpty)
        // PNG signature: 0x89 'P' 'N' 'G' \r \n \x1A \n
        #expect(data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
    }

    // Continuous stock (Stock.Preset.label4x, e.g. used by example-reminderlist) has a nil
    // heightDots by design (Stock.heightInches). This used to force-unwrap and crash the whole
    // process (docs/reviews/PROJECT_REVIEW.md F3, docs/reviews/code-review_src_2026-07-09.md
    // HIGH #1); it must now throw a catchable error instead.
    @Test func continuousStockThrowsInsteadOfCrashing() async throws {
        let device = Device.Preset.ZD620
        let stock = Stock.Preset.label4x
        let geometry = RenderGeometry(
            dpi: device.nativeDPI.rawValue,
            widthDots: stock.widthDots(at: device.nativeDPI),
            heightDots: stock.heightDots(at: device.nativeDPI)
        )
        let options = ImageRenderOptions(geometry: geometry, timeout: 10)

        let renderer = try ZPL2PNGRenderer()
        await #expect(throws: PreviewError.self) {
            _ = try await renderer.render(from: "^XA^FO20,20^A0N,30,30^FDHi^FS^XZ", options: options)
        }
    }

    // Regression test for the pipe deadlock: a tiled grid of barcodes renders a PNG well
    // over the ~64KB OS pipe buffer. Reading stdout only after the process exits used to
    // hang here indefinitely (the helper blocks in write() with nobody draining stdout),
    // relying on the timeout+terminate to eventually recover
    // (docs/reviews/code-review_src_2026-07-09.md HIGH #3, GitHub #30). This must complete
    // well within the timeout, not merely survive it.
    @Test func largeOutputDoesNotDeadlock() async throws {
        let device = Device.Preset.ZD620
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var zpl = "^XA\n"
        for row in 0..<90 {
            let y = row * 300
            for col in 0..<9 {
                let x = col * 700
                let code = String((0..<20).map { _ in chars.randomElement()! })
                zpl += "^FO\(x),\(y)^BY2^BCN,80,Y,N,N^FD\(code)^FS\n"
            }
        }
        zpl += "^XZ"

        let geometry = RenderGeometry(dpi: device.nativeDPI.rawValue, widthDots: 3600, heightDots: 8400)
        let options = ImageRenderOptions(geometry: geometry, timeout: 30)

        let renderer = try ZPL2PNGRenderer()
        let start = Date()
        let data = try await renderer.render(from: zpl, options: options)
        let elapsed = Date().timeIntervalSince(start)

        #expect(data.count > 65536)
        #expect(data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
        // A deadlocked render would consume the full 30s timeout; a healthy one finishes
        // in well under a second on this input size.
        #expect(elapsed < 10)
    }

    // `render` hands its blocking Process work to a dedicated concurrent DispatchQueue rather
    // than running it on Swift's cooperative thread pool, where enough simultaneous renders
    // would occupy every pool thread and starve unrelated tasks
    // (docs/reviews/code-review_src_2026-07-09.md CR-9, GitHub #33). More concurrent renders
    // than the pool has threads must all still finish.
    @Test func concurrentRendersAllComplete() async throws {
        let geometry = RenderGeometry(dpi: 300, widthDots: 600, heightDots: 300)
        let options = ImageRenderOptions(geometry: geometry, timeout: 20)
        let renderer = try ZPL2PNGRenderer()

        try await withThrowingTaskGroup(of: Data.self) { group in
            for i in 0..<32 {
                group.addTask {
                    try await renderer.render(
                        from: "^XA^FO20,20^A0N,30,30^FD\(i)^FS^XZ",
                        options: options
                    )
                }
            }
            var count = 0
            for try await data in group {
                #expect(data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
                count += 1
            }
            #expect(count == 32)
        }
    }

    // Regression test for the mm-rounding bug: runHelper used to round dots -> inches to a
    // whole number *before* converting to mm (`round(dots / dpi) * 25.4`), so a non-whole-inch
    // dimension like 1.5in became 2in's worth of mm. 450 dots @ 300 dpi = 1.5in; the correct
    // width is round(1.5in * 25.4) = 38mm, but the old formula produced round(1.5) * 25.4 =
    // 50mm. At the zpl2png helper's dpmm of 12, that's a real, checkable difference in the
    // rendered PNG's pixel width: 456px (correct) vs. 600px (buggy)
    // (docs/reviews/code-review_src_2026-07-09.md HIGH #2, GitHub #29).
    @Test func nonWholeInchDimensionsProduceCorrectPixelSize() async throws {
        let geometry = RenderGeometry(dpi: 300, widthDots: 450, heightDots: 450)
        let options = ImageRenderOptions(geometry: geometry, timeout: 10)

        let renderer = try ZPL2PNGRenderer()
        let data = try await renderer.render(from: "^XA^FO10,10^A0N,20,20^FDx^FS^XZ", options: options)

        let dimensions = pngDimensions(data)
        #expect(dimensions?.width == 456)
        #expect(dimensions?.height == 456)
    }
}
