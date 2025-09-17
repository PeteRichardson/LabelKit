//
//  PreviewService.swift
//  LabelKit
//
//  Created by Peter Richardson on 9/17/25.
//

import Foundation

struct PreviewService {
    let processor = StencilZPLProcessor()
    let imageRenderer: ImageRenderer
    
    func png(for label: ZPLRepresentable, env: ZPLEnvironment, imageOptions: ImageRenderOptions) async throws -> Data {
        let zpl = try processor?.process(label.zpl(), env: env) ?? "^FDNo ZPLProcessor installed, or processing failed!^FS"
        return try await imageRenderer.render(from: zpl, options: imageOptions)
    }
}
