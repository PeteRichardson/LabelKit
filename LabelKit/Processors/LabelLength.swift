//
//  LabelLength.swift
//  LabelKit
//
//  Created by Peter Richardson on 8/30/25.
//

import Foundation

/// Estimates the label length (in dots) by parsing a subset of ZPL.
/// Strategy: walk commands, track current field origin (x,y), current font height,
/// and update `maxBottom` whenever we see something that occupies vertical space:
/// - Text (^FD ... ^FS) -> lines * (fontHeight + lineGap)
/// - Barcode (^BC) -> barcodeHeight (if provided) else a default
/// - Box/line (^GB) -> uses its height parameter
/// Also captures ^LL (explicit length) and returns max(computed, LL).
public struct ZPLLengthEstimator {
    public struct Config {
        var defaultFontHeight: Int  // dots, if no ^A has been set
        var defaultLineGap: Int  // dots between lines
        var defaultBarcodeHeight: Int  // dots if ^BC height omitted
        
        public init(defaultFontHeight: Int = 30,
                    defaultLineGap: Int = 2,
                    defaultBarcodeHeight: Int = 100) {
            self.defaultFontHeight = defaultFontHeight
            self.defaultLineGap = defaultLineGap
            self.defaultBarcodeHeight = defaultBarcodeHeight
        }
    }

    public let zpl: String
    public let cfg: Config

    public init(zpl: String, config: Config = .init()) {
        self.zpl = zpl
        self.cfg = config
    }

    /// Public API: returns estimated label height in dots.
    public func estimateHeightDots() -> Int {
        var state = ParserState(config: cfg)
        let tokens = tokenize(zpl)

        var i = 0
        while i < tokens.count {
            let t = tokens[i]

            // print("# \(t.name)")

            switch t.name {
            case "LH":  // ^LHx,y
                let (x, y) = parseTwoInts(t.params)
                state.homeX = x ?? 0
                state.homeY = y ?? 0

            case "FO":  // ^FOx,y
                let (x, y) = parseTwoInts(t.params)
                state.fieldX = (x ?? 0) + state.homeX
                state.fieldY = (y ?? 0) + state.homeY

            case "A":  // ^A[f][o],[h],[w]  We mostly care about height
                // Accept variants like ^ADN,30,30 or ^A0N,30,30 or ^A30,30
                let parsedHeight = parseA(params: t.params)
                if let h = parsedHeight {
                    state.fontHeight = h
                }

            case "CF":  // ^CFf,h,w  OR ^CF,h,w  OR ^CFf
                let cf = parseCF(t.params)
                // if a height was provided, update defaults and current
                if let h = cf.height {
                    state.defaultFontHeight = h
                    state.fontHeight = h
                }

            case "BC":  // ^BCo,h,f,g,m (we care about h)
                // Height is param #2 (after optional orientation)
                let barcodeHeight = parseBCHeight(t.params) ?? cfg.defaultBarcodeHeight
                let bottom = state.fieldY + barcodeHeight
                state.maxBottom = max(state.maxBottom, bottom)
                // print("#    BC maxBottom = \(state.maxBottom)")

            case "GB":  // ^GBw,h,t,c,r  -> use h
                if let h = parseGBHeight(t.params) {
                    let bottom = state.fieldY + h
                    state.maxBottom = max(state.maxBottom, bottom)
                    // print("#    GB maxBottom = \(state.maxBottom)")
                }

            case "LL":  // explicit label length in dots
                if let n = parseInt(t.params) {
                    // print("Inside the LL parser.  explicitLL = max(\(state.explicitLL), \(n))")
                    state.explicitLL = max(state.explicitLL, n)
                }

            case "FD":  // ^FD ... ^FS captured as a single token by tokenizer
                // Count lines: \& starts a new line in ZPL, plus actual newlines if present.
                let (lines, tallestLine) = measureFDText(
                    t.params, fontHeight: state.fontHeight, lineGap: cfg.defaultLineGap)
                let contentHeight =
                    (lines == 0
                        ? 0 : (lines * tallestLine + (max(0, lines - 1) * cfg.defaultLineGap)))
                let bottom = state.fieldY + contentHeight
                state.maxBottom = max(state.maxBottom, bottom)
                // print(
                //     "#    FD state.fieldY, bottom, maxBottom = \(state.fieldY),\(bottom),\(state.maxBottom)"
                // )

            default:
                break
            }

            i += 1
        }

        // Final answer: be generous and obey whichever is larger.
        // print("returning max(\(state.maxBottom), \(state.explicitLL))")
        return max(state.maxBottom, state.explicitLL)
    }
}

