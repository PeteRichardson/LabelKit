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
        let label = StencilZPLLabel(template, context: ["name": "World"]) // constructor schedules a render

        // When: we force an immediate render to avoid debounce
        await label.renderNow()

        // Then: the renderedZPL should contain the interpolated value
        let out = try label.zpl()
        #expect(out.contains("Hello World"))
        #expect(label.lastRenderError == nil)
    }

    @Test("Updating rawTemplate and calling renderNow updates output")
    func updateTemplateThenRender() async throws {
        let label = StencilZPLLabel("^XA\n^FO0,0^FDHi {{ who }}^FS\n^XZ", context: ["who": "Alice"]) 

        await label.renderNow()
        var out = try label.zpl()
        #expect(out.contains("Hi Alice"))

        // Change template and context; debouncer will schedule but we force immediate render
        label.rawTemplate = "^XA\n^FO0,0^FDBye {{ who }}^FS\n^XZ"
        label.setContextValue("who", "Bob")

        await label.renderNow()
        out = try label.zpl()
        #expect(out.contains("Bye Bob"))
        #expect(label.lastRenderError == nil)
    }

    @Test("Template error sets lastRenderError and preserves previous renderedZPL")
    func templateErrorHandling() async throws {
        // A valid starting template
        let good = "^XA\n^FO0,0^FDOK {{ val }}^FS\n^XZ"
        let label = StencilZPLLabel(good, context: ["val": "1"]) 
        await label.renderNow()
        let before = try label.zpl()
        #expect(before.contains("OK 1"))

        // Introduce a Stencil syntax error (unclosed tag)
        label.rawTemplate = "^XA\n^FO0,0^FDBroken {{ val ^FS\n^XZ"
        await label.renderNow()

        // Should report an error and keep the previous renderedZPL
        #expect(label.lastRenderError != nil)
        let after = try label.zpl()
        #expect(after == before)
    }

    @Test("setContextValue updates context and affects render")
    func setContextValueAffectsRender() async throws {
        let label = StencilZPLLabel("^XA\n^FO0,0^FDItem: {{ item }}^FS\n^XZ", context: ["item": "A"]) 
        await label.renderNow()
        var out = try label.zpl()
        #expect(out.contains("Item: A"))

        label.setContextValue("item", "B")
        await label.renderNow()
        out = try label.zpl()
        #expect(out.contains("Item: B"))
    }
}
