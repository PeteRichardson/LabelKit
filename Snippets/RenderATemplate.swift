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
