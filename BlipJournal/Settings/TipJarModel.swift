import Foundation
import Observation
import StoreKit

/// Loads the three tip products and buys one. A tip unlocks nothing, so nothing is
/// stored: the only lasting effect of a purchase is Apple's own receipt.
@MainActor @Observable
final class TipJarModel {
    /// Every In-App Purchase the app offers. `TipJar.storekit` and App Store Connect use
    /// the same IDs.
    nonisolated static let productIDs = [
        "io.github.basilj-s.BlipJournal.tip.small",
        "io.github.basilj-s.BlipJournal.tip.medium",
        "io.github.basilj-s.BlipJournal.tip.large",
    ]

    enum Phase: Equatable {
        case loading, unavailable, ready
    }

    /// The last purchase's result, shown above the tip options.
    enum Outcome: Equatable {
        case thanked, cancelled, pending, failed

        /// Nil for a cancellation: the person chose not to tip, which is not an error.
        var message: String? {
            switch self {
            case .thanked: "Thank you for supporting Blip Journal."
            case .cancelled: nil
            case .pending: "Your tip is waiting for approval. Thank you for the thought."
            case .failed: "Something went wrong with that tip. You can try again later."
            }
        }
    }

    private(set) var phase = Phase.loading
    private(set) var products: [Product] = []
    private(set) var purchasingID: Product.ID?
    private(set) var outcome: Outcome?

    func load() async {
        do {
            products = try await Product.products(for: Self.productIDs).sorted { $0.price < $1.price }
            phase = products.isEmpty ? .unavailable : .ready
        } catch {
            phase = .unavailable
        }
    }

    /// `buy` is the view's SwiftUI `PurchaseAction`, which presents the payment sheet in
    /// the right scene. It is passed as a closure because `PurchaseAction` only exists
    /// where SwiftUI is imported, and SwiftUI's own `Transaction` would clash here.
    func purchase(_ product: Product, using buy: @MainActor (Product) async throws -> Product.PurchaseResult) async {
        guard purchasingID == nil else { return }
        purchasingID = product.id
        outcome = nil
        defer { purchasingID = nil }
        do {
            switch try await buy(product) {
            case .success(let verification):
                // Thanked even if unverified: the App Store has charged them, and a tip
                // unlocks nothing that verification would protect.
                await Self.finish(verification)
                outcome = .thanked
            case .userCancelled:
                outcome = .cancelled
            case .pending:
                outcome = .pending
            @unknown default:
                outcome = .failed
            }
        } catch StoreKitError.userCancelled {
            outcome = .cancelled
        } catch {
            outcome = .failed
        }
    }

    /// Finishes a transaction, verified or not. Tips are consumables that unlock nothing
    /// (R1, R2), so an unverified one has nothing to withhold, and leaving it unfinished
    /// would only redeliver it at every launch.
    nonisolated static func finish(_ result: VerificationResult<Transaction>) async {
        await result.unsafePayloadValue.finish()
    }

    /// Finishes transactions that complete outside a purchase call: Ask to Buy approvals,
    /// purchases interrupted by a crash, and anything left unfinished at the last launch,
    /// which `Transaction.updates` delivers once at startup. Start it once, at launch.
    nonisolated static func listenForTransactions() -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                await TipJarModel.finish(result)
            }
        }
    }
}
