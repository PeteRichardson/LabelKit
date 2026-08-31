//
//  GenerateLabelTests.swift
//  ReminderListTests
//

import Testing
import LabelKit
@testable import ReminderList

@Suite("ReminderList label generation")
struct GenerateLabelTests {

    private func reminder(_ title: String) -> ReminderSummary {
        ReminderSummary(title: title, priority: 0, dueDate: nil, isCompleted: false)
    }

    @Test func utf8EncodingIsDeclared() throws {
        let zpl = try generate_label(reminders: [reminder("café")]).zpl()
        #expect(zpl.contains("^CI28"))
    }

    @Test func defaultFontIsDeclaredOnceRatherThanPerReminder() throws {
        let zpl = try generate_label(reminders: [reminder("a"), reminder("b")]).zpl()
        #expect(zpl.contains("^CF0,50,50"))
        #expect(!zpl.contains("^A0N,50,50"))
    }

    @Test func commandIntroducersInReminderTitlesAreEscaped() throws {
        // Reminder titles are arbitrary user text from Reminders.app.
        let zpl = try generate_label(reminders: [reminder("pay ^XZ rent ~JA now_ok")]).zpl()
        #expect(zpl.contains("^FH^FDpay _5EXZ rent _7EJA now_5Fok^FS"))
        // Exactly one ^XZ: the label terminator, not one smuggled in via a title.
        #expect(zpl.components(separatedBy: "^XZ").count - 1 == 1)
    }

    @Test func remindersShareOneFieldBlockAtTheFirstRowOrigin() throws {
        let zpl = try generate_label(reminders: [reminder("first"), reminder("second")]).zpl()
        // topMargin 20 + fontSize 50 + gap 20 = 90, indented to 80. The second
        // row's origin is the printer's job now, so ^FB carries the 20-dot gap
        // and the rows are joined with \&.
        #expect(zpl.contains("^FO80,90^FB1060,9999,20,L,0^FH^FDfirst\\&second^FS"))
        #expect(zpl.contains("^LL478"))   // 90 + 70 for the second row + 318
    }

    @Test func labelLengthAndPublishedGeometryAgree() throws {
        let label = generate_label(reminders: [reminder("only")])
        #expect(try label.zpl().contains("^LL408"))   // 90 + 318 cutter clearance
        #expect(label.environment.options.geometry.heightDots == 408)
    }

    @Test func printWidthMatchesTheFourInchStock() throws {
        let zpl = try generate_label(reminders: [reminder("only")]).zpl()
        #expect(zpl.contains("^PW1200"))
    }

    @Test func emptyReminderListStillProducesAWellFormedLabel() throws {
        let zpl = try generate_label(reminders: []).zpl()
        #expect(zpl.hasPrefix("^XA"))
        #expect(zpl.hasSuffix("^XZ"))
    }
}
