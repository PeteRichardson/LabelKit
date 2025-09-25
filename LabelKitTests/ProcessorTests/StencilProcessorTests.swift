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
        let ctx = KeyValueContext(["name": "World"])
        let zpl = """
            ^XA
            ^FO40,300
            ^A0N,40,40
            ^FDHello, {{ name }}!^FS
            ^XZ
            """
        let label = ZPLLabel(zpl,
                             processors: [ResolveTemplates()!],
                             environment: .init(context: ctx)
        )
        let finalzpl = label.zpl()
        #expect(finalzpl.contains("Hello, World!"))
    }

}
