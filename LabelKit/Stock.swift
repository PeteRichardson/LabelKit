//
//  Stock.swift
//  LabelKit
//
//  Created by Peter Richardson on 8/31/25.
//

public struct Stock: Hashable {
    public let widthDots: Int
    public let heightDots: Int
    public let isContinuous: Bool
    public let gapDots: Int

    public init(widthInches: Double, heightInches: Double, dpi: DPI, continuous: Bool, gapInches: Double) {
        self.init(widthDots: Int((widthInches * Double(dpi.rawValue)).rounded()),
                  heightDots:  Int((heightInches * Double(dpi.rawValue)).rounded()),
                  continuous: continuous,
                  gapDots: Int((gapInches * Double(dpi.rawValue)).rounded()))
    }
    
    public init(widthDots: Int, heightDots: Int, continuous: Bool, gapDots: Int) {
        self.widthDots = widthDots
        self.heightDots = heightDots
        self.isContinuous = continuous
        self.gapDots = gapDots
    }
}
