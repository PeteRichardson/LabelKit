//
//  main.swift
//  LabelKit
//
//  Created by Peter Richardson on 10/5/25.
//

import LabelKit

@main
struct ReminderListCLI {
    static func printToPrinter(_ label: ZPLLabel) async throws {
        let zd620 = label.environment.options.device
        let printer = NetworkTarget(device: zd620, host: "192.168.0.133", port: 9100)
        try await printer.send(Payload.zpl(label.zpl(), dpi: zd620.nativeDPI))
    }
    
    static func printPreview<T: ImageRenderer>(_ label: ZPLLabel, using rendererType: T.Type) async throws {
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
    
    public static func main() async throws {
        let reminders = try await Reminders().getUncompleted()
        
        let fontsize = 50
        let gap = 20
        var i = 0
        let todoitems = reminders
            .map {
                i = i + fontsize + gap
                return "^A0N,\(fontsize),\(fontsize)^FO80,\(i)^FD\($0.title)^FS"
            }
            .joined(separator: "\n")

        let zpl = "^XA\(todoitems)^XZ"

        let zplenv = ZPLEnvironment(stock: Stock.Preset.label4x, device: Device.Preset.ZD620)
        let label: ZPLLabel = ZPLLabel(
            zpl,
            processors: [InjectLength()],
            environment: zplenv
        )
        
        try await printPreview(label, using: ZPL2PNGRenderer.self)
        try await printToPrinter(label)
    }
}

