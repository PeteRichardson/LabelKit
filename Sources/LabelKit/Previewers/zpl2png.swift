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
    case noOutput
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

/// Searches the `PATH` entries of `environment` for an executable named `name`.
///
/// Takes the environment as a parameter (rather than always reading `ProcessInfo`) so the
/// search order can be exercised deterministically from tests.
func lookupInPath(
    named name: String,
    environment: [String: String] = ProcessInfo.processInfo.environment
) -> URL? {
    guard let pathEnv = environment["PATH"] else { return nil }
    for dir in pathEnv.split(separator: ":") {
        let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(name)
        if isExecutableFile(candidate) {
            return candidate
        }
    }
    return nil
}

/// True when `url` names an existing, executable regular file (not a directory, which
/// `FileManager.isExecutableFile(atPath:)` happily reports as executable).
func isExecutableFile(_ url: URL) -> Bool {
    let fm = FileManager.default
    var isDirectory: ObjCBool = false
    guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
        return false
    }
    return fm.isExecutableFile(atPath: url.path)
}

public enum LabelKitResources {
    public static func zpl2pngURL() -> URL? {
        Bundle.module.url(forResource: "zpl2png", withExtension: nil)
    }
}


public struct ZPL2PNGRenderer: ImageRenderer {

    /// Name of the environment variable that overrides which `zpl2png` binary is used.
    ///
    /// Set it to an absolute path to point LabelKit at a specific helper build from the
    /// shell; the programmatic equivalent is ``init(helperURL:)``.
    public static let helperOverrideEnvironmentVariable = "LABELKIT_ZPL2PNG"

    /// Blocking `Process` work (`write`, `waitUntilExit`, `readDataToEndOfFile`) must not run
    /// on Swift's cooperative thread pool: those threads are a fixed, small resource and
    /// blocking them starves unrelated tasks. `render` hands the work to this queue instead
    /// (docs/reviews/code-review_src_2026-07-09.md CR-9, GitHub #33). It is concurrent so
    /// simultaneous renders don't serialize behind each other.
    private static let helperQueue = DispatchQueue(
        label: "com.labelkit.zpl2png.helper",
        qos: .userInitiated,
        attributes: .concurrent
    )

    var helperURL: URL

    /// Creates a renderer, locating the `zpl2png` helper automatically.
    ///
    /// See ``resolveHelperURL(explicitHelperURL:environment:sandboxed:)`` for the search order.
    ///
    /// - Throws: ``PreviewError/helperNotFound(_:)`` if no executable helper can be found.
    public init() throws {
        try self.init(explicitHelperURL: nil)
    }

    /// Creates a renderer that uses a specific `zpl2png` binary.
    ///
    /// Use this when you ship or build your own helper and don't want LabelKit guessing —
    /// it takes precedence over `$LABELKIT_ZPL2PNG` and every automatic search location.
    ///
    /// - Parameter helperURL: File URL of the helper executable.
    /// - Throws: ``PreviewError/helperNotFound(_:)`` if `helperURL` isn't an executable file.
    public init(helperURL: URL) throws {
        try self.init(explicitHelperURL: helperURL)
    }

    /// Designated initializer. The environment and sandbox flag are parameters so tests can
    /// drive resolution without mutating process-wide state.
    init(
        explicitHelperURL: URL?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        sandboxed: Bool = isSandboxed()
    ) throws {
        self.helperURL = try Self.resolveHelperURL(
            explicitHelperURL: explicitHelperURL,
            environment: environment,
            sandboxed: sandboxed
        )
    }

