import SwiftUI

// Keep the editing buffer and native focus local; report focus to the runner for scrolling.
struct TextInput: View {
    let value: String
    let onChange: (String) -> Void
    let onCommit: () -> Void
    let onFocusChange: (Bool) -> Void
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(value: String, onChange: @escaping (String) -> Void, onCommit: @escaping () -> Void, onFocusChange: @escaping (Bool) -> Void) {
        self.value = value
        self.onChange = onChange
        self.onCommit = onCommit
        self.onFocusChange = onFocusChange
        _text = State(initialValue: value)
    }

    var body: some View {
        VStack(alignment: .trailing) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Quick note")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: Binding(
                    get: { text },
                    set: { newValue in
                        let limited = String(newValue.prefix(500))
                        text = limited
                        onChange(limited)
                    }
                ))
                .scrollContentBackground(.hidden)
                .frame(height: 120)
                .focused($isFocused)
                .accessibilityLabel("Quick note")
            }
            .padding(4)
            // Include the box's padding in the first-tap focus target while leaving
            // native cursor placement and selection available inside the editor.
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    if !isFocused { isFocused = true }
                }
            )
            .background(BlipBrand.paper, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(BlipBrand.cardBorder, lineWidth: 1)
            }
            Text("\(text.count) / 500").font(.caption).accessibilityLabel("\(text.count) of 500 characters")
        }
        .onChange(of: value) { _, newValue in
            if text != newValue { text = newValue }
        }
        .onChange(of: isFocused) { wasFocused, isFocused in
            onFocusChange(isFocused)
            if wasFocused && !isFocused { onCommit() }
        }
    }
}
