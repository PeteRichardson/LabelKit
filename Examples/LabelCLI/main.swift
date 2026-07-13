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
    let printer = NetworkTarget(device: label.environment.options.device, host: "192.168.0.133", port: 9100)
    try await label.print(to: printer)
}

/// Print label zpl text to stdout
func printZPL(_ label: ZPLLabel) async throws {
    let stdout = StdoutTarget(device: label.environment.options.device)
    try await label.print(to: stdout)
}

func printPreview<T: ImageRenderer>(_ label: ZPLLabel, using rendererType: T.Type) async throws {
    let target = ITerm2Target(device: label.environment.options.device)
    try await label.preview(using: rendererType, to: target, timeout: 2.0)
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
