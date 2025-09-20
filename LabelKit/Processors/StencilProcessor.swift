//
//  StencilProcessor.swift
//  LabelKit
//
//  Created by Peter Richardson on 8/31/25.
//

import Foundation


enum PrintError: Error {
    case dpiMismatch(render: DPI, device: DPI)
    case widthOverflow(requested: Int, max: Int)
    case lengthOverflow(requested: Int, max: Int)
}

/// A ZPLProcessor that resolves Stencil templates in the raw zpl from a StencilTemplateStore
public struct StencilZPLProcessor: ZPLProcessor {
    private var templateStore : StencilTemplateStore? = nil
    private var context: [String: Any]
    
    public init? (context: [String: Any] = [:]) {
        self.context = context
        
        do {
            // Get Templates from Application Support/.../templates.json
            templateStore = try StencilTemplateStore()
            try templateStore!.load()
        } catch {
            print ("Error initializing StencilZPLProcessor::templateStore: \(error)")
        }
    }
    public func process(_ input: String, env: ZPLEnvironment) throws -> String {
        var zpl : String = ""

        if templateStore != nil {
            // Render the given zpl in the given context
            zpl = try templateStore!.renderZPL(input, context: context)
        }
        
        // Ensure ^XA/^XZ
        if !zpl.starts(with: "\\s+^XA") { zpl = "^XA\n" + zpl }
        if !zpl.hasSuffix("^XZ\\s") { zpl += "\n^XZ" }

        return zpl
    }


}




public struct RenderGeometry: Sendable {
    public var dpi: Int
    public var widthDots: Int?      // optional; renderer may infer from ^PW
    public var heightDots: Int?     // optional; renderer may auto-size
    
    public init(dpi: Int, widthDots: Int? = nil, heightDots: Int? = nil) {
        self.dpi = dpi
        self.widthDots = widthDots
        self.heightDots = heightDots
    }
}


