//  ContentView.swift
//  zpled
//
//  Created by Peter Richardson on 8/19/25.
//

import SwiftUI
import AppKit
import LabelKit
import Observation

private var editorFont: Font {
    // Try your named font first
    let name = "MonaspaceNeon-Regular"
    let size = 14.0
    if NSFont(name:name, size: size) != nil {
        return .custom(name, size: size)
    } else {
        return .system(.body, design: .serif)
    }
}



struct ContentView: View {
    //@State private var text: String
    @State private var label: ZPLLabel
    @State private var previewImage: NSImage? = nil
    @State private var ctx: KeyValueContext

    private static func loadSomeZPL() -> String {
        return "^XA\n^FO10,10^A0N,20,20^FDHello, {{name}}!^FS\n^XZ"
    }
    
    // New initializer lets callers pass initial text
    init(initialText: String? = nil) {
        let text = initialText ?? Self.loadSomeZPL()
        let zd620 = Device.Preset.ZD620
        let stock = Stock.Preset.label2x1

        // Build an initial context without touching self before all properties are initialized
        let initialCtx = KeyValueContext(["name": "Pete", "sku": "A123"])

        // Initialize @State wrappers explicitly
        self._ctx = State(initialValue: initialCtx)
        self._label = State(initialValue:
            ZPLLabel(
                text,
                processors: [InjectLength(), ResolveTemplates()!],
                environment: .init(context: self._ctx.wrappedValue, options: .init(stock: stock, device: zd620))
            )
        )
    }
    
    var body: some View {
        VStack {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    KeyValueTableView(context: $ctx)
                    Divider()
                    TextEditor(text: $label.source)
                        .environment(\.font, editorFont)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment:.topLeading)
                    
                }
//                TextEditor(text: .constant(label.zpl()))
                TextEditor(text: .constant(label.zpl()))
                    .environment(\.font, editorFont)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .disabled(true)
                
                if let labelPreview  = previewImage {
                    Image(nsImage: labelPreview)
                        .resizable()
                        .interpolation(.none)   // keeps thermal-label “crisp”
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .scaledToFit()
                        .frame(maxWidth: 406, maxHeight: 203)
                        .shadow(radius: 8)

                }
            }
            .frame(maxWidth: .infinity)
            HStack {
                Spacer()
                Button("Render", systemImage: "paperplane.circle") {
                    Task {
                        let dpi = Device.Preset.ZD620.nativeDPI
                        let geometry = RenderGeometry(
//                            dpi: label.device.nativeDPI.rawValue,
//                            widthDots: label.stock.widthDots(at: label.device.nativeDPI),
//                            heightDots: label.stock.heightDots(at: label.device.nativeDPI)
                            dpi: dpi.rawValue,
                            widthDots: Stock.Preset.label2x1.widthDots(at: dpi),
                            heightDots: Stock.Preset.label2x1.heightDots(at: dpi)
                        )
                        let imageOpts = ImageRenderOptions(geometry: geometry, timeout: 2.0)
                        do {
                            let imageData = try await LabelaryRenderer().render(from: label.zpl(), options: imageOpts)
                            if let nsImage = NSImage(data: imageData) {
                                print("Got image data!")
                                await MainActor.run { previewImage = nsImage }
                            }
                        } catch {
                            print("Didn't get image data!")
                            await MainActor.run { previewImage = nil }
                        }
                    }
                }
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}

