# LabelKit Examples Reorganization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize LabelKit's ad-hoc examples into three tiers (compiled tutorial snippets, installable tools, advanced demos), promoting the duplicated list-layout logic into the library where it can finally be tested.

**Architecture:** Layout (`[ListLine]` → `ZPLLabel`) moves into LabelKit because it gains a second consumer (`t`); text parsing stays in the `labelprint` example because it has only one. Tutorials become SwiftPM `Snippets/`, which compile on every build so they cannot rot. CI is added because that compile-checking is the entire justification for snippets and nothing currently runs `swift build`.

**Tech Stack:** Swift 6, SwiftPM, Swift Testing (`import Testing`, `@Suite`/`@Test` — not XCTest), ArgumentParser, Stencil, GitHub Actions.

**Spec:** `docs/specs/2026-08-30-examples-reorganization-design.md`

## Global Constraints

- Swift tools version 6.0; platform floor `.macOS(.v14)`. Do not change either.
- Tests use Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`). Never XCTest.
- An example must not add a dependency, entitlement, or permission prompt that LabelKit itself does not need.
- Tier 2 tools must run on a fresh clone with zero setup (no Application Support state).
- Tier 1 snippets take no command-line flags and must fit on one screen.
- Tier 2 product names drop the `example-` prefix. Tier 1 snippet executables are named by their filename.
- `Workspace/Build/` and `Apps/LabelGUI/Build/` are derived artifacts — never edit or search them.
- Do not send anything to the physical printer during implementation.

## Scope

This plan covers the **LabelKit repo only** — spec steps 1, 2, 3, 4, 6, 7.

Spec step 5 (extracting `Reminders.swift` into a new `reminders` repo) is a
separate subsystem in a different repo with a different dependency (EventKit)
and no shared code. It gets its own plan. **Task 8 here deletes
`example-reminderlist`, so the extraction plan must be executed first** — or
Task 8 deferred until it is.

## Prerequisites

The working tree currently has uncommitted work from an earlier session: an
untracked `Examples/ListLabel/` plus modifications to `Package.swift`,
`README.md`, and `AGENTS.md`. Task 4 transforms that code into `labelprint`.
Commit it first so Task 4's diff is meaningful:

```bash
git add Examples/ListLabel Package.swift README.md AGENTS.md
git commit -m "feat(examples): add example-listlabel for printing stdin as a list label"
```

## File Structure

| File | Responsibility |
|---|---|
| `.github/workflows/ci.yml` | Build + test on every push/PR |
| `Sources/LabelKit/Labels/ListLayout.swift` | `ListLine`, `ListLayout` — lines to ZPL. New public API. |
| `Tests/LabelKitTests/ListLayoutTests.swift` | Layout unit tests |
| `Sources/LabelKit/Processors/StencilTemplates.swift` | Gains `init(fileURL:)` |
| `Examples/Resources/templates.json` | Seed templates, checked in |
| `Examples/labelprint/LabelPrint.swift` | Tier 2 CLI. Parsing + subcommands. **Not** named `main.swift`. |
| `Tests/LabelPrintTests/ParseLinesTests.swift` | Parser tests |
| `Snippets/*.swift` | Tier 1 tutorials |
| `Examples/Advanced/compare-renderers/CompareRenderers.swift` | Tier 3 renderer diff |
| `Examples/Advanced/batch-badges/BatchBadges.swift` | Tier 3 template batch |

---

### Task 1: Add CI

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: nothing
- Produces: a CI job that runs `swift build` (which compiles `Snippets/`) and `swift test`. Every later task depends on this to enforce that snippets cannot rot.

Verified facts that make this safe: `Sources/LabelKit/Helpers/zpl2png` is a
universal binary (x86_64 + arm64), so it runs on any GitHub macOS runner; and
the Labelary tests use an in-process `StubURLProtocol` rather than real network
calls, so the suite does not need internet.

- [ ] **Step 1: Create the workflow**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  build-and-test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Show toolchain
        run: swift --version

      # Builds the library, the example executables, and every file in
      # Snippets/. A tutorial referencing a renamed API fails here.
      - name: Build
        run: swift build

      - name: Test
        run: swift test
```

- [ ] **Step 2: Verify the same commands pass locally**

Run: `swift build && swift test`
Expected: `Build complete!` then a passing run (89 tests at time of writing).

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: build and test on macOS via GitHub Actions"
```

---

### Task 2: Template store file-URL initializer + seed templates

**Files:**
- Modify: `Sources/LabelKit/Processors/StencilTemplates.swift:24`
- Create: `Examples/Resources/templates.json`
- Create: `Tests/LabelKitTests/StencilTemplateStoreTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `public init(fileURL: URL)` on `StencilTemplateStore`, and a checked-in template archive at `Examples/Resources/templates.json` containing a template named `label`. Tasks 5 and 7 consume both.

Why: the store currently exposes only `public init() throws`, which resolves to
Application Support / group-container paths. There is no way to point it at a
file in the repo, so the zero-setup rule cannot be met without this.

- [ ] **Step 1: Write the failing test**

Create `Tests/LabelKitTests/StencilTemplateStoreTests.swift`:

```swift
//
//  StencilTemplateStoreTests.swift
//  LabelKitTests
//

import Foundation
import Testing
@testable import LabelKit

@Suite("StencilTemplateStore file-URL initializer")
struct StencilTemplateStoreTests {

    @Test func loadsTemplatesFromAnExplicitFileURL() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("labelkit-store-\(UUID().uuidString).json")
        let json = #"{"version":1,"templates":{"greeting":"^XA^FD{{ who }}^FS^XZ"}}"#
        try Data(json.utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = StencilTemplateStore(fileURL: tmp)
        try store.load()

        #expect(try store.render(name: "greeting", context: ["who": "world"])
                == "^XA^FDworld^FS^XZ")
    }

    @Test func missingFileLeavesTheStoreEmptyRatherThanThrowing() throws {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("labelkit-absent-\(UUID().uuidString).json")

        let store = StencilTemplateStore(fileURL: missing)
        try store.load()   // documented no-op when the file is absent

        #expect(store.listNames().isEmpty)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter StencilTemplateStoreTests`
Expected: FAIL — compile error, no `init(fileURL:)` member.

- [ ] **Step 3: Add the initializer**

In `Sources/LabelKit/Processors/StencilTemplates.swift`, directly after the
existing `public init() throws` (line 24-27), add:

```swift
    /// Initializes a store backed by an explicit file, bypassing the
    /// Application Support / group-container search performed by `init()`.
    ///
    /// Used by examples and snippets so they read templates checked into the
    /// repository and run on a fresh clone with no user state. Apps that want
    /// the user's own template store should keep using `init()`.
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter StencilTemplateStoreTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Create the seed template archive**

Create `Examples/Resources/templates.json`:

```json
{
  "version": 1,
  "templates": {
    "label": "^XA^PW600^LL354\n^FO10,30^A0N,30,30^FDHeader^FS\n^FO10,80^A0N,24,24^FD{{ line1 }}^FS\n^FO10,120^A0N,24,24^FD{{ line2 }}^FS\n^XZ",
    "badge": "^XA^PW600^LL354\n^FO20,40^A0N,40,40^FD{{ name }}^FS\n^FO20,100^A0N,24,24^FD{{ title }}^FS\n^XZ"
  }
}
```

- [ ] **Step 6: Run the full suite and commit**

Run: `swift test`
Expected: all tests pass.

```bash
git add Sources/LabelKit/Processors/StencilTemplates.swift \
        Tests/LabelKitTests/StencilTemplateStoreTests.swift \
        Examples/Resources/templates.json
git commit -m "feat(templates): add StencilTemplateStore.init(fileURL:) and seed templates

Examples and snippets can now read templates checked into the repo instead of
depending on Application Support state that does not exist on a fresh clone."
```

---

### Task 3: Promote `ListLayout` into the library

**Files:**
- Create: `Sources/LabelKit/Labels/ListLayout.swift`
- Create: `Tests/LabelKitTests/ListLayoutTests.swift`

**Interfaces:**
- Consumes: `ZPLLabel(_:processors:environment:)`, `ZPLEnvironment(stock:device:)`, `ZPLOptions.geometry.heightDots`
- Produces:
  - `public enum ListLine: Sendable, Equatable { case header(String), item(String), blank }`
  - `public struct ListLayout: Sendable` with properties `headerFontSize`, `itemFontSize`, `gap`, `headerIndent`, `itemIndent`, `topMargin`, `bottomMargin`, `printWidthDots`, a memberwise-defaulted `init`, and
    `public func makeLabel(_ lines: [ListLine], environment: ZPLEnvironment) -> ZPLLabel`

  Task 4 (`labelprint`) and the companion `t` work both consume these exact names.

Note: `^`/`~` sanitizing lives here, not in the parser. Emitting valid ZPL from
arbitrary text is layout's job, and putting it here means `t` gets the same
protection for free — reminder titles are arbitrary user text too.

- [ ] **Step 1: Write the failing tests**

Create `Tests/LabelKitTests/ListLayoutTests.swift`:

```swift
//
//  ListLayoutTests.swift
//  LabelKitTests
//

import Testing
@testable import LabelKit

@Suite("ListLayout")
struct ListLayoutTests {

    private var environment: ZPLEnvironment {
        ZPLEnvironment(stock: Stock.Preset.label4x, device: Device.Preset.ZD620)
    }

    @Test func itemUsesItemFontAndIndentAtFirstBaseline() throws {
        let zpl = try ListLayout().makeLabel([.item("eggs")], environment: environment).zpl()
        // topMargin 20 + itemFontSize 50 + gap 20 = 90
        #expect(zpl.contains("^A0N,50,50^FO100,90^FDeggs^FS"))
    }

    @Test func headerUsesHeaderFontAndSmallerIndent() throws {
        let zpl = try ListLayout().makeLabel([.header("Costco:")], environment: environment).zpl()
        // topMargin 20 + headerFontSize 60 + gap 20 = 100
        #expect(zpl.contains("^A0N,60,60^FO60,100^FDCostco:^FS"))
    }

    @Test func blankAdvancesHalfAnItemPitchAndEmitsNothing() throws {
        let zpl = try ListLayout()
            .makeLabel([.item("a"), .blank, .item("b")], environment: environment).zpl()
        // a at 90; blank adds (50+20)/2 = 35 -> 125; b adds 70 -> 195
        #expect(zpl.contains("^FO100,90^FDa^FS"))
        #expect(zpl.contains("^FO100,195^FDb^FS"))
    }

    @Test func labelLengthIsLastBaselinePlusBottomMargin() throws {
        let zpl = try ListLayout().makeLabel([.item("only")], environment: environment).zpl()
        #expect(zpl.contains("^LL408"))   // 90 + 318
    }

    @Test func emptyInputStillProducesAWellFormedLabel() throws {
        let zpl = try ListLayout().makeLabel([], environment: environment).zpl()
        #expect(zpl.hasPrefix("^XA"))
        #expect(zpl.hasSuffix("^XZ"))
        #expect(zpl.contains("^LL338"))   // topMargin 20 + 318
    }

    @Test func commandIntroducersAreStrippedFromText() throws {
        let zpl = try ListLayout()
            .makeLabel([.item("bad^XZand~JAmore")], environment: environment).zpl()
        #expect(zpl.contains("^FDbadXZandJAmore^FS"))
        // Exactly one ^XZ: the label terminator, not one smuggled in via text.
        #expect(zpl.components(separatedBy: "^XZ").count - 1 == 1)
    }

    @Test func computedLengthIsPublishedOnTheEnvironmentGeometry() throws {
        let label = ListLayout().makeLabel([.item("only")], environment: environment)
        #expect(label.environment.options.geometry.heightDots == 408)
    }

    @Test func styleOverridesAreHonored() throws {
        var layout = ListLayout()
        layout.itemFontSize = 30
        layout.gap = 10
        layout.itemIndent = 40
        let zpl = try layout.makeLabel([.item("small")], environment: environment).zpl()
        #expect(zpl.contains("^A0N,30,30^FO40,60^FDsmall^FS"))   // 20 + 30 + 10
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ListLayoutTests`
Expected: FAIL — compile error, `ListLayout` / `ListLine` not found.

- [ ] **Step 3: Write the implementation**

Create `Sources/LabelKit/Labels/ListLayout.swift`:

```swift
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
    public var printWidthDots: Int

    public init(
        headerFontSize: Int = 60,
        itemFontSize: Int = 50,
        gap: Int = 20,
        headerIndent: Int = 60,
        itemIndent: Int = 100,
        topMargin: Int = 20,
        bottomMargin: Int = 318,
        printWidthDots: Int = 1200
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

        // ^LH/^LS persist in printer configuration between jobs, so zero them
        // explicitly rather than inheriting whatever the last job left behind.
        let zpl = "^XA^PW\(printWidthDots)^LH0,0^LS0^LL\(length)\(body)^XZ"

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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ListLayoutTests`
Expected: PASS (8 tests).

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: all pass, no regressions.

- [ ] **Step 6: Commit**

```bash
git add Sources/LabelKit/Labels/ListLayout.swift Tests/LabelKitTests/ListLayoutTests.swift
git commit -m "feat(labels): add ListLayout for rendering line lists as long labels

Promotes layout logic that was duplicated across two examples into the library,
where it is unit-tested for the first time and reusable by outside consumers."
```

---

### Task 4: Convert `example-listlabel` into `labelprint`

**Files:**
- Create: `Examples/labelprint/LabelPrint.swift`
- Create: `Tests/LabelPrintTests/ParseLinesTests.swift`
- Delete: `Examples/ListLabel/ListLabel.swift`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: `ListLine`, `ListLayout.makeLabel(_:environment:)` from Task 3
- Produces: executable product `labelprint`; internal `parseLines(_ text: String) -> [ListLine]`

Verified: a `testTarget` can `@testable import` an executable target with
`@main` on Swift 6/macOS. The source file must **not** be named `main.swift` —
top-level code conflicts with `@main`.

- [ ] **Step 1: Write the failing parser tests**

Create `Tests/LabelPrintTests/ParseLinesTests.swift`:

```swift
//
//  ParseLinesTests.swift
//  LabelPrintTests
//

import Testing
import LabelKit
@testable import labelprint

@Suite("labelprint line parsing")
struct ParseLinesTests {

    @Test func lineEndingInColonBecomesAHeader() {
        #expect(parseLines("Costco:") == [.header("Costco:")])
    }

    @Test func ordinaryLineBecomesAnItem() {
        #expect(parseLines("eggs") == [.item("eggs")])
    }

    @Test func interiorBlankLineIsPreserved() {
        #expect(parseLines("a\n\nb") == [.item("a"), .blank, .item("b")])
    }

    @Test func trailingBlankLinesAreTrimmed() {
        // A text file almost always ends in a newline; that must not stretch
        // the label with empty rows.
        #expect(parseLines("a\n\n\n") == [.item("a")])
    }

    @Test func surroundingWhitespaceIsStripped() {
        #expect(parseLines("   eggs   ") == [.item("eggs")])
        #expect(parseLines("  \t  ") == [])
    }

    @Test func emptyInputYieldsNoLines() {
        #expect(parseLines("") == [])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ParseLinesTests`
Expected: FAIL — no such module `labelprint`.

- [ ] **Step 3: Create the tool**

Create `Examples/labelprint/LabelPrint.swift` (git mv the old file first if you
prefer to preserve history: `git mv Examples/ListLabel/ListLabel.swift Examples/labelprint/LabelPrint.swift`):

```swift
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
        try await label.preview(using: ZPL2PNGRenderer.self, to: target,
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
```

- [ ] **Step 4: Wire up Package.swift**

In `Package.swift`, replace the `example-listlabel` product with:

```swift
        .executable(name: "labelprint", targets: ["labelprint"])
```

replace the `ListLabel` target with:

```swift
        .executableTarget(
            name: "labelprint",
            dependencies: [
                "LabelKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Examples/labelprint"
        ),
        .testTarget(
            name: "LabelPrintTests",
            dependencies: ["labelprint"],
            path: "Tests/LabelPrintTests"
        )
```

- [ ] **Step 5: Remove the old example**

```bash
rm -rf Examples/ListLabel
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter ParseLinesTests`
Expected: PASS (6 tests).

- [ ] **Step 7: Verify the tool end to end**

Run:
```bash
printf 'Costco:\neggs\n\nDraegers:\ncream\n' | swift run labelprint list
```
Expected:
```
HEADER  Costco:
ITEM    eggs
BLANK
HEADER  Draegers:
ITEM    cream
```

Run: `printf 'Costco:\neggs\n' | swift run labelprint zpl`
Expected: one `^XA...^XZ` label containing `^A0N,60,60^FO60,100^FDCostco:^FS`.

Run: `printf '' | swift run labelprint zpl`
Expected: the "No input on stdin" error and a non-zero exit status.

- [ ] **Step 8: Commit**

```bash
git add -A Package.swift Examples Tests/LabelPrintTests
git commit -m "refactor(examples): replace example-listlabel with labelprint

Layout now comes from LabelKit's ListLayout; the tool keeps only stdin parsing.
Drops the example- prefix since Tier 2 tools are meant to be installed."
```

---

### Task 5: Add Tier 1 snippets

**Files:**
- Create: `Snippets/PrintToStdout.swift`, `Snippets/ChooseStockAndDevice.swift`, `Snippets/PrintAList.swift`, `Snippets/RenderATemplate.swift`, `Snippets/PreviewInITerm2.swift`

**Interfaces:**
- Consumes: `ListLayout`/`ListLine` (Task 3), `StencilTemplateStore.init(fileURL:)` and `Examples/Resources/templates.json` (Task 2)
- Produces: nothing consumed by later tasks

SwiftPM auto-discovers a top-level `Snippets/` directory — **do not add anything
to `Package.swift`**. Each file is compiled and linked as an executable named
after the file, and uses top-level code with no `@main`.

- [ ] **Step 1: Create the snippets**

`Snippets/PrintToStdout.swift`:

```swift
//! Write a label's ZPL to stdout.
//!
//! The smallest end-to-end LabelKit pipeline: build a label, pick a target,
//! deliver it.

import LabelKit

let label = ZPLLabel(
    "^XA^FO50,50^A0N,40,40^FDHello^FS^XZ",
    environment: ZPLEnvironment(stock: Stock.Preset.label2x1,
                                device: Device.Preset.ZD620)
)

try await label.print(to: StdoutTarget(device: Device.Preset.ZD620))
```

`Snippets/ChooseStockAndDevice.swift`:

```swift
//! Combine media and printer into a render geometry.
//!
//! Stock describes the physical media in inches; Device describes the printer's
//! resolution. Together they produce the geometry in dots that ZPL needs.

import LabelKit

let stock = Stock.Preset.label2x1
let device = Device.Preset.ZD620

print("stock:  \(stock.widthInches)in wide")
print("device: \(device.dpi.rawValue) dpi")
print("width:  \(stock.widthDots(at: device.dpi) ?? 0) dots")

// Continuous stock has no fixed height, so heightDots is nil.
print("height: \(String(describing: Stock.Preset.label4x.heightDots(at: device.dpi)))")
```

`Snippets/PrintAList.swift`:

```swift
//! Lay a list of lines out as one long label.
//!
//! ListLayout computes each row's baseline and the label's overall length, so
//! callers supply text rather than coordinates.

import LabelKit

let lines: [ListLine] = [
    .header("Costco:"),
    .item("eggs"),
    .item("bananas"),
    .blank,
    .header("Draegers:"),
    .item("cream cheese"),
]

let label = ListLayout().makeLabel(
    lines,
    environment: ZPLEnvironment(stock: Stock.Preset.label4x,
                                device: Device.Preset.ZD620)
)

try await label.print(to: StdoutTarget(device: Device.Preset.ZD620))
```

`Snippets/RenderATemplate.swift`:

```swift
//! Fill a Stencil template with values and render it to ZPL.
//!
//! Templates keep the layout separate from the data, so the same label can be
//! reused with different content.

import Foundation
import LabelKit

// snippet.hide
// Read the templates checked into the repository so this runs on a fresh clone.
let templates = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()            // Snippets/
    .deletingLastPathComponent()            // package root
    .appendingPathComponent("Examples/Resources/templates.json")
// snippet.show

let store = StencilTemplateStore(fileURL: templates)
try store.load()

let zpl = try store.render(name: "label", context: [
    "line1": "First line",
    "line2": "Second line",
])

print(zpl)
```

`Snippets/PreviewInITerm2.swift`:

```swift
//! Render a label to a PNG and show it inline in iTerm2.
//!
//! ITerm2Target emits the escape codes that display an image in the terminal.
//! Run this in iTerm2; other terminals will print the raw escape sequence.

import LabelKit

let label = ZPLLabel(
    "^XA^FO50,50^A0N,40,40^FDPreview^FS^XZ",
    environment: ZPLEnvironment(stock: Stock.Preset.label2x1,
                                device: Device.Preset.ZD620)
)

try await label.preview(
    using: ZPL2PNGRenderer.self,
    to: ITerm2Target(device: Device.Preset.ZD620),
    timeout: 2.0
)
```

- [ ] **Step 2: Verify SwiftPM discovers and compiles them**

Run: `swift build`
Expected: `Compiling PrintToStdout`, `Compiling PrintAList`, etc., then
`Build complete!` — with no `Package.swift` change.

- [ ] **Step 3: Verify they run**

Run: `swift run PrintToStdout`
Expected: `^XA^FO50,50^A0N,40,40^FDHello^FS^XZ`

Run: `swift run PrintAList`
Expected: a `^XA...^XZ` label containing `^FDCostco:^FS` and `^FDeggs^FS`.

Run: `swift run RenderATemplate`
Expected: ZPL containing `First line` and `Second line`, proving the seed
templates resolve without Application Support state.

- [ ] **Step 4: Verify the anti-rot property actually holds**

Temporarily append `let broken = LabelKit.NoSuchType()` to
`Snippets/PrintToStdout.swift`, run `swift build`, and confirm it **fails** with
`no member named 'NoSuchType'`. Then remove the line and confirm the build
passes again. This is the property the whole tier depends on; verify it once
rather than trusting it.

- [ ] **Step 5: Commit**

```bash
git add Snippets
git commit -m "docs(snippets): add Tier 1 tutorial snippets

Compiled on every build, so a tutorial referencing a renamed API breaks CI."
```

---

### Task 6: Add `compare-renderers` and retire `example-label`

**Files:**
- Create: `Examples/Advanced/compare-renderers/CompareRenderers.swift`
- Delete: `Examples/LabelCLI/LabelCLI.swift`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: `LabelaryRenderer`, `ZPL2PNGRenderer`, `ITerm2Target`
- Produces: executable product `compare-renderers`

`example-label`'s parts are now fully rehomed: template rendering and iTerm2
preview became snippets in Task 5, and its dual-renderer behavior becomes this
tool. This tool exists because that dual rendering is a real debugging
technique — it is what reveals that `zpl2png` does not implement `^FB` line
breaks while Labelary does (see issue #54).

- [ ] **Step 1: Create the tool**

```swift
//
//  CompareRenderers.swift
//  compare-renderers
//
//  Renders the same ZPL through both previewers to expose disagreements.
//

import Foundation
import LabelKit
import ArgumentParser

@main
struct CompareRenderers: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compare-renderers",
        abstract: "Render ZPL from stdin through Labelary and zpl2png, side by side",
        discussion: """
            The two renderers do not implement identical subsets of ZPL. When a \
            label prints differently than it previews, rendering it both ways \
            shows which renderer is wrong. Labelary is the reference \
            implementation; zpl2png runs locally and offline.
            """
    )

    @Option(name: .long, help: "Label width in inches")
    var width: Double = 4.0

    @Option(name: .long, help: "Label height in inches")
    var height: Double = 6.0

    func run() async throws {
        let zpl = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        guard !zpl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError("No ZPL on stdin. Pipe a label, e.g. `labelprint zpl < list.txt | compare-renderers`.")
        }

        let device = Device.Preset.ZD620
        let stock = Stock(widthInches: width, heightInches: height,
                          isContinuous: false, gapInches: 0)
        let label = ZPLLabel(zpl, environment: ZPLEnvironment(stock: stock, device: device))
        let target = ITerm2Target(device: device)

        print("── Labelary (reference) ──")
        try await label.preview(using: LabelaryRenderer.self, to: target, timeout: 10.0)

        print("── zpl2png (local) ──")
        try await label.preview(using: ZPL2PNGRenderer.self, to: target, timeout: 10.0)

        print("If these differ, the local renderer is missing a ZPL feature.")
    }
}
```

- [ ] **Step 2: Wire up Package.swift**

Remove the `example-label` product and the `LabelCLI` target. Add:

```swift
        .executable(name: "compare-renderers", targets: ["CompareRenderers"])
```

and:

```swift
        .executableTarget(
            name: "CompareRenderers",
            dependencies: [
                "LabelKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Examples/Advanced/compare-renderers"
        )
```

- [ ] **Step 3: Delete the old example**

```bash
rm -rf Examples/LabelCLI
```

- [ ] **Step 4: Verify**

Run: `swift build`
Expected: `Build complete!`, no `example-label` product.

Run: `printf 'Costco:\neggs\n' | swift run labelprint zpl | swift run compare-renderers`
Expected: two labelled preview blocks. Requires network for the Labelary half;
if offline, the Labelary preview errors and that is acceptable for this check.

Run: `printf '' | swift run compare-renderers`
Expected: the "No ZPL on stdin" error, non-zero exit.

- [ ] **Step 5: Commit**

```bash
git add -A Package.swift Examples
git commit -m "feat(examples): add compare-renderers, retire example-label

example-label's template and preview behavior moved to snippets; its
dual-renderer behavior becomes a debugging tool for renderer disagreements."
```

---

### Task 7: Add `batch-badges`

**Files:**
- Create: `Examples/Advanced/batch-badges/BatchBadges.swift`
- Create: `Examples/Resources/badges.csv`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: `StencilTemplateStore.init(fileURL:)` and the `badge` template from Task 2
- Produces: executable product `batch-badges`

- [ ] **Step 1: Create the sample data**

Create `Examples/Resources/badges.csv`:

```csv
name,title
Ada Lovelace,First Programmer
Grace Hopper,Rear Admiral
Alan Turing,Cryptanalyst
```

- [ ] **Step 2: Create the tool**

```swift
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

        return lines.dropFirst().map { line in
            let values = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            return Dictionary(uniqueKeysWithValues: zip(keys, values))
        }
    }
}
```

- [ ] **Step 3: Wire up Package.swift**

```swift
        .executable(name: "batch-badges", targets: ["BatchBadges"])
```

```swift
        .executableTarget(
            name: "BatchBadges",
            dependencies: [
                "LabelKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Examples/Advanced/batch-badges"
        )
```

- [ ] **Step 4: Verify**

Run: `swift run batch-badges`
Expected: three `^XA...^XZ` labels, containing `Ada Lovelace`, `Grace Hopper`,
and `Alan Turing` respectively.

- [ ] **Step 5: Commit**

```bash
git add -A Package.swift Examples
git commit -m "feat(examples): add batch-badges advanced template example"
```

---

### Task 8: Retire `example-reminderlist`, fix docs, reconcile LabelGUI

**Files:**
- Delete: `Examples/ReminderList/`
- Modify: `Package.swift`, `Sources/LabelKit/LabelKit.docc/LabelKit.md`, `README.md`, `AGENTS.md`
- Investigate: `Apps/LabelGUI/LabelGUI/KeyValueContext.swift` vs `Sources/LabelKit/Processors/KeyValueContext.swift`

**Interfaces:**
- Consumes: everything above
- Produces: final documented state

**Blocked by** the companion `reminders` repo plan. Do not delete
`Examples/ReminderList/` until `Reminders.swift` has been transplanted into that
repo and it builds there. If that has not happened, stop and say so rather than
deleting the only copy.

- [ ] **Step 1: Confirm the reminders code has a new home**

Verify `Reminders.swift` exists in the new `reminders` repo and builds there.
If it does not, stop — the rest of this task can proceed, but skip Steps 2-3.

- [ ] **Step 2: Delete the example**

```bash
rm -rf Examples/ReminderList
```

- [ ] **Step 3: Remove it from Package.swift**

Delete the `example-reminderlist` product and the `ReminderList` target. After
this, `Package.swift` declares exactly these executables: `labelprint`,
`compare-renderers`, `batch-badges`. EventKit no longer appears anywhere in the
package.

- [ ] **Step 4: Fix the DocC dead symbol references**

In `Sources/LabelKit/LabelKit.docc/LabelKit.md`, the processor list names two
types that do not exist. Replace:

```
    - ``StencilProcessor``: a processor to resolve Swift-Stencil Template to generate ZPL
    - LengthInjector: a processor to inject an estimated length (^LL) into a ZPL string
```

with:

```
    - ``ResolveTemplates``: a processor to resolve Swift-Stencil templates to generate ZPL
    - ``InjectLength``: a processor to inject an estimated length (^LL) into a ZPL string
```

Then add `ListLayout` to the "Other Types" list:

```
- ``ListLayout``: Lays a sequence of ``ListLine`` values out as a single long label.
```

- [ ] **Step 5: Verify no other docs reference deleted symbols**

Run:
```bash
grep -rn "StencilProcessor\|LengthInjector\|example-label\|example-reminderlist\|example-listlabel" \
  README.md AGENTS.md Sources/LabelKit/LabelKit.docc/
```
Expected: no matches once Step 6 is done. Every hit is a doc that still
advertises a deleted executable.

- [ ] **Step 6: Update README.md and AGENTS.md**

Rewrite the Examples section of `README.md` to describe the three tiers, with
the real commands:

```sh
swift run PrintToStdout                      # Tier 1: tutorial snippets
swift run PrintAList

cat list.txt | swift run labelprint          # Tier 2: print to the printer
cat list.txt | swift run labelprint preview  #         PNG preview in iTerm2
cat list.txt | swift run labelprint zpl      #         ZPL to stdout
cat list.txt | swift run labelprint list     #         show the parsed lines

swift run batch-badges                       # Tier 3: template + CSV -> N labels
cat list.txt | swift run labelprint zpl | swift run compare-renderers
```

Update the Commands block in `AGENTS.md` to match, replacing the
`example-label` / `example-reminderlist` / `example-listlabel` lines.

- [ ] **Step 7: Investigate the LabelGUI KeyValueContext fork**

Do not assume this is duplication. `Apps/LabelGUI/LabelGUI/KeyValueContext.swift`
is 164 lines; `Sources/LabelKit/Processors/KeyValueContext.swift` is 45. Run:

```bash
diff Sources/LabelKit/Processors/KeyValueContext.swift \
     Apps/LabelGUI/LabelGUI/KeyValueContext.swift
```

Classify every addition in the fork as one of:
- **(a) GUI-specific** — stays in LabelGUI
- **(b) generally useful** — promote into LabelKit's type
- **(c) redundant** — delete

Write the classification into the commit message. If (b) is non-empty, promoting
it is a library API change; do that as its own commit with tests. If the diff
turns out to be larger or more entangled than a single task can absorb, stop and
report rather than pushing through — this step is scoped as an investigation, and
discovering it is a bigger job is a valid outcome.

- [ ] **Step 8: Full verification**

Run: `swift build && swift test`
Expected: `Build complete!` and a fully passing suite.

Run: `swift package describe --type json | grep -o '"name" : "[a-z-]*"' | sort -u`
Expected: confirms only the intended products remain.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "refactor(examples): retire example-reminderlist and refresh docs

EventKit leaves the package entirely; the reminders tool now lives in its own
repo. Fixes DocC references to StencilProcessor and LengthInjector, neither of
which has ever existed."
```

---

## Self-Review

**Spec coverage:**

| Spec item | Task |
|---|---|
| CI in scope | 1 |
| `StencilTemplateStore.init(fileURL:)` | 2 |
| Seed templates, zero-setup | 2 |
| Promote list layout, with tests | 3 |
| Layout in library / parsing in example seam | 3, 4 |
| `labelprint`, drop `example-` prefix | 4 |
| Parser test target | 4 |
| Tier 1 snippets | 5 |
| `compare-renderers`, dissolve `example-label` | 5, 6 |
| `batch-badges` | 7 |
| Delete `example-reminderlist` | 8 |
| DocC dead symbols | 8 |
| LabelGUI fork investigation | 8 |
| No shared example target | honored — `PrinterOptions` appears only in Task 4 |
| `reminders` repo extraction | out of scope, companion plan |

**Type consistency:** `ListLine` and `ListLayout.makeLabel(_:environment:)` are
defined in Task 3 and used with those exact names in Tasks 4 and 5.
`parseLines(_:)` is defined in Task 4 and tested there. `PrinterOptions` is
defined once, in Task 4.

**Placeholder scan:** clean. An earlier draft had Task 7 stage an intentionally
invalid `parseCSV` signature for a later step to replace; that was a placeholder
and has been removed in favor of the real implementation inline.

## Follow-on issues (do not implement here)

- LabelKit #53 — `^CF`, `^CI28`, `^FH`. Now a change to `ListLayout` in one place.
- LabelKit #54 — `^FB` field blocks; needs `ZPLLengthEstimator` to learn `^FB` first.
- jazzy → DocC migration, which is what makes `//!` and `@Snippet` render.
- `t` #41 / #42 — unblocked once Task 3 lands.
