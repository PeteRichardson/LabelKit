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

    // NOTE: deliberately no "DPI matches, so it proceeds to sendRaw" test here.
    // sendRaw's connect-timeout is defeated by a task-group/continuation deadlock
    // (docs/reviews/code-review_src_2026-07-09.md HIGH #5) — against an unroutable
    // host it can hang far past its nominal timeout, or indefinitely. Exercising
    // that path needs either the deadlock fixed first or NetworkTarget refactored
    // behind a mockable connection abstraction; forcing it here would risk hanging
    // the whole test suite.
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
