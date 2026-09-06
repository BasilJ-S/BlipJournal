import BlipJournalCore
import SwiftUI

/// Shared scale configuration form used by question creation and editing.
struct ScaleFields: View {
    @Binding var scale: ScaleConfig

    var body: some View {
        Stepper("Minimum: \(scale.min)", value: $scale.min, in: -100...100)
        Stepper("Maximum: \(scale.max)", value: $scale.max, in: -100...100)
        TextField("Minimum label", text: $scale.minLabel)
        TextField("Maximum label", text: $scale.maxLabel)
        if !scale.isValid {
            Text("Choose endpoints from -100 to 100 with at least two values.")
                .foregroundStyle(.red)
                .font(.footnote)
        }
    }
}