    /// Resolves which `zpl2png` binary to run, in this order:
    ///
    /// 1. `explicitHelperURL` (from ``init(helperURL:)``)
    /// 2. `$LABELKIT_ZPL2PNG`
    /// 3. `Bundle.main`'s auxiliary executable, for apps shipping the helper in
    ///    `Contents/Helpers`
    /// 4. `zpl2png` on `$PATH`
    /// 5. `/usr/local/bin/zpl2png`
    /// 6. the copy bundled with the LabelKit package itself
    ///
    /// A sandboxed process can't execute anything outside its container, so when `sandboxed`
    /// is true steps 4 and 5 are skipped; only the two overrides and the two in-bundle
    /// locations apply.
    ///
    /// The overrides are checked before anything else and are hard failures when they point
    /// at something unusable: silently falling back to a different binary would hide a typo'd
    /// path. Everything else is a best-effort search, so non-matches just fall through.
    static func resolveHelperURL(
        explicitHelperURL: URL?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        sandboxed: Bool = isSandboxed()
    ) throws -> URL {
        if let explicitHelperURL {
            guard isExecutableFile(explicitHelperURL) else {
                throw PreviewError.helperNotFound(
                    "\(explicitHelperURL.path) (passed to init(helperURL:)) is not an executable file"
                )
            }
            return explicitHelperURL
        }

        if let override = environment[helperOverrideEnvironmentVariable], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            guard isExecutableFile(url) else {
                throw PreviewError.helperNotFound(
                    "\(url.path) (from $\(helperOverrideEnvironmentVariable)) is not an executable file"
                )
            }
            return url
        }

        // A sandboxed process can only execute what's inside its container, so it skips the
        // system locations entirely; LabelKit's own bundled copy is the last resort either way.
        let systemLocations: [URL?] = sandboxed ? [] : [
            lookupInPath(named: "zpl2png", environment: environment),
            URL(fileURLWithPath: "/usr/local/bin/zpl2png")
        ]
        let candidates: [URL?] =
            [Bundle.main.url(forAuxiliaryExecutable: "zpl2png")]
            + systemLocations
            + [LabelKitResources.zpl2pngURL()]

        guard let url = candidates.compactMap({ $0 }).first(where: isExecutableFile) else {
            let searched = sandboxed
                ? "in the app bundle (a sandboxed process can't execute binaries outside its container)"
                : "in the app bundle, on $PATH, in /usr/local/bin, or among LabelKit's bundled resources"
            throw PreviewError.helperNotFound(
                "no executable zpl2png found \(searched). Set "
                + "$\(helperOverrideEnvironmentVariable) or pass one to ZPL2PNGRenderer(helperURL:)."
            )
        }
        return url
    }

    public func render(from zpl: String, options: ImageRenderOptions) async throws -> Data {
        let helperURL = self.helperURL
        return try await withCheckedThrowingContinuation { continuation in
            // The continuation now earns its keep: it bridges from the cooperative pool to a
            // thread that is allowed to block, instead of wrapping a `Task` that was already
            // on the pool it was trying to leave.
            Self.helperQueue.async {
                continuation.resume(with: Result {
                    try Self.runHelper(helperURL: helperURL, zpl: zpl, options: options)
                })
            }
        }
    }

    /// Runs the helper synchronously. Callers must be on ``helperQueue`` (or another thread
    /// that may block) — never on the cooperative pool.
    private static func runHelper(helperURL: URL, zpl: String, options: ImageRenderOptions) throws -> Data {
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
        let stdoutData = DataBox()
        let stderrData = DataBox()
        let readGroup = DispatchGroup()
        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutData.value = outPipe.fileHandleForReading.readDataToEndOfFile()
            readGroup.leave()
        }
        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrData.value = errPipe.fileHandleForReading.readDataToEndOfFile()
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

        let out = stdoutData.value
        if p.terminationStatus != 0 {
            let err = String(data: stderrData.value, encoding: .utf8) ?? ""
            throw PreviewError.helperFailed(status: p.terminationStatus, stderr: err)
        }
        guard !out.isEmpty else {
            throw PreviewError.noOutput
        }
        return out
    }

}

/// A lock-protected `Data` box, so the background pipe drains can hand their bytes back to
/// `runHelper` without capturing `nonisolated(unsafe)` mutable locals in a `@Sendable`
/// closure — an escape hatch that asserts safety rather than providing it.
private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var value: Data {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }
}
