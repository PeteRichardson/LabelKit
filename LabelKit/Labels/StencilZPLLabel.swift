//
//  ZPLLabel.swift
//  LabelKit
//
//  Created by Peter Richardson on 8/23/25.
//
import Foundation
import Stencil



//@Observable
//public final class ZPLLabel: ZPLRepresentable {
//    public var rawText: String
//    public func zpl() throws -> String {
//        return rawText
//    }
//    
//    public init(rawText: String) {
//        self.rawText = rawText
//    }
//}

// MARK: - Observable ZPLLabel that renders a Stencil template into finalized ZPL
@Observable
public final class StencilZPLLabel: ZPLRepresentable {
    // User-editable template (left editor binds to this)
    public var rawTemplate: String { didSet { scheduleRender() } }

    // Finalized ZPL after Stencil rendering (middle editor shows this)
    public private(set) var renderedZPL: String = "<not rendered yet>"

    // Arbitrary data used by the template
    public var context: [String: Any] = [:] { didSet { scheduleRender() } }

    // Optional error string from the last render attempt
    public private(set) var lastRenderError: String? = nil

    // MARK: Init
    public init(_ initialTemplate: String, context: [String: Any] = [:]) {
        self.rawTemplate = initialTemplate
        self.context = context
        // initial pass
        scheduleRender()
    }

    public func zpl() throws -> String { renderedZPL }

    // MARK: Rendering
    private let env = Environment(loader: nil)
    private let debouncer = Debouncer()

    private func scheduleRender() {
        debouncer.schedule { [weak self] in
            await self?.renderNow()
        }
    }

    /// Render template immediately (debouncer calls this). Safe to call from any thread.
    @MainActor
    public func renderNow() async {
        do {
            let out = try env.renderTemplate(string: rawTemplate, context: context)
            self.renderedZPL = out
            self.lastRenderError = nil
        } catch {
            self.lastRenderError = String(describing: error)
            // Keep the previous renderedZPL on failure
        }
    }

    /// Convenience for setting a single context key.
    public func setContextValue(_ key: String, _ value: Any) { self.context[key] = value }
}

// MARK: - Simple async debouncer (Duration-based)
public final class Debouncer {
    private var task: Task<Void, Never>? = nil
    public init() {}

    public func schedule(delay: Duration = .milliseconds(300), _ action: @escaping @Sendable () async -> Void) {
        task?.cancel()
        task = Task { [action] in
            try? await Task.sleep(for: delay)
            if Task.isCancelled { return }
            await action()
        }
    }
}
