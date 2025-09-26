//
//  Stock.swift
//  LabelKit
//
//  Created by Peter Richardson on 8/31/25.
//

/// Stock represents physical media (i.e. a roll of labels or receipt paper)
/// for example a roll of 2"x1" labels with 1/8" gap between each label,
/// or a roll of 4" wide continuous receipt paper
///
/// Stock is stored in Inches.  Measurement is not done in dots because
/// that depends on the dpi of the renderer (i.e. printer or png algorithm)
public struct Stock : Hashable, Sendable {
    public let widthInches: Double
    public let heightInches: Double?  // continuous stock has no specific height (i.e. nil)
    public let isContinuous: Bool
    public let gapInches: Double
    
    public init(widthInches: Double, heightInches: Double?, isContinuous: Bool, gapInches: Double) {
        self.widthInches = widthInches
        self.heightInches = heightInches
        self.isContinuous = isContinuous
        self.gapInches = gapInches
        
        assert(isContinuous == (heightInches == nil))  // continuous stock must have nil height
    }
}

enum Units {
    static let millimetersPerInch: Double = 25.4
}

extension Stock {
    
    public func widthDots(at dpi: DPI) -> Int {
        Int((widthInches * Double(dpi.rawValue)).rounded())
    }
    public func heightDots(at dpi: DPI) -> Int? {
        heightInches.map { Int(( $0 * Double(dpi.rawValue)).rounded()) }
    }
    public func gapDots(at dpi: DPI) -> Int {
        Int((gapInches * Double(dpi.rawValue)).rounded())
    }
    
    public func widthMM() -> Double {
        widthInches * Units.millimetersPerInch
    }
    public func heightMM() -> Double? {
        heightInches.map { $0 * Units.millimetersPerInch }
    }
    public func gapMM() -> Double {
        gapInches * Units.millimetersPerInch
    }
}


public extension Stock {
    enum Preset {
        public static let label2x1 = Stock(
            widthInches: 2.0,
            heightInches: 1.0,
            isContinuous: false,
            gapInches: 0.125
        )
        
        public static let label4x = Stock(
            widthInches: 4.0,
            heightInches: nil,
            isContinuous: true,
            gapInches: 0.0
        )
    }
}
