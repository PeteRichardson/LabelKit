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
    
    private static func loadSomeZPL() -> String {
        return "^XA\n^FO10,10^A0N,20,20^FDHello, World!^FS\n^XZ"
    }
    
    // New initializer lets callers pass initial text
    init(initialText: String? = nil) {
        let text = initialText ?? Self.loadSomeZPL()
        let zd620 = Device.Preset.ZD620
        let stock = Stock.Preset.label2x1
        label = ZPLLabel(
            text,
            processors: [InjectLength()],
            environment: .init(options: .init(stock: stock, device: zd620))
        )
    }
    
    private static let defaultDebounceDelay = Duration.milliseconds(800)
    
    @State private var autoRefreshTask: Task<Void, Never>? = nil
    @State private var autoRefreshEnabled = false
    
    var body: some View {
        VStack {
            HStack(alignment: .top, spacing: 12) {
                TextEditor(text: $label.source)
                    .environment(\.font, editorFont)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment:.topLeading)
                TextEditor(text: .constant(label.zpl()))
                    .environment(\.font, editorFont)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .disabled(true)
                
                //                    if let labelPreview  = previewImage {
                //                        Image(nsImage: labelPreview)
                //                            .resizable()
                //                            .interpolation(.none)   // keeps thermal-label “crisp”
                //                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                //                            .scaledToFit()
                //                            .frame(maxWidth: 406, maxHeight: 203)
                //                            .shadow(radius: 8)
                //
                //                    }
            }
            .frame(maxWidth: .infinity)
            HStack {
                Spacer()
                Button("Print", systemImage: "paperplane.circle") {
                    Task {
                        //                            let geometry = RenderGeometry(
                        //                                dpi: label.device.nativeDPI.rawValue,
                        //                                widthDots: label.stock.widthDots(at: label.device.nativeDPI),
                        //                                heightDots: label.stock.heightDots(at: label.device.nativeDPI)
                        //                            )
                        //                            let imageOpts = ImageRenderOptions(geometry: geometry, timeout: 2.0)
                        //                            do {
                        //                                let png = try await LabelaryRenderer().render(from: label.zpl(), options: imageOpts)
                        //                                await MainActor.run { previewImage = png }
                        //                            } catch {
                        //                                await MainActor.run { previewImage = nil }
                        //                            }
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

