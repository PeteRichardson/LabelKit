# Examples Reorganization — Design

**Date:** 2026-08-30
**Status:** Approved, ready for implementation planning

## Context

LabelKit ships three example executables that have grown ad hoc. Each tangles
three orthogonal concerns — data source, layout, and delivery — and
re-implements all three:

| | data source | layout | delivery |
|---|---|---|---|
| `example-label` | template store | Stencil | stdout + printer + 2 previewers |
| `example-reminderlist` | EventKit | hand-built ZPL | 4 subcommands |
| `example-listlabel` (uncommitted) | stdin | hand-built ZPL (near-identical) | 4 subcommands |

Concrete symptoms:

- `PrinterOptions` is copy-pasted verbatim into all three files.
- `generate_label()` is duplicated between `ReminderList.swift` and
  `ListLabel.swift` with only cosmetic differences.
- `example-label` depends on a `templates.json` that is not in the repo. It runs
  today only because a copy exists in
  `~/Library/Group Containers/group.com.peterichardson.labelkit/`, almost
  certainly left by LabelGUI. `StencilTemplateStore.load()` silently no-ops when
  the file is missing (`StencilTemplates.swift:50`), so on a fresh clone
  `render(name: "label")` throws. The flagship example depends on invisible
  machine state.
- `example-reminderlist` pulls EventKit — a dependency and a permission prompt
  the library itself does not need — into a package that otherwise just makes
  ZPL.
- The DocC catalog documents `StencilProcessor` and `LengthInjector`, neither of
  which exists. The real types are `ResolveTemplates` and `InjectLength`.
- LabelGUI carries a 164-line fork of LabelKit's 45-line `KeyValueContext`.

There is no seam, so each new example copies the last one.

## Goals

Three tiers, each with acceptance criteria. The criteria are the part that was
missing; without them the ad-hoc drift recurs.

| Tier | Purpose | Must | Must not |
|---|---|---|---|
| **1. Tutorial** | Teach one LabelKit feature | Be a `Snippets/*.swift` file; compile on every build; fit on one screen | Take flags; require setup; teach two things |
| **2. Useful** | A tool you would actually run | Run on a fresh clone with zero setup; do one job | Add a dependency, entitlement, or permission prompt LabelKit itself does not need |
| **3. Advanced** | Show non-obvious technique | Demonstrate something not guessable from the API docs | Duplicate Tier 2's job with more knobs |

Two criteria carry most of the weight:

- **Tier 2 zero-setup** forces seed templates into the repo, fixing the
  `example-label` failure above.
- **Tier 2 no-extra-dependency** sends EventKit to its own repo.

## Non-goals

- Migrating documentation from jazzy to DocC. Tracked separately; see
  *Deferred*.
- Building a second SwiftUI app. LabelGUI *is* the Tier 3 GUI example.
- Reworking ZPL emission (`^FB`, `^CF`, `^CI28`). Tracked as LabelKit #53 and
  #54; this design only affects *where* that code lives.

## Design

### Structure

```
Snippets/                    Tier 1 — auto-discovered, no Package.swift entry
  PrintToStdout.swift
  PreviewInITerm2.swift
  PrintAList.swift
  RenderATemplate.swift
  ChooseStockAndDevice.swift

Examples/
  labelprint/                Tier 2 — stdin -> print | preview | zpl | list
  Advanced/
    compare-renderers/       Tier 3 — Labelary vs zpl2png, for debugging
    batch-badges/            Tier 3 — one template + CSV -> N labels
Apps/LabelGUI                Tier 3 — the GUI example

-> reminders                 new separate repo
```

### Snippets (Tier 1)

Verified behavior, not assumed: a top-level `Snippets/` directory is
auto-discovered by SwiftPM with **no `Package.swift` entry**; each file is
compiled and linked as an executable; `swift run <Name>` runs it; and a stale
API reference **fails the build** (confirmed with
`module 'LabelKit' has no member named ...`). Top-level `try await` works, which
matters because LabelKit's delivery API is async.

Snippets use top-level code — no `@main`, no ArgumentParser. They take no flags:
a tutorial that needs configuring is teaching two things at once.

`// snippet.hide` / `// snippet.show` fence off setup code, and `//!` is the
snippet doc comment. These affect rendered documentation only, which this
project does not yet generate — see *Deferred*.

