//
//  zpl2png.swift
//  LabelKit
//
//  Created by Peter Richardson on 9/2/25.
//

import AppKit

enum PreviewError: Error {
    case helperNotFound
    case cannotLaunch(String)
    case noOutput
    case badImageData
}

// MARK: - zpl2png (local helper in Contents/Helpers)

public struct ZPL2PNGRenderer: ImageRenderer {
    let helperURL: URL
    public func render(from zpl: String, options: ImageRenderOptions) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            Task.detached {
                do {
                    let data = try runHelper(helperURL: helperURL, zpl: zpl, options: options)
                    cont.resume(returning: data)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func runHelper(helperURL: URL, zpl: String, options: ImageRenderOptions) throws -> Data {
        let p = Process()
        p.executableURL = helperURL
        var args: [String] = []
        
        let widthMM = Int(round(Double(options.geometry.widthDots!) / 25.4))
        let heightMM = Int(round(Double(options.geometry.heightDots!) / 25.4))
        args += ["--width-mm", String(widthMM)]
        args += ["--height-mm", String(heightMM)]
        args += ["--dpmm", String(Int(round(Double(options.geometry.dpi)/25.4)))]
        p.arguments = args
        print(args)

        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = errPipe

        try p.run()
        inPipe.fileHandleForWriting.write(Data(zpl.utf8))
        try? inPipe.fileHandleForWriting.close()

        // crude timeout; polish as needed
        let deadline = Date().addingTimeInterval(options.timeout)
        while p.isRunning, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        if p.isRunning { p.terminate() }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        if p.terminationStatus != 0 || data.isEmpty {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "ZPL2PNG", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: err])
        }
        return data
    }
    public init(helperURL: URL) {
        self.helperURL = helperURL
    }
}
