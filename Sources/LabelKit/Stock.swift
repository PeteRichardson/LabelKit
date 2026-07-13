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


extension RenderGeometry {
    /// Converts a dot measurement at this geometry's dpi to inches.
    public func inches(fromDots dots: Int) -> Double {
        Double(dots) / Double(dpi)
    }

    /// Converts a dot measurement at this geometry's dpi to millimeters, using the same
    /// `Units.millimetersPerInch` constant as `Stock.widthMM()`/`heightMM()`, so every
    /// dots<->mm conversion in the package agrees. `zpl2png.swift` and `Labelary.swift`
    /// each reimplemented this independently, which is exactly why a rounding-order bug
    /// (docs/reviews/code-review_src_2026-07-09.md HIGH #2, GitHub #29) shipped in one but
    /// not the other (docs/reviews/PROJECT_REVIEW.md F6, GitHub #7).
    public func millimeters(fromDots dots: Int) -> Double {
        inches(fromDots: dots) * Units.millimetersPerInch
    }

    /// This geometry's dpi expressed as dots-per-millimeter, rounded — the unit both
    /// zpl2png and the Labelary API expect.
    public var dotsPerMillimeter: Int {
        Int((Double(dpi) / Units.millimetersPerInch).rounded())
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
