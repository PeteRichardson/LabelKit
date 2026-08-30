//
//  ListLabel.swift
//  LabelKit
//
//  Reads lines of text on stdin and prints them as a single long list label.
//

import Foundation
import LabelKit
import ArgumentParser
import OSLog

// Logger for the ListLabel tool
fileprivate let logger = Logger(subsystem: "com.example.listlabel", category: "printing")

/// Printer connection options.
///
/// Resolution order is flag → environment variable → ``PrinterDefaults``, so the
/// example printer stays the default when nothing is supplied.
struct PrinterOptions: ParsableArguments {
    @Option(name: .long, help: "Printer hostname or IP address (env: LABELKIT_PRINTER_HOST)")
    var host: String = ProcessInfo.processInfo.environment["LABELKIT_PRINTER_HOST"] ?? PrinterDefaults.host

    @Option(name: .long, help: "Printer TCP port (env: LABELKIT_PRINTER_PORT)")
    var port: UInt16 = ProcessInfo.processInfo.environment["LABELKIT_PRINTER_PORT"].flatMap(UInt16.init) ?? PrinterDefaults.port
}

/// One line of input, classified by how it should be laid out on the label.
enum ListLine: Equatable {
    /// A section header — a non-empty line ending in `:`, set larger and flush left.
    case header(String)
    /// An ordinary list item, set smaller and indented under its header.
    case item(String)
    /// A blank separator line, which contributes vertical space but no text.
    case blank
}

/// Classifies raw input lines, dropping the trailing blanks a text file usually ends with.
///
/// - Parameter text: The full contents of stdin.
/// - Returns: One ``ListLine`` per input line, with trailing blanks removed so a
///   file ending in newlines doesn't stretch the label.
func parseLines(_ text: String) -> [ListLine] {
    var lines = text
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { line -> ListLine in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return .blank }
            if trimmed.hasSuffix(":") { return .header(trimmed) }
            return .item(trimmed)
        }

    while lines.last == .blank {
        lines.removeLast()
    }
    return lines
}

/// Removes the characters ZPL treats as command introducers.
///
/// Input arrives from stdin, so a stray `^` or `~` would otherwise be parsed as
/// the start of a ZPL command rather than printed as text.
func sanitize(_ text: String) -> String {
    text.filter { $0 != "^" && $0 != "~" }
}

/// Builds a single long label listing every parsed line.
///
/// Headers are set at ``headerFontSize`` flush against the left margin; items are
/// set at ``itemFontSize`` and indented beneath them; blank lines advance the
/// cursor by a half gap. The label's `^LL` is computed from the final cursor
/// position plus the bottom margin the cutter needs.
func generate_label(lines: [ListLine]) -> ZPLLabel {
    let headerFontSize = 60
    let itemFontSize = 50
    let gap = 20

    let headerIndent = 60
    let itemIndent = 100

    let topMargin = 20          // space before first line
    let bottomMargin = 318      // empirically needed for ZD620 + cutter @ 300 dpi

    var y = topMargin

    let rows = lines.compactMap { line -> String? in
        switch line {
        case .header(let text):
            y += headerFontSize + gap
            return "^A0N,\(headerFontSize),\(headerFontSize)^FO\(headerIndent),\(y)^FD\(sanitize(text))^FS"
        case .item(let text):
            y += itemFontSize + gap
            return "^A0N,\(itemFontSize),\(itemFontSize)^FO\(itemIndent),\(y)^FD\(sanitize(text))^FS"
        case .blank:
            y += (itemFontSize + gap) / 2
            return nil
        }
    }
    .joined(separator: "\n")

    // y now holds the baseline of the last line
    let length = y + bottomMargin   // label length in dots

    let header = "^PW1200^LH0,0^LS0"

    let zpl = "^XA\(header)^LL\(length)\(rows)^XZ"

    var zplenv = ZPLEnvironment(stock: Stock.Preset.label4x,
                                device: Device.Preset.ZD620)
    zplenv.options.geometry.heightDots = length

    let label = ZPLLabel(
        zpl,
        processors: [],
        environment: zplenv
    )
    return label
}

/// Reads all of stdin and classifies it, failing if nothing was piped in.
func readLinesFromStdin() throws -> [ListLine] {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    let text = String(decoding: data, as: UTF8.self)
    let lines = parseLines(text)
    guard !lines.isEmpty else {
        throw ValidationError("No input on stdin. Pipe a file, e.g. `cat list.txt | example-listlabel`.")
    }
    return lines
}

@main
struct ListLabel: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "example-listlabel",
        abstract: "Print lines of text from stdin as a long list label",
        subcommands: [Print.self, Preview.self, Zpl.self],
        defaultSubcommand: Print.self
    )
}

struct Print: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print list to network printer (defaults to \(PrinterDefaults.host):\(PrinterDefaults.port))",
    )

    @OptionGroup var printer: PrinterOptions

    @Flag(name: .shortAndLong, help: "Enable debug logging to Console")
    var debug: Bool = false

    func run() async throws {
        if debug {
            logger.info("Reading list from stdin")
        }
        let lines = try readLinesFromStdin()
        if debug {
            logger.info("Read \(lines.count) line(s) from stdin")
            logger.info("Generating ZPL label")
        }

        let label = generate_label(lines: lines)
        let zpl = try label.zpl()
        if debug {
            logger.info("Label generated, ZPL length: \(zpl.count) bytes")
            logger.info("Connecting to printer at \(printer.host):\(printer.port)")
        }

        let target = NetworkTarget(device: label.environment.options.device, host: printer.host, port: printer.port)

        if debug {
            logger.info("Sending ZPL payload to printer")
        }
        try await label.print(to: target)

        if debug {
            logger.info("Print command completed successfully")
        }
    }
}

struct Preview: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print list as a png preview to stdout (requires iterm2 image support)",
    )

    @Flag(name: .shortAndLong, help: "Enable debug logging to Console")
    var debug: Bool = false

    func run() async throws {
        if debug {
            logger.info("Reading list from stdin")
        }
        let lines = try readLinesFromStdin()
        if debug {
            logger.info("Read \(lines.count) line(s) from stdin")
            logger.info("Generating ZPL label preview")
        }

        let label = generate_label(lines: lines)
        let target = ITerm2Target(device: label.environment.options.device)
        try await label.preview(using: ZPL2PNGRenderer.self, to: target, timeout: 2.0, fallbackHeightDots: 500)

        if debug {
            logger.info("Preview command completed successfully")
        }
    }
}

struct Zpl: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print ZPL for the list to stdout",
    )

    @Flag(name: .shortAndLong, help: "Enable debug logging to Console")
    var debug: Bool = false

    func run() async throws {
        if debug {
            logger.info("Reading list from stdin")
        }
        let lines = try readLinesFromStdin()
        if debug {
            logger.info("Read \(lines.count) line(s) from stdin")
            logger.info("Generating ZPL label")
        }

        let label = generate_label(lines: lines)
        let zpl = try label.zpl()
        if debug {
            logger.info("Label generated, ZPL length: \(zpl.count) bytes")
        }

        print(zpl)
    }
}
