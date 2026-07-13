//
//  LocalizedErrorsTests.swift
//  LabelKitTests
//

import Testing
@testable import LabelKit

// Confirms LabelKit's domain errors produce actionable messages via
// error.localizedDescription instead of a raw enum dump like
// "lengthOverflow(requested: 5000, max: 4000)" (docs/reviews/PROJECT_REVIEW.md
// F4/F19/F24, GitHub #5/#18/#23 - the same fix, tracked separately for its
// consistency/CLI-UX/idiom angles).

@Suite("PrintError localized descriptions")
struct PrintErrorLocalizedDescriptionTests {
    @Test func dpiMismatchMentionsBothDPIValues() {
        let error = PrintError.dpiMismatch(render: .dpi203, device: .dpi300)
        let message = error.localizedDescription
        #expect(message.contains("203"))
        #expect(message.contains("300"))
        #expect(!message.contains("dpiMismatch("))
    }

    @Test func lengthOverflowMentionsRequestedAndMax() {
        let error = PrintError.lengthOverflow(requested: 5000, max: 4000)
        let message = error.localizedDescription
        #expect(message.contains("5000"))
        #expect(message.contains("4000"))
        #expect(!message.contains("lengthOverflow("))
    }
}

@Suite("LabelaryError localized descriptions")
struct LabelaryErrorLocalizedDescriptionTests {
    @Test func httpErrorMentionsStatusAndBody() {
        let error = LabelaryError.httpError(400, "bad size")
        let message = error.localizedDescription
        #expect(message.contains("400"))
        #expect(message.contains("bad size"))
        #expect(!message.contains("httpError("))
    }

    @Test func invalidDPmmIsNotARawEnumDump() {
        #expect(LabelaryError.invalidDPmm.localizedDescription != "invalidDPmm")
    }
}

@Suite("PreviewError localized descriptions")
struct PreviewErrorLocalizedDescriptionTests {
    @Test func helperFailedMentionsStatusAndStderr() {
        let error = PreviewError.helperFailed(status: 1, stderr: "boom")
        let message = error.localizedDescription
        #expect(message.contains("1"))
        #expect(message.contains("boom"))
        #expect(!message.contains("helperFailed("))
    }

    @Test func missingGeometryIncludesTheReason() {
        let error = PreviewError.missingGeometry("heightDots is nil")
        #expect(error.localizedDescription.contains("heightDots is nil"))
    }
}
