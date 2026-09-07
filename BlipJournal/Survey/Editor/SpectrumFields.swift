import BlipJournalCore
import SwiftUI

/// Shared spectrum configuration form used by question creation and editing.
struct SpectrumFields: View {
    @Binding var spectrum: SpectrumConfig

    var body: some View {
        Menu("Load a preset") {
            ForEach(SpectrumConfig.presets, id: \.name) { preset in
                Button(preset.name) { spectrum = preset.config }
            }
        }
        ForEach(spectrum.zones.indices, id: \.self) { index in
            HStack {
                ColorPicker("", selection: Binding(
                    get: { spectrum.zones[index].color.color },
                    set: { spectrum.zones[index].color = SpectrumColor($0) }))
                    .labelsHidden().fixedSize()
                TextField("Zone label", text: Binding(
                    get: { spectrum.zones[index].label },
                    set: { spectrum.zones[index].label = $0 }))
                if spectrum.zones.count > 2 {
                    Button(role: .destructive) { removeZone(at: index) } label: {
                        Image(systemName: "minus.circle")
                    }.accessibilityLabel("Remove zone \(spectrum.zones[index].label)")
                }
            }
            if index < spectrum.breakpoints.count {
                HStack {
                    Text("Boundary").foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { spectrum.breakpoints[index] },
                        set: { setBreakpoint(index, to: $0) }), in: 0.01...0.99)
                    Text("\(Int(spectrum.breakpoints[index] * 100))%").monospacedDigit()
                }.font(.footnote)
            }
        }
        Button("Add zone") { addZone() }
        if !spectrum.isValid {
            Text("Zones must be labelled and their boundaries in order.")
                .foregroundStyle(.red)
                .font(.footnote)
        }
    }

    private func setBreakpoint(_ index: Int, to value: Double) {
        let lowerBound = index == 0 ? 0.01 : spectrum.breakpoints[index - 1] + 0.01
        let upperBound = index == spectrum.breakpoints.count - 1 ? 0.99 : spectrum.breakpoints[index + 1] - 0.01
        spectrum.breakpoints[index] = min(max(value, lowerBound), upperBound)
    }

    private func addZone() {
        spectrum.zones.append(SpectrumConfig.Zone(label: "New zone", color: SpectrumColor(red: 0.6, green: 0.6, blue: 0.6)))
        let lastBreakpoint = spectrum.breakpoints.last ?? 0
        spectrum.breakpoints.append((lastBreakpoint + 1) / 2)
    }

    private func removeZone(at index: Int) {
        spectrum.zones.remove(at: index)
        spectrum.breakpoints.remove(at: index == spectrum.breakpoints.count ? index - 1 : index)
    }
}
