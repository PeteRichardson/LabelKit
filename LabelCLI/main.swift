//
//  main.swift
//  LabelCLI
//
//  Created by Peter Richardson on 8/22/25.
//

import Foundation
import LabelKit
import Stencil

// Get Templates from Application Support/.../templates.json
let store = try StencilTemplateStore(preferredFolderName: "com.peterichardson.label")
try store.load()

// Configure printer and label settings
let zd620 = try StandardPrinter.ZD620(.dpi300, host: "192.168.0.133")
var label = ZPLLabel(label: .Roll4, for: zd620)

// Render the given template
let llMarker = "<<LL_MARKER>>"    // set up context that allows dynamic ^LL command
var ctx = ["ll_marker" :  llMarker] as [String: Any]
let zpl = try store.render(name: "label", context: ctx)

// Estimate the dot length of the label from the ZPL (without ^LL)
let zplForEstimation = zpl.replacingOccurrences(of: "llMarker", with: "")
let estimator = ZPLLengthEstimator(zpl: zpl)
let zplLength = estimator.estimateHeightDots()
label.height = zplLength

// Inject estimated label length as an ^LL command.
// Add 150 dots to estmated label length to push top of text past the tear off point
let finalZPL = zpl.replacingOccurrences(of: llMarker, with: "^LL\(label.height+150)")

print("length of label in dots at \(label.resolution) dots: \(label.height)")

// Fetch png from Labelary using finalZPL
let pngData = try await fetchLabelImageData(label: label, zpl: finalZPL)
showImageInITerm2(data: pngData)

//// Send ZPL to Printer
try zd620.print(finalZPL)
try await Task.sleep(nanoseconds: 200_000_000)  // 0.2ms grace period
                                                //  Needed if main quits before labelary responds

// Send ZPL to stdout
print(ZPLFormatter.prettyPrint(finalZPL))

