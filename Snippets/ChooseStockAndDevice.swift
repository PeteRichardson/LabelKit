//! Combine media and printer into a render geometry.
//!
//! Stock describes the physical media in inches; Device describes the printer's
//! resolution. Together they produce the geometry in dots that ZPL needs.

import LabelKit

let stock = Stock.Preset.label2x1
let device = Device.Preset.ZD620

print("stock:  \(stock.widthInches)in wide")
print("device: \(device.nativeDPI.rawValue) dpi")
print("width:  \(stock.widthDots(at: device.nativeDPI)) dots")

// Continuous stock has no fixed height, so heightDots is nil.
print("height: \(String(describing: Stock.Preset.label4x.heightDots(at: device.nativeDPI)))")
