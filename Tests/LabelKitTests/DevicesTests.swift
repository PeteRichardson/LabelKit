//
//  DevicesTests.swift
//  LabelKitTests
//

import Testing
@testable import LabelKit

@Suite("DPI")
struct DPITests {

    @Test func rawValuesMatchDotsPerInch() {
        #expect(DPI.dpi203.rawValue == 203)
        #expect(DPI.dpi300.rawValue == 300)
        #expect(DPI.dpi600.rawValue == 600)
    }

    @Test func lessThanOrdersByRawValue() {
        #expect(DPI.dpi203 < .dpi300)
        #expect(DPI.dpi300 < .dpi600)
        #expect(!(DPI.dpi600 < .dpi300))
        #expect(!(DPI.dpi300 < .dpi300))
    }

    @Test func allCasesContainsExactlyTheThreePresets() {
        #expect(Set(DPI.allCases) == [.dpi203, .dpi300, .dpi600])
    }

    @Test func sortsAscendingByResolution() {
        #expect([DPI.dpi600, .dpi203, .dpi300].sorted() == [.dpi203, .dpi300, .dpi600])
    }

    @Test func supportsMinAndMax() {
        #expect(max(DPI.dpi203, .dpi600) == .dpi600)
        #expect(min(DPI.dpi300, .dpi203) == .dpi203)
        #expect(DPI.allCases.max() == .dpi600)
        #expect(DPI.allCases.min() == .dpi203)
    }

    @Test func formsRangesOverResolutions() {
        let range = DPI.dpi203 ... DPI.dpi600
        #expect(range.contains(.dpi300))
        #expect(range.contains(.dpi203))
        #expect(range.contains(.dpi600))
        #expect(!(DPI.dpi203 ..< DPI.dpi600).contains(.dpi600))
    }

    @Test func derivedComparisonOperatorsFollowRawValue() {
        #expect(DPI.dpi600 > .dpi203)
        #expect(DPI.dpi300 <= .dpi300)
        #expect(DPI.dpi300 >= .dpi203)
    }
}

@Suite("Device")
struct DeviceTests {

    @Test func zd620PresetMatchesDocumentedCapabilities() {
        let device = Device.Preset.ZD620
        #expect(device.name == "ZD620")
        #expect(device.nativeDPI == .dpi300)
        #expect(device.maxWidthDots == 1200)
        #expect(device.maxLengthDots == 12000)
    }

    @Test func equalDevicesAreEqualAndHash() {
        let a = Device(name: "ZD620", nativeDPI: .dpi300, maxWidthDots: 1200, maxLengthDots: 12000)
        let b = Device(name: "ZD620", nativeDPI: .dpi300, maxWidthDots: 1200, maxLengthDots: 12000)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test func devicesWithDifferentDPIAreNotEqual() {
        let a = Device(name: "ZD620", nativeDPI: .dpi300, maxWidthDots: 1200, maxLengthDots: 12000)
        let b = Device(name: "ZD620", nativeDPI: .dpi203, maxWidthDots: 1200, maxLengthDots: 12000)
        #expect(a != b)
    }
}
