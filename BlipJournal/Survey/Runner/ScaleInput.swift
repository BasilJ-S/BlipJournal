import BlipJournalCore
import SwiftUI

struct ScaleInput: View {
    let scale: ScaleConfig; let value: Int?; let onChange: (Int) -> Void
    var body: some View {
        VStack {
            if scale.max - scale.min <= 6 { LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))]) { ForEach(scale.min...scale.max, id: \.self) { n in Button { onChange(n) } label: { Text("\(n)").frame(minWidth: 44, minHeight: 44).background(value == n ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(value == n ? .white : .primary) }.accessibilityLabel("\(n)") } } }
            else { Text(value.map(String.init) ?? "Not selected").font(.title2.bold()); Slider(value: Binding(get: { Double(value ?? scale.min) }, set: { onChange(Int($0.rounded())) }), in: Double(scale.min)...Double(scale.max), step: 1).accessibilityValue(value.map(String.init) ?? "Not selected") }
            HStack { Text(scale.minLabel); Spacer(); Text(scale.maxLabel) }.font(.caption).foregroundStyle(.secondary)
        }
    }
}
