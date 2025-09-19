//
//  InjectLengthTests.swift
//  LabelKitTests
//
//  Created by Peter Richardson on 9/19/25.
//

import Testing
import LabelKit

struct InjectLengthTests {

    @Test func SimpleTest() async throws {
        let zpl = """
            ^XA
            <<LL_MARKER>>
            ^FO40,40
            ^A0N,40,40
            ^FDHello, ZPL!^FS
            ^XZ
            """
        let label = ZPLLabel(source: zpl, processors: [InjectLength()])
        let finalzpl = (try? label.zpl()) ?? "zpl() failed"
        #expect(finalzpl.contains("^LL"))
    }
    
}
