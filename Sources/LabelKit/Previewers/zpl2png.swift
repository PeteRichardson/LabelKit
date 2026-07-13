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
    case missingGeometry(String)
}

func isSandboxed() -> Bool {
    guard let task = SecTaskCreateFromSelf(nil) else { return false }
    // defer { CFRelease(task) }
    if let value = SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil) {
        // defer { CFRelease(value) }
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
        } else {
            let candidates: [URL?] = [
                Bundle.main.url(forAuxiliaryExecutable: "zpl2png"),
                URL(fileURLWithPath: "/Users/pete/bin/zpl2png"),
                URL(fileURLWithPath: "/usr/local/bin/zpl2png")
            ]
            if let url = candidates.compactMap({ $0 }).first(where: {
                FileManager.default.isExecutableFile(atPath: $0.path) }) {
                self.helperURL = url
            } else {
                throw NSError(domain: "Engine", code: 2,
                              userInfo: [NSLocalizedDescriptionKey:
                                            "zpl2png not found in bundle or common system paths"])
            }
        }
    }
    
    public func render(from zpl: String, options: ImageRenderOptions) async throws -> Data {
        return try await withCheckedThrowingContinuation { cont in
            Task {
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
        
        // widthDots/heightDots are nil for continuous stock (see Stock.heightInches) or when
        // geometry hasn't been fully resolved yet; there's no safe fallback for actual PNG
        // dimensions, so surface that as a typed error instead of crashing (docs/reviews/
        // PROJECT_REVIEW.md F3, docs/reviews/code-review_src_2026-07-09.md HIGH #1).
        guard let widthDots = options.geometry.widthDots else {
            throw PreviewError.missingGeometry("widthDots is nil")
        }
        guard let heightDots = options.geometry.heightDots else {
            throw PreviewError.missingGeometry("heightDots is nil (continuous stock has no fixed height)")
        }
        // Convert dots -> inches -> mm and round once, at the end. Rounding the
        // intermediate inches value first (the old `round(dots / dpi) * 25.4`) truncated
        // every non-whole-inch dimension to the nearest whole inch before converting,
        // e.g. 1.5in became 2in -> 50.8mm instead of 38.1mm (docs/reviews/
        // code-review_src_2026-07-09.md HIGH #2, GitHub #29).
        let widthMM = Int((Double(widthDots) / Double(options.geometry.dpi) * 25.4).rounded())
        let heightMM = Int((Double(heightDots) / Double(options.geometry.dpi) * 25.4).rounded())
        args += ["--width-mm", String(widthMM)]
        args += ["--height-mm", String(heightMM)]
        args += ["--dpmm", String(Int(round(Double(options.geometry.dpi)/25.4)))]
        p.arguments = args
        //print(args)
        
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = errPipe

        try p.run()

        // Drain stdout/stderr on background queues *while* the process runs, rather than
        // reading only after it exits. Reading after exit deadlocks once the helper fills
        // the OS pipe buffer (~64KB) writing its PNG: it blocks in write() and never exits,
        // so the old poll loop just timed out waiting for a stuck process instead of a
        // finished one (docs/reviews/code-review_src_2026-07-09.md HIGH #3, GitHub #30).
        nonisolated(unsafe) var stdoutData = Data()
        nonisolated(unsafe) var stderrData = Data()
        let readGroup = DispatchGroup()
        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutData = outPipe.fileHandleForReading.readDataToEndOfFile()
            readGroup.leave()
        }
        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrData = errPipe.fileHandleForReading.readDataToEndOfFile()
            readGroup.leave()
        }

        do {
            try inPipe.fileHandleForWriting.write(contentsOf: Data(zpl.utf8))
            try inPipe.fileHandleForWriting.close()
        }
        catch {
            p.terminate()
            throw NSError(
                domain: "ZPL2PNG",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to write ZPL data: \(error.localizedDescription)"]
            )}

        let timeoutWorkItem = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + options.timeout, execute: timeoutWorkItem)
        p.waitUntilExit()
        timeoutWorkItem.cancel()

        // The background reads finish as soon as the process's pipes close, which
        // waitUntilExit() above already waited for; this just synchronizes with them.
        readGroup.wait()

        if p.terminationStatus != 0 || stdoutData.isEmpty {
            let err = String(data: stderrData, encoding: .utf8) ?? ""
            throw NSError(domain: "ZPL2PNG", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: err])
        }
        return stdoutData
    }
    
}
