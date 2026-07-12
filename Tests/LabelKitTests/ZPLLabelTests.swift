//
//  ZPLLabelTests.swift
//  LabelKitTests
//
//  Created by Peter Richardson on 9/16/25.
//

import Testing
@testable import LabelKit

@Suite("ZPLLabel basic behavior")
struct ZPLLabelTests {

    @Test("Initial render with context")
    func initialRenderWithContext() async throws {
        // Given a simple Stencil template using a context key
        let template = "^XA\n^FO0,0^FDHello {{ name }}^FS\n^XZ"
        let label = ZPLLabel(template,
                             processors: [ResolveTemplates()!],
                             environment: .init(context: KeyValueContext(["name": "World"])))

        // Then: the renderedZPL should contain the interpolated value
        let out = try label.zpl()
        #expect(out.contains("Hello World"))
    }

    @Test("Updating rawTemplate and calling renderNow updates output")
    func updateTemplateThenRender() async throws {
        var label = ZPLLabel("^XA\n^FO0,0^FDHi {{ who }}^FS\n^XZ",
                             processors: [ResolveTemplates()!],
                             environment: .init(context: KeyValueContext(["who": "Alice"]))
        )

        var out = try label.zpl()
        #expect(out.contains("Hi Alice"))

        // Change template and context; debouncer will schedule but we force immediate render
        label.source = "^XA\n^FO0,0^FDBye {{ who }}^FS\n^XZ"
        label.environment.context = KeyValueContext(["who": "Bob"])

        out = try label.zpl()
        #expect(out.contains("Bye Bob"))
    }


    @Test("setContextValue updates context and affects render")
    func setContextValueAffectsRender() async throws {
        var label = ZPLLabel("^XA\n^FO0,0^FDItem: {{ item }}^FS\n^XZ",
                             processors: [ResolveTemplates()!],
                             environment: .init(context: KeyValueContext(["item": "A"])))
        var out = try label.zpl()
        #expect(out.contains("Item: A"))

        label.environment.context = KeyValueContext(["item": "B"])
        out = try label.zpl()
        #expect(out.contains("Item: B"))
    }
}

