//
//  ZPLLabel.swift
//  LabelKit
//
//  Created by Peter Richardson on 8/23/25.
//
import Foundation

// will flesh out printer struct over time.
// e.g. maybe hasCutter, defaultFont, availableFlash, etc
public struct Printer {
    let resolution : Int    // dots per inch
}

public enum StandardPrinter {
    case ZD620_203

    var spec: Printer {
        switch self {
        case .ZD620_203:
            return Printer(resolution: 203)
        }
    }
}
public struct ZPLLabelGeometry {
    // All measurements are stored in Inches
    let widthInches: Double  // = e.g. 2.0
    let heightInches: Double  // = e.g. 1.0
    let gapInches: Double   // = e.g. 0.125 (1/8")
}

public enum StandardLabel {
    case Roll2x1
    
    var geo: ZPLLabelGeometry {
        switch self {
        case .Roll2x1:
            return ZPLLabelGeometry(widthInches: 2, heightInches: 1, gapInches: 0.125)
        }
    }
}

public struct ZPLLabel {
    // all measurements are in dots
    let width: Int  // in dots
    let height: Int // in dots
    let gap: Int    // in dots
    let resolution : Int  // dpi
    
    // convenience initializer for predefined label sizes and printers
    // e.g. label = ZPLLabel(.Roll2x1, .ZD620_203)
    public init(label: StandardLabel, for printer: StandardPrinter) {
        self = .init(geo: label.geo, atDPI: printer.spec.resolution)
    }
    
    init(geo: ZPLLabelGeometry, atDPI resolution: Int) {
        self = .init(widthInches: geo.widthInches, heightInches: geo.heightInches, gapInches: geo.gapInches, atDPI: resolution)
    }
    
    init(widthInches: CGFloat, heightInches: CGFloat, gapInches: CGFloat, atDPI resolution: Int) {
        self.width = Int(round(widthInches * Double(resolution)))
        self.height = Int(round(heightInches * Double(resolution)))
        self.gap = Int(round(gapInches * Double(resolution)))
        self.resolution = resolution
    }
    
    init(widthMM: CGFloat, heightMM: CGFloat, gapMM: CGFloat, atDPI resolution: Int) {
        let mmPerInch: CGFloat = 25.4
        self = .init(widthInches: widthMM / mmPerInch, heightInches: heightMM / mmPerInch, gapInches: gapMM / mmPerInch, atDPI: resolution)
    }
    
    func fontHeightToFitLines(
        labelHeight H: Int,
        padTop: Int,
        padBottom: Int,
        gap: Int,
        lines N: Int
    ) -> Int {
        precondition(N > 0)
        let available = H - padTop - padBottom
        return max(0, (available - (N - 1) * gap) / N)
    }
}

