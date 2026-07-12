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

    // MARK: - FD field data: known corruption bug (docs/reviews/code-review_src_2026-07-09.md, HIGH #4)

    /// The mnemonic reader in `format(_:pretty:)` consumes up to 3 uppercase letters
    /// before checking `code == "FD"`. For `^FDHello...` it reads "FDH", the FD-preservation
    /// branch is skipped, and the content is instead treated as ordinary command params —
    /// which strips whitespace. This test documents the bug so it fails loudly (not silently)
    /// once someone fixes the mnemonic reader to special-case FD/FS.
    @Test func minifyCorruptsFDContentThatStartsUppercase() {
        withKnownIssue("ZPLFormatter reads a 3-char mnemonic before checking for FD, so content starting with an uppercase letter isn't recognized as field data and gets whitespace-stripped like a normal command's params (docs/reviews/code-review_src_2026-07-09.md HIGH #4)") {
            let zpl = "^FDHello World^FS"
            let out = ZPLFormatter.minify(zpl)
            #expect(out == "^FDHello World^FS")
        }
    }

    @Test func prettyPrintCorruptsCommaSpacingInFDContentThatStartsUppercase() {
        withKnownIssue("Same root cause as the minify case: FD content starting with an uppercase letter falls through to normalizeParams(), which strips the space after commas inside label text (docs/reviews/code-review_src_2026-07-09.md HIGH #4)") {
            let zpl = "^FDHello, World^FS"
            let out = ZPLFormatter.prettyPrint(zpl)
            #expect(out == "^FDHello, World^FS")
        }
    }
}
