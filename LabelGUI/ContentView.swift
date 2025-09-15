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
    
    private static func loadSomeZPL() -> String {
        return "{{label}}"
    }
    
    // New initializer lets callers pass initial text
    init(initialText: String? = nil) {
        let text = initialText ?? Self.loadSomeZPL()
        label = ZPLLabel(text)
    }
    
    private static let defaultDebounceDelay = Duration.milliseconds(800)
    
    @State private var autoRefreshTask: Task<Void, Never>? = nil
    @State private var autoRefreshEnabled = true
    
    func sendZPL(label: ZPLLabel) {
        do {
            let zd620 = Device ( name:"ZD620", nativeDPI: .dpi300, maxWidthDots: 1200, maxLengthDots: 12000)
            let stock = Stock(widthInches: 2.0, heightInches: 1.0, isContinuous: false, gapInches: 0.125)
            let geometry = RenderGeometry(
                dpi: zd620.nativeDPI.rawValue,
                widthDots: stock.widthDots(at: zd620.nativeDPI),
                heightDots: stock.heightDots(at: zd620.nativeDPI)
            )
            let zplopts  = ZPLOptions(geometry: geometry, stock: stock, device: zd620)
            
            guard let engine = StencilZPLEngine() else {
                fatalError("Couldn't create ZPLEngine")
            }
            
            let finalZPL = try engine.render(label, options: zplopts)
            
            let printer = NetworkTarget(device: zd620, host: "192.168.0.133", port: 9100)
            try printer.send(Payload.zpl(finalZPL, dpi: zd620.nativeDPI))
        } catch {
            print("WTF \(error)")
        }

    }
    
    var body: some View {
        @Bindable var label = label
        VStack {
            HStack(alignment: .top, spacing: 12) {
                TextEditor(text: $label.rawTemplate)
                    .environment(\.font, editorFont)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment:.topLeading)
                TextEditor(text: .constant(label.renderedZPL))
                    .environment(\.font, editorFont)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .disabled(true)
                    .overlay(alignment: .topLeading) {
                        if let err = label.lastRenderError {
                            Text("⚠️ \(err)").font(.caption).foregroundStyle(.red)
                        }
                    }
            }
            .frame(maxWidth: .infinity)
            HStack {
                Spacer()
                Button("Print", systemImage: "paperplane.circle") {
                    Task { await label.renderNow() }
                    sendZPL(label: label)
                }
            }
        }
        .padding()
        // Debounce only while auto-refresher is enabled
        .onChange(of: label.rawTemplate) {
            if autoRefreshEnabled {
                scheduleAutoRefresh(delay: ContentView.defaultDebounceDelay)
            }
        }
        // React to toggling
        .onChange(of: autoRefreshEnabled) { oldValue, newValue in
            if newValue {
                scheduleAutoRefresh(delay: ContentView.defaultDebounceDelay)
            } else {
                autoRefreshTask?.cancel()
            }
        }
        // Refresh once on appear if enabled
        .task {
            if autoRefreshEnabled {
                Task { await label.renderNow() }
            }
        }
    }
    
    private func scheduleAutoRefresh(delay: Duration = defaultDebounceDelay) {
        // Cancel any in-flight debounce task
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [label] in
            // Debounce window; if cancelled, exit without refreshing
            do {
                try await Task.sleep(for: delay)
            } catch {
                return // cancelled during sleep
            }
            guard !Task.isCancelled else { return }
            Task { @MainActor in
                await label.renderNow() 
            }
        }
    }
    
    
}

#Preview {
    ContentView()
}
