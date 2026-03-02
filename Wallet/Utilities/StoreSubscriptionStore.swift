//
//  StoreSubscriptionStore.swift
//  FrugalPilot
//
//  Created by Codex on 2/3/26.
//

import Foundation
import Combine
import StoreKit

@MainActor
final class StoreSubscriptionStore: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isPurchasing: Bool = false
    @Published var statusMessage: String? = nil
    @Published private(set) var missingProductIDs: [String] = []

    private var didLoadProducts: Bool = false

    func prepareIfNeeded() async {
        guard didLoadProducts == false else { return }
        await loadProducts()
        await refreshEntitlements()
    }

    func loadProducts() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let ids = SubscriptionPlan.allCases
            .flatMap { SubscriptionManager.productIDs(for: $0) }
        do {
            let loaded = try await Product.products(for: ids)
            products = loaded.sorted { lhs, rhs in
                lhs.price < rhs.price
            }
            let loadedIDs = Set(loaded.map(\.id))
            missingProductIDs = ids.filter { !loadedIDs.contains($0) }
            if loaded.isEmpty {
                statusMessage = "No App Store products were returned. Check product IDs in App Store Connect."
            } else if !missingProductIDs.isEmpty {
                statusMessage = "Some plans are unavailable on this build. Missing IDs: \(missingProductIDs.joined(separator: ", "))"
            }
            didLoadProducts = true
        } catch {
            statusMessage = "Could not load App Store products."
        }
    }

    func product(for plan: SubscriptionPlan) -> Product? {
        let ids = Set(SubscriptionManager.productIDs(for: plan))
        guard !ids.isEmpty else { return nil }
        return products.first(where: { ids.contains($0.id) })
    }

    func purchase(plan: SubscriptionPlan) async {
        guard let product = product(for: plan) else {
            statusMessage = "This plan is not available yet in App Store Connect."
            return
        }
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    statusMessage = "Purchase could not be verified."
                    return
                }
                apply(storeTransaction: transaction)
                await transaction.finish()
                statusMessage = "Purchase successful."
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            statusMessage = "Purchase failed. Please try again."
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            statusMessage = "Purchases restored."
        } catch {
            statusMessage = "Could not restore purchases."
        }
    }

    func refreshEntitlements() async {
        var highestPlan: SubscriptionPlan = .free
        for await entitlement in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            guard let plan = SubscriptionManager.plan(for: transaction.productID) else { continue }
            if planPriority(plan) > planPriority(highestPlan) {
                highestPlan = plan
            }
        }
        SubscriptionManager.setPlan(highestPlan)
    }

    private func apply(storeTransaction: StoreKit.Transaction) {
        guard let plan = SubscriptionManager.plan(for: storeTransaction.productID) else { return }
        SubscriptionManager.setPlan(plan)
    }

    private func planPriority(_ plan: SubscriptionPlan) -> Int {
        SubscriptionManager.planCatalog.first(where: { $0.plan == plan })?.priority ?? 0
    }
}
