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
                rows.append("^A0N,\(headerFontSize),\(headerFontSize)"
                            + "^FO\(headerIndent),\(y)^FD\(Self.sanitized(text))^FS")
            case .item(let text):
                y += itemFontSize + gap
                rows.append("^A0N,\(itemFontSize),\(itemFontSize)"
                            + "^FO\(itemIndent),\(y)^FD\(Self.sanitized(text))^FS")
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
        let zpl = "^XA^PW\(width)^LH0,0^LS0^LL\(length)\(body)^XZ"

        var environment = environment
        environment.options.geometry.heightDots = length
        return ZPLLabel(zpl, processors: [], environment: environment)
    }

    /// Removes the two characters ZPL treats as command introducers.
    ///
    /// List text is arbitrary user input, so a stray `^` or `~` would otherwise
    /// be parsed as the start of a command rather than printed.
    private static func sanitized(_ text: String) -> String {
        text.filter { $0 != "^" && $0 != "~" }
    }
}
