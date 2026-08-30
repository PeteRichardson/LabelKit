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

        print("── Labelary (reference) ──")
        try await label.preview(using: LabelaryRenderer.self, to: target, timeout: 10.0)

        print("── zpl2png (local) ──")
        try await label.preview(using: ZPL2PNGRenderer.self, to: target, timeout: 10.0)

        print("If these differ, the local renderer is missing a ZPL feature.")
    }
}
