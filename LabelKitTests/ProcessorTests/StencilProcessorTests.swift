//
//  StencilProcessorTests.swift
//  LabelKitTests
//
//  Created by Peter Richardson on 9/20/25.
//

import Testing
import LabelKit

struct StencilProcessorTests {

    @Test func SimpleStencil() async throws {
        let ctx = ["name": "World"]
        let zpl = """
            ^XA
            ^FO40,300
            ^A0N,40,40
            ^FDHello, {{ name }}!^FS
            ^XZ
            """
        let label = ZPLLabel(source: zpl, processors: [StencilZPLProcessor(context: ctx)!])
        let finalzpl = (try? label.zpl()) ?? "zpl() failed"
        #expect(finalzpl.contains("Hello, World!"))
    }
    
    @Test func InsertsXAXZ() async throws {
        let ctx = ["name": "World"]
        let zpl = """
            ^FDHello, World!^FS
            """
        let label = ZPLLabel(source: zpl, processors: [StencilZPLProcessor(context: ctx)!])
        let finalzpl = (try? label.zpl()) ?? "zpl() failed"
        #expect(finalzpl.starts(with: "^XA\n"))
        #expect(finalzpl.hasSuffix("\n^XZ"))
    }

}
