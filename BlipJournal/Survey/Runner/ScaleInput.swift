import BlipJournalCore
import SwiftUI

struct ScaleInput: View {
    let scale: ScaleConfig; let value: Int?; let onChange: (Int) -> Void
    var body: some View {
        VStack {
            Text(value.map(String.init) ?? "Not selected").font(.title2.bold())
            Slider(value: Binding(get: { Double(value ?? scale.min) }, set: { onChange(Int($0.rounded())) }), in: Double(scale.min)...Double(scale.max), step: 1)
                .accessibilityLabel("Scale answer")
                .accessibilityValue(value.map(String.init) ?? "Not selected")
            HStack { Text(scale.minLabel); Spacer(); Text(scale.maxLabel) }.font(.caption).foregroundStyle(.secondary)
        }
    }
}
