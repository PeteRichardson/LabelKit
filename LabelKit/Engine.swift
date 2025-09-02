//
//  Engine.swift
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

protocol ZPLEngine {
    func render(_ label: Label, options: ZPLOptions) throws -> String
}

public struct DefaultZPLEngine: ZPLEngine {
    public func render(_ label: Label, options: ZPLOptions) throws -> String {
        var zpl = try label.zpl()
        
        // Ensure ^XA/^XZ
        if !zpl.contains("^XA") { zpl = "^XA\n" + zpl }
        if !zpl.contains("^XZ") { zpl += "\n^XZ" }
        
        // 1) Set print width from stock@dpi
        //zpl = injectOrReplace(command: "^PW", value: options.printWidthDots, in: zpl)
        
        // 2) Handle length:
        //  - For continuous: compute from content (your height estimator) and set ^LL
        //  - For die-cut: usually set ^LL near nominal height (plus safety margin)
        let llMarker = "<<LL_MARKER>>"
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
    
    // --- helpers you likely already have ---
    private func injectOrReplace(command: String, value: Int, in zpl: String) -> String {
        zpl.replacingOccurrences(of: command, with: "^LL\(value)")
    }
    private func computeLabelLengthDots(from zpl: String, options: ZPLOptions) throws -> Int {
        let zplForEstimation = zpl.replacingOccurrences(of: "llMarker", with: "")
        let estimator = ZPLLengthEstimator(zpl: zplForEstimation)
        return estimator.estimateHeightDots()
    }
    
    public init () {}
}

struct PreviewService {
    let zplEngine = DefaultZPLEngine()
    let imageRenderer: ImageRenderer
    func png(for label: Label, zplOptions: ZPLOptions, imageOptions: ImageRenderOptions) async throws -> Data {
        let zpl = try zplEngine.render(label, options: zplOptions)
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


