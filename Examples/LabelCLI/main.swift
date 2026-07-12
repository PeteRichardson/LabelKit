//
//  main.swift
//  LabelCLI
//
//  Created by Peter Richardson on 8/22/25.
//

import Foundation
import LabelKit
import Stencil

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
    let printer = NetworkTarget(device: zd620, host: "192.168.0.133", port: 9100)
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

    let label = try makeLabel()
    
//    try await printToPrinter(label)
    try await printZPL(label)
    try await printPreview(label, using: LabelaryRenderer.self)
    try await printPreview(label, using: ZPL2PNGRenderer.self)

    exit(EXIT_SUCCESS)
}

dispatchMain()
