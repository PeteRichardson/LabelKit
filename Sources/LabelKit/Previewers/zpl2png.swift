//
//  zpl2png.swift
//  LabelKit
//
//  Created by Peter Richardson on 9/2/25.
//

import Foundation
import Security

enum PreviewError: Error, LocalizedError {
    case helperNotFound(String)
    case cannotLaunch(String)
    case noOutput(String)
    case badImageData
    case missingGeometry(String)
    case writeFailed(String)
    case helperFailed(status: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .helperNotFound(let reason):
            return "zpl2png helper not found: \(reason)"
        case .cannotLaunch(let reason):
            return "Failed to launch zpl2png helper: \(reason)"
        case .noOutput:
            return "zpl2png helper exited successfully but produced no output."
        case .badImageData:
            return "zpl2png helper produced data that isn't a valid image."
        case .missingGeometry(let reason):
            return "Cannot render label: \(reason)"
        case .writeFailed(let reason):
            return "Failed to write ZPL data to zpl2png helper: \(reason)"
        case .helperFailed(let status, let stderr):
            return "zpl2png helper exited with status \(status)" + (stderr.isEmpty ? "." : ": \(stderr)")
        }
    }
}

extension PreviewError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .helperNotFound(detail):
            return "zpl2png helper not found: \(detail)"
        case let .cannotLaunch(detail):
            return "Could not run zpl2png helper: \(detail)"
        case let .noOutput(detail):
            return "zpl2png helper produced no output: \(detail)"
        case .badImageData:
            return "zpl2png helper produced data that isn't a valid image"
        case let .missingGeometry(detail):
            return "Missing render geometry: \(detail)"
        }
    }
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
                throw PreviewError.helperNotFound("not found in Contents/Helpers")
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
                throw PreviewError.helperNotFound("not found in bundle or common system paths")
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
        // Convert dots -> mm via RenderGeometry's shared helper (docs/reviews/
        // PROJECT_REVIEW.md F6, GitHub #7), which Labelary.swift now uses too. It rounds
        // once, at the end, avoiding the rounding-order bug fixed in GitHub #29.
        let widthMM = Int(options.geometry.millimeters(fromDots: widthDots).rounded())
        let heightMM = Int(options.geometry.millimeters(fromDots: heightDots).rounded())
        args += ["--width-mm", String(widthMM)]
        args += ["--height-mm", String(heightMM)]
        args += ["--dpmm", String(options.geometry.dotsPerMillimeter)]
        p.arguments = args
        //print(args)
        
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = errPipe

        do {
            try p.run()
        } catch {
            throw PreviewError.cannotLaunch(error.localizedDescription)
        }

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
            throw PreviewError.writeFailed(error.localizedDescription)
        }

        let timeoutWorkItem = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + options.timeout, execute: timeoutWorkItem)
        p.waitUntilExit()
        timeoutWorkItem.cancel()

        // The background reads finish as soon as the process's pipes close, which
        // waitUntilExit() above already waited for; this just synchronizes with them.
        readGroup.wait()

        if p.terminationStatus != 0 {
            let err = String(data: stderrData, encoding: .utf8) ?? ""
            throw PreviewError.helperFailed(status: p.terminationStatus, stderr: err)
        }
        guard !stdoutData.isEmpty else {
            throw PreviewError.noOutput
        }
        return stdoutData
    }
    
}
