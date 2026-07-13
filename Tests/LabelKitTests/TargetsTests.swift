//
//  TargetsTests.swift
//  LabelKitTests
//

import Testing
import Foundation
@testable import LabelKit

@Suite("Target strict DPI guard")
struct NetworkTargetDPIGuardTests {
    // NetworkTarget checks `strict && dpi != device.nativeDPI` and throws before ever
    // touching the network, so this is exercisable without a live connection or printer.
    // (docs/reviews/PROJECT_REVIEW.md F11 — this guard was previously untested.)

    let device = Device.Preset.ZD620 // nativeDPI == .dpi300

    @Test func strictZPLSendThrowsOnDPIMismatch() async throws {
        let target = NetworkTarget(device: device, host: "203.0.113.1", port: 9100)
        await #expect(throws: PrintError.self) {
            try await target.send(.zpl("^XA^XZ", dpi: .dpi203), strict: true)
        }
    }

    @Test func strictPNGSendThrowsOnDPIMismatch() async throws {
        let target = NetworkTarget(device: device, host: "203.0.113.1", port: 9100)
        await #expect(throws: PrintError.self) {
            try await target.send(.png(Data(), dpi: .dpi600), strict: true)
        }
    }

    // 203.0.113.1 (RFC 5737 TEST-NET-3) is guaranteed non-routable. Depending on the
    // network this runs on, connecting to it either fails fast (.failed) or parks the
    // connection unresolved (.waiting) until the OS's own connect timeout (75s+) —
    // confirmed to be the latter in this environment via a raw `nc` connect that didn't
    // resolve within several seconds. Before the fix, a task-group/continuation deadlock
    // meant the .waiting case could hang for that OS timeout or indefinitely, regardless
    // of the `timeout:` argument below (docs/reviews/code-review_src_2026-07-09.md HIGH
    // #5, GitHub #31); the assertion is bounded well under 75s to catch that regression
    // while staying tolerant of the fail-fast case on networks where that's what happens.
    @Test func sendRawTimesOutInsteadOfHangingOnUnroutableHost() async throws {
        let target = NetworkTarget(device: device, host: "203.0.113.1", port: 9100)

        let start = Date()
        await #expect(throws: (any Error).self) {
            try await target.sendRaw(Data("^XA^XZ".utf8), timeout: 2)
        }
        let elapsed = Date().timeIntervalSince(start)

        #expect(elapsed < 10)
    }
}

@Suite("FileTarget")
struct FileTargetTests {
    let device = Device.Preset.ZD620

    @Test func writesZPLPayloadToFile() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("labelkit-test-\(UUID().uuidString).zpl")
        defer { try? FileManager.default.removeItem(at: url) }

        let target = FileTarget(url: url, device: device)
        try await target.send(.zpl("^XA^FDHi^FS^XZ", dpi: device.nativeDPI), strict: true)

        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(written == "^XA^FDHi^FS^XZ")
    }

    @Test func writesPNGPayloadToFile() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("labelkit-test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        let target = FileTarget(url: url, device: device)
        try await target.send(.png(bytes, dpi: device.nativeDPI), strict: true)

        let written = try Data(contentsOf: url)
        #expect(written == bytes)
    }
}

@Suite("StdoutTarget and ITerm2Target")
struct ConsoleTargetTests {
    let device = Device.Preset.ZD620

    @Test func stdoutTargetDoesNotThrowForEitherPayloadKind() async throws {
        let target = StdoutTarget(device: device)
        try await target.send(.zpl("^XA^XZ", dpi: device.nativeDPI), strict: true)
        try await target.send(.png(Data([1, 2, 3]), dpi: device.nativeDPI), strict: true)
    }

    @Test func iterm2TargetIgnoresZPLPayload() async throws {
        // `send` guards on `case .png` and silently returns for `.zpl` — this just
        // asserts that path doesn't throw or hang.
        let target = ITerm2Target(device: device)
        try await target.send(.zpl("^XA^XZ", dpi: device.nativeDPI), strict: true)
    }

    @Test func iterm2TargetAcceptsPNGPayload() async throws {
        let target = ITerm2Target(device: device)
        try await target.send(.png(Data([1, 2, 3]), dpi: device.nativeDPI), strict: true)
    }
}
