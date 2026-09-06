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
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 100
            let cardSize = 61 * scale
            let radius = 16.5 * scale
            let back = RoundedRectangle(cornerRadius: radius, style: .circular)
                .path(in: CGRect(x: 29.5 * scale, y: 9.5 * scale, width: cardSize, height: cardSize))
            let frontRect = CGRect(x: 9.5 * scale, y: 29.5 * scale, width: cardSize, height: cardSize)
            let front = RoundedRectangle(cornerRadius: radius, style: .circular).path(in: frontRect)

            // The rear card is visible only outside the front card's footprint.
            var outsideFront = Path(CGRect(origin: .zero, size: canvasSize))
            outsideFront.addPath(front)
            context.clip(to: outsideFront, style: FillStyle(eoFill: true))
            context.stroke(back, with: .color(BlipBrand.ink), lineWidth: 9 * scale)

            context.stroke(front, with: .color(BlipBrand.ink), lineWidth: 9 * scale)
            let dot = Path(ellipseIn: CGRect(x: 29 * scale, y: 49 * scale, width: 22 * scale, height: 22 * scale))
            context.fill(dot, with: .color(BlipBrand.violet))
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
