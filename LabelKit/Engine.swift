//
//  Engine.swift
//  LabelKit
//
//  Created by Peter Richardson on 8/31/25.
//

import Foundation

public struct PrintJob {
    public enum Mode { case zpl, image } // add .pdf later if you like
    public let label: Label
    public let stock: Stock
    public let device: Device
    public let mode: Mode
    public let target: Target
    
    public init(label: Label, stock: Stock, device: Device, mode: Mode, target: Target) {
        self.label = label
        self.stock = stock
        self.device = device
        self.mode = mode
        self.target = target
    }
}


public struct PrintService {
    let engine: Engine
    public func submit(_ job: PrintJob) throws {
        switch job.mode {
        case .zpl:
            let zpl = try engine.renderZPL(label: job.label, stock: job.stock, device: job.device)
            try job.target.send(.zpl(zpl))
        case .image:
            let img = try engine.renderImage(label: job.label, stock: job.stock, device: job.device)
            try job.target.send(.png(img))
        }
    }
    
    public init(engine: Engine) {
        self.engine = engine
    }
}

/// Turns a Label + Stock + Device into ZPL or image
public protocol Engine {
    func renderZPL(label: Label, stock: Stock, device: Device) throws -> String
    func renderImage(label: Label, stock: Stock, device: Device) throws -> Data
}

public struct ZPLEngine: Engine {
    public func renderZPL(label: Label, stock: Stock, device: Device) throws -> String {
        let zpl = try label.zpl()
        // Inject ^XA/^XZ if missing, normalize ^PW based on stock width & device dpi, compute ^LL for continuous, etc.
        // (you already have helpers for these)
        return zpl
    }
    public func renderImage(label: Label, stock: Stock, device: Device) throws -> Data {
        let _ = try renderZPL(label: label, stock: stock, device: device)
        // Call your zpl->png path (zpl2png or printer-sim)
        // return try ZPLToPNG.render(zpl: zpl, dpi: device.dpi)
        return Data()
    }
    
    public init() {}
}
