//
//  RenderGeometryTests.swift
//  LabelKitTests
//

import Testing
@testable import LabelKit

@Suite("RenderGeometry dots<->inches<->mm conversion")
struct RenderGeometryConversionTests {
    // The shared helpers zpl2png.swift and Labelary.swift both route through
    // (docs/reviews/PROJECT_REVIEW.md F6, GitHub #7).

    @Test func inchesFromDotsDividesByDPI() {
        let geometry = RenderGeometry(dpi: 300, widthDots: nil, heightDots: nil)
        #expect(geometry.inches(fromDots: 450) == 1.5)
        #expect(geometry.inches(fromDots: 300) == 1.0)
    }

    @Test func millimetersFromDotsConvertsViaInches() {
        let geometry = RenderGeometry(dpi: 300, widthDots: nil, heightDots: nil)
        // 450 dots @ 300dpi = 1.5in = 38.1mm. Binary floating point can't represent
        // 38.1 exactly (1.5 * 25.4 == 38.099999999999994), so compare with tolerance.
        #expect(abs(geometry.millimeters(fromDots: 450) - 38.1) < 0.0001)
        // 300 dots @ 300dpi = 1.0in = 25.4mm.
        #expect(abs(geometry.millimeters(fromDots: 300) - 25.4) < 0.0001)
    }

    @Test func dotsPerMillimeterRoundsDPI() {
        #expect(RenderGeometry(dpi: 203, widthDots: nil, heightDots: nil).dotsPerMillimeter == 8)
        #expect(RenderGeometry(dpi: 300, widthDots: nil, heightDots: nil).dotsPerMillimeter == 12)
        #expect(RenderGeometry(dpi: 600, widthDots: nil, heightDots: nil).dotsPerMillimeter == 24)
    }
}
