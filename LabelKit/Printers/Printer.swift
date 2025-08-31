//
//  Printer.swift
//  LabelKit
//
//  Created by Peter Richardson on 8/22/25.
//

import Network
import Foundation

// MARK: - Core protocol

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

// MARK: - A concrete printer implementation (example: raw TCP 9100)

public struct NetworkZPLPrinter: Printer {
    public let model: Model
    public let resolution: Int
    public let host: String
    public let port: UInt16

    public init(model: Model, resolution: Int, host: String, port: UInt16 = 9100) {
        self.model = model
        self.resolution = resolution
        self.host = host
        self.port = port
    }

    public func print(_ zpl: String) throws {
        Task {
            do {
                let conn = NWConnection(
                    host: NWEndpoint.Host(host),
                    port: NWEndpoint.Port(rawValue: port)!,
                    using: .tcp
                )
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    conn.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            conn.send(
                                content: zpl.data(using: .utf8),
                                completion: .contentProcessed { sendError in
                                    if let sendError = sendError {
                                        conn.cancel()
                                        cont.resume(throwing: sendError)
                                    } else {
                                        conn.cancel()
                                        cont.resume(returning: ())
                                    }
                                }
                            )
                        case .failed(let error):
                            conn.cancel()
                            cont.resume(throwing: error)
                        default:
                            break
                        }
                    }
                    conn.start(queue: .global())
                }

            } catch {
                try print("Error: \(error)")
            }
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


public func showImageInITerm2(data: Data) {
    // Base64-encode the image
    let base64 = data.base64EncodedString()

    // iTerm2 escape sequence format for inline images
    let esc = "\u{1b}"  // Escape character
    let osc = "]"
    let st = "\\"

    let header = "\(esc)\(osc)1337;File=inline=1;width=auto;height=auto;preserveAspectRatio=1:"
    let footer = "\(esc)\(st)"

    // Print the sequence to the terminal
    print("\(header)\(base64)\(footer)")
}
