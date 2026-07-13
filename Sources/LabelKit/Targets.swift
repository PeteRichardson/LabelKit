//
//  Targets.swift
//  LabelKit
//
//  Created by Peter Richardson on 8/31/25.
//

import Foundation
@preconcurrency import Network

public enum Payload: Sendable {
    case zpl(String, dpi: DPI)      // carry the render DPI with the ZPL
    case png(Data, dpi: DPI)
}

/// Target describes a delivery mechanism and where the output goes
/// e.g. network socket, file, stdout, iTerm2, …
/// This is different from Device, which describes capabilities (like nativeDPI))
/// You might want the zpl generated for a 300 DPI ZD620, then sent to labelary
/// to get an image, and then send that image to iTerm2 or to a file.
/// Everything is the same up to the final "send to iTerm2" or "save to file" part.
/// You are sending the same data to two different Targets.
public protocol Target {
    var device: Device { get }
    func send(_ payload: Payload, strict: Bool) async throws
}

public struct NetworkTarget: Target {
    public let device: Device
    private let host: String
    private let port: UInt16

    public func send(_ payload: Payload, strict: Bool = true) async throws {
        switch payload {
        case let .zpl(zpl, dpi):
            if strict && dpi != device.nativeDPI {
                throw PrintError.dpiMismatch(render: dpi, device: device.nativeDPI)
            }
            // If not strict, you *could* still send, but it will look wrong.
            try await sendRaw(Data(zpl.utf8), timeout: 3)
        case let .png(data, dpi):
            // Usually you don't send PNGs to a ZPL device; same check applies if you ever did.
            if strict && dpi != device.nativeDPI {
                throw PrintError.dpiMismatch(render: dpi, device: device.nativeDPI)
            }
            try await sendRaw(data)
        }
    }

    public func sendRaw(_ data: Data, timeout seconds: Double = 10) async throws {
        let host = self.host
        let port = self.port

        enum NetworkSendError: Error { case invalidPort, timeout, cancelled }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw NetworkSendError.invalidPort }

        let conn = NWConnection(
            host: NWEndpoint.Host(host),
            port: nwPort,
            using: .tcp
        )

        // Await connection readiness or failure, with timeout
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    // withCheckedThrowingContinuation is not cancellation-aware on its own:
                    // when the timeout task below wins and group.cancelAll() marks this task
                    // cancelled, nothing would resume the continuation, so it (and the group)
                    // would hang until the connection resolves on its own — the OS's own
                    // connect timeout (75s+) for an unroutable/black-holed host, or forever
                    // (docs/reviews/code-review_src_2026-07-09.md HIGH #5, GitHub #31).
                    // withTaskCancellationHandler bridges that gap: cancellation calls
                    // conn.cancel(), which drives the state machine to .cancelled and resumes
                    // the continuation, breaking the wait.
                    try await withTaskCancellationHandler {
                        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                            conn.stateUpdateHandler = { state in
                                switch state {
                                case .ready:
                                    conn.stateUpdateHandler = nil
                                    cont.resume(returning: ())
                                case .failed(let error):
                                    conn.stateUpdateHandler = nil
                                    cont.resume(throwing: error)
                                case .cancelled:
                                    conn.stateUpdateHandler = nil
                                    cont.resume(throwing: NetworkSendError.cancelled)
                                default:
                                    break
                                }
                            }
                            conn.start(queue: .global(qos: .userInitiated))
                        }
                    } onCancel: {
                        conn.cancel()
                    }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    throw NetworkSendError.timeout
                }

                // First finished wins
                _ = try await group.next()
                group.cancelAll()
            }
        } catch {
            conn.cancel()
            throw error
        }

        // Send data and await completion
        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                conn.send(
                    content: data,
                    completion: .contentProcessed { sendError in
                        if let sendError = sendError {
                            cont.resume(throwing: sendError)
                        } else {
                            cont.resume(returning: ())
                        }
                    }
                )
            }
        } catch {
            conn.cancel()
            throw error
        }

        conn.cancel()
    }
    
    public init(device: Device, host: String, port: UInt16) {
        self.device = device
        self.host = host
        self.port = port
    }
}

public struct StdoutTarget: Target {
    public let device: Device
    public func send(_ payload: Payload, strict: Bool = true) async throws {
        switch payload {
        case .zpl(let s, _):
            Swift.print(s)
        case .png(let d, _):
            // iTerm2-safe? If not, hex dump or error:
            Swift.print("PNG \(d.count) bytes")
        }
    }
    public init(device: Device) {
        self.device = device
    }
}

public struct ITerm2Target: Target {
    public let device: Device
    public func send(_ payload: Payload, strict: Bool = true) async throws {
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
    public func send(_ payload: Payload, strict: Bool = true) async throws {
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
