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

    private var didLoadProducts: Bool = false
    private var productsByID: [String: Product] {
        Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
    }

    func prepareIfNeeded() async {
        guard didLoadProducts == false else { return }
        await loadProducts()
        await refreshEntitlements()
    }

    func loadProducts() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let ids = Array(Set(SubscriptionPlan.allCases
            .flatMap { SubscriptionManager.productIDs(for: $0) }))
        do {
            let loaded = try await Product.products(for: ids)
            products = loaded.sorted { lhs, rhs in
                lhs.price < rhs.price
            }
            let unavailablePlans = SubscriptionManager.planCatalog
                .map(\.plan)
                .filter { product(for: $0) == nil }
            if loaded.isEmpty {
                statusMessage = "No App Store products were returned. Please try again later."
            } else if !unavailablePlans.isEmpty {
                statusMessage = "Some plans are currently unavailable. Please try again later."
            }
            didLoadProducts = true
        } catch {
            statusMessage = "Could not load App Store products."
        }
    }

    func product(for plan: SubscriptionPlan) -> Product? {
        for productID in SubscriptionManager.productIDs(for: plan) {
            if let product = productsByID[productID] {
                return product
            }
        }
        return nil
    }

    func purchase(plan: SubscriptionPlan) async {
        if products.isEmpty || !didLoadProducts {
            await loadProducts()
        }

        guard let product = product(for: plan) else {
            statusMessage = "This plan is not available for purchase right now."
            return
        }
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    _ = await SubscriptionManager.refreshPlanFromStoreKit()
                    await transaction.finish()
                    statusMessage = "Purchase successful."
                case .unverified(_, let verificationError):
                    let nsError = verificationError as NSError
                    statusMessage = "Purchase could not be verified (\(nsError.domain) \(nsError.code))."
                }
            case .userCancelled:
                let planBefore = SubscriptionManager.currentPlan
                // Some environments briefly return `userCancelled` while entitlement updates are still propagating.
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                var planAfter = await SubscriptionManager.refreshPlanFromStoreKit()
                if planAfter != planBefore {
                    statusMessage = "Purchase successful."
                    return
                }

                // Secondary recovery: request App Store sync, then re-check entitlements.
                do {
                    try await AppStore.sync()
                    planAfter = await SubscriptionManager.refreshPlanFromStoreKit()
                    if planAfter != planBefore {
                        statusMessage = "Purchase successful."
                    } else {
                        statusMessage = "Purchase was not completed."
                    }
                } catch {
                    statusMessage = "Purchase was not completed."
                }
            case .pending:
                statusMessage = "Purchase is pending approval."
            @unknown default:
                statusMessage = "Purchase could not be completed."
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
        _ = await SubscriptionManager.refreshPlanFromStoreKit()
    }
}
