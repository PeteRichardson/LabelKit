//
//  main.swift
//  LabelCLI
//
//  Created by Peter Richardson on 8/22/25.
//

import Foundation
import LabelKit
import Stencil

///
func loadSomeZPL() throws -> String {
    // Get Templates from Application Support/.../templates.json
    let store = try StencilTemplateStore()
    try store.load()
    return try store.render(name: "label")
}


let zpl = try loadSomeZPL()
let stock = Stock.Preset.label2x1
let zd620 = Device.Preset.ZD620

let zplenv = ZPLEnvironment(stock: stock, device: zd620)
let label: ZPLLabel = ZPLLabel(
    zpl,
    processors: [ResolveTemplates()!,  InjectLength(), PrettyPrint()],
    environment: zplenv
)

let finalZPL = label.zpl()

let printer = NetworkTarget(device: zd620, host: "192.168.0.133", port: 9100)
try printer.send(Payload.zpl(finalZPL, dpi: zd620.nativeDPI))

// Print final zpl text to stdout
let stdout = StdoutTarget(device: zd620)
try stdout.send(Payload.zpl(finalZPL, dpi: zd620.nativeDPI), strict: true)

// Print Labelary and ZPL2PNG preview png's to iTerm2 terminal
let iterm2 = ITerm2Target(device: zd620)
let imageOpts = ImageRenderOptions(geometry: zplenv.options.geometry, timeout: 2.0)
let png = try await LabelaryRenderer().render(from: finalZPL, options: imageOpts)
try iterm2.send(Payload.png(png, dpi: zd620.nativeDPI), strict: true)

// CLI program has no bundle, so path to helper must be specified
let helperURL = URL(fileURLWithPath: "/Users/pete/bin/zpl2png")
let png2 = try await ZPL2PNGRenderer(helperURL: helperURL).render(
    from: finalZPL,
    options: imageOpts
)
try iterm2.send(Payload.png(png2, dpi: zd620.nativeDPI), strict: true)

try await Task.sleep(nanoseconds: 200_000_000)  // 0.2ms grace period in case main quits too soon

