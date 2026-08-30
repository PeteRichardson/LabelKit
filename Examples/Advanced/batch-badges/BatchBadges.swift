//
//  BatchBadges.swift
//  batch-badges
//
//  One template + a CSV -> one label per row.
//

import Foundation
import LabelKit
import ArgumentParser

@main
struct BatchBadges: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "batch-badges",
        abstract: "Render one badge label per row of a CSV, from a single template",
        discussion: """
            Shows the payoff of keeping layout in a template and data outside it: \
            the template is written once and rendered N times with different \
            values, rather than building N labels by string concatenation.
            """
    )

    @Option(name: .long, help: "CSV file with a header row (default: the bundled sample)")
    var csv: String?

    @Option(name: .long, help: "Template name in the store")
    var template: String = "badge"

    func run() async throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // batch-badges/
            .deletingLastPathComponent()   // Advanced/
            .deletingLastPathComponent()   // Examples/
            .deletingLastPathComponent()   // package root

        let resources = packageRoot.appendingPathComponent("Examples/Resources")
        let csvURL = csv.map { URL(fileURLWithPath: $0) }
            ?? resources.appendingPathComponent("badges.csv")

        let store = StencilTemplateStore(
            fileURL: resources.appendingPathComponent("templates.json"))
        try store.load()

        let rows = try parseCSV(String(contentsOf: csvURL, encoding: .utf8))
        guard !rows.isEmpty else {
            throw ValidationError("No data rows in \(csvURL.lastPathComponent).")
        }

        for row in rows {
            print(try store.render(name: template, context: row))
        }
    }

    /// Minimal comma-splitting CSV reader: a header row names the template
    /// variables, and each later row supplies their values. Deliberately does
    /// not handle quoted fields or embedded commas — that is not the lesson.
    func parseCSV(_ text: String) throws -> [[String: String]] {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard let header = lines.first else { return [] }
        let keys = header.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        var seenKeys = Set<String>()
        for key in keys where !seenKeys.insert(key).inserted {
            throw ValidationError("Duplicate column '\(key)' in CSV header.")
        }

        return try lines.dropFirst().enumerated().map { index, line in
            let values = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard values.count == keys.count else {
                // +2: 1-based, plus the header row itself.
                throw ValidationError(
                    "Row \(index + 2) has \(values.count) field(s), expected \(keys.count) to match the header.")
            }
            return Dictionary(uniqueKeysWithValues: zip(keys, values))
        }
    }
}
