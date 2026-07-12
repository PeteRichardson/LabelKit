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
    // force-unwrap crash on continuous stock (docs/reviews/PROJECT_REVIEW.md F3,
    // docs/reviews/code-review_src_2026-07-09.md HIGH #1) — that path can't be covered by a
    // test at all today, since a force-unwrap trap kills the whole test process rather than
    // throwing something `#expect(throws:)` can catch. It needs the production code fixed to
    // throw first.
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
}
