//
//  ParseLinesTests.swift
//  LabelPrintTests
//

import Testing
import LabelKit
@testable import labelprint

@Suite("labelprint line parsing")
struct ParseLinesTests {

    @Test func lineEndingInColonBecomesAHeader() {
        #expect(parseLines("Costco:") == [.header("Costco:")])
    }

    @Test func ordinaryLineBecomesAnItem() {
        #expect(parseLines("eggs") == [.item("eggs")])
    }

    @Test func interiorBlankLineIsPreserved() {
        #expect(parseLines("a\n\nb") == [.item("a"), .blank, .item("b")])
    }

    @Test func trailingBlankLinesAreTrimmed() {
        // A text file almost always ends in a newline; that must not stretch
        // the label with empty rows.
        #expect(parseLines("a\n\n\n") == [.item("a")])
    }

    @Test func surroundingWhitespaceIsStripped() {
        #expect(parseLines("   eggs   ") == [.item("eggs")])
        #expect(parseLines("  \t  ") == [])
    }

    @Test func emptyInputYieldsNoLines() {
        #expect(parseLines("") == [])
    }

    @Test func crlfHeaderLineIsClassifiedAsHeader() {
        #expect(parseLines("Costco:\r\n") == [.header("Costco:")])
    }

    @Test func crlfDocumentParsesSameAsItsLFEquivalent() {
        let lf = "Costco:\neggs\n\nDraegers:\nmilk\n"
        let crlf = "Costco:\r\neggs\r\n\r\nDraegers:\r\nmilk\r\n"
        #expect(parseLines(crlf) == parseLines(lf))
        #expect(parseLines(crlf) == [
            .header("Costco:"), .item("eggs"), .blank, .header("Draegers:"), .item("milk"),
        ])
    }

    @Test func loneCarriageReturnLineEndingsAlsoSplit() {
        #expect(parseLines("a\rb\rc") == [.item("a"), .item("b"), .item("c")])
    }
}
