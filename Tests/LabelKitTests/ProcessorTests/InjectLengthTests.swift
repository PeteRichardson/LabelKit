//
//  InjectLengthTests.swift
//  LabelKitTests
//
//  Created by Peter Richardson on 9/19/25.
//

import Testing
import LabelKit

struct InjectLengthTests {
    
    /// NOTE: Remember that ZPLLabel adds 150 dots to LL to
    ///       make sure the printed area is pushed past the
    ///       tear-off area of the printer...
    ///
    /// TODO: Should NOT add 150 dots for non-continuous stock
    
    /// if no embedded LL, then inject it right after the ^XA
    @Test func WithoutLLTest() async throws {
        let zpl = """
            ^XA
            ^FO40,50
            ^A0N,40,40
            ^FDHello, ZPL!^FS
            ^XZ
            """
        let label = ZPLLabel(zpl, processors: [InjectLength()])
        let finalzpl = label.zpl()
        #expect(finalzpl.contains("^LL240"))
    }
    
    /// if embedded LL replace it with max(embeddedLL, estimate) + 150
    /// here, estimate == max(100, 90), so replaced value is 100+150 = 250
    @Test func EmbeddedLLLessThanEstimateTest() async throws {
        let zpl = """
            ^XA
            ^LL100
            ^FO40,50
            ^A0N,40,40
            ^FDHello, ZPL!^FS
            ^XZ
            """
        let label = ZPLLabel(zpl, processors: [InjectLength()])
        let finalzpl = label.zpl()
        #expect(finalzpl.contains("^LL250"))
    }
    
    /// if embedded LL replace it with max(embeddedLL, estimate) + 150
    /// here, estimate == max(300, 240), so replaced value is 340+150 = 490
    @Test func EmbeddedLLGreaterThanThanEstimateTTest() async throws {
        let zpl = """
            ^XA
            ^LL300
            ^FO40,300
            ^A0N,40,40
            ^FDHello, ZPL!^FS
            ^XZ
            """
        let label = ZPLLabel(zpl, processors: [InjectLength()])
        let finalzpl = label.zpl()
        #expect(finalzpl.contains("^LL490"))
    }
    
    
}
