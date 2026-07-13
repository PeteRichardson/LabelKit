//
//  ZPLLabelDeliveryTests.swift
//  LabelKitTests
//

import Testing
import Foundation
@testable import LabelKit

actor RecordingTarget: Target {
    nonisolated let device: Device
    private(set) var sentPayload: Payload?
    private(set) var sentStrict: Bool?

    init(device: Device) {
        self.device = device
    }

    func send(_ payload: Payload, strict: Bool) async throws {
        sentPayload = payload
        sentStrict = strict
    }
}

actor RenderCallRecorder {
    private(set) var lastGeometry: RenderGeometry?

    func record(geometry: RenderGeometry) {
        lastGeometry = geometry
    }
}

// FakeImageRenderer is constructed internally by ZPLLabel.renderPreview via `R()`, so tests
// can't hold a reference to the instance that ran. A task-local recorder lets each test inject
// its own observer without sharing mutable state across the suite's parallel tests.
enum RenderCallRecorderKey {
    @TaskLocal static var current: RenderCallRecorder?
}

struct FakeImageRenderer: ImageRenderer {
    init() throws {}

    func render(from zpl: String, options: ImageRenderOptions) async throws -> Data {
        if let recorder = RenderCallRecorderKey.current {
            await recorder.record(geometry: options.geometry)
        }
        return Data([0xAA, 0xBB])
    }
}

@Suite("ZPLLabel print/preview convenience API")
struct ZPLLabelDeliveryTests {
    let device = Device.Preset.ZD620

    @Test func printSendsRenderedZPLAtDeviceNativeDPI() async throws {
        let label = ZPLLabel("^XA^FDHi^FS^XZ", environment: .init(stock: Stock.Preset.label2x1, device: device))
        let target = RecordingTarget(device: device)

        try await label.print(to: target)

        guard case let .zpl(sent, dpi) = await target.sentPayload else {
            Issue.record("expected .zpl payload")
            return
        }
        #expect(sent == "^XA^FDHi^FS^XZ")
        #expect(dpi == device.nativeDPI)
    }

    @Test func printDefaultsToStrict() async throws {
        let label = ZPLLabel("^XA^XZ", environment: .init(stock: Stock.Preset.label2x1, device: device))
        let target = RecordingTarget(device: device)

        try await label.print(to: target)

        #expect(await target.sentStrict == true)
    }

    @Test func printForwardsExplicitStrictFlag() async throws {
        let label = ZPLLabel("^XA^XZ", environment: .init(stock: Stock.Preset.label2x1, device: device))
        let target = RecordingTarget(device: device)

        try await label.print(to: target, strict: false)

        #expect(await target.sentStrict == false)
    }

    @Test func previewRendersAndSendsPNGAtDeviceNativeDPI() async throws {
        let label = ZPLLabel("^XA^XZ", environment: .init(stock: Stock.Preset.label2x1, device: device))
        let target = RecordingTarget(device: device)

        try await label.preview(using: FakeImageRenderer.self, to: target)

        guard case let .png(data, dpi) = await target.sentPayload else {
            Issue.record("expected .png payload")
            return
        }
        #expect(data == Data([0xAA, 0xBB]))
        #expect(dpi == device.nativeDPI)
    }

    @Test func previewLeavesNilHeightAloneWithoutFallback() async throws {
        let recorder = RenderCallRecorder()
        // label4x is continuous stock: heightInches (and thus heightDots) is nil.
        let label = ZPLLabel("^XA^XZ", environment: .init(stock: Stock.Preset.label4x, device: device))
        let target = RecordingTarget(device: device)

        try await RenderCallRecorderKey.$current.withValue(recorder) {
            try await label.preview(using: FakeImageRenderer.self, to: target)
        }

        let geometry = await recorder.lastGeometry
        #expect(geometry?.heightDots == nil)
    }

    @Test func previewAppliesFallbackHeightWhenGeometryHeightIsNil() async throws {
        let recorder = RenderCallRecorder()
        let label = ZPLLabel("^XA^XZ", environment: .init(stock: Stock.Preset.label4x, device: device))
        let target = RecordingTarget(device: device)

        try await RenderCallRecorderKey.$current.withValue(recorder) {
            try await label.preview(using: FakeImageRenderer.self, to: target, fallbackHeightDots: 500)
        }

        let geometry = await recorder.lastGeometry
        #expect(geometry?.heightDots == 500)
    }

    @Test func previewFallbackDoesNotOverrideExistingHeight() async throws {
        let recorder = RenderCallRecorder()
        let label = ZPLLabel("^XA^XZ", environment: .init(stock: Stock.Preset.label2x1, device: device))
        let target = RecordingTarget(device: device)

        try await RenderCallRecorderKey.$current.withValue(recorder) {
            try await label.preview(using: FakeImageRenderer.self, to: target, fallbackHeightDots: 999)
        }

        let geometry = await recorder.lastGeometry
        #expect(geometry?.heightDots != 999)
    }
}
