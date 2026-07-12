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
        return """
        ^XA\n^LL{{length}}^FO10,10\n^A0N,40,80\n^FB600,7,0,L,0\n^FDHey, {{name}}!
        Have you heard about updog?
        Whats updog?
        Not much! What's up with you?^FS\n^XZ
        """
    }
    
    // New initializer lets callers pass initial text
    init(initialText: String? = nil) {
        let text = initialText ?? Self.loadSomeZPL()
        let zd620 = Device.Preset.ZD620
        let stock = Stock.Preset.label2x1

        // Build an initial context without touching self before all properties are initialized
        let initialCtx = KeyValueContext(["name": "Pete",
                                          "length": "400"])

        // Template resolution degrades gracefully: if the template store can't load,
        // skip it rather than crash — the label still renders with Stencil syntax unresolved.
        var processors: [any ZPLProcessor] = [InjectLength()]
        if let resolveTemplates = ResolveTemplates() {
            processors.append(resolveTemplates)
        }

        // Initialize @State wrappers explicitly
        self._ctx = State(initialValue: initialCtx)
        self._label = State(initialValue:
            ZPLLabel(
                text,
                processors: processors,
                environment: .init(context: self._ctx.wrappedValue, options: .init(stock: stock, device: zd620))
            )
        )
    }
    
    /// For the read-only preview pane only — never sent to a printer. Surfaces
    /// processor failures visibly instead of hiding them behind valid-looking ZPL.
    private var resolvedZPLOrError: String {
        do {
            return try label.zpl()
        } catch {
            return "⚠️ Failed to resolve ZPL: \(error)"
        }
    }

    func printToPrinter() async throws {
        let zd620 = label.environment.options.device
        let printer = NetworkTarget(device: zd620, host: "192.168.0.133", port: 9100)
        try await printer.send(Payload.zpl(try label.zpl(), dpi: zd620.nativeDPI))
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
                VStack {
                    
                    if let labelPreview  = previewImage {
                        // widthDots/heightDots are nil for continuous stock (see Stock.swift);
                        // fall back to the same size used for the empty-state placeholder below.
                        let geometry = label.environment.options.geometry
                        let frameWidth = geometry.widthDots.map(CGFloat.init) ?? 406
                        let frameHeight = geometry.heightDots.map(CGFloat.init) ?? 203
                        Image(nsImage: labelPreview)
                            .resizable()
                            .interpolation(.none)   // keeps thermal-label “crisp”
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .scaledToFit()
                            .frame(maxWidth: frameWidth, maxHeight: frameHeight)
                            .shadow(radius: 8)
                    }
                    else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).frame(maxWidth: 406, maxHeight: 203)
                    }
                    TextEditor(text: .constant(resolvedZPLOrError))
                        .environment(\.font, editorFont)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .disabled(true)
                    
                }
            }
            .frame(maxWidth: .infinity)
            HStack {
                Spacer()
                Button("Render", systemImage: "paperplane.circle") {
                    Task {
                        let device = $label.wrappedValue.environment.options.device
                        let stock = $label.wrappedValue.environment.options.stock
                        let geometry = RenderGeometry(
                            dpi: device.nativeDPI.rawValue,
                            widthDots: stock.widthDots(at: device.nativeDPI),
                            heightDots: stock.heightDots(at: device.nativeDPI)
                        )
                        let imageOpts = ImageRenderOptions(geometry: geometry, timeout: 2.0)
                        do {
                            let imageData = try await LabelaryRenderer().render(
//                            let imageData = try await ZPL2PNGRenderer().render(
                                from: try label.zpl(),
                                options: imageOpts
                            )
                            if let nsImage = NSImage(data: imageData) {
                                print("Got image data!")
                                await MainActor.run { previewImage = nsImage }
                            }
                        } catch {
                            print("Didn't get image data! \(error)")
                            await MainActor.run { previewImage = nil }
                        }
                    }
                }
                Button("Print", systemImage: "printer.fill") {
                    Task {
                        try await printToPrinter()
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

