//
//  InjectLength.swift
//  LabelKit
//
//  Created by Peter Richardson on 9/19/25.
//

import Foundation

// MARK: - InjectLength

/// ZPLProcessor that injects an ^LL command with the estimated length of the label content
/// If an ^LL command already exists, it will be updated with the estimate if the estimate
/// is larger.
public struct InjectLength: ZPLProcessor {
    public func process(_ input: String, env: ZPLEnvironment) throws -> String {
        let ll = ZPLLengthEstimator.estimate(input)
        // print("# Calling \(String(describing: type(of: self))): Estimated Length: \(ll)")
        let newzpl: String
        if !input.contains("^LL") {
            newzpl = input.replacingOccurrences(of: "^XA",
                                                with: "^XA\n^LL\(ll+150)")
        } else {
            newzpl = input.replacingOccurrences(of: "\\^LL\\d+", with: "^LL\(ll+150)",
                                                options: .regularExpression)
        }
        
        // Sanity check that calculated length isn't too long for the device
        // TODO: Should also check Stock limits
        let maxLengthDots = env.options.device.maxLengthDots
        guard ll <= maxLengthDots else {
            throw PrintError.lengthOverflow(requested: ll, max: maxLengthDots)
        }
        
        return newzpl
    }
    public init(){}
}
