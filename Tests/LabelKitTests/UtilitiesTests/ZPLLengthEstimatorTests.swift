//
//  ZPLLengthEstimatorTests.swift
//  LabelKitTests
//
//  Created by Peter Richardson on 9/19/25.
//

import Testing
import LabelKit

struct ZPLLengthEstimatorTests {

    @Test func SimpleOriginPlusOneLine() async throws {
        let zpl = """
            ^XAs
            ^FO40,40
            ^A0N,40,40
            ^FDHello, ZPL!^FS
            ^XZ
            """
        
        let ll = ZPLLengthEstimator.estimate(zpl)
        #expect(ll == 80)
    }

}

/// `^FB` hands the line advance to the printer, so the estimator has to model
/// the block itself: the `\&`-separated segments, the wrapping the printer will
/// do inside the block width, and `^FB`'s own inter-line spacing parameter.
@Suite("ZPLLengthEstimator ^FB field blocks")
struct ZPLLengthEstimatorFieldBlockTests {

    @Test func blockLinesUseTheBlockSpacingRatherThanTheDefaultLineGap() {
        // 3 lines * 50 + 2 gaps * 20 = 190, the 70-dot pitch ^FB reproduces.
        let zpl = "^XA^FO0,0^A0N,50,50^FB1040,99,20,L,0^FDa\\&b\\&c^FS^XZ"
        #expect(ZPLLengthEstimator.estimate(zpl) == 190)
    }

    @Test func textWiderThanTheBlockWrapsRatherThanBeingCountedAsOneLine() {
        // A 50-dot cell averages 30 dots per glyph, so a 200-dot block holds 6
        // characters and an unbroken run of 8 spills onto a second line.
        let zpl = "^XA^FO0,0^A0N,50,50^FB200,99,0,L,0^FDabcdefgh^FS^XZ"
        #expect(ZPLLengthEstimator.estimate(zpl) == 100)
    }

    @Test func wrappingBreaksAtWordBoundariesRatherThanMidWord() {
        // A 120-dot block holds 4 characters. Blind chunking would make these
        // 11 characters 3 lines, but ^FB breaks at spaces, so no line fits more
        // than one "ab" and there are 4.
        let zpl = "^XA^FO0,0^A0N,50,50^FB120,99,0,L,0^FDab ab ab ab^FS^XZ"
        #expect(ZPLLengthEstimator.estimate(zpl) == 200)
    }

    @Test func aZeroFontWidthMeansProportionalAndFallsBackToTheHeight() {
        // ^A0N,50,0 asks the printer to derive the width from the height, so a
        // literal zero must not be read as "no characters fit".
        let zpl = "^XA^FO0,0^A0N,50,0^FB120,99,0,L,0^FDab ab ab ab^FS^XZ"
        #expect(ZPLLengthEstimator.estimate(zpl) == 200)
    }

    @Test func maxLinesCapsTheBlockBecauseThePrinterDiscardsTheRest() {
        // 4 lines of text in a 2-line block: the printer prints 2 and drops the
        // rest, so the label is 2 lines tall, not 4.
        let zpl = "^XA^FO0,0^A0N,50,50^FB120,2,0,L,0^FDab ab ab ab^FS^XZ"
        #expect(ZPLLengthEstimator.estimate(zpl) == 100)
    }

    @Test func blockAppliesOnlyToTheFieldItPrecedes() {
        // ^FB is per-field. The second ^FD is an ordinary field and must fall
        // back to the default line gap of 2, not inherit the block's 20.
        let zpl = "^XA^FO0,0^A0N,50,50^FB1040,99,20,L,0^FDa^FS^FO0,0^FDb\\&c^FS^XZ"
        #expect(ZPLLengthEstimator.estimate(zpl) == 102)
    }
}
