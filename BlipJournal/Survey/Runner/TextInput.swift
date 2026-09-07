import SwiftUI

// A vertical-axis TextField inside a ScrollView/LazyVStack (as in SurveyRunnerView) needs an
// explicit FocusState binding, or the first tap only positions the cursor without raising the
// keyboard — the field then requires a second tap to actually focus. `focus`/`fieldId` exist to
// make that focus explicit; any future field embedded the same way should follow this pattern.
struct TextInput: View {
    let value: String
    let onChange: (String) -> Void
    let onCommit: () -> Void
    let fieldId: String
    var focus: FocusState<String?>.Binding
    var body: some View {
        VStack(alignment: .trailing) {
            TextField("Quick note", text: Binding(get: { value }, set: onChange), axis: .vertical)
                .lineLimit(2...6)
                .textFieldStyle(.roundedBorder)
                .focused(focus, equals: fieldId)
                .onSubmit(onCommit)
                .accessibilityLabel("Quick note")
            Text("\(value.count) / 500").font(.caption).accessibilityLabel("\(value.count) of 500 characters")
        }
    }
}
