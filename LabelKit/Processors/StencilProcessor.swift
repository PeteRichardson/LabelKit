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


public protocol ImageRenderer: Sendable {
    func render(from zpl: String, options: ImageRenderOptions) async throws -> Data
}


/// A ZPLProcessor can modify raw zpl before rendering.
/// Labels have a (possibly empty) list of ZPLProcessor instances to apply.
protocol ZPLProcessor {
    func process(_ label: Label, options: ZPLOptions) throws -> String
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
    
    public func process(_ label: Label, options: ZPLOptions) throws -> String {
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
        let ll = try computeLabelLengthDots(from: zpl, options: options)
        zpl = injectOrReplace(command: llMarker, value: ll+150, in: zpl)
        
        // 3) Optional validation against device limits
        guard  options.stock.widthDots(at: options.device.nativeDPI) <= options.device.maxWidthDots else {
            throw PrintError.widthOverflow(requested: options.stock.widthDots(at: options.device.nativeDPI), max: options.device.maxWidthDots)
        }
        guard ll <= options.device.maxLengthDots else {
            throw PrintError.lengthOverflow(requested: ll, max: options.device.maxLengthDots)
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

struct PreviewService {
    let processor = StencilZPLProcessor()
    let imageRenderer: ImageRenderer
    func png(for label: Label, zplOptions: ZPLOptions, imageOptions: ImageRenderOptions) async throws -> Data {
        let zpl = try processor?.process(label, options: zplOptions) ?? "^FDNo ZPLProcessor installed, or processing failed!^FS"
        return try await imageRenderer.render(from: zpl, options: imageOptions)
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

public struct ImageRenderOptions: Sendable {
    public var geometry: RenderGeometry
    public var timeout: TimeInterval = 10
    public init(geometry: RenderGeometry, timeout: TimeInterval) {
        self.geometry = geometry
        self.timeout = timeout
    }
}

public struct ZPLOptions: Sendable {
    public var geometry: RenderGeometry
    public var stock: Stock
    public var device: Device
    
    public init(geometry: RenderGeometry, stock: Stock, device: Device) {
        self.geometry = geometry
        self.stock = stock
        self.device = device
    }
}


