//
//  ZPLProcessor.swift
//  LabelKit
//
//  Created by Peter Richardson on 9/15/25.
//

/// A ZPLProcessor can modify raw zpl before rendering.
/// Labels have a (possibly empty) list of ZPLProcessor instances to apply.
protocol ZPLProcessor {
    func process(_ label: Label, options: ZPLOptions) throws -> String
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

