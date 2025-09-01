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

public struct PrintJob {
    public enum Mode { case zpl, image }
    public let label: ZPLLabel
    public let options: RenderOptions     // carries the render DPI
    public let device: Device             // carries native DPI
    public let target: Target
    public let mode: Mode
    
    public init(label: ZPLLabel, options: RenderOptions, device: Device, mode: Mode, target: Target) {
        self.label = label
        self.options = options
        self.device = device
        self.mode = mode
        self.target = target
    }

}
public struct PrintService {
    let engine: Engine
    public func submit(_ job: PrintJob, strictDPI: Bool = true) async throws {
        switch job.mode {
        case .zpl:
            let zpl = try await engine.renderZPL(label: job.label, options: job.options, device: job.device)
            try job.target.send(.zpl(zpl, dpi: job.options.dpi), strict: strictDPI)
        case .image:
            let png = try await engine.renderImage(label: job.label, options: job.options, device: job.device)
            try job.target.send(.png(png, dpi: job.options.dpi), strict: strictDPI)
        }
    }
    
    public init(engine: Engine) {
        self.engine = engine
    }
}

/// Turns a Label + Stock + Device into ZPL or image
public protocol Engine {
    func renderZPL(label: ZPLLabel, options: RenderOptions, device: Device) async throws -> String
    func renderImage(label: ZPLLabel, options: RenderOptions, device: Device) async throws -> Data
}

public struct ZPLEngine: Engine {

    public func renderZPL(label: ZPLLabel, options: RenderOptions, device: Device) throws -> String {
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
        guard options.dpi == device.nativeDPI else {
            throw PrintError.dpiMismatch( render: options.dpi, device: device.nativeDPI )
        }
        guard options.printWidthDots <= device.maxWidthDots else {
            throw PrintError.widthOverflow(requested: options.printWidthDots, max: device.maxWidthDots)
        }
        guard ll <= device.maxLengthDots else {
            throw PrintError.lengthOverflow(requested: ll, max: device.maxLengthDots)
        }
        
        return zpl
    }
    
    public func renderImage(label: ZPLLabel, options: RenderOptions, device: Device) async throws -> Data {
        let pngData = try await fetchLabelImageData(label: label, stock: options.stock, dpi: options.dpi)
        //showImageInITerm2(data: pngData)
        return pngData
    }
    
    // --- helpers you likely already have ---
    private func injectOrReplace(command: String, value: Int, in zpl: String) -> String {
        zpl.replacingOccurrences(of: command, with: "^LL\(value)")
    }
    private func computeLabelLengthDots(from zpl: String, options: RenderOptions) throws -> Int {
        let zplForEstimation = zpl.replacingOccurrences(of: "llMarker", with: "")
        let estimator = ZPLLengthEstimator(zpl: zplForEstimation)
        return estimator.estimateHeightDots()
    }
    
    public init() {}

}


struct Preview {
    static func zpl(_ label: ZPLLabel, device: Device, stock: Stock) throws -> String {
        try ZPLEngine().renderZPL(label: label,
                                  options: RenderOptions(for: device, stock: stock),
                                  device: device)
    }
    static func image(_ label: ZPLLabel, device: Device, stock: Stock) async throws -> Data {
        try await ZPLEngine().renderImage(label: label,
                                    options: RenderOptions(for: device, stock: stock),
                                    device: device)
    }
}
