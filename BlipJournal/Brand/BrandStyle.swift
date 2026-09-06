import SwiftUI

enum BlipBrand {
    static let ink = Color(hex: 0x1F1A17)
    static let violet = Color(hex: 0xB37CFF)
    static let sand = Color(hex: 0xF6EFE5)
    static let paper = Color(hex: 0xFBF7F2)
    static let muted = Color(hex: 0x6B6158)
}

struct BlipMark: View {
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.21, style: .continuous)
                .stroke(BlipBrand.ink, lineWidth: size * 0.09)
                .frame(width: size * 0.7, height: size * 0.7)
                .offset(x: size * 0.14, y: -size * 0.14)
            RoundedRectangle(cornerRadius: size * 0.21, style: .continuous)
                .stroke(BlipBrand.ink, lineWidth: size * 0.09)
                .frame(width: size * 0.7, height: size * 0.7)
            Circle()
                .fill(BlipBrand.violet)
                .frame(width: size * 0.22, height: size * 0.22)
                .offset(x: -size * 0.1, y: size * 0.1)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Blip")
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

extension View {
    func blipScreenBackground() -> some View {
        self.background(BlipBrand.paper.ignoresSafeArea())
            .tint(BlipBrand.violet)
    }
}
