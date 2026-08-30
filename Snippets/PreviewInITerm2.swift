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
