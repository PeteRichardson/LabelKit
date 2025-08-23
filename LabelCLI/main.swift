//
//  main.swift
//  LabelCLI
//
//  Created by Peter Richardson on 8/22/25.
//

import Foundation
import LabelKit

let store = try StencilTemplateStore(preferredFolderName: "com.peterichardson.label")
try store.load()

let label = ZPLLabel(label: .Roll2x1, for: .ZD620_203)
print(label)
let zpl = try store.render(name: "label", context: [:])

// Fetch png from Labelary
let pngData = try await fetchLabelImageData(label: label, zpl: zpl)
showImageInITerm2(data: pngData)

// try await Task.sleep(nanoseconds: 200_000_000)  // 0.2ms grace period
                                                   // Needed if main quits before labelary responds


// Send ZPL to Printer
// sendZPL(zpl)

// Send ZPL to stdout
// print(ZPLFormatter.prettyPrint(zpl)

