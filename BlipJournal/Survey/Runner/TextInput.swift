import SwiftUI

// Keep focus and the immediate editing buffer inside the input. If either lives in
// SurveyRunnerView, focusing or typing invalidates the whole LazyVStack and can replace
// the active field before the keyboard settles.
struct TextInput: View {
    let value: String
    let onChange: (String) -> Void
    let onCommit: () -> Void
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(value: String, onChange: @escaping (String) -> Void, onCommit: @escaping () -> Void) {
        self.value = value
        self.onChange = onChange
        self.onCommit = onCommit
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
                .frame(minHeight: 72, maxHeight: 160)
                .focused($isFocused)
                .accessibilityLabel("Quick note")
            }
            .padding(4)
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
            if wasFocused && !isFocused { onCommit() }
        }
    }
}
