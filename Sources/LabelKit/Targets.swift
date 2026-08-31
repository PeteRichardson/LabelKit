//
//  Targets.swift
//  LabelKit
//
//  Created by Peter Richardson on 8/31/25.
//

import Foundation

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

/// Shared default connection info for the example printer used by LabelCLI, ReminderList, and LabelGUI.
public enum PrinterDefaults {
    public static let host = "192.168.0.133"
    public static let port: UInt16 = 9100
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

    /// Errors raised while talking to the printer socket.
    enum NetworkSendError: Error, LocalizedError {
        case invalidPort
        case unresolvedHost(String)
        case timeout
        case connectionFailed(String)
        case sendFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidPort: return "Invalid printer port."
            case .unresolvedHost(let host): return "Could not resolve printer address \(host)."
            case .timeout: return "Connection to the printer timed out."
            case .connectionFailed(let why): return "Could not connect to the printer: \(why)."
            case .sendFailed(let why): return "Could not send data to the printer: \(why)."
            }
        }
    }

    public func sendRaw(_ data: Data, timeout seconds: Double = 10) async throws {
        let host = self.host
        let port = self.port

        // Hop off the cooperative pool: the socket work below blocks in poll().
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try Self.writeToSocket(data, host: host, port: port, timeout: seconds)
                    cont.resume(returning: ())
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    /// Connects, writes `data`, half-closes, and hands the rest to the kernel.
    ///
    /// Deliberately a BSD socket rather than `NWConnection`. Network.framework offers no
    /// signal that means "these bytes reached the wire": `.contentProcessed` only means the
    /// connection took them out of our buffer, and the `.cancelled` state that follows
    /// `cancel()` arrives before the flush completes. A short-lived CLI that returned on
    /// either signal exited while bytes were still queued inside the framework, so print
    /// jobs silently vanished. This was invisible over loopback — which delivers inline, so
    /// tests and a local listener saw all 334 bytes every time — and only showed up against
    /// a real printer across the network.
    ///
    /// A kernel socket has the semantics we actually need: once `send()` returns, the bytes
    /// are in the kernel's send buffer, and after `shutdown(SHUT_WR)` and `close()` the
    /// kernel finishes delivering them and the FIN even if the process has already exited.
    /// This is why piping the identical payload through `nc` always worked.
    private static func writeToSocket(_ data: Data, host: String, port: UInt16, timeout seconds: Double) throws {
        guard port > 0 else { throw NetworkSendError.invalidPort }

        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &list) == 0, list != nil else {
            throw NetworkSendError.unresolvedHost(host)
        }
        defer { freeaddrinfo(list) }

        // Try each resolved address in turn (v6 then v4, typically).
        var lastError: any Error = NetworkSendError.unresolvedHost(host)
        var candidate = list
        while let info = candidate {
            candidate = info.pointee.ai_next
            do {
                let fd = try connectSocket(info, timeout: seconds)
                defer { close(fd) }
                try writeAll(data, to: fd, timeout: seconds)
                shutdown(fd, SHUT_WR)
                return
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func connectSocket(_ info: UnsafeMutablePointer<addrinfo>, timeout seconds: Double) throws -> Int32 {
        let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard fd >= 0 else { throw NetworkSendError.connectionFailed(lastErrnoText()) }

        var connected = false
        defer { if !connected { close(fd) } }

        // A printer that hangs up mid-write should surface as an error, not SIGPIPE.
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        // Non-blocking connect, so `timeout` bounds an unroutable host instead of waiting
        // out the OS's own 75s+ connect timeout.
        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            throw NetworkSendError.connectionFailed(lastErrnoText())
        }

        if connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen) != 0 {
            guard errno == EINPROGRESS else { throw NetworkSendError.connectionFailed(lastErrnoText()) }
            try waitUntilWritable(fd, timeout: seconds)

            var pending: Int32 = 0
            var size = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &pending, &size) == 0 else {
                throw NetworkSendError.connectionFailed(lastErrnoText())
            }
            guard pending == 0 else {
                throw NetworkSendError.connectionFailed(String(cString: strerror(pending)))
            }
        }

        connected = true
        return fd
    }

    private static func writeAll(_ data: Data, to fd: Int32, timeout seconds: Double) throws {
        try data.withUnsafeBytes { buffer in
            guard var cursor = buffer.baseAddress else { return }
            var remaining = buffer.count
            while remaining > 0 {
                let written = Darwin.send(fd, cursor, remaining, 0)
                if written > 0 {
                    cursor = cursor.advanced(by: written)
                    remaining -= written
                } else if written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    try waitUntilWritable(fd, timeout: seconds)
                } else if written < 0 && errno == EINTR {
                    continue
                } else {
                    throw NetworkSendError.sendFailed(lastErrnoText())
                }
            }
        }
    }

    private static func waitUntilWritable(_ fd: Int32, timeout seconds: Double) throws {
        let deadline = Date().addingTimeInterval(seconds)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw NetworkSendError.timeout }

            var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let ready = poll(&descriptor, 1, Int32(remaining * 1000))
            if ready > 0 { return }
            if ready == 0 { throw NetworkSendError.timeout }
            guard errno == EINTR else { throw NetworkSendError.connectionFailed(lastErrnoText()) }
        }
    }

    private static func lastErrnoText() -> String { String(cString: strerror(errno)) }

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
