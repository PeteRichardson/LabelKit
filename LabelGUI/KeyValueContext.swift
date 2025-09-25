//
//  KeyValueContext.swift
//  tablestudy
//
//  Created by Peter Richardson on 9/23/25.
//

import SwiftUI
import LabelKit


// MARK: - View

/// Spreadsheet-like two-column editor with headers.
/// - Displays and edits a `KeyValueContext`
/// - Call `onCommit` to receive the updated `[String:String]`
public struct KeyValueTableView: View {
    @Binding private var context: KeyValueContext
    public var onCommit: (([String: String]) -> Void)?

    // Column sizing
    @State private var keyWidth: CGFloat = 150
    @State private var valueWidth: CGFloat = 200

    public init(context: Binding<KeyValueContext>,
                onCommit: (([String: String]) -> Void)? = nil) {
        self.onCommit = onCommit
        self._context = context
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView([.vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach($context.rows) { $row in
                        rowView(row: $row)
                            .scrollTargetLayout()
                        Divider()
                    }
                    addRowButton
                }
                .padding(.vertical, 0)
            }
            .scrollTargetBehavior(.viewAligned)
            .background(.background)
        }
        .frame(width: keyWidth + valueWidth + 120, height: 190)
        .onChange(of: context) {
            commitDebounced()
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 0) {
            rowHeader(title: "Key", width: keyWidth)
            Divider()
            rowHeader(title: "Value", width: valueWidth + 120.0)
            Spacer(minLength: 0)
        }
        .background(.quaternary.opacity(0.25))
        .frame(width: keyWidth + valueWidth + 32, height: 30, alignment: .leading)

    }

    private func rowView(row: Binding<KeyValueRow>) -> some View {
        HStack(spacing: 0) {
            TextField("key", text: row.key)
                .font(.system(.body, design: .rounded))
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .frame(width: keyWidth, alignment: .leading)

            Divider()

            TextField("value", text: row.value, axis: .vertical)
                .font(.system(.body, design: .rounded))
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .frame(width: valueWidth, alignment: .leading)

            Spacer()

            Button {
                withAnimation {
                    if let idx = context.rows.firstIndex(where: { $0.id == row.wrappedValue.id }) {
                        context.rows.remove(at: idx)
                    }
                    commit()
                }
            } label: {
                Image(systemName: "trash")
                    .help("Delete row")
            }
            .padding(.horizontal)
            .frame(alignment: .trailing)
            .buttonStyle(.borderless)
        }
        .frame(minWidth: keyWidth + valueWidth + 16, minHeight: 30, alignment: .leading)
    }

    private var addRowButton: some View {
        HStack {
            Button {
                withAnimation {
                    context.rows.append(KeyValueRow())
                }
            } label: {
                Label("Add Row", systemImage: "plus.circle")
            }
            .buttonStyle(.link)
            .padding(.vertical, 8)

            Spacer()
        }
        .padding(.leading, 8)
    }

    // MARK: Helpers

    private func rowHeader(title: String, width: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.headline)
                .padding(.leading, 8)
        }
        .frame(width: width, alignment: .leading)
    }

    /// Immediately deliver the merged dictionary
    private func commit() {
        onCommit?(context.asDictionary())
    }

    /// Simple debounce so we don’t spam commits on each keystroke
    @State private var debounceTask: Task<Void, Never>?
    private func commitDebounced() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000) // 350ms
            commit()
        }
    }
}

// MARK: - Previews

#Preview("KeyValueTableView") {
    @Previewable @State var context: KeyValueContext = KeyValueContext([
        "firstName": "Ada",
        "lastName": "Lovelace",
        "occupation": "Mathematician",
        "favorite_language": "Analytical Engine"
    ])
    KeyValueTableView(
        context: $context
    ) { dict in
        // Example: this is where you'd pass to Swift-Stencil
        print("Context updated:", dict)
    }
    .padding()
}
