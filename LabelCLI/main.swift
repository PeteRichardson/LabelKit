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
let opts  = RenderOptions(for: zd620, stock: stock)

let engine = ZPLEngine()
let svc = PrintService(engine: engine)

// 1) Print to a real printer
try await svc.submit(PrintJob(label: label, options: opts, device: zd620, mode: .zpl,
                        target: NetworkTarget(device: zd620, host: "192.168.0.133", port: 9100)))

// 2) Pretty ZPL to stdout
try await svc.submit(PrintJob(label: label, options: opts, device: zd620, mode: .zpl,
                        target: StdoutTarget(pretty: true, device: zd620)))

// 3) Rendered image to file
try await svc.submit(PrintJob(label: label, options: opts, device: zd620, mode: .image,
                              target: FileTarget(url: URL(fileURLWithPath: "/tmp/label.png"), device: zd620)))

// 4) Rendered image inline in iTerm2
try await svc.submit(PrintJob(label: label, options: opts, device: zd620, mode: .image,
                        target: ITerm2Target(device: zd620)))

try await Task.sleep(nanoseconds: 200_000_000)  // 0.2ms grace period in case main quits too soon

