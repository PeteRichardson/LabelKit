//
//  Stock.swift
//  LabelKit
//
//  Created by Peter Richardson on 8/31/25.
//

public struct Stock : Hashable, Sendable {
    public let widthInches: Double
    public let heightInches: Double
    public let isContinuous: Bool
    public let gapInches: Double
    
    public init(widthInches: Double, heightInches: Double, isContinuous: Bool, gapInches: Double) {
        self.widthInches = widthInches
        self.heightInches = heightInches
        self.isContinuous = isContinuous
        self.gapInches = gapInches
    }
}

enum Units {
    static let millimetersPerInch: Double = 25.4
}
extension Stock {
    
    public func widthDots(at dpi: DPI) -> Int {
        Int((widthInches * Double(dpi.rawValue)).rounded())
    }
    public func heightDots(at dpi: DPI) -> Int {
        Int((heightInches * Double(dpi.rawValue)).rounded())
    }
    public func gapDots(at dpi: DPI) -> Int {
        Int((gapInches * Double(dpi.rawValue)).rounded())
    }
    
    public func widthMM() -> Double {
        widthInches * Units.millimetersPerInch
    }
    public func heightMM() -> Double {
        heightInches * Units.millimetersPerInch
    }
    public func gapMM() -> Double {
        gapInches * Units.millimetersPerInch
    }
}
