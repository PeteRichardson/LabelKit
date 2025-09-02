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
    let store = try StencilTemplateStore(preferredFolderName: "com.peterichardson.label")
    try store.load()

    // Render the given template
    //let llMarker = "<<LL_MARKER>>"    // set up context that allows dynamic ^LL command
    let llMarker = ""    // set up context that allows dynamic ^LL command
    let ctx = ["ll_marker" :  llMarker] as [String: Any]
    return try store.render(name: "label", context: ctx)
}


let zpl = try loadSomeZPL()

let label: ZPLLabel = ZPLLabel(zpl)
let zd620 = Device ( name:"ZD620", nativeDPI: .dpi300, maxWidthDots: 1200, maxLengthDots: 12000)
let stock = Stock(widthInches: 2.0, heightInches: 1.0, isContinuous: false, gapInches: 0.125)
let geometry = RenderGeometry(
    dpi: zd620.nativeDPI.rawValue,
    widthDots: stock.widthDots(at: zd620.nativeDPI),
    heightDots: stock.heightDots(at: zd620.nativeDPI)
)
let zplopts  = ZPLOptions(geometry: geometry, stock: stock, device: zd620)

let engine = DefaultZPLEngine()

let finalZPL = try engine.render(label, options: zplopts)

let printer = NetworkTarget(device: zd620, host: "192.168.0.133", port: 9100)
try printer.send(Payload.zpl(finalZPL, dpi: zd620.nativeDPI))

let stdout = StdoutTarget(pretty: true, device: zd620)
try stdout.send(Payload.zpl(finalZPL, dpi: zd620.nativeDPI), strict: true)

let iterm2 = ITerm2Target(device: zd620)
let imageOpts = ImageRenderOptions(geometry: geometry, timeout: 2.0)
let png = try await LabelaryImageRenderer().render(from: finalZPL, options: imageOpts)
try iterm2.send(Payload.png(png, dpi: zd620.nativeDPI), strict: true)

let helperURL = URL(fileURLWithPath: "/Users/pete/bin/zpl2png")
let png2 = try await ZPL2PNGRenderer(helperURL: helperURL).render(
    from: finalZPL,
    options: imageOpts
)
try iterm2.send(Payload.png(png2, dpi: zd620.nativeDPI), strict: true)

try await Task.sleep(nanoseconds: 200_000_000)  // 0.2ms grace period in case main quits too soon

