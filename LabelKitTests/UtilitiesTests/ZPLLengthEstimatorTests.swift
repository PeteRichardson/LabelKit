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
