//
//  ImageRenderer.swift
//  LabelKit
//
//  Created by Peter Richardson on 9/15/25.
//
import Foundation

public protocol ImageRenderer: Sendable {
    func render(from zpl: String, options: ImageRenderOptions) async throws -> Data
}


public struct ImageRenderOptions: Sendable {
    public var geometry: RenderGeometry
    public var timeout: TimeInterval = 10
    public init(geometry: RenderGeometry, timeout: TimeInterval) {
        self.geometry = geometry
        self.timeout = timeout
    }
}
