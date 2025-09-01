//
//  Targets.swift
//  LabelKit
//
//  Created by Peter Richardson on 8/31/25.
//

import Foundation
import Network

/// Where the output goes (network socket, file, stdout, iTerm2, …)
public enum Payload {
    case zpl(String, dpi: DPI)      // carry the render DPI with the ZPL
    case png(Data, dpi: DPI)
}


public protocol Target {
    var device: Device { get }
    func send(_ payload: Payload, strict: Bool) throws
}

public struct NetworkTarget: Target {
    public let device: Device
    private let host: String
    private let port: UInt16

    public func send(_ payload: Payload, strict: Bool = true) throws {
        switch payload {
        case let .zpl(zpl, dpi):
            if strict && dpi != device.nativeDPI {
                throw PrintError.dpiMismatch(render: dpi, device: device.nativeDPI)
            }
            // If not strict, you *could* still send, but it will look wrong.
            try sendRaw(Data(zpl.utf8))
        case let .png(data, dpi):
            // Usually you don't send PNGs to a ZPL device; same check applies if you ever did.
            if strict && dpi != device.nativeDPI {
                throw PrintError.dpiMismatch(render: dpi, device: device.nativeDPI)
            }
            try sendRaw(data)
        }
    }

    private func sendRaw(_ data: Data) throws {
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
                                content: data,
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
                print("Error: \(error)")
            }
        }
    }
    
    public init(device: Device, host: String, port: UInt16) {
        self.device = device
        self.host = host
        self.port = port
    }
}

public struct StdoutTarget: Target {
    public let device: Device
    let pretty: Bool
    public func send(_ payload: Payload, strict: Bool) throws {
        switch payload {
        case .zpl(let s, _):
            Swift.print(pretty ? ZPLFormatter.prettyPrint(s) : ZPLFormatter.minify(s))
        case .png(let d, _):
            // iTerm2-safe? If not, hex dump or error:
            Swift.print("PNG \(d.count) bytes")
        }
    }
    public init(pretty: Bool, device: Device) {
        self.pretty = pretty
        self.device = device
    }
}

public struct ITerm2Target: Target {
    public let device: Device
    public func send(_ payload: Payload, strict: Bool) throws {
        guard case .png(let data, _) = payload else { return }
        let b64 = data.base64EncodedString()
        Swift.print("\u{1b}]1337;File=inline=1;width=auto;height=auto;preserveAspectRatio=1:\(b64)\u{07}")
    }
    public init(device: Device) {
        self.device = device
    }
}

public struct FileTarget: Target {
    public let device: Device
    let url: URL
    public func send(_ payload: Payload, strict: Bool) throws {
        switch payload {
        case .zpl(let s, _): try s.write(to: url, atomically: true, encoding: .utf8)
        case .png(let data, _): try data.write(to: url)
        }
    }
    public init(url: URL, device: Device) {
        self.url = url
        self.device = device
    }
}
