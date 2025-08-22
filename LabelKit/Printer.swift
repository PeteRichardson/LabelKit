//
//  Printer.swift
//  LabelKit
//
//  Created by Peter Richardson on 8/22/25.
//

import Network
import Foundation

public func sendZPL(_ zpl: String, to host: String = "192.168.0.133", port: UInt16 = 9100) {
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
            print("Error: \(error)")
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
