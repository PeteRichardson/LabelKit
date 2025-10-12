//
//  main.swift
//  LabelKit
//
//  Created by Peter Richardson on 10/5/25.
//

import LabelKit
import ArgumentParser

public func generate_label(reminders: [ReminderSummary]) -> ZPLLabel {
    let fontsize = 50
    let gap = 20
    var i = 0
    let todoitems = reminders
        .map {
            i = i + fontsize + gap
            return "^A0N,\(fontsize),\(fontsize)^FO80,\(i)^FD\($0.title)^FS"
        }
        .joined(separator: "\n")
    
    let length = reminders.count * (fontsize + gap) + 100
    
    let zpl = "^XA^LL\(length)\(todoitems)^XZ"
    
    var zplenv = ZPLEnvironment(stock: Stock.Preset.label4x, device: Device.Preset.ZD620)
    zplenv.options.geometry.heightDots = length
    let label: ZPLLabel = ZPLLabel(
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
        subcommands: [List.self, Preview.self, Print.self],
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


    
    
    


