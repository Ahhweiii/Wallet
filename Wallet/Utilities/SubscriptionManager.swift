//
//  SubscriptionManager.swift
//  FrugalPilot
//
//  Created by Codex on 27/2/26.
//

import Foundation
import StoreKit

enum SubscriptionPlan: String, CaseIterable, Identifiable {
    case free
    case proMonthly
    case proYearly
    case lifetime

    var id: String { rawValue }
}

struct SubscriptionPlanDescriptor: Identifiable {
    let plan: SubscriptionPlan
    let title: String
    let subtitle: String
    let priority: Int
    var id: SubscriptionPlan { plan }
}

enum SubscriptionManager {
    static let planKey = "subscription_plan"
    static let legacyProEnabledKey = "pro_enabled"
    static let freeAccountLimit = 3
    static let freeMonthlyTransactionLimit = 200
    static let unlimitedCountText = "Unlimited"
    static let planCatalog: [SubscriptionPlanDescriptor] = [
        SubscriptionPlanDescriptor(plan: .proMonthly,
                                   title: "Pro - Monthly",
                                   subtitle: "All premium features",
                                   priority: 1),
        SubscriptionPlanDescriptor(plan: .proYearly,
                                   title: "Pro - Yearly",
                                   subtitle: "All premium features",
                                   priority: 2),
        SubscriptionPlanDescriptor(plan: .lifetime,
                                   title: "Lifetime",
                                   subtitle: "All premium features forever",
                                   priority: 3)
    ]
    private static var updatesListenerTask: Task<Void, Never>?
    private static let productIDsByPlan: [SubscriptionPlan: [String]] = [
        .free: [],
        .proMonthly: [
            "ahhweii.frugalpilot.pro.monthly"
        ],
        .proYearly: [
            "ahhweii.frugalpilot.pro.yearly"
        ],
        .lifetime: [
            "ahhweii.frugalpilot.lifetime.v2"
        ]
    ]
    private static let productIDToPlan: [String: SubscriptionPlan] = {
        var map: [String: SubscriptionPlan] = [:]
        for (plan, productIDs) in productIDsByPlan {
            for productID in productIDs {
                map[productID] = plan
            }
        }
        return map
    }()
    private static let planPriorityByPlan: [SubscriptionPlan: Int] = {
        Dictionary(uniqueKeysWithValues: planCatalog.map { ($0.plan, $0.priority) })
    }()

    static var currentPlan: SubscriptionPlan {
        if let raw = UserDefaults.standard.string(forKey: planKey) {
            if let plan = SubscriptionPlan(rawValue: raw) {
                return plan
            }
        }
        if UserDefaults.standard.bool(forKey: legacyProEnabledKey) {
            UserDefaults.standard.set(SubscriptionPlan.proMonthly.rawValue, forKey: planKey)
            return .proMonthly
        }
        return .free
    }

    static func setPlan(_ plan: SubscriptionPlan) {
        UserDefaults.standard.set(plan.rawValue, forKey: planKey)
    }

    static var accountLimitText: String {
        hasPaidLimits ? unlimitedCountText : String(freeAccountLimit)
    }

    static var monthlyTransactionLimitText: String {
        hasPaidLimits ? unlimitedCountText : String(freeMonthlyTransactionLimit)
    }

    static var hasPaidLimits: Bool {
        currentPlan != .free
    }

    static var hasProFeatures: Bool {
        hasPaidLimits
    }

    static var hasICloudSync: Bool {
        true
    }

    static var hasAppLock: Bool {
        return hasProFeatures
    }

    static func displayName(for plan: SubscriptionPlan) -> String {
        switch plan {
        case .free: return "Free"
        case .proMonthly: return "Pro Monthly"
        case .proYearly: return "Pro Yearly"
        case .lifetime: return "Lifetime"
        }
    }

    static func productIDs(for plan: SubscriptionPlan) -> [String] {
        productIDsByPlan[plan] ?? []
    }

    static func plan(for storeProductID: String) -> SubscriptionPlan? {
        productIDToPlan[storeProductID]
    }

    static func refreshPlanFromStoreKit() async -> SubscriptionPlan {
        var highestPlan: SubscriptionPlan = .free
        for await entitlement in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            guard let plan = plan(for: transaction.productID) else { continue }
            if planPriority(plan) > planPriority(highestPlan) {
                highestPlan = plan
            }
        }
        setPlan(highestPlan)
        return highestPlan
    }

    static func startTransactionUpdatesListener() {
        guard updatesListenerTask == nil else { return }
        updatesListenerTask = Task.detached(priority: .background) {
            // Ensure state is accurate at startup before waiting for incoming updates.
            _ = await refreshPlanFromStoreKit()

            for await update in StoreKit.Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                _ = await refreshPlanFromStoreKit()
                await transaction.finish()
            }
        }
    }

    private static func planPriority(_ plan: SubscriptionPlan) -> Int {
        planPriorityByPlan[plan] ?? 0
    }

}
