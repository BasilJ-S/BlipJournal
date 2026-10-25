import StoreKit
import StoreKitTest
import Testing
import UIKit
@testable import BlipJournal

/// Runs `TipJarModel` against StoreKit's local test store. The test session is global to
/// the process, so these run one at a time.
@MainActor @Suite(.serialized)
struct TipJarStoreKitTests {
    private let session: SKTestSession

    init() throws {
        session = try SKTestSession(configurationFileNamed: "TipJar")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
    }

    private func loadedModel() async throws -> (TipJarModel, Product) {
        let model = TipJarModel()
        await model.load()
        return (model, try #require(model.products.first))
    }

    private func buy(_ product: Product) async throws -> Product.PurchaseResult {
        let scene = try #require(UIApplication.shared.connectedScenes.first)
        return try await product.purchase(confirmIn: scene)
    }

    private func unfinishedCount() async -> Int {
        var count = 0
        for await _ in Transaction.unfinished { count += 1 }
        return count
    }

    @Test func loadsTheThreeTipsCheapestFirst() async throws {
        let model = TipJarModel()
        await model.load()
        #expect(model.phase == .ready)
        #expect(model.products.map(\.id) == TipJarModel.productIDs)
        #expect(model.products.allSatisfy { !$0.displayPrice.isEmpty })
    }

    @Test func noProductsMeansUnavailable() async throws {
        let empty = try SKTestSession(configurationFileNamed: "NoTips")
        empty.disableDialogs = true
        let model = TipJarModel()
        await model.load()
        #expect(model.phase == .unavailable)
        #expect(model.products.isEmpty)
    }

    @Test func successThanksAndFinishes() async throws {
        let (model, product) = try await loadedModel()
        await model.purchase(product) { try await buy($0) }
        #expect(model.outcome == .thanked)
        #expect(model.purchasingID == nil)
        #expect(await unfinishedCount() == 0)
    }

    @Test func failedTransactionShowsTheFailureNote() async throws {
        session.failTransactionsEnabled = true
        let (model, product) = try await loadedModel()
        await model.purchase(product) { try await buy($0) }
        #expect(model.outcome == .failed)
    }

    @Test func askToBuyIsPending() async throws {
        session.askToBuyEnabled = true
        let (model, product) = try await loadedModel()
        await model.purchase(product) { try await buy($0) }
        #expect(model.outcome == .pending)
    }
}
