//
//  ZPLLabel.swift
//  LabelKit
//
//  Created by Peter Richardson on 8/23/25.
//
import Foundation
import Network

public protocol Label {
    /// Produce ZPL for this label (templates can render here).
    func zpl() throws -> String
}

public struct ZPLLabel: Label {
    public let zplSource: String
    public func zpl() throws -> String { zplSource }
    
    public init(_ zplSource: String) {
        self.zplSource = zplSource
    }
}
