//
//  main.swift
//  LabelKit
//
//  Created by Peter Richardson on 10/5/25.
//

import LabelKit
import ArgumentParser

public func generate_label(reminders: [ReminderSummary]) -> ZPLLabel {
    let fontSize = 50
    let gap = 20
    let lineHeight = fontSize + gap

    let topMargin = 20          // space before first line
    let bottomMargin = 350      // empirically needed for ZD620 + cutter @ 300 dpi

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
    
    func printPreview<T: ImageRenderer>(_ label: ZPLLabel, using rendererType: T.Type) async throws {
        let device = label.environment.options.device
        let target = ITerm2Target(device: device)
        var imageOpts = ImageRenderOptions(geometry: label.environment.options.geometry, timeout: 2.0)
        if imageOpts.geometry.heightDots == nil {
            imageOpts.geometry.heightDots = 500
        }
        let renderer = try T()
        
        let pngData = try await renderer.render(
            from: label.zpl(),
            options: imageOpts
        )
        try await target.send(Payload.png(pngData, dpi: device.nativeDPI), strict: true)
    }
    
    func run() async throws {
        let reminders = try await Reminders().getUncompleted()
        let label = generate_label(reminders: reminders)
        try await printPreview(label, using: ZPL2PNGRenderer.self)
    }
}


struct Print: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print list to network printer (at 192.168.0.133:9100)",
    )
    
    func run() async throws {
        let reminders = try await Reminders().getUncompleted()
        let label = generate_label(reminders: reminders)
        let zd620 = label.environment.options.device
        
        let printer = NetworkTarget(device: zd620, host: "192.168.0.133", port: 9100)
        try await printer.send(Payload.zpl(label.zpl(), dpi: zd620.nativeDPI))
    }
}

struct Zpl: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print ZPL for reminder list to stdout",
    )
    
    func run() async throws {
        let reminders = try await Reminders().getUncompleted()
        let label = generate_label(reminders: reminders)
        
        print(label.zpl())
    }
}

    
    
    