### No shared example target

The `PrinterOptions` triplication resolves by deletion rather than abstraction.
Once `example-label` dissolves and `example-reminderlist` is extracted,
`PrinterOptions` has exactly one consumer (`labelprint`); `compare-renderers`
and `batch-badges` do not print to a network printer. **No `ExampleSupport`
target is created.** Revisit only if a second printing tool appears.

Tier 1 snippets duplicate freely by design — copy-pasteability is the point, and
a shared helper would defeat it. Applying one sharing policy across both tiers is
what produced the current mess.

### Library change 1: promote list layout

`t` (github.com/PeteRichardson/t) will consume LabelKit to print reminders,
making it a second consumer of the "lines -> long label" logic. Leaving layout in
example code would mean `t` reimplements it — a third copy of `generate_label`.

```swift
public enum ListLine: Sendable, Equatable {
    case header(String), item(String), blank
}

public struct ListLayout: Sendable {
    public var headerFontSize = 60, itemFontSize = 50, gap = 20
    public var headerIndent = 60, itemIndent = 100
    public var topMargin = 20
    public var bottomMargin = 318   // empirical: ZD620 + cutter @ 300dpi

    public func makeLabel(_ lines: [ListLine],
                          environment: ZPLEnvironment) -> ZPLLabel
}
```

The name is `ListLayout`. (`TextListLayout` and `ListLabelBuilder` were
considered; `ListLayout` wins on brevity and because the type describes a layout,
not a builder.) `makeLabel` also sets
`environment.options.geometry.heightDots` to the computed length, as the current
`generate_label` does.

`bottomMargin` is a known wart — an empirical cutter allowance rather than a
style choice. It stays a defaulted property with a comment rather than being
invented into a larger abstraction.

**The seam:** *layout* (`[ListLine]` -> `ZPLLabel`) moves to the library because
it has two consumers. *Parsing* (text -> `[ListLine]`: the `:`-suffix header
convention, blank collapsing, trailing-blank trimming) stays in `labelprint`
because it has one — `t` builds `ListLine`s from Eisenhower quadrants directly
and never parses text.

This also improves LabelKit #54: the `^FB` rework then lands in one library-side
place next to the `ZPLLengthEstimator` changes it depends on, rather than in
example code.

### Library change 2: `StencilTemplateStore.init(fileURL:)`

`StencilTemplateStore` currently exposes only `public init() throws`, which
resolves to Application Support / group-container paths, and `fileURL` is
`private(set)`. There is no way to point it at a template file shipped in the
repo, so the Tier 2 zero-setup rule cannot be satisfied without this addition.
Prerequisite, not a nicety.

Seed templates are then checked into the repo at
`Examples/Resources/templates.json` and used by `RenderATemplate` and
`batch-badges`. Snippets and examples resolve it relative to the package so a
fresh clone works with no Application Support state; the existing zero-argument
`init()` behavior is unchanged for apps like LabelGUI that want the user's own
template store.

### CI

There is no `.github/workflows/` at all. This is load-bearing: the entire case
for snippets is that `swift build` catches rot, which is only true if something
runs `swift build`. A minimal macOS workflow running `swift build` and
`swift test` is **in scope for this work**, not deferred.

### Tier 2: `labelprint`

Subcommands `print` (default), `preview`, `zpl`, `list`. `list` echoes the parsed
lines, which is how the header/blank parse gets debugged without burning a label.
Printer options resolve flag -> environment (`LABELKIT_PRINTER_HOST` /
`LABELKIT_PRINTER_PORT`) -> `PrinterDefaults`.

**Tier 2 tools drop the `example-` prefix.** They are meant to be symlinked into
`~/bin`, and the prefix argues against the thing we want people to do with them.
Accepted tradeoff: it is less obvious from `swift run --list` which products are
examples.

### Tier 3

- **`compare-renderers`** — takes ZPL, renders through both `LabelaryRenderer`
  and `ZPL2PNGRenderer`, shows both inline and reports dimensions. This tool
  would have caught the `^FB` discrepancy behind #54 immediately, which is the
  concrete case for its existence.
