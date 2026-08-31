//
//  main.swift
//  LabelKit
//
//  Created by Peter Richardson on 10/5/25.
//

import Foundation
import LabelKit
import ArgumentParser
import OSLog

// Logger for the ReminderList tool
fileprivate let logger = Logger(subsystem: "com.example.reminderlist", category: "printing")

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

/// Lays the reminders out as a single long list label.
///
/// The geometry and the ZPL itself come from ``ListLayout``, so this example
/// inherits its UTF-8 declaration, one-shot `^CF` font and `^FH` escaping
/// rather than hand-rolling a second, weaker copy of them. Reminder titles are
/// arbitrary user text, so the escaping is what keeps a title containing `^XZ`
/// from terminating the label.
public func generate_label(reminders: [ReminderSummary]) -> ZPLLabel {
    // Reminders have no section headings; every row is a plain item.
    // itemIndent 80 keeps the historical left margin for this example.
    let layout = ListLayout(itemIndent: 80)
    let environment = ZPLEnvironment(stock: Stock.Preset.label4x,
                                     device: Device.Preset.ZD620)

    return layout.makeLabel(reminders.map { .item($0.title) }, environment: environment)
}

@main
struct Todo : AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "example-reminderlist",
        abstract: "Print a list of uncompleted reminders",
        subcommands: [List.self, Preview.self, Print.self, Zpl.self],
        defaultSubcommand: List.self // optional: default to `list` if no subcommand given
    )
}

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print list as text on stdout",
    )

    @Flag(name: .shortAndLong, help: "Enable debug logging to Console")
    var debug: Bool = false
    
    func run() async throws {
        if debug {
            logger.info("Fetching uncompleted reminders from Reminders.app")
        }
        let reminders = try await Reminders().getUncompleted().sortedByPriority()
        if debug {
            logger.info("Retrieved \(reminders.count) uncompleted reminder(s)")
        }

        for reminder in reminders {
            print(reminder.title)
        }
    }
}

struct Preview: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print list as a png preview to stdout (requires iterm2 image support)",
    )

    @Flag(name: .shortAndLong, help: "Enable debug logging to Console")
    var debug: Bool = false

    func run() async throws {
        if debug {
            logger.info("Fetching uncompleted reminders from Reminders.app")
        }
        let reminders = try await Reminders().getUncompleted().sortedByPriority()
        if debug {
            logger.info("Retrieved \(reminders.count) uncompleted reminder(s)")
            logger.info("Generating ZPL label preview")
        }
        let label = generate_label(reminders: reminders)
        let target = ITerm2Target(device: label.environment.options.device)
        // Labelary, not the bundled zpl2png helper: list labels are laid out with
        // ^FB, which zpl2png does not implement — it renders only the first line
        // of a block and silently drops the rest. Labelary matches the ZD620.
        try await label.preview(using: LabelaryRenderer.self, to: target, timeout: 2.0, fallbackHeightDots: 500)
        if debug {
            logger.info("Preview command completed successfully")
        }
    }
}


struct Print: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print list to network printer (defaults to \(PrinterDefaults.host):\(PrinterDefaults.port))",
    )

    @OptionGroup var printer: PrinterOptions

    @Flag(name: .shortAndLong, help: "Enable debug logging to Console")
    var debug: Bool = false

    func run() async throws {
        if debug {
            logger.info("Starting print command")
        }
        
        if debug {
            logger.info("Fetching uncompleted reminders from Reminders.app")
        }
        let reminders = try await Reminders().getUncompleted().sortedByPriority()
        if debug {
            logger.info("Retrieved \(reminders.count) uncompleted reminder(s)")
        }
        
        if debug {
            logger.info("Generating ZPL label")
        }
        let label = generate_label(reminders: reminders)
        let zpl = try label.zpl()
        if debug {
            logger.info("Label generated, ZPL length: \(zpl.count) bytes")
        }

        if debug {
            logger.info("Connecting to printer at \(printer.host):\(printer.port)")
        }
        let target = NetworkTarget(device: label.environment.options.device, host: printer.host, port: printer.port)

        if debug {
            logger.info("Sending ZPL payload to printer")
        }
        try await label.print(to: target)

        if debug {
            logger.info("Print command completed successfully")
        }
    }
}

struct Zpl: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print ZPL for reminder list to stdout",
    )

    @Flag(name: .shortAndLong, help: "Enable debug logging to Console")
    var debug: Bool = false
    
    func run() async throws {
        if debug {
            logger.info("Fetching uncompleted reminders from Reminders.app")
        }
        let reminders = try await Reminders().getUncompleted().sortedByPriority()
        if debug {
            logger.info("Retrieved \(reminders.count) uncompleted reminder(s)")
            logger.info("Generating ZPL label")
        }
        let label = generate_label(reminders: reminders)
        let zpl = try label.zpl()
        if debug {
            logger.info("Label generated, ZPL length: \(zpl.count) bytes")
        }

        print(zpl)
    }
}

    
    
    

