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

enum SubscriptionManager {
    static let planKey = "subscription_plan"
    static let legacyProEnabledKey = "pro_enabled"
    static let freeAccountLimit = 3
    static let freeMonthlyTransactionLimit = 200

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

    static var hasPaidLimits: Bool {
        switch currentPlan {
        case .free: return false
        case .proLiteMonthly, .proLiteYearly, .proMonthly, .proYearly, .lifetime:
            return true
        }
    }

    static var hasProFeatures: Bool {
        switch currentPlan {
        case .proMonthly, .proYearly, .lifetime:
            return true
        case .free, .proLiteMonthly, .proLiteYearly:
            return false
        }
    }

    static var hasICloudSync: Bool {
        hasProFeatures
    }

    static var hasAppLock: Bool {
        hasProFeatures
    }

    static var isProLite: Bool {
        switch currentPlan {
        case .proLiteMonthly, .proLiteYearly: return true
        default: return false
        }
    }
}
