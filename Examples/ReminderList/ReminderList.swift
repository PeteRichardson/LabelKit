//
//  main.swift
//  LabelKit
//
//  Created by Peter Richardson on 10/5/25.
//

import LabelKit
import ArgumentParser
import OSLog

// Logger for the ReminderList tool
fileprivate let logger = Logger(subsystem: "com.example.reminderlist", category: "printing")

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
        abstract: "Print a list of uncompleted reminders",
        subcommands: [List.self, Preview.self, Print.self, Zpl.self],
        defaultSubcommand: List.self // optional: default to `list` if no subcommand given
    )
}

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print list as text on stdout",
    )
    
    func run() async throws {
        for reminder in try await Reminders().getUncompleted() {
            print(reminder.title)
        }
    }
}

struct Preview: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print list as a png preview to stdout (requires iterm2 image support)",
    )
   
    var reminders: [ReminderSummary] = []
    
    func run() async throws {
        let reminders = try await Reminders().getUncompleted()
        let label = generate_label(reminders: reminders)
        let target = ITerm2Target(device: label.environment.options.device)
        try await label.preview(using: ZPL2PNGRenderer.self, to: target, timeout: 2.0, fallbackHeightDots: 500)
    }
}


struct Print: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print list to network printer (at \(PrinterDefaults.host):\(PrinterDefaults.port))",
    )
    
    @Flag(name: .shortAndLong, help: "Enable debug logging to Console")
    var debug: Bool = false
    
    func run() async throws {
        if debug {
            logger.info("Starting print command")
        }
        
        if debug {
            logger.info("Fetching uncompleted reminders from Reminders.app")
        }
        let reminders = try await Reminders().getUncompleted()
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
            logger.info("Connecting to printer at \(PrinterDefaults.host):\(PrinterDefaults.port)")
        }
        let printer = NetworkTarget(device: label.environment.options.device, host: PrinterDefaults.host, port: PrinterDefaults.port)

        if debug {
            logger.info("Sending ZPL payload to printer")
        }
        try await label.print(to: printer)

        if debug {
            logger.info("Print command completed successfully")
        }
    }
}

struct Zpl: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print ZPL for reminder list to stdout",
    )
    
    func run() async throws {
        let reminders = try await Reminders().getUncompleted()
        let label = generate_label(reminders: reminders)
        
        print(try label.zpl())
    }
}

    
    
    


