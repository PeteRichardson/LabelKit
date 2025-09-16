//
//  ZPLRepresentable.swift
//  LabelKit
//
//  Created by Peter Richardson on 9/16/25.
//

public protocol ZPLRepresentable {
    /// Produce ZPL for this label (render templates, add lengths, etc).
    func zpl() throws -> String
}
