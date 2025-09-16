//
//  ZPLProcessor.swift
//  LabelKit
//
//  Created by Peter Richardson on 9/15/25.
//

/// A ZPLProcessor can modify raw zpl before rendering.
/// Labels have a (possibly empty) list of ZPLProcessor instances to apply.
public protocol ZPLProcessor {
    func process(_ input: String, env: ZPLEnvironment) throws -> String
}


public struct ZPLEnvironment {
    public var context: [String: String]        // stencil/vars/etc
    public var options: ZPLOptions              // DPI, width, etc (extend as needed)
    public init(context: [String: String] = [:], options: ZPLOptions = .default) {
        self.context = context
        self.options = options
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

public extension ZPLOptions {
    init(stock: Stock, device: Device) {
        let geometry = RenderGeometry(
            dpi: device.nativeDPI.rawValue,
            widthDots: stock.widthDots(at: device.nativeDPI),
            heightDots: stock.heightDots(at: device.nativeDPI)
        )
        self.init(geometry: geometry, stock: stock, device: device)
    }
    
    static var `default`: ZPLOptions {
        .init(
            stock: Stock.Preset.label2x1,
            device: Device.Preset.ZD620
        )
    }

}
