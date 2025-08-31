//
//  Printer.swift
//  LabelKit
//
//  Created by Peter Richardson on 8/22/25.
//

import Foundation

/// What a device can do (model, dpi, print area limits, etc.)
public struct DeviceCapabilities: Hashable {
    public let model: String
    public let supportedDPIs: Set<DPI>
    public let maxWidthDots: Int
    public let maxLengthDots: Int
    
    public init(model: String, supportedDPIs: Set<DPI>, maxWidthDots: Int, maxLengthDots: Int) {
        self.model = model
        self.supportedDPIs = supportedDPIs
        self.maxWidthDots = maxWidthDots
        self.maxLengthDots = maxLengthDots
    }
}

public protocol Device {
    var name: String { get }
    var dpi: DPI { get }
    var capabilities: DeviceCapabilities { get }
}


public protocol Printer {
    var model: Model { get }
    var resolution: Int { get }   // dots per inch
    func print(_ zpl: String) throws
}

public enum DPI: Int, CaseIterable, Hashable {
    case dpi203 = 203
    case dpi300 = 300
    case dpi600 = 600
}

extension DPI: Comparable {
    public static func < (lhs: DPI, rhs: DPI) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum Model {
    case ZD620
    case ZT411

    var allowedDPIs: Set<DPI> {
        switch self {
        case .ZD620: return [.dpi203, .dpi300]
        case .ZT411: return [.dpi300, .dpi600]
        }
    }
}



// MARK: - StandardPrinter: façade + validation + conveniences

public struct StandardPrinter {
    public let impl: Printer

    /// Primary convenience initializer:
    /// Validates that `dpi` is supported for `model`, then creates a concrete `Printer`.
    public init(_ model: Model, _ dpi: DPI, host: String, port: UInt16 = 9100) throws {
        guard model.allowedDPIs.contains(dpi) else {
            throw PrinterConfigError.invalidResolution(model: model, dpi: dpi.rawValue,
                                                       allowed: Array(model.allowedDPIs).sorted())
        }
        self.impl = NetworkZPLPrinter(model: model, resolution: dpi.rawValue, host: host, port: port)
    }

    /// Forwarding convenience so you can call `printer.print(zpl)`.
    public func print(_ zpl: String) throws {
        try impl.print(zpl)
    }

    // Optional: pre-canned helpers if you like the ultra-short form.
    public static func ZD620(_ dpi: DPI, host: String, port: UInt16 = 9100) throws -> Printer {
        try StandardPrinter(.ZD620, dpi, host: host, port: port).impl
    }

}

public enum PrinterConfigError: Error, CustomStringConvertible {
    case invalidResolution(model: Model, dpi: Int, allowed: [DPI])
    public var description: String {
        switch self {
        case let .invalidResolution(model, dpi, allowed):
            return "DPI \(dpi) is not valid for \(model). Allowed: \(allowed)"
        }
    }
}

