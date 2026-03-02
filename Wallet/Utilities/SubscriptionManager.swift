//
//  SubscriptionManager.swift
//  FrugalPilot
//
//  Created by Codex on 27/2/26.
//

import Foundation

enum SubscriptionPlan: String, CaseIterable, Identifiable {
    case free
    case proLiteMonthly
    case proLiteYearly
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
    // Temporary rollout flag: keep every feature unlocked while still preserving StoreKit plumbing.
    static let allFeaturesFree = false
    static let freeAccountLimit = 3
    static let freeMonthlyTransactionLimit = 200
    static let unlimitedCountText = "Unlimited"

    static var currentPlan: SubscriptionPlan {
        if let raw = UserDefaults.standard.string(forKey: planKey),
           let plan = SubscriptionPlan(rawValue: raw) {
            return plan
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
        allFeaturesFree ? unlimitedCountText : String(freeAccountLimit)
    }

    static var monthlyTransactionLimitText: String {
        allFeaturesFree ? unlimitedCountText : String(freeMonthlyTransactionLimit)
    }

    static var hasPaidLimits: Bool {
        if allFeaturesFree { return true }
        switch currentPlan {
        case .free: return false
        case .proLiteMonthly, .proLiteYearly, .proMonthly, .proYearly, .lifetime:
            return true
        }
    }

    static var hasProFeatures: Bool {
        if allFeaturesFree { return true }
        switch currentPlan {
        case .proMonthly, .proYearly, .lifetime:
            return true
        case .free, .proLiteMonthly, .proLiteYearly:
            return false
        }
    }

    static var hasICloudSync: Bool {
        if allFeaturesFree { return true }
        return hasProFeatures
    }

    static var hasAppLock: Bool {
        if allFeaturesFree { return true }
        return hasProFeatures
    }

    static var isProLite: Bool {
        switch currentPlan {
        case .proLiteMonthly, .proLiteYearly: return true
        default: return false
        }
    }

    static func productID(for plan: SubscriptionPlan) -> String? {
        productIDs(for: plan).first
    }

    static func productIDs(for plan: SubscriptionPlan) -> [String] {
        switch plan {
        case .free:
            return []
        case .proLiteMonthly:
            return [
                "ahhweii.frugalpilot.prolite.monthly",
                "ahhweii.Frugal-Pilot.prolite.monthly",
                "ahhweii.FrugalPilot.prolite.monthly"
            ]
        case .proLiteYearly:
            return [
                "ahhweii.frugalpilot.prolite.yearly",
                "ahhweii.Frugal-Pilot.prolite.yearly",
                "ahhweii.FrugalPilot.prolite.yearly"
            ]
        case .proMonthly:
            return [
                "ahhweii.frugalpilot.pro.monthly",
                "ahhweii.Frugal-Pilot.pro.monthly",
                "ahhweii.FrugalPilot.pro.monthly"
            ]
        case .proYearly:
            return [
                "ahhweii.frugalpilot.pro.yearly",
                "ahhweii.Frugal-Pilot.pro.yearly",
                "ahhweii.FrugalPilot.pro.yearly"
            ]
        case .lifetime:
            return [
                "ahhweii.frugalpilot.lifetime",
                "ahhweii.Frugal-Pilot.lifetime",
                "ahhweii.FrugalPilot.lifetime"
            ]
        }
    }

    static func plan(for storeProductID: String) -> SubscriptionPlan? {
        SubscriptionPlan.allCases.first { plan in
            productIDs(for: plan).contains(storeProductID)
        }
    }

    static var planCatalog: [SubscriptionPlanDescriptor] {
        [
            SubscriptionPlanDescriptor(plan: .proLiteMonthly,
                                       title: "Pro Lite Monthly",
                                       subtitle: "Unlimited accounts and transactions",
                                       priority: 1),
            SubscriptionPlanDescriptor(plan: .proLiteYearly,
                                       title: "Pro Lite Yearly",
                                       subtitle: "Unlimited accounts and transactions",
                                       priority: 2),
            SubscriptionPlanDescriptor(plan: .proMonthly,
                                       title: "Pro Monthly",
                                       subtitle: "Face ID unlock and premium features",
                                       priority: 3),
            SubscriptionPlanDescriptor(plan: .proYearly,
                                       title: "Pro Yearly",
                                       subtitle: "Face ID unlock and premium features",
                                       priority: 4),
            SubscriptionPlanDescriptor(plan: .lifetime,
                                       title: "Lifetime",
                                       subtitle: "All premium features forever",
                                       priority: 5)
        ]
    }
}
