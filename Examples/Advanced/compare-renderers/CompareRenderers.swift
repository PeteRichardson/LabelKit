//
//  CompareRenderers.swift
//  compare-renderers
//
//  Renders the same ZPL through both previewers to expose disagreements.
//

import Foundation
import LabelKit
import ArgumentParser

@main
struct CompareRenderers: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compare-renderers",
        abstract: "Render ZPL from stdin through Labelary and zpl2png, side by side",
        discussion: """
            The two renderers do not implement identical subsets of ZPL. When a \
            label prints differently than it previews, rendering it both ways \
            shows which renderer is wrong. Labelary is the reference \
            implementation; zpl2png runs locally and offline.
            """
    )

    @Option(name: .long, help: "Label width in inches")
    var width: Double = 4.0

    @Option(name: .long, help: "Label height in inches")
    var height: Double = 6.0

    func run() async throws {
        let zpl = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        guard !zpl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError("No ZPL on stdin. Pipe a label, e.g. `labelprint zpl < list.txt | compare-renderers`.")
        }

        let device = Device.Preset.ZD620
        let stock = Stock(widthInches: width, heightInches: height,
                          isContinuous: false, gapInches: 0)
        let label = ZPLLabel(zpl, environment: ZPLEnvironment(stock: stock, device: device))
        let target = ITerm2Target(device: device)

        // Each renderer gets its own error boundary: one renderer being unreachable
        // (e.g. Labelary with no network) must not stop the other from running —
        // the offline zpl2png path is half of what this tool is for.
        await renderAndShow(label, using: LabelaryRenderer.self, name: "Labelary (reference)", to: target)
        await renderAndShow(label, using: ZPL2PNGRenderer.self, name: "zpl2png (local)", to: target)

        print("If these differ, the local renderer is missing a ZPL feature.")
    }

    /// Renders `label` via `rendererType`, reports its pixel dimensions and byte size
    /// (the actual diagnostic signal when two renderers disagree), and displays it
    /// inline. Failures are reported and swallowed so the caller can move on to the
    /// next renderer.
    private func renderAndShow<R: ImageRenderer>(
        _ label: ZPLLabel,
        using rendererType: R.Type,
        name: String,
        to target: ITerm2Target,
        timeout: TimeInterval = 10.0
    ) async {
        print("── \(name) ──")
        do {
            let data = try await label.renderPreview(using: rendererType, timeout: timeout)
            if let (width, height) = Self.pngDimensions(data) {
                print("\(width)×\(height) px, \(data.count) bytes")
            } else {
                print("\(data.count) bytes (could not parse PNG dimensions)")
            }
            try await target.send(.png(data, dpi: target.device.nativeDPI), strict: true)
        } catch {
            print("Failed: \(error)")
        }
    }

    /// Reads the width/height from a PNG's IHDR chunk (big-endian `UInt32`s at
    /// byte offsets 16 and 20) without pulling in an image framework.
    private static func pngDimensions(_ data: Data) -> (width: Int, height: Int)? {
        let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        guard data.count >= 24, [UInt8](data.prefix(8)) == signature else { return nil }
        let bytes = [UInt8](data)
        func readUInt32(at offset: Int) -> UInt32 {
            (UInt32(bytes[offset]) << 24) | (UInt32(bytes[offset + 1]) << 16)
                | (UInt32(bytes[offset + 2]) << 8) | UInt32(bytes[offset + 3])
        }
        return (Int(readUInt32(at: 16)), Int(readUInt32(at: 20)))
    }
}
