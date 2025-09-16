//
//  ZPLLabel.swift
//  LabelKit
//
//  Created by Peter Richardson on 9/16/25.
//

public struct ZPLLabel: ZPLRepresentable {
    public var source: String
    public var processors: [any ZPLProcessor]
    public var environment: ZPLEnvironment

    public init(source: String,
                processors: [any ZPLProcessor] = [],
                environment: ZPLEnvironment = .init()) {
        self.source = source
        self.processors = processors
        self.environment = environment
    }

    public func zpl() throws -> String {
        try processors.reduce(source) { acc, p in
            try p.process(acc, env: environment)
        }
    }
}
