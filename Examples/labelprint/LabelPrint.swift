//
//  LabelPrint.swift
//  labelprint
//
//  Reads lines of text on stdin and prints them as a single long list label.
//

import Foundation
import LabelKit
import ArgumentParser
import OSLog

fileprivate let logger = Logger(subsystem: "com.example.labelprint", category: "printing")

/// Printer connection options.
///
/// Resolution order is flag → environment variable → ``PrinterDefaults``.
struct PrinterOptions: ParsableArguments {
    @Option(name: .long, help: "Printer hostname or IP address (env: LABELKIT_PRINTER_HOST)")
    var host: String = ProcessInfo.processInfo.environment["LABELKIT_PRINTER_HOST"] ?? PrinterDefaults.host

    @Option(name: .long, help: "Printer TCP port (env: LABELKIT_PRINTER_PORT)")
    var port: UInt16 = ProcessInfo.processInfo.environment["LABELKIT_PRINTER_PORT"].flatMap(UInt16.init) ?? PrinterDefaults.port
}

/// Classifies raw input lines, dropping the trailing blanks a text file usually
/// ends with.
///
/// A line ending in `:` is a section header. This is the convention producers
/// pipe against, which is why it lives here rather than in LabelKit.
func parseLines(_ text: String) -> [ListLine] {
    var lines = text
        .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        .map { line -> ListLine in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return .blank }
            if trimmed.hasSuffix(":") { return .header(trimmed) }
            return .item(trimmed)
        }

    while lines.last == .blank {
        lines.removeLast()
    }
    return lines
}

func makeEnvironment() -> ZPLEnvironment {
    ZPLEnvironment(stock: Stock.Preset.label4x, device: Device.Preset.ZD620)
}

/// Reads all of stdin and classifies it, failing if nothing was piped in.
func readLinesFromStdin() throws -> [ListLine] {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    let lines = parseLines(String(decoding: data, as: UTF8.self))
    guard !lines.isEmpty else {
        throw ValidationError("No input on stdin. Pipe a file, e.g. `cat list.txt | labelprint`.")
    }
    return lines
}

@main
struct LabelPrint: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "labelprint",
        abstract: "Print lines of text from stdin as a long list label",
        subcommands: [Print.self, Preview.self, Zpl.self, List.self],
        defaultSubcommand: Print.self
    )
}

struct Print: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print list to network printer (defaults to \(PrinterDefaults.host):\(PrinterDefaults.port))"
    )

    @OptionGroup var printer: PrinterOptions

    @Flag(name: .shortAndLong, help: "Enable debug logging to Console")
    var debug: Bool = false

    func run() async throws {
        let lines = try readLinesFromStdin()
        if debug { logger.info("Read \(lines.count) line(s); printing to \(printer.host):\(printer.port)") }

        let label = ListLayout().makeLabel(lines, environment: makeEnvironment())
        let target = NetworkTarget(device: label.environment.options.device,
                                   host: printer.host, port: printer.port)
        try await label.print(to: target)
    }
}

struct Preview: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print list as a png preview to stdout (requires iterm2 image support)"
    )

    @Flag(name: .shortAndLong, help: "Enable debug logging to Console")
    var debug: Bool = false

    func run() async throws {
        let lines = try readLinesFromStdin()
        if debug { logger.info("Read \(lines.count) line(s); rendering preview") }

        let label = ListLayout().makeLabel(lines, environment: makeEnvironment())
        let target = ITerm2Target(device: label.environment.options.device)
        // Labelary, not the bundled zpl2png helper: ListLayout emits ^FB blocks,
        // which zpl2png does not implement — it renders only the first line of a
        // block and silently drops the rest. Labelary matches the ZD620.
        try await label.preview(using: LabelaryRenderer.self, to: target,
                                timeout: 2.0, fallbackHeightDots: 500)
    }
}

struct Zpl: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print ZPL for the list to stdout"
    )

    @Flag(name: .shortAndLong, help: "Enable debug logging to Console")
    var debug: Bool = false

    func run() async throws {
        let lines = try readLinesFromStdin()
        if debug { logger.info("Read \(lines.count) line(s); emitting ZPL") }

        let label = ListLayout().makeLabel(lines, environment: makeEnvironment())
        print(try label.zpl())
    }
}

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Echo the parsed lines as text, to debug header and blank detection"
    )

    func run() async throws {
        for line in try readLinesFromStdin() {
            switch line {
            case .header(let text): print("HEADER  \(text)")
            case .item(let text):   print("ITEM    \(text)")
            case .blank:            print("BLANK")
            }
        }
    }
}
