//
//  Targets.swift
//  LabelKit
//
//  Created by Peter Richardson on 8/31/25.
//

import Foundation

/// Where the output goes (network socket, file, stdout, iTerm2, …)
public enum Payload {
    case zpl(String)
    case png(Data) // or .tiff/.pdf depending on engine
}

public protocol Target {
    func send(_ payload: Payload) throws
}

public struct NetworkTarget: Target {
    let host: String
    let port: UInt16
    public func send(_ payload: Payload) throws {
        switch payload {
        case .zpl(let s): try sendRaw(Data(s.utf8))
        case .png(let d): try sendRaw(d) // only if printer supports EPL/ZPL-graphics upload (optional)
        }
    }
    private func sendRaw(_ d: Data) throws { /* open TCP, write, close */ }
    
    public init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }
}

public struct StdoutTarget: Target {
    let pretty: Bool
    public func send(_ payload: Payload) throws {
        switch payload {
        case .zpl(let s):
            Swift.print(pretty ? ZPLFormatter.prettyPrint(s) : ZPLFormatter.minify(s))
        case .png(let d):
            // iTerm2-safe? If not, hex dump or error:
            Swift.print("PNG \(d.count) bytes")
        }
    }
    public init(pretty: Bool) {
        self.pretty = pretty
    }
}

public struct ITerm2Target: Target {
    public func send(_ payload: Payload) throws {
        guard case .png(let data) = payload else { return }
        let b64 = data.base64EncodedString()
        Swift.print("\u{1b}]1337;File=inline=1;width=auto;height=auto;preserveAspectRatio=1:\(b64)\u{07}")
    }
    public init() {}
}

public struct FileTarget: Target {
    let url: URL
    public func send(_ payload: Payload) throws {
        switch payload {
        case .zpl(let s): try s.write(to: url, atomically: true, encoding: .utf8)
        case .png(let d): try d.write(to: url)
        }
    }
    public init(url: URL) {
        self.url = url
    }
}
