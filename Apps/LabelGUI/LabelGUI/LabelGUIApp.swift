//
//  LabelGUIApp.swift
//  LabelGUI
//
//  Created by Peter Richardson on 8/22/25.
//

import SwiftUI
import LabelKit

@main
struct LabelGUIApp: App {
    var body: some Scene {
        // Editor window that accepts an optional String value
        WindowGroup("ZPL Editor", for: String.self) { $initialZPL in
            ContentView(initialText: initialZPL)
        }
        .defaultSize(width: 900, height: 600)
        .windowResizability(.contentSize)
    }
}
