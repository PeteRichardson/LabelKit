//
//  RenderOptions.swift
//  LabelKit
//
//  Created by Peter Richardson on 9/1/25.
//

public struct RenderOptions: Hashable {
    public let dpi: DPI             // the DPI we will render for this job
    public let stock: Stock         // size in inches/mm, continuous/die-cut, etc.
    public init(dpi: DPI, stock: Stock) {
        self.dpi = dpi
        self.stock = stock
    }

    public init(for device: Device, stock: Stock) {
        self.dpi   = device.nativeDPI
        self.stock = stock
    }
    
    // Frequently used derived values:
    public var printWidthDots: Int { stock.widthDots(at: dpi) }
    public var nominalHeightDots: Int { stock.heightDots(at: dpi) }
    public var gapDots: Int { stock.gapDots(at: dpi) }
}
