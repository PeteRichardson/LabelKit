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
