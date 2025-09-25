//
//  KeyValueContext.swift
//  LabelKit
//
//  Created by Peter Richardson on 9/25/25.
//

import Foundation

// MARK: - Model

/// One editable row (key/value pair)
public struct KeyValueRow: Identifiable, Hashable {
    public let id: UUID
    public var key: String
    public var value: String

    public init(id: UUID = UUID(), key: String = "", value: String = "") {
        self.id = id
        self.key = key
        self.value = value
    }
}

/// A lightweight wrapper you can pass around and export back to [String: String]
public struct KeyValueContext: Hashable {
    public var rows: [KeyValueRow]

    public init(_ dictionary: [String: String] = [:]) {
        self.rows = dictionary.map { KeyValueRow(key: $0.key, value: $0.value) }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
    }

    /// Merge rows into a dictionary; last occurrence of a duplicate key wins.
    public func asDictionary() -> [String: String] {
        var out: [String: String] = [:]
        for row in rows where !row.key.isEmpty {
            out[row.key] = row.value
        }
        return out
    }

    /// Convenience alias specifically for your Stencil context use.
    public func asStencilContext() -> [String: String] { asDictionary() }
}
