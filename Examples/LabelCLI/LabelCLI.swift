//
//  LabelCLI.swift
//  LabelCLI
//
//  Created by Peter Richardson on 8/22/25.
//

import ArgumentParser
import Foundation
import LabelKit
import Stencil
import OSLog

// Logger for the LabelCLI tool
fileprivate let logger = Logger(subsystem: "com.example.labelcli", category: "label")

/// Printer connection options.
///
/// Resolution order is flag → environment variable → ``PrinterDefaults``, so the
/// example printer stays the default when nothing is supplied.
struct PrinterOptions: ParsableArguments {
    @Option(name: .long, help: "Printer hostname or IP address (env: LABELKIT_PRINTER_HOST)")
    var host: String = ProcessInfo.processInfo.environment["LABELKIT_PRINTER_HOST"] ?? PrinterDefaults.host

    @Option(name: .long, help: "Printer TCP port (env: LABELKIT_PRINTER_PORT)")
    var port: UInt16 = ProcessInfo.processInfo.environment["LABELKIT_PRINTER_PORT"].flatMap(UInt16.init) ?? PrinterDefaults.port
}

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

func printToPrinter(_ label: ZPLLabel, host: String, port: UInt16) async throws {
    let printer = NetworkTarget(device: label.environment.options.device, host: host, port: port)
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

@main
struct LabelCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "example-label",
        abstract: "Render the 'label' template to ZPL and preview it inline in iTerm2"
    )

    @OptionGroup var printer: PrinterOptions

    @Flag(name: [.customShort("p"), .customLong("print")],
          help: "Also send the label to the network printer")
    var sendToPrinter: Bool = false

    @Flag(name: .shortAndLong, help: "Enable debug logging to Console")
    var debug: Bool = false

    // Errors thrown here are surfaced by ArgumentParser on stderr with a non-zero
    // exit status, so they no longer vanish the way a bare top-level Task's did.
    func run() async throws {
        if debug {
            logger.info("Building label")
        }
        let label = try makeLabel()

        if debug {
            logger.info("Sending ZPL to stdout")
        }
        try await printZPL(label)

        if sendToPrinter {
            if debug {
                logger.info("Connecting to printer at \(printer.host):\(printer.port)")
            }
            try await printToPrinter(label, host: printer.host, port: printer.port)
        }

        if debug {
            logger.info("Rendering Labelary preview")
        }
        try await printPreview(label, using: LabelaryRenderer.self)

        if debug {
            logger.info("Rendering zpl2png preview")
        }
        try await printPreview(label, using: ZPL2PNGRenderer.self)

        if debug {
            logger.info("LabelCLI completed successfully")
        }
    }
}
