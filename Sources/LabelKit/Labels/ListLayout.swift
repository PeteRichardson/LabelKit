//
//  ListLayout.swift
//  LabelKit
//

import Foundation

/// One row of a list label.
public enum ListLine: Sendable, Equatable {
    /// A section heading, set larger and closer to the left margin.
    case header(String)
    /// An ordinary list entry, set smaller and indented under its header.
    case item(String)
    /// A separator that contributes vertical space but no text.
    case blank
}

/// Lays a sequence of ``ListLine`` values out as a single long label.
///
/// The printer has no notion of a list, so every row's baseline is computed
/// here and emitted as an absolute `^FO` coordinate. The label's `^LL` follows
/// from the final baseline plus ``bottomMargin``.
///
/// Callers supply the text; this type owns the geometry. Parsing text *into*
/// ``ListLine`` values is deliberately not part of it — different producers
/// (piped text, reminder quadrants) group their lines differently.
public struct ListLayout: Sendable {
    public var headerFontSize: Int
    public var itemFontSize: Int
    public var gap: Int
    public var headerIndent: Int
    public var itemIndent: Int
    public var topMargin: Int
    /// Trailing blank media the ZD620 needs to clear its cutter at 300 dpi.
    /// Empirically determined; not a style choice.
    public var bottomMargin: Int
    /// `^PW` override. An explicit value wins; `nil` (the default) derives the
    /// width from the environment's `RenderGeometry` instead, so the emitted
    /// `^PW` agrees with the geometry `makeLabel` publishes for previewers.
    public var printWidthDots: Int?

    public init(
        headerFontSize: Int = 60,
        itemFontSize: Int = 50,
        gap: Int = 20,
        headerIndent: Int = 60,
        itemIndent: Int = 100,
        topMargin: Int = 20,
        bottomMargin: Int = 318,
        printWidthDots: Int? = nil
    ) {
        self.headerFontSize = headerFontSize
        self.itemFontSize = itemFontSize
        self.gap = gap
        self.headerIndent = headerIndent
        self.itemIndent = itemIndent
        self.topMargin = topMargin
        self.bottomMargin = bottomMargin
        self.printWidthDots = printWidthDots
    }

    /// Builds a label listing `lines`, and publishes the computed length on the
    /// returned label's geometry so previewers and targets agree on its size.
    public func makeLabel(_ lines: [ListLine], environment: ZPLEnvironment) -> ZPLLabel {
        var y = topMargin
        var rows: [String] = []

        for line in lines {
            switch line {
            case .header(let text):
                y += headerFontSize + gap
                // Headers are the only rows that deviate from the ^CF default,
                // so they alone carry a font command. ^A applies to its own
                // field only; the next item falls back to ^CF.
                rows.append("^A0N,\(headerFontSize),\(headerFontSize)"
                            + "^FO\(headerIndent),\(y)^FH^FD\(Self.escaped(text))^FS")
            case .item(let text):
                y += itemFontSize + gap
                rows.append("^FO\(itemIndent),\(y)^FH^FD\(Self.escaped(text))^FS")
            case .blank:
                y += (itemFontSize + gap) / 2
            }
        }

        // y is the last baseline; the cutter needs clearance past it.
        let length = y + bottomMargin
        let body = rows.joined(separator: "\n")
        let width = printWidthDots ?? environment.options.geometry.widthDots ?? 1200

        // ^LH/^LS persist in printer configuration between jobs, so zero them
        // explicitly rather than inheriting whatever the last job left behind.
        // ^CI28 selects UTF-8; without it any non-ASCII input prints as garbage.
        // ^CF sets the item font once, so ordinary rows need no ^A of their own.
        let zpl = "^XA^CI28^PW\(width)^LH0,0^LS0"
            + "^CF0,\(itemFontSize),\(itemFontSize)^LL\(length)\(body)^XZ"

        var environment = environment
        environment.options.geometry.heightDots = length
        return ZPLLabel(zpl, processors: [], environment: environment)
    }

    /// Hex-escapes the characters that a `^FH` field cannot carry literally.
    ///
    /// List text is arbitrary user input, so a stray `^` or `~` would otherwise
    /// be parsed as the start of a command rather than printed. Emitting them
    /// as `_5E`/`_7E` under `^FH` prints the real character instead of dropping
    /// it, so the user's text survives intact.
    ///
    /// `_` is the `^FH` escape introducer itself and so must escape to `_5F`;
    /// left alone it would silently swallow the next two characters.
    ///
    /// Escaping is per-`Character`, so multi-byte UTF-8 passes through
    /// untouched for the `^CI28` printer to decode.
    private static func escaped(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "^": out += "_5E"
            case "~": out += "_7E"
            case "_": out += "_5F"
            default:  out.append(character)
            }
        }
        return out
    }
}
