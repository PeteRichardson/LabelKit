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

public func generate_label(reminders: [ReminderSummary]) -> ZPLLabel {
    let fontSize = 50
    let gap = 20
    let lineHeight = fontSize + gap

    let topMargin = 20          // space before first line
    let bottomMargin = 318      // empirically needed for ZD620 + cutter @ 300 dpi

    var y = topMargin

    let todoItems = reminders
        .map { reminder -> String in
            y += lineHeight
            return "^A0N,\(fontSize),\(fontSize)^FO80,\(y)^FD\(reminder.title)^FS"
        }
        .joined(separator: "\n")

    // y now holds the baseline of the last line
    let length = y + bottomMargin   // label length in dots

    let header = "^PW1200^LH0,0^LS0"

    let zpl = "^XA\(header)^LL\(length)\(todoItems)^XZ"

    var zplenv = ZPLEnvironment(stock: Stock.Preset.label4x,
                                device: Device.Preset.ZD620)
    zplenv.options.geometry.heightDots = length

    let label = ZPLLabel(
        zpl,
        processors: [],
        environment: zplenv
    )
    return label
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
        try await label.preview(using: ZPL2PNGRenderer.self, to: target, timeout: 2.0, fallbackHeightDots: 500)
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

    
    
    

