//
//  main.swift
//  LabelCLI
//
//  Created by Peter Richardson on 8/22/25.
//

import Foundation
import LabelKit
import Stencil
import OSLog

private let logger = Logger(subsystem: "com.example.labelcli", category: "label")

func loadSomeZPL() throws -> String {
    // Get Templates from Application Support/.../templates.json
    let store = try StencilTemplateStore()
    try store.load()
    return try store.render(name: "label")
}

enum LabelCLIError: Error {
    case templateStoreUnavailable
}

func makeLabel() throws -> ZPLLabel {
    let zpl = try loadSomeZPL()
    let stock = Stock.Preset.label2x1
    let zd620 = Device.Preset.ZD620

    guard let resolveTemplates = ResolveTemplates() else {
        throw LabelCLIError.templateStoreUnavailable
    }

    let zplenv = ZPLEnvironment(stock: stock, device: zd620)
    let label: ZPLLabel = ZPLLabel(
        zpl,
        processors: [resolveTemplates, InjectLength(), PrettyPrint()],
        environment: zplenv
    )
    return label
}

func printToPrinter(_ label: ZPLLabel) async throws {
    let zd620 = label.environment.options.device
    let printer = NetworkTarget(device: zd620, host: PrinterDefaults.host, port: PrinterDefaults.port)
    try await printer.send(Payload.zpl(try label.zpl(), dpi: zd620.nativeDPI))
}

/// Print label zpl text to stdout
func printZPL(_ label: ZPLLabel) async throws {
    let zd620 = label.environment.options.device
    let stdout = StdoutTarget(device: label.environment.options.device)
    try await stdout.send(Payload.zpl(try label.zpl(), dpi: zd620.nativeDPI), strict: true)
}

func printPreview<T: ImageRenderer>(_ label: ZPLLabel, using rendererType: T.Type) async throws {
    let device = label.environment.options.device
    let target = ITerm2Target(device: device)
    let imageOpts = ImageRenderOptions(geometry: label.environment.options.geometry, timeout: 2.0)
    let renderer = try T()
    let pngData = try await renderer.render(
        from: try label.zpl(),
        options: imageOpts
    )
    try await target.send(Payload.png(pngData, dpi: device.nativeDPI), strict: true)
}

Task {
    do {
        logger.info("Building label")
        let label = try makeLabel()

        logger.info("Sending ZPL to stdout")
//        try await printToPrinter(label)
        try await printZPL(label)

        logger.info("Rendering Labelary preview")
        try await printPreview(label, using: LabelaryRenderer.self)

        logger.info("Rendering zpl2png preview")
        try await printPreview(label, using: ZPL2PNGRenderer.self)

        exit(EXIT_SUCCESS)
    } catch {
        // Previously uncaught: an error thrown here just vanished, since a top-level
        // Task's error isn't surfaced anywhere on its own.
        logger.error("LabelCLI failed: \(error)")
        exit(EXIT_FAILURE)
    }
}

dispatchMain()
