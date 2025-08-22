//
//  ZPLFormatter.swift
//  LabelKit
//
//  Created by Peter Richardson on 8/22/25.
//

import Foundation

public enum ZPLFormatter {
    /// Pretty-prints ZPL:
    /// - one command per line
    /// - preserves everything between ^FD ... ^FS
    /// - strips stray spaces around commas/numbers for other commands
    public static func prettyPrint(_ zpl: String) -> String {
        format(zpl, pretty: true)
    }

    /// Minifies ZPL:
    /// - removes all non-essential whitespace outside ^FD ... ^FS
    /// - outputs a single line unless ^FD blocks are present (those stay compact as "^FD...^FS")
    public static func minify(_ zpl: String) -> String {
        format(zpl, pretty: false)
    }

    // MARK: - Implementation

    private static func format(_ input: String, pretty: Bool) -> String {
        let s = input.replacingOccurrences(of: "\r\n", with: "\n")
        var i = s.startIndex
        var lines: [String] = []

        func peekIsCommandStart(_ idx: String.Index) -> Bool {
            guard idx < s.endIndex else { return false }
            let ch = s[idx]
            return ch == "^" || ch == "~"
        }

        while i < s.endIndex {
            // skip non-command whitespace
            if s[i].isWhitespace {
                i = s.index(after: i)
                continue
            }

            guard peekIsCommandStart(i) else {
                // If we find junk outside commands, consume until next command start.
                if let next = s[i...].firstIndex(where: { $0 == "^" || $0 == "~" }) {
                    i = next
                    continue
                } else {
                    break
                }
            }

            let sig = s[i]  // '^' or '~'
            i = s.index(after: i)

            // Read command code (A–Z, 1–2 chars commonly; accept up to 3 to be safe)
            var code = ""
            var j = i
            while j < s.endIndex, s[j].isUppercaseLetter, code.count < 3 {
                code.append(s[j]); j = s.index(after: j)
            }
            // No code? skip
            if code.isEmpty {
                i = j
                continue
            }
            i = j

            if code == "FD" {
                // Capture until ^FS (don’t consume content whitespace)
                // Find the literal sequence "^FS"
                let searchRange = i..<s.endIndex
                if let fsStart = s.range(of: "^FS", options: [], range: searchRange) {
                    let content = String(s[i..<fsStart.lowerBound])
                    // consume to just after ^FS
                    i = fsStart.upperBound
                    let line = "\(sig)\(code)\(content)^FS"
                    lines.append(pretty ? line.trimmingCharacters(in: .whitespacesAndNewlines) : compactOutsideFD(line))
                } else {
                    // No terminator; treat rest as FD content
                    let content = String(s[i..<s.endIndex])
                    i = s.endIndex
                    let line = "\(sig)\(code)\(content)"
                    lines.append(pretty ? line.trimmingCharacters(in: .whitespacesAndNewlines) : compactOutsideFD(line))
                }
                continue
            }

            // For non-FD commands, capture until next command start
            let nextIdx = s[i...].firstIndex(where: { $0 == "^" || $0 == "~" }) ?? s.endIndex
            var params = String(s[i..<nextIdx])
            i = nextIdx

            // Normalize parameters: strip outer whitespace, collapse spaces around commas
            if pretty {
                params = normalizeParams(params)
                lines.append("\(sig)\(code)\(params)")
            } else {
                params = compactParams(params)
                lines.append("\(sig)\(code)\(params)")
            }
        }

        if pretty {
            // Keep ^XA at top and ^XZ at bottom if they exist; otherwise just join with \n
            return lines.joined(separator: "\n")
        } else {
            // Minified: join without newlines
            return lines.joined()
        }
    }

    private static func normalizeParams(_ p: String) -> String {
        // Trim ends
        var s = p.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove spaces around commas
        s = s.replacingOccurrences(of: #"\s*,\s*"#, with: ",", options: .regularExpression)
        // Collapse internal whitespace runs to single space (rarely needed)
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return s
    }

    private static func compactParams(_ p: String) -> String {
        var s = p
        // Remove all whitespace outside commas
        s = s.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        return s
    }

    /// For lines like "^FD...^FS", ensure no accidental newlines around tokens
    private static func compactOutsideFD(_ line: String) -> String {
        // The FD content is everything between "^FD" and "^FS" and may contain spaces/newlines deliberately.
        // Here we only trim at the edges.
        return line
            .replacingOccurrences(of: #"^\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
    }
}

// Small helpers
private extension Character {
    var isUppercaseLetter: Bool { ("A"..."Z").contains(self) }
}
