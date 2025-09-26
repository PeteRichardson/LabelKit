# Stock Article

Learn more about ``Stock``: its purpose, properties, and how to use it for both die‑cut and continuous media.

## Description

``Stock`` represents a roll of label media. It captures width, an optional height (for die‑cut media), whether the media is continuous, and the inter‑label gap. For continuous media, ``Stock/heightInches`` is `nil` and gap is `0`.

## Properties

- ``Stock/widthInches``: The physical width of the media in inches.
- ``Stock/heightInches``: The physical height of a single label in inches; `nil` for continuous media.
- ``Stock/isContinuous``: `true` for continuous media, `false` for die‑cut labels.
- ``Stock/gapInches``: The gap or mark distance between labels in inches; `0` for continuous media.

## Unit Conversion

``Stock`` provides helpers to convert to printer dots and millimeters.

```swift
let stock = Stock(widthInches: 2.0, heightInches: 1.0, isContinuous: false, gapInches: 0.125)

let widthDots = stock.widthDots(at: .dpi300)
let heightDots = stock.heightDots(at: .dpi300) // Int?
let gapDots = stock.gapDots(at: .dpi300)

let widthMM = stock.widthMM()
let heightMM = stock.heightMM() // Double?
let gapMM = stock.gapMM()