// MARK: - Internal Types

private struct ParserState {
    var homeX: Int = 0
    var homeY: Int = 0
    var fieldX: Int = 0
    var fieldY: Int = 0

    var defaultFontHeight: Int
    var fontHeight: Int  // “current” in effect

    var maxBottom: Int = 0
    var explicitLL: Int = 0

    init(config: ZPLLengthEstimator.Config) {
        self.defaultFontHeight = config.defaultFontHeight
        self.fontHeight = config.defaultFontHeight
    }
}

// MARK: - Tokenizer
// We need special handling so ^FD captures until the *matching* ^FS.

private struct Token {
    let name: String  // e.g. "FO", "FD", "A", "A@", "BC", "B3", "LL", "LH"
    let params: String  // raw parameter payload (for FD it's the literal text)
}

private func tokenize(_ zpl: String) -> [Token] {
    var tokens: [Token] = []
    let scalars = Array(zpl.unicodeScalars)
    var i = 0
    let n = scalars.count

    func isCommandStart(_ s: UnicodeScalar) -> Bool { s == "^" || s == "~" }

    func readMnemonic(from start: Int) -> (name: String, next: Int) {
        var j = start
        guard j < n else { return ("", start) }
        let c1 = scalars[j]
        j += 1
        var name = String(c1)

        // Special cases:
        // ^A  -> "A" (single-letter mnemonic)
        // ^A@ -> "A@" (downloadable font variant)
        if name == "A" {
            if j < n, String(scalars[j]) == "@" {
                name.append("@")
                j += 1
            }
            return (name, j)
        }

        // Most others are 2-char mnemonics (letter+letter or letter+digit)
        if j < n {
            let c2 = scalars[j]
            if CharacterSet.alphanumerics.contains(c2) {
                name.append(String(c2))
                j += 1
            }
        }
        return (name, j)
    }

    func readParams(untilNextCommandFrom start: Int) -> (String, Int) {
        var j = start
        var out = ""
        while j < n {
            let c = scalars[j]
            if isCommandStart(c) { break }
            out.unicodeScalars.append(c)
            j += 1
        }
        return (out.trimmingCharacters(in: .whitespacesAndNewlines), j)
    }

    while i < n {
        let c = scalars[i]

        guard isCommandStart(c) else {
            i += 1
            continue
        }
        // Skip '^' or '~'
        let afterSigil = i + 1
        let (name, afterName) = readMnemonic(from: afterSigil)

        // ^FD ... ^FS needs special capture
        if name == "FD" {
            var j = afterName
            var payload = ""
            // scan until we find the next ^FS (exact mnemonic)
            while j < n {
                if scalars[j] == "^" {
                    let (maybe, next) = readMnemonic(from: j + 1)
                    if maybe == "FS" {
                        tokens.append(Token(name: "FD", params: payload))
                        i = next  // position after ^FS
                        break
                    } else {
                        // Not FS -> treat '^' as part of content only if escaped via ^FH (user responsibility).
                        // Keep it literal inside FD so previews don't break unexpectedly.
                        payload.unicodeScalars.append("^")
                        j += 1
                        continue
                    }
                } else {
                    payload.unicodeScalars.append(scalars[j])
                    j += 1
                }
                if j >= n {
                    // Unclosed ^FD; emit what we have
                    tokens.append(Token(name: "FD", params: payload))
                    i = j
                    break
                }
            }
            if j < n { continue } else { break }
        }

        // Normal command: read params until next '^' or '~'
        let (params, next) = readParams(untilNextCommandFrom: afterName)
        tokens.append(Token(name: name, params: params))
        i = next
    }

    return tokens
}

// MARK: - Parsers for specific commands

