//
//  InjectLength.swift
//  LabelKit
//
//  Created by Peter Richardson on 9/19/25.
//

import Foundation

// MARK: - InjectLength
// TODO: remove need for explicit <<LL_MARKER>> in source

/// ZPLProcessor that injects an ^LL command with the estimated length of the label content
/// It uses ZPLLengthEstimator, and currently relies on an artificial sentinal <<LL_MARKER>>
/// in the ZPL.  That requirement will be removed in a future version
/// If an ^LL command already exists, it will be updated with the estimate if the estimate
/// is larger.
public struct InjectLength: ZPLProcessor {
    public func process(_ input: String, env: ZPLEnvironment) throws -> String {
        let device = env.options.device
        let ll = ZPLLengthEstimator.estimate(input)
        let newzpl: String
        if !input.contains("^LL") {
            newzpl = input.replacingOccurrences(of: "^XA",
                                                with: "^XA\n^LL\(ll+150)")
        } else {
            newzpl = input.replacingOccurrences(of: "\\^LL\\d+", with: "^LL\(ll+150)",
                                                options: .regularExpression)
        }
        
        guard ll <= device.maxLengthDots else {
            throw PrintError.lengthOverflow(requested: ll, max: device.maxLengthDots)
        }
        return newzpl
    }
    public init(){}
}
