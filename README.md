<!-- 🖊 TODO: Add logo to docs/images/logo.png and uncomment:
<p align="center">
  <img src="docs/images/logo.png" alt="LabelKit logo" width="200">
</p>
-->

# LabelKit

> _A Swift package for generating, previewing, and printing ZPL labels on Zebra thermal printers._

LabelKit models the two things you have to get right before sending ZPL to a
label printer: the physical media (`Stock` — width, height, gap, die-cut vs.
continuous, in inches) and the printer's capabilities (`Device` — native DPI,
printable limits, in dots). From those it derives render geometry, runs your
label source through a chain of composable processors (Stencil templating,
automatic `^LL` length injection, pretty-printing), and delivers the result to
a `Target` — a network printer, a file, stdout, or an inline iTerm2 image
preview. Because every payload carries its render DPI, sending 203 dpi ZPL to
a 300 dpi printer fails loudly instead of printing tiny.

macOS 14+ only; presets currently cover one printer (Zebra ZD620) and two
stocks, though both types are trivially constructible for other hardware.

<!-- 🖊 TODO: Set project status — delete the others:
> **Status:** Active development — APIs may change between minor versions.
> **Status:** Experimental / proof-of-concept — use at your own risk.
-->

---

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Examples](#examples)
- [Configuration](#configuration)
- [Documentation](#documentation)
- [Known Limitations](#known-limitations)
- [License](#license)

---

## Features

- **Media-first modeling** — `Stock` (inches) and `Device` (dots @ DPI) are
  separate types; `RenderGeometry` is derived, so inch→dot math lives in one place.
- **Composable ZPL processors** — `ZPLLabel` folds its source through an
  ordered `[ZPLProcessor]` chain:
  - `ResolveTemplates` — [Stencil](https://github.com/stencilproject/Stencil)
    templating with a `KeyValueContext` of variables
  - `InjectLength` — estimates label length by walking ZPL commands
    (`ZPLLengthEstimator`) and injects a `^LL`
  - `PrettyPrint` / `ZPLFormatter` — pretty-print or minify ZPL
- **Pluggable delivery targets** — `NetworkTarget` (raw TCP, port 9100),
  `FileTarget`, `StdoutTarget`, and `ITerm2Target` (renders PNG previews
  inline in your terminal).
- **Two PNG preview renderers** — `LabelaryRenderer` (Labelary web API) and
  `ZPL2PNGRenderer` (offline, via a `zpl2png` helper binary bundled as a
  package resource).
- **DPI safety** — payloads are tagged with their render DPI; targets reject
  mismatches with the device's native DPI unless you pass `strict: false`.
- **Named template store** — `StencilTemplateStore` loads reusable label
  templates from `~/Library/Application Support/LabelKit/templates.json`.

---

## Prerequisites

- **macOS 14** (Sonoma) or later
- **Swift 6.0** toolchain (Xcode 16+)
- A Zebra ZPL printer on your network (optional — previews work without one)
- [iTerm2](https://iterm2.com) for inline image previews (optional)
- [jazzy](https://github.com/realm/jazzy) only if you want to regenerate docs

---

## Installation

### Swift Package Manager

Add LabelKit to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/PeteRichardson/LabelKit.git", branch: "main")
]
```

<!-- 🖊 TODO: Tag a release and switch the dependency above to `from: "x.y.z"` -->

### From source

```sh
git clone git@github.com:PeteRichardson/LabelKit.git
cd LabelKit
swift build
swift test
```

---

## Quick Start

```swift
import LabelKit

// 1. Describe the media and the printer
let env = ZPLEnvironment(
    context: KeyValueContext(["name": "World"]),
    stock: Stock.Preset.label2x1,      // 2"x1" die-cut labels, 1/8" gap
    device: Device.Preset.ZD620        // 300 dpi Zebra ZD620
)

// 2. Build a label: source + processor chain + environment
let label = ZPLLabel(
    "^XA^FO50,50^A0N,40,40^FDHello {{ name }}^FS^XZ",
    processors: [ResolveTemplates()!, InjectLength(), PrettyPrint()],
    environment: env
)

// 3. Deliver it — to a printer...
let printer = NetworkTarget(device: Device.Preset.ZD620, host: "192.168.0.133", port: 9100)
try await printer.send(.zpl(label.zpl(), dpi: .dpi300))

// ...or preview it inline in iTerm2 without a printer
let renderer = try ZPL2PNGRenderer()
let png = try await renderer.render(
    from: label.zpl(),
    options: ImageRenderOptions(geometry: env.options.geometry, timeout: 2.0)
)
try await ITerm2Target(device: Device.Preset.ZD620).send(.png(png, dpi: .dpi300))
```

<!-- 🖊 TODO: Add a screenshot of an iTerm2 inline preview here — highest-ROI
visual for this project.
<p align="center">
  <img src="docs/images/preview-demo.png" alt="Label preview in iTerm2" width="700">
</p>
-->

---

## Examples

Three example executables ship with the package:

| Executable | Description |
|------------|-------------|
| `example-label` | Loads a Stencil template from the template store, prints the processed ZPL to stdout, and renders iTerm2 previews via both Labelary and zpl2png |
| `example-reminderlist` | Prints your uncompleted Reminders.app items as a label on 4" continuous stock |
| `example-listlabel` | Reads lines of text on stdin and prints them as one long list label; lines ending in `:` become section headers and blank lines become gaps |

```sh
swift run example-label                   # ZPL to stdout + iTerm2 previews
swift run example-label --print           # ...and send it to the printer
swift run example-label -d                # ...with debug logging to Console

swift run example-reminderlist list       # reminder titles as text
swift run example-reminderlist zpl        # generated ZPL to stdout
swift run example-reminderlist preview    # PNG preview inline in iTerm2
swift run example-reminderlist print      # send to network printer
swift run example-reminderlist print -d   # ...with debug logging to Console

cat shopping.txt | swift run example-listlabel          # send to network printer
cat shopping.txt | swift run example-listlabel preview  # PNG preview inline in iTerm2
cat shopping.txt | swift run example-listlabel zpl      # generated ZPL to stdout
```

`example-listlabel` defaults to its `print` subcommand, so a bare pipe goes
straight to the printer.

Every subcommand takes `-d`/`--debug` to enable OSLog output to Console.

### Choosing a printer

All three examples default to a printer at `192.168.0.133:9100`. Override it with
`--host`/`--port` on any command that talks to a printer:

```sh
swift run example-reminderlist print --host 10.0.1.42 --port 9100
swift run example-label --print --host 10.0.1.42
cat shopping.txt | swift run example-listlabel print --host 10.0.1.42
```

or set the environment variables once:

```sh
export LABELKIT_PRINTER_HOST=10.0.1.42
export LABELKIT_PRINTER_PORT=9100
```

Precedence is flag → environment variable → built-in default. No source edit
or rebuild required. `example-reminderlist` will prompt for Reminders access
on first run.

There is also a SwiftUI app, **LabelGUI**, in `Apps/LabelGUI` (open
`Apps/LabelGUI/LabelGUI.xcodeproj` or `Workspace/LabelWorkspace.xcworkspace`
in Xcode).

---

## Configuration

`StencilTemplateStore` (used by `example-label` and available to your own
code) reads named templates from:

```
~/Library/Application Support/LabelKit/templates.json
```

The folder and file are created on first use. Templates are named Stencil
strings rendered against a `[String: Any]` context, e.g.:

```json
{
  "label": "^XA^FO50,50^A0N,40,40^FD{{ name }}^FS^XZ"
}
```

<!-- 🖊 TODO: Confirm the templates.json shape above matches what
StencilTemplateStore actually reads/writes. -->

---

## Documentation

- API reference lives in the DocC catalog at
  `Sources/LabelKit/LabelKit.docc/` — browse it in Xcode
  (Product ▸ Build Documentation).
- HTML docs can be generated with `./Scripts/generate_docs.sh` (requires
  [jazzy](https://github.com/realm/jazzy)).

---

## Known Limitations

- **macOS only** (14+). Uses `Network.framework`, `Security`, and a bundled
  macOS helper binary — no Linux support.
- **One device preset** — only the ZD620 (300 dpi) ships as a preset;
  construct your own `Device` for other printers.
- **`LabelaryRenderer` needs internet** — it calls the
  [Labelary](https://labelary.com) web API. Use `ZPL2PNGRenderer` for offline
  previews.
- **`InjectLength` checks the device but not the stock, and its check ignores
  padding** — the estimate is validated against `Device.maxLengthDots`, but the
  value actually injected is the estimate plus 150 dots. A label landing within
  150 dots of the device maximum passes the check and still emits an over-long
  `^LL`. Stock height is not checked at all.
- **Length estimation parses a subset of ZPL** — `ZPLLengthEstimator` accounts
  for `^FD` text, `^BC` barcodes and `^GB` boxes. Other barcode types and
  graphics contribute nothing to the estimate, so `^LL` can come out short for
  labels that use them.
- **No print-job feedback** — `NetworkTarget` fires raw TCP at port 9100 and
  does not read printer status back. It surfaces connection failures and
  timeouts, but never a paper-out, head-open, or job-rejected condition.
- **Sandboxed apps must ship the helper** — a sandboxed process cannot execute
  binaries outside its container, so `ZPL2PNGRenderer` skips the `$PATH` and
  `/usr/local/bin` search steps when sandboxed. Bundle `zpl2png` in
  `Contents/Helpers`, or pass it explicitly to `ZPL2PNGRenderer(helperURL:)`.

### Known bugs

Bugs are tracked as
[GitHub issues](https://github.com/PeteRichardson/LabelKit/issues) — that
tracker, not this list, is the current source of truth. `docs/reviews/PROJECT_REVIEW.md`
records the audit those issues were filed from.

The crash and correctness bugs raised by earlier review rounds are fixed: the
force-unwrap on continuous stock (previews now throw
`PreviewError.missingGeometry`), `^FD` content corruption in the formatter, the
pipe deadlock on previews larger than the OS pipe buffer, and the defeated
`NetworkTarget` connect timeout.

---

## License

<!-- 🖊 TODO: No LICENSE file found in the repo. Add one and update this line, e.g.:
Licensed under the **MIT License** — see [LICENSE](LICENSE) for details.
-->
_License not yet specified._
