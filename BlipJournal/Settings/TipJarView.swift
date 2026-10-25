import Accessibility
import StoreKit
import SwiftUI

/// Optional tips for the developer. Reached only from its Settings row; nothing else in
/// the app mentions it.
struct TipJarView: View {
    init() {}

    @Environment(\.purchase) private var purchase
    @State private var model = TipJarModel()

    var body: some View {
        Form {
            Section {
                Text("Blip Journal is open source and has no ads. If you enjoy it, you can leave a tip as a thank-you. Tips are entirely optional and don't unlock or change anything.")
            }
            if let message = model.outcome?.message {
                Section {
                    Label {
                        Text(message)
                    } icon: {
                        Image(systemName: model.outcome == .thanked ? "heart.fill" : "info.circle")
                            .foregroundStyle(model.outcome == .thanked ? BlipBrand.violet : Color.secondary)
                    }
                }
            }
            Section {
                switch model.phase {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Loading tips")
                case .unavailable:
                    Text("Tips are unavailable right now.")
                        .foregroundStyle(.secondary)
                case .ready:
                    ForEach(model.products) { product in
                        tipButton(product)
                    }
                }
            }
        }
        .blipScreen("Tip jar")
        .task { await model.load() }
    }

    private func tipButton(_ product: Product) -> some View {
        Button {
            Task {
                await model.purchase(product) { try await purchase($0) }
                // The payment sheet has just closed, so VoiceOver hears how it went.
                if let message = model.outcome?.message { AccessibilityNotification.Announcement(message).post() }
            }
        } label: {
            HStack {
                Text(product.displayName)
                    .foregroundStyle(BlipBrand.ink)
                Spacer()
                if model.purchasingID == product.id {
                    ProgressView()
                } else {
                    Text(product.displayPrice)
                        .monospacedDigit()
                }
            }
        }
        .disabled(model.purchasingID != nil)
        .accessibilityLabel("\(product.displayName), \(product.displayPrice)")
        .accessibilityHint("Leaves a one-time tip. It doesn't unlock anything.")
    }
}
