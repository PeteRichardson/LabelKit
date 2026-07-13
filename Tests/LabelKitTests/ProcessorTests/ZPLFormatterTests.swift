//
//  ZPLFormatterTests.swift
//  LabelKitTests
//

import Testing
import LabelKit

@Suite("ZPLFormatter")
struct ZPLFormatterTests {

    // MARK: - Non-FD commands

    @Test func minifyStripsWhitespaceInParams() {
        let zpl = "^FO 40 , 60 \n^A0N , 30 , 30"
        let out = ZPLFormatter.minify(zpl)
        #expect(out == "^FO40,60^A0N,30,30")
    }

    @Test func prettyPrintNormalizesSpacingAroundCommas() {
        let zpl = "^FO40  ,  60^A0N,30,30"
        let out = ZPLFormatter.prettyPrint(zpl)
        #expect(out == "^FO40,60\n^A0N,30,30")
    }

    @Test func prettyPrintOneCommandPerLine() {
        let zpl = "^XA^FO0,0^A0N,30,30^XZ"
        let out = ZPLFormatter.prettyPrint(zpl)
        #expect(out == "^XA\n^FO0,0\n^A0N,30,30\n^XZ")
    }

    // MARK: - FD field data: currently-correct cases (content starting lowercase)

    @Test func minifyPreservesFDContentThatStartsLowercase() {
        // Regression guard: FD content is only mis-tokenized when it starts with
        // an uppercase letter (see corruption tests below). Lowercase-leading
        // content is unaffected and must stay verbatim.
        let zpl = "^FDhello world^FS"
        let out = ZPLFormatter.minify(zpl)
        #expect(out == "^FDhello world^FS")
    }

    @Test func prettyPrintPreservesFDContentThatStartsLowercase() {
        let zpl = "^FDhello, world^FS"
        let out = ZPLFormatter.prettyPrint(zpl)
        #expect(out == "^FDhello, world^FS")
    }

    // MARK: - FD field data: content starting uppercase (docs/reviews/code-review_src_2026-07-09.md, HIGH #4)

    @Test func minifyPreservesFDContentThatStartsUppercase() {
        let zpl = "^FDHello World^FS"
        let out = ZPLFormatter.minify(zpl)
        #expect(out == "^FDHello World^FS")
    }

    @Test func prettyPrintPreservesCommaSpacingInFDContentThatStartsUppercase() {
        let zpl = "^FDHello, World^FS"
        let out = ZPLFormatter.prettyPrint(zpl)
        #expect(out == "^FDHello, World^FS")
    }
}