/// Parses strings like "50,100" -> (50, 100)
private func parseTwoInts(_ s: String) -> (Int?, Int?) {
    let parts = s.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false)
    func toInt(_ sub: Substring) -> Int? {
        Int(sub.trimmingCharacters(in: .whitespaces))
    }
    if parts.count >= 2 {
        return (toInt(parts[0]), toInt(parts[1]))
    } else if parts.count == 1 {
        return (toInt(parts[0]), nil)
    } else {
        return (nil, nil)
    }
}

private func parseInt(_ s: String) -> Int? {
    Int(s.trimmingCharacters(in: .whitespaces))
}

/// Accepts variants of ^A like:
///  - "DN,30,30"  => height 30
///  - "0N,30,30"  => height 30
///  - "30,20"     => height 30
/// Returns height if found.
private func parseA(params: String) -> Int? {
    // Grab the first two comma-separated numbers (if any), treating the first numeric as height.
    // We ignore rotation/orientation and font selection here.
    // Examples:
    //   "DN,30,30"   -> height=30
    //   "0N,30,30"   -> height=30
    //   "30,20"      -> height=30
    let parts = params.split(separator: ",", omittingEmptySubsequences: false)
    // Search for the first numeric field
    for p in parts {
        if let n = Int(p.trimmingCharacters(in: .whitespaces)) {
            return n
        }
    }
    return nil
}

/// ^BC parameters: o,h,f,g,m  (height is the second parameter if present)
private func parseBCHeight(_ params: String) -> Int? {
    let parts = params.split(separator: ",", omittingEmptySubsequences: false).map {
        $0.trimmingCharacters(in: .whitespaces)
    }
    // If the first part is a single letter (orientation), height may be in parts[1].
    if parts.isEmpty { return nil }
    if parts[0].count == 1 || parts[0].isEmpty {
        if parts.count >= 2, let h = Int(parts[1]) { return h }
    } else {
        // No orientation given; first part might be height
        if let h = Int(parts[0]) { return h }
    }
    return nil
}

private func parseCF(_ params: String) -> (font: String?, height: Int?, width: Int?) {
    // Forms:
    //   "D,30,20"  -> font D, h=30, w=20
    //   ",30,20"   -> h=30, w=20 (font unchanged)
    //   "D"        -> font D only
    //   ""         -> no-op
    let raw = params.trimmingCharacters(in: .whitespaces)
    if raw.isEmpty { return (nil, nil, nil) }

    let parts = raw.split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }

    var font: String? = nil
    var height: Int? = nil
    var width: Int? = nil

    switch parts.count {
    case 1:
        // Either "D" (font only) or "30" (height only – uncommon but allow it)
        if let n = Int(parts[0]) {
            height = n
        } else if !parts[0].isEmpty {
            font = parts[0]
        }
    default:
        // 2 or 3 fields: first may be font or empty for “no font change”
        if !parts[0].isEmpty, Int(parts[0]) == nil {
            font = parts[0]
            if parts.count >= 2, let h = Int(parts[1]) { height = h }
            if parts.count >= 3, let w = Int(parts[2]) { width = w }
        } else {
            // Starts with comma (no font specified) or a number
            if parts.count >= 1, let h = Int(parts[0]) { height = h }
            if parts.count >= 2, let w = Int(parts[1]) { width = w }
        }
    }
    return (font, height, width)
}

/// ^GBw,h,t,c,r -> return h
private func parseGBHeight(_ params: String) -> Int? {
    let parts = params.split(separator: ",", omittingEmptySubsequences: false).map {
        $0.trimmingCharacters(in: .whitespaces)
    }
    if parts.count >= 2, let h = Int(parts[1]) { return h }
    return nil
}

/// Measure text payload for ^FD (already isolated until ^FS)
/// We treat "\&" as newline, as well as literal newlines.
/// Returns (lineCount, per-line-height)
private func measureFDText(_ payload: String, fontHeight: Int, lineGap: Int) -> (Int, Int) {
    // Split on \& (ZPL newline in ^FD) and also on actual '\n'
    let replaced = payload.replacingOccurrences(of: "\\&", with: "\n")
    let lines = replaced.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    let count = max(1, lines.count)  // consider at least one line even if empty
    return (count, fontHeight)
}
