# AGENTS.md

This file provides guidance to AI Agents (e.g. Claude, Codex) when working with code in this repository.

## Project Overview

LabelKit is a Swift package (Swift 6, macOS 14+) for generating ZPL (Zebra Programming Language) and printing labels to Zebra thermal printers (e.g. a ZD620). It also includes example CLIs and a SwiftUI app that consume the library.

## Commands

```sh
swift build                  # build library + example executables
swift test                   # run all tests (uses Swift Testing, not XCTest)
swift test --filter ZPLLabelTests            # run one suite
swift test --filter ZPLLabelTests/initialRenderWithContext   # run one test
swift run example-label      # LabelCLI example
swift run example-reminderlist zpl|preview|print|list        # ReminderList example
./Scripts/generate_docs.sh   # generate docs with jazzy
```

The `LabelGUI` SwiftUI app is not part of the package; build it via `Apps/LabelGUI/LabelGUI.xcodeproj` or `Workspace/LabelWorkspace.xcworkspace` (xcodebuild/Xcode).

## Architecture

The core flow is a pipeline: **source text → processors → renderable ZPL → payload → target**.

- `ZPLLabel` (Sources/LabelKit/Labels/) holds source text, an ordered chain of `ZPLProcessor`s, and a `ZPLEnvironment`. `label.zpl()` folds the source through the processors.
- `ZPLProcessor` implementations (Sources/LabelKit/Processors/): `ResolveTemplates` (Stencil templating with a `KeyValueContext`), `InjectLength` (computes and injects `^LL` via `ZPLLengthEstimator`), `PrettyPrint`/`ZPLFormatter`. `StencilTemplateStore` loads named templates from `~/Library/Application Support/LabelKit/templates.json`.
- `ZPLEnvironment`/`ZPLOptions` combine a `Stock` (physical media, measured in inches — presets like `label2x1`, `label4x`) and a `Device` (printer capabilities, native DPI — preset `ZD620`) into a `RenderGeometry` in dots. The Stock/Device distinction (media vs. printer) and the DPI-carrying `Payload` exist so mismatched-DPI output can be rejected at send time (`strict:` flag).
- `Target` (Sources/LabelKit/Targets.swift) is the delivery side: `NetworkTarget` (raw TCP to printer port 9100), `StdoutTarget`, `ITerm2Target` (inline image escape codes), `FileTarget`. Targets receive a `Payload` (`.zpl` or `.png`, each tagged with its render DPI).
- `ImageRenderer` (Sources/LabelKit/Previewers/) turns ZPL into PNG previews: `LabelaryRenderer` (Labelary web API) or `ZPL2PNGRenderer`, which shells out to the `zpl2png` binary bundled as a package resource in Sources/LabelKit/Helpers/.

## Notes

- Tests use the Swift Testing framework (`import Testing`, `@Suite`/`@Test`), not XCTest.
- DocC catalog lives at Sources/LabelKit/LabelKit.docc/; keep it in sync when adding public API.
- Examples hardcode a printer at 192.168.0.133:9100.
- `Workspace/Build/` and `Apps/LabelGUI/Build/` contain derived/checkout artifacts — don't edit or search them.
