//
//  Device.swift
//  LabelKit
//
//  Created by Peter Richardson on 8/22/25.
//

import Foundation

// A physical printer.  The ultimate target for the iterative workflow
// of designing, tweaking and printing a label.
// We preview the design often, and print it at the end.
//
// maxWidthDots and maxLengthDots indicate the physical limits of the
// printer, and may or may not match the physical size of the currently
// install Stock.
// e.g. a ZD620 can print 4", but the current Stock might be a 2"x1" label.
// so Device.maxWidthDots would be 1200 (for a 300 dpi printhead)
public struct Device : Hashable, Sendable {
    public var name: String
    public var nativeDPI: DPI
    public let maxWidthDots: Int
    public let maxLengthDots: Int
    public init(name: String, nativeDPI: DPI, maxWidthDots: Int, maxLengthDots: Int) {
        self.name = name
        self.nativeDPI = nativeDPI
        self.maxWidthDots = maxWidthDots
        self.maxLengthDots = maxLengthDots
    }
}

public enum DPI: Int, CaseIterable, Hashable, Sendable {
    case dpi203 = 203
    case dpi300 = 300
    case dpi600 = 600
    public static func < (lhs: DPI, rhs: DPI) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}


