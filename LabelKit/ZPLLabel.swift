//
//  ZPLLabel.swift
//  LabelKit
//
//  Created by Peter Richardson on 8/23/25.
//
import Foundation
import Network

public protocol Label {
    /// Produce ZPL for this label (templates can render here).
    func zpl() throws -> String
}

public struct ZPLLabel: Label {
    public let zplSource: String
    public func zpl() throws -> String { zplSource }
    
    public init(_ zplSource: String) {
        self.zplSource = zplSource
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
    case Roll4
    
    var geo: ZPLLabelGeometry {
        switch self {
        case .Roll2x1:
            return ZPLLabelGeometry(widthInches: 2, heightInches: 1, gapInches: 0.125)
        case .Roll4:
            return ZPLLabelGeometry(widthInches: 4, heightInches: 0, gapInches: 0)
        }
    }
}

public struct OldZPLLabel {
    // all measurements are in dots
    public let width: Int  // in dots
    public var height: Int // in dots
    public var gap: Int    // in dots
    public var resolution : Int  // dpi
    
    // convenience initializer for predefined label sizes and printers
    // e.g. label = ZPLLabel(.Roll2x1, .ZD620_203)
    public init(label: StandardLabel, for printer: Printer) {
        self = .init(geo: label.geo, atDPI: printer.resolution)
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

