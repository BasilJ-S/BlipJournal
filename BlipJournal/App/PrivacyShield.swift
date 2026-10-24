import SwiftUI
import UIKit

/// Covers the app with a plain branded screen whenever the scene stops being active, so
/// the app-switcher snapshot never shows journal content.
///
/// A window of its own rather than a SwiftUI overlay: sheets are presented above the root
/// view, so an overlay on the root would leave an open runner or editor sheet in the
/// snapshot. Covering rather than locking keeps those sheets, and any half-written entry,
/// in place for when the person comes straight back.
@MainActor
final class PrivacyShield {
    private var window: UIWindow?

    init() {}

    func show() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState != .unattached })
        else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = UIHostingController(rootView: PrivacyCoverView())
        window.isHidden = false
        self.window = window
    }

    func hide() {
        window?.isHidden = true
        window = nil
    }
}

/// What the app switcher shows: the mark on paper, nothing else.
private struct PrivacyCoverView: View {
    var body: some View {
        BlipMark(size: 72)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BlipBrand.paper.ignoresSafeArea())
            .accessibilityHidden(true)
    }
}
