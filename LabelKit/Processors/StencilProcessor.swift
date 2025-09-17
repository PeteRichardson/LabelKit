//
//  StencilProcessor.swift
//  LabelKit
//
//  Created by Peter Richardson on 8/31/25.
//

import Foundation


enum PrintError: Error {
    case dpiMismatch(render: DPI, device: DPI)
    case widthOverflow(requested: Int, max: Int)
    case lengthOverflow(requested: Int, max: Int)
}

/// A ZPLProcessor that resolves Stencil templates in the raw zpl from a StencilTemplateStore
public struct StencilZPLProcessor: ZPLProcessor {
    private var templateStore : StencilTemplateStore? = nil
    
    public init? () {
        do {
            // Get Templates from Application Support/.../templates.json
            templateStore = try StencilTemplateStore()
            try templateStore!.load()
        } catch {
            print ("Error initializing StencilZPLProcessor::templateStore: \(error)")
        }
    }
    public func process(_ input: String, env: ZPLEnvironment) throws -> String {
        var zpl : String = ""
        
        //let llMarker = "<<LL_MARKER>>"    // set up context that allows dynamic ^LL command
        let llMarker = ""    // set up context that allows dynamic ^LL command

        if templateStore != nil {
            // Render the given template
            let ctx = ["ll_marker" :  llMarker] as [String: Any]
            zpl = try templateStore!.render(name: "label", context: ctx)
        }
        
        // Ensure ^XA/^XZ
        if !zpl.contains("^XA") { zpl = "^XA\n" + zpl }
        if !zpl.contains("^XZ") { zpl += "\n^XZ" }
        
        // 1) Set print width from stock@dpi
        //zpl = injectOrReplace(command: "^PW", value: options.printWidthDots, in: zpl)
        
        // 2) Handle length:
        //  - For continuous: compute from content (your height estimator) and set ^LL
        //  - For die-cut: usually set ^LL near nominal height (plus safety margin)
        let opts = env.options
        let device = env.options.device
        let stock = opts.stock
        let ll = try computeLabelLengthDots(from: zpl, options: opts)
        zpl = injectOrReplace(command: llMarker, value: ll+150, in: zpl)
        
        // 3) Optional validation against device limits
        guard  stock.widthDots(at: device.nativeDPI) <= device.maxWidthDots else {
            throw PrintError.widthOverflow(requested: stock.widthDots(at: device.nativeDPI), max: device.maxWidthDots)
        }
        guard ll <= device.maxLengthDots else {
            throw PrintError.lengthOverflow(requested: ll, max: device.maxLengthDots)
        }
        
        return zpl
    }
    private func injectOrReplace(command: String, value: Int, in zpl: String) -> String {
        zpl.replacingOccurrences(of: command, with: "^LL\(value)")
    }
    private func computeLabelLengthDots(from zpl: String, options: ZPLOptions) throws -> Int {
        let zplForEstimation = zpl.replacingOccurrences(of: "llMarker", with: "")
        let estimator = ZPLLengthEstimator(zpl: zplForEstimation)
        return estimator.estimateHeightDots()
    }
}




public struct RenderGeometry: Sendable {
    public var dpi: Int
    public var widthDots: Int?      // optional; renderer may infer from ^PW
    public var heightDots: Int?     // optional; renderer may auto-size
    
    public init(dpi: Int, widthDots: Int? = nil, heightDots: Int? = nil) {
        self.dpi = dpi
        self.widthDots = widthDots
        self.heightDots = heightDots
    }
}


