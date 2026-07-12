//
//  ZPLLabel.swift
//  LabelKit
//
//  Created by Peter Richardson on 9/16/25.
//
import Observation

/// Represents a label, including source text, a (possibly empty) chain of processors to
/// convert the source text into renderable ZPL, and an Environment containing information
/// needed for the conversion (e.g. context variables, media dimensions, device DPI, etc)
public struct ZPLLabel: ZPLRepresentable, Observable {
    public var source: String /// input text.  converted to renderable ZPL by a chain of processors
    public var processors: [any ZPLProcessor]  /// an ordered list of processors to apply to the input text to end up with renderable ZPL
    public var environment: ZPLEnvironment /// Information needed to generate renderable ZPL
    
    public init(_ source: String,
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
