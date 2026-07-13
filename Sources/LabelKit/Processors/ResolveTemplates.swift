//
//  StencilProcessor.swift
//  LabelKit
//
//  Created by Peter Richardson on 8/31/25.
//

import Foundation


enum PrintError: Error, LocalizedError {
    case dpiMismatch(render: DPI, device: DPI)
    case widthOverflow(requested: Int, max: Int)
    case lengthOverflow(requested: Int, max: Int)

    var errorDescription: String? {
        switch self {
        case .dpiMismatch(let render, let device):
            return "Render DPI (\(render.rawValue)) doesn't match the device's native DPI (\(device.rawValue)). Pass strict: false to send anyway."
        case .widthOverflow(let requested, let max):
            return "Requested width (\(requested) dots) exceeds the device's maximum width (\(max) dots)."
        case .lengthOverflow(let requested, let max):
            return "Requested length (\(requested) dots) exceeds the device's maximum length (\(max) dots)."
        }
    }
}

/// A ZPLProcessor that resolves Stencil templates in the raw zpl from a StencilTemplateStore
public struct ResolveTemplates: ZPLProcessor {
    private let templateStore: StencilTemplateStore

    public func process(_ input: String, env: ZPLEnvironment) throws -> String {
        try templateStore.renderZPL(input, context: env.context.asDictionary())
    }

    public init?() {
        do {
            // Get Templates from Application Support/.../templates.json
            let store = try StencilTemplateStore()
            try store.load()
            templateStore = store
        } catch {
            print("Error initializing ResolveTemplates::templateStore: \(error)")
            return nil
        }
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

extension RenderGeometry {
    /// `widthDots`/`heightDots` are `nil` for continuous stock (see `Stock.heightInches`).
    /// Callers that just need *some* concrete size (e.g. sizing a preview frame) should
    /// resolve through these instead of force-unwrapping independently.
    public func resolvedWidthDots(fallback: Int) -> Int {
        widthDots ?? fallback
    }
    public func resolvedHeightDots(fallback: Int) -> Int {
        heightDots ?? fallback
    }
}


