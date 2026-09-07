import SwiftUI
import UIKit

enum BlipBrand {
    static let ink = Color(hex: 0x1F1A17)
    static let violet = Color(hex: 0xB37CFF)
    static let sand = Color(hex: 0xF6EFE5)
    static let paper = Color(hex: 0xFBF7F2)
    static let muted = Color(hex: 0x6B6158)

    /// Not one of the spec's five named colours: a hairline row border, derived from
    /// `muted` rather than hand-picked, so a future palette edit carries it along.
    static let cardBorder = muted.opacity(0.16)
}

/// Nunito and JetBrains Mono, both shipped as variable fonts (see `Brand/Fonts/OFL.txt`).
/// `UIFont(name:)` only ever hands back the default-weight instance, so every other
/// weight is dialled in at draw time via the `wght` axis rather than a second file.
enum BlipFont {
    static let nunitoPostScriptName = "Nunito-ExtraLight"
    static let jetBrainsMonoPostScriptName = "JetBrainsMono-Regular"
    static let weightAxis: UInt32 = 0x7767_6874 // 'wght'

    /// Nunito 800 — the wordmark and screen/section titles.
    static func title(_ size: CGFloat) -> Font { nunito(size: size, weight: 800) }
    /// Nunito 600 — the long-form qualifier and emphasis within body copy.
    static func qualifier(_ size: CGFloat) -> Font { nunito(size: size, weight: 600) }
    /// Nunito 400 — body copy.
    static func body(_ size: CGFloat) -> Font { nunito(size: size, weight: 400) }
    /// JetBrains Mono 500 — labels, badges, metadata. Pair with `.blipMonoLabel()`
    /// for the uppercase/tracked treatment the spec calls for, rather than using bare.
    static func mono(_ size: CGFloat) -> Font { Font(variableUIFont(jetBrainsMonoPostScriptName, weight: 500, size: size)) }

    private static func nunito(size: CGFloat, weight: CGFloat) -> Font {
        Font(variableUIFont(nunitoPostScriptName, weight: weight, size: size))
    }

    /// Dials a weight into a variable font's `wght` axis at draw time, since
    /// `UIFont(name:)` only ever hands back the file's default-weight instance.
    static func variableUIFont(_ postScriptName: String, weight: CGFloat, size: CGFloat) -> UIFont {
        guard let base = UIFont(name: postScriptName, size: size) else {
            return .systemFont(ofSize: size)
        }
        let variationAttribute = UIFontDescriptor.AttributeName(rawValue: "NSCTFontVariationAttribute")
        let descriptor = base.fontDescriptor.addingAttributes([
            variationAttribute: [weightAxis: weight]
        ])
        return UIFont(descriptor: descriptor, size: size)
    }
}

/// Uppercase, tracked JetBrains Mono, muted — the spec's voice for section headers,
/// metadata and badges. Never above 12pt per the spec.
struct BlipMonoLabelStyle: ViewModifier {
    var size: CGFloat = 11
    var color: Color = BlipBrand.muted

    func body(content: Content) -> some View {
        content
            .font(BlipFont.mono(size))
            .tracking(size * 0.1)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

extension View {
    func blipMonoLabel(size: CGFloat = 11, color: Color = BlipBrand.muted) -> some View {
        modifier(BlipMonoLabelStyle(size: size, color: color))
    }

    /// The shared treatment for every navigated screen. Lists and Forms bring their
    /// own opaque system canvas, so hiding it belongs here alongside the title and
    /// page surface rather than being reimplemented by each feature.
    func blipScreen(
        _ title: String,
        titleDisplayMode: NavigationBarItem.TitleDisplayMode = .automatic
    ) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(titleDisplayMode)
            .fontDesign(.rounded)
            .scrollContentBackground(.hidden)
            .blipScreenBackground()
    }

    /// A row that reads as a paper card sitting on the sand ground, rather than a
    /// system grouped-list row. No shadow: the spec calls depth-via-shadow a misuse.
    func blipCardRow() -> some View {
        self
            .listRowBackground(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(BlipBrand.sand)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(BlipBrand.cardBorder, lineWidth: 1))
                    .padding(.vertical, 4))
            .listRowSeparator(.hidden)
    }
}

/// One-time global chrome: reliable rounded navigation titles and tab labels in
/// JetBrains Mono 500. Call once at launch.
enum BlipAppearance {
    static func configure() {
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = UIColor(BlipBrand.paper)
        navigation.titleTextAttributes = [
            .font: navigationFont(size: 17),
            .foregroundColor: UIColor(BlipBrand.ink)
        ]
        navigation.largeTitleTextAttributes = [
            .font: navigationFont(size: 34),
            .foregroundColor: UIColor(BlipBrand.ink)
        ]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation

        let tabItem = UITabBarItemAppearance()
        let tabFont = BlipFont.variableUIFont(BlipFont.jetBrainsMonoPostScriptName, weight: 500, size: 10)
        tabItem.normal.titleTextAttributes = [.font: tabFont]
        tabItem.selected.titleTextAttributes = [.font: tabFont, .foregroundColor: UIColor(BlipBrand.violet)]
        let tabBar = UITabBarAppearance()
        tabBar.configureWithTransparentBackground()
        tabBar.backgroundColor = UIColor(BlipBrand.paper)
        tabBar.stackedLayoutAppearance = tabItem
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar
    }

    /// UIKit's large-title renderer does not reliably draw a variable-font descriptor
    /// at the scroll edge. The rounded system face is the safe native-chrome fallback;
    /// content headings continue to use Nunito through `BlipFont`.
    private static func navigationFont(size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .heavy)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
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
            context.drawLayer { layer in
                layer.clip(to: outsideFront, style: FillStyle(eoFill: true))
                layer.stroke(back, with: .color(BlipBrand.ink), lineWidth: 9 * scale)
            }

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
