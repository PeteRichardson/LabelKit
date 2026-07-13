//
//  ZPLLabel+Delivery.swift
//  LabelKit
//

import Foundation

/// Convenience wrappers around the render-then-send pattern that LabelCLI, ReminderList,
/// and LabelGUI each reimplemented independently (docs/reviews/PROJECT_REVIEW.md F1).
public extension ZPLLabel {
    /// Renders this label's ZPL and sends it to `target` at the environment's device DPI.
    func print(to target: some Target, strict: Bool = true) async throws {
        try await target.send(.zpl(try zpl(), dpi: environment.options.device.nativeDPI), strict: strict)
    }

    /// Renders a PNG preview via `rendererType`. `fallbackHeightDots` fills in a height when
    /// the environment's geometry has none (e.g. continuous stock) so the renderer still gets
    /// a concrete canvas size.
    func renderPreview<R: ImageRenderer>(
        using rendererType: R.Type,
        timeout: TimeInterval = 10,
        fallbackHeightDots: Int? = nil
    ) async throws -> Data {
        var geometry = environment.options.geometry
        if let fallbackHeightDots {
            geometry.heightDots = geometry.resolvedHeightDots(fallback: fallbackHeightDots)
        }
        let renderer = try R()
        return try await renderer.render(from: try zpl(), options: ImageRenderOptions(geometry: geometry, timeout: timeout))
    }

    /// Renders a PNG preview via `rendererType` and sends it to `target` at the environment's device DPI.
    func preview<R: ImageRenderer>(
        using rendererType: R.Type,
        to target: some Target,
        timeout: TimeInterval = 10,
        fallbackHeightDots: Int? = nil,
        strict: Bool = true
    ) async throws {
        let pngData = try await renderPreview(using: rendererType, timeout: timeout, fallbackHeightDots: fallbackHeightDots)
        try await target.send(.png(pngData, dpi: environment.options.device.nativeDPI), strict: strict)
    }
}
