//
//  zpl2png.swift
//  LabelKit
//
//  Created by Peter Richardson on 9/2/25.
//

import Foundation
import Security
enum PreviewError: Error {
    case helperNotFound
    case cannotLaunch(String)
    case noOutput
    case badImageData
}

func isSandboxed() -> Bool {
    guard let task = SecTaskCreateFromSelf(nil) else { return false }
    if let value = SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil) {
        return (value as? Bool) == true
    }
    return false
}
// MARK: - zpl2png (local helper in Contents/Helpers)

func lookupInPath(named name: String) -> URL? {
    let fm = FileManager.default
    guard let pathEnv = ProcessInfo.processInfo.environment["PATH"] else { return nil }
    for dir in pathEnv.split(separator: ":") {
        let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(name)
        if fm.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
    }
    return nil
}

public enum LabelKitResources {
    public static func zpl2pngURL() -> URL? {
        Bundle.module.url(forResource: "zpl2png", withExtension: nil)
    }
}


public struct ZPL2PNGRenderer: ImageRenderer {
    
    var helperURL: URL
    
    public init() throws {
        if isSandboxed() {
            guard let url = LabelKitResources.zpl2pngURL() else {
                throw NSError(domain: "Engine", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    "zpl2png not found in Contents/Helpers"])
            }
            self.helperURL = url
            return
        } else {
            let candidates: [URL?] = [
                Bundle.main.url(forAuxiliaryExecutable: "zpl2png"),
                URL(fileURLWithPath: "/Users/pete/bin/zpl2png"),
                URL(fileURLWithPath: "/usr/local/bin/zpl2png")
            ]
            for url in candidates.compactMap({ $0 }) {
                if FileManager.default.isExecutableFile(atPath: url.path) {
                    self.helperURL = url
                    return
                    
                }
            }
            throw NSError(domain: "Engine", code: 2, userInfo: [NSLocalizedDescriptionKey:
                "zpl2png not found in bundle or common system paths"])
        }
    }

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
        
        let widthMM = Int(round(Double(options.geometry.widthDots!)  / Double(options.geometry.dpi)) * 25.4)
        let heightMM = Int(round(Double(options.geometry.heightDots!) / Double(options.geometry.dpi)) * 25.4)
        args += ["--width-mm", String(widthMM)]
        args += ["--height-mm", String(heightMM)]
        args += ["--dpmm", String(Int(round(Double(options.geometry.dpi)/25.4)))]
        p.arguments = args
        //print(args)

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

}
