//
//  main.swift
//  LabelCLI
//
//  Created by Peter Richardson on 8/22/25.
//

import Foundation
import LabelKit

let preferred = "com.peterichardson.label"
let legacy = [Bundle.main.bundleIdentifier, ProcessInfo.processInfo.processName].compactMap { $0 }
let store = try StencilTemplateStore(preferredFolderName: preferred, legacyFolderNames: legacy)
try store.load()

let zpl = try store.render(name: "label", context: [:])
sendZPL(zpl)

//try await Task.sleep(nanoseconds: 200_000_000)  // 0.2ms grace period
print(ZPLFormatter.prettyPrint(zpl))

let pngData = try await fetchLabelImageData(
            dpmm: 8,  // 203 dpi
            widthMM: 50.8,  // 2.0"
            heightMM: 25.4,  // 1.0"
            zpl: zpl
        )
        showImageInITerm2(data: pngData)
