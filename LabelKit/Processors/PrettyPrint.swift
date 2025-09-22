//
//  PrettyPrint.swift
//  LabelKit
//
//  Created by Peter Richardson on 9/22/25.
//

import Foundation

// MARK: - PrettyPrint

/// ZPLProcessor that formats ZPL
public struct PrettyPrint: ZPLProcessor {
    public func process(_ input: String, env: ZPLEnvironment) throws -> String {
        // print("# Calling \(String(describing: type(of: self)))")
        return ZPLFormatter.prettyPrint(input)
    }
    public init(){}
}
