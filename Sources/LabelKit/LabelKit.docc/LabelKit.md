# ``LabelKit``

A lightweight framework for modeling label media and producing values useful for ZPL-based printing (e.g., Zebra ZD620). It provides types for stock/media modeling, device capabilities, geometry, ZPL processing, preview rendering, and delivery targets.

## Overview

LabelKit models the physical label stock and device constraints you need to safely produce ZPL, and includes helpers to render/transform ZPL and deliver it to different destinations.

Core pieces include:

- ``ZPLLabel``: 
- ``Stock``: Describes the media roll characteristics like width, height, gap and die‑cut vs. continuous.  All measurements are in inches. Some Presets are available.
    - ``Label2x1``: 2"x1" labels with 1/8" gap between
    - ``Label4x``: 4" wide receipt paper
- ``Device``: Describes the target printer’s DPI and printable limits (in dots).  Some Presets are available.
    - ``ZD620``: A 300 DPI Zebra ZD620 direct thermal label printer
- ``Target``: Describes a destination and/or method for delivering ZPL or images.
    - ``NetworkTarget``: can receive ZPL at an IP address for printing
    - ``StdoutTarget``: can display ZPL on the terminal
    - ``ITerm2Target``: can display ZPL or a rendered ZPL PNG in ITerm2
    - ``FileTarget``: can save ZPL or a rendered ZPL PNG in a file

- ``ZPLProcessor``: A protocol for components that transform ZPL prior to output
    - ``StencilProcessor``: a processor to resolve Swift-Stencil Template to generate ZPL
    - LengthInjector: a processor to inject an estimated length (^LL) into a ZPL string
    - ``ZPLFormatter``: a processor to pretty‑print or minify ZPL
    - ``ZPLEnvironment`` / ``ZPLOptions``: Context and options passed to processors.

- ``ImageRenderer``: A protocol for components that render ZPL into PNG
    - ``LabelaryRenderer``: Renders ZPL to a PNG using the Labelary web API.
    - ``ZPL2PNGRenderer``: Renders ZPL to a PNG using ZPL2PNG helper tool embedded in LabelKit

Other Types:
- ``ZPLRepresentable``: Protocol for types that can produce ZPL on demand.
- ``DPI``: The printer resolution used when converting inches to dots.  `Comparable`, ordered by resolution, so resolutions can be sorted, ranged and compared with `min`/`max`.
- ``ZPLLengthEstimator``: Estimates ZPL label length (in dots) by walking commands.

## Getting Started

### Define your device

```swift
import LabelKit

let device = Device.Preset.ZD620
