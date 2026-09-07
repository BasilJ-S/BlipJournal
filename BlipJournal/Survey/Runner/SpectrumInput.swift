import BlipJournalCore
import SwiftUI

/// A continuous slider over `0...1`, coloured by a smooth gradient through the
/// spectrum's zones. Unlike `ScaleInput`, the value never snaps: only the label above
/// the thumb changes, when the drag crosses a zone boundary.
struct SpectrumInput: View {
    let spectrum: SpectrumConfig
    let value: Double?
    let onChange: (Double) -> Void

    private var current: Double { value ?? 0.5 }
    private var displayedLabel: String {
        guard let value else { return "Not selected" }
        return spectrum.zone(for: value)?.label ?? "Unavailable"
    }
    private let trackHeight: CGFloat = 28
    private let thumbSize: CGFloat = 32

    var body: some View {
        VStack(spacing: 12) {
            Text(displayedLabel)
                .font(.headline)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: spectrum.zoneIndex(for: current))
            GeometryReader { proxy in
                let width = proxy.size.width - thumbSize
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: trackHeight / 2, style: .continuous)
                        .fill(gradient)
                        .frame(height: trackHeight)
                    Circle()
                        .fill(.white)
                        .overlay(Circle().stroke(.black.opacity(0.15), lineWidth: 1))
                        .shadow(radius: 2, y: 1)
                        .frame(width: thumbSize, height: thumbSize)
                        .offset(x: current * width)
                        .opacity(value == nil ? 0 : 1)
                        .animation(value == nil ? nil : .interactiveSpring(), value: current)
                }
                .frame(height: max(trackHeight, thumbSize))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    guard width > 0 else { return }
                    onChange(min(max((drag.location.x - thumbSize / 2) / width, 0), 1))
                })
            }
            .frame(height: max(trackHeight, thumbSize))
            .accessibilityElement()
            .accessibilityLabel("Spectrum answer")
            .accessibilityValue(displayedLabel)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onChange(min(current + 0.05, 1))
                case .decrement: onChange(max(current - 0.05, 0))
                @unknown default: break
                }
            }
            HStack {
                ForEach(spectrum.zones.indices, id: \.self) { index in
                    Text(spectrum.zones[index].label)
                        .frame(maxWidth: .infinity, alignment: index == 0 ? .leading : (index == spectrum.zones.count - 1 ? .trailing : .center))
                }
            }.font(.caption).foregroundStyle(.secondary)
        }
    }

    /// A smooth gradient across the whole track: each zone's colour at its own
    /// midpoint, plus the first and last zones' colours pinned to the track's ends, so
    /// the colour never blocks into discrete bands.
    private var gradient: LinearGradient {
        guard spectrum.isValid else {
            return LinearGradient(colors: [.secondary.opacity(0.3), .secondary.opacity(0.3)], startPoint: .leading, endPoint: .trailing)
        }
        var stops: [Gradient.Stop] = []
        for (index, zone) in spectrum.zones.enumerated() {
            let lower = index == 0 ? 0 : spectrum.breakpoints[index - 1]
            let upper = index == spectrum.zones.count - 1 ? 1 : spectrum.breakpoints[index]
            let midpoint = (lower + upper) / 2
            if index == 0 { stops.append(Gradient.Stop(color: zone.color.color, location: 0)) }
            stops.append(Gradient.Stop(color: zone.color.color, location: midpoint))
            if index == spectrum.zones.count - 1 { stops.append(Gradient.Stop(color: zone.color.color, location: 1)) }
        }
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }
}
