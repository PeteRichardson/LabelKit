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
