//
//  ZPL2PNGRendererTests.swift
//  LabelKitTests
//

import Testing
import Foundation
@testable import LabelKit

/// True when a zpl2png helper binary is discoverable via any of ZPL2PNGRenderer's search
/// paths (bundled resource, `Bundle.main` auxiliary executable, or one of its hardcoded
/// fallback paths). Gates the end-to-end render test so it skips cleanly on machines/CI
/// where no helper is present, rather than failing for an unrelated reason.
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
