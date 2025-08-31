//
//  NetworkPrinter.swift
//  LabelKit
//
//  Created by Peter Richardson on 8/31/25.
//

import Network

// MARK: - Concrete printer communicating via TCP, like a ZD620

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