- **`batch-badges`** — one Stencil template + a CSV -> N labels, via
  `ResolveTemplates` and `KeyValueContext`. Natural consumer of the seed
  template.
- **LabelGUI** — documented as the Tier 3 GUI example. Its forked
  `KeyValueContext` is reconciled with the library type. The reconciliation
  *direction* is not yet decided, because nobody has read the 119-line
  difference. Step 7 therefore begins with an explicit investigation task —
  diff the two, classify what the fork added as (a) GUI-specific and staying in
  LabelGUI, (b) generally useful and promoted into LabelKit, or (c) redundant
  and deleted — and only then edit. Do not assume the fork is pure duplication.

## Migration map

| Today | Becomes |
|---|---|
| `example-label` | `Snippets/RenderATemplate.swift` + `Snippets/PreviewInITerm2.swift` + `Advanced/compare-renderers`; target deleted |
| `ReminderList.swift` (layout) | `ListLayout` in LabelKit |
| `ReminderList.swift` (CLI) | deleted |
| `Reminders.swift` | new `reminders` repo |
| `example-listlabel` (uncommitted) | `Examples/labelprint/`, layout removed |
| `PrinterOptions` x3 | x1, in `labelprint` |
| LabelGUI forked `KeyValueContext` (164 lines) | reconciled with library's (45) |
| DocC `StencilProcessor` / `LengthInjector` | corrected to real symbol names |

## Testing

Promoting layout makes it testable for the first time — neither example ever had
a test for it. `Tests/LabelKitTests/` gains coverage for `ListLayout`: per-line-
type cursor advance, `^LL` computation, empty input, header vs item indent.

`labelprint` gets a small test target for its parser: header detection, blank
collapsing, trailing-blank trimming, `^`/`~` handling.

Snippets are covered by compilation. CI runs `swift build` + `swift test`.

Tests use Swift Testing (`import Testing`, `@Suite`/`@Test`), matching the rest
of the suite.

## Sequencing

1. CI + `StencilTemplateStore.init(fileURL:)` + seed templates — unblocks the rest
2. `ListLayout` into LabelKit, with tests
3. `labelprint`; delete `example-listlabel`
4. Snippets; delete `example-label`
5. `reminders` extraction; delete `example-reminderlist`
6. Tier 3 tools
7. LabelGUI `KeyValueContext` reconciliation + DocC symbol fixes

Steps 1-2 unblock `t` #42.

## Companion work in other repos

- **`reminders`** — a **new** repo, seeded with `Reminders.swift` from
  `Examples/ReminderList/`. The name is deliberately broader than
  `get-reminders`, which would constrain the tool to reading at the outset;
  `reminders` leaves room to add functionality later.

  `asyncgetreminders` is **not** reused. It was a 2022 experiment in async +
  EventKit rather than a usable tool, and its contents are strictly worse than
  what already exists here: an Xcode project rather than a package, the
  deprecated `requestAccess(to:completion:)`, and an `init()` that fires the
  authorization request without awaiting it — so a fetch can run before access is
  granted. It stays where it is, as the experiment it was.

  Output contract is plain lines sorted by priority; priority and due date do not
  survive the pipe, which is the trade that keeps it composable. A `--by-list`
  mode emitting `Groceries:` headers composes with `labelprint`'s header
  convention with no shared code — only a shared text convention.

  **Naming note:** `keith/reminders-cli` (~900 stars) also installs a binary
  called `reminders`. The repo name is unaffected, but the installed binary name
  would collide if that tool is ever installed via Homebrew.
- **`t` #41** — bump deployment target to macOS 14 (LabelKit requires it).
- **`t` #42** — add label printing via LabelKit. Blocked by #41 and by step 2
  above.

## Deferred

- **jazzy -> DocC migration.** Snippets' compile-checking, zero-wiring and
  runnability are available today; `@Snippet` embedding in generated docs is not,
  because `Scripts/generate_docs.sh` uses jazzy, which does not understand DocC
  directives. Separate issue.
- **LabelKit #53** (`^CF`, `^CI28`, `^FH`) and **#54** (`^FB`) — sequenced after
  this reorganization, since both touch code that moves here.
- **`ResolveTemplates.init?()` prints to stdout on failure**
  (`ResolveTemplates.swift:43`) — a library writing to stdout. Noted, out of
  scope.
