//
//  AccountSpendingAlertStore.swift
//  FrugalPilot
//
//  Created by Codex on 3/3/26.
//

import Foundation

enum AccountSpendingAlertStore {
    private static let thresholdsKey = "account_spending_alert_thresholds_v1"
    private static let notifiedKey = "account_spending_alert_notified_v1"

    static func loadThresholds() -> [UUID: Decimal] {
        guard let rawMap = UserDefaults.standard.dictionary(forKey: thresholdsKey) as? [String: String] else {
            return [:]
        }

        var result: [UUID: Decimal] = [:]
        for (key, value) in rawMap {
            guard let accountID = UUID(uuidString: key), let threshold = Decimal(string: value) else { continue }
            result[accountID] = threshold
        }
        return result
    }

    static func setThreshold(_ threshold: Decimal?, for accountID: UUID) {
        var rawMap = UserDefaults.standard.dictionary(forKey: thresholdsKey) as? [String: String] ?? [:]
        if let threshold {
            rawMap[accountID.uuidString] = NSDecimalNumber(decimal: threshold).stringValue
        } else {
            rawMap.removeValue(forKey: accountID.uuidString)
        }
        UserDefaults.standard.set(rawMap, forKey: thresholdsKey)
    }

    static func isNotified(for accountID: UUID) -> Bool {
        let map = UserDefaults.standard.dictionary(forKey: notifiedKey) as? [String: Bool] ?? [:]
        return map[accountID.uuidString] ?? false
    }

    static func setNotified(_ isNotified: Bool, for accountID: UUID) {
        var map = UserDefaults.standard.dictionary(forKey: notifiedKey) as? [String: Bool] ?? [:]
        map[accountID.uuidString] = isNotified
        UserDefaults.standard.set(map, forKey: notifiedKey)
    }

    static func exportThresholdsRaw(filteredTo accountIDs: Set<UUID>? = nil) -> [String: String] {
        let map = UserDefaults.standard.dictionary(forKey: thresholdsKey) as? [String: String] ?? [:]
        guard let accountIDs else { return map }
        let allowed = Set(accountIDs.map(\.uuidString))
        return map.filter { allowed.contains($0.key) }
    }

    static func importThresholdsRaw(_ rawMap: [String: String], merge: Bool) {
        var target: [String: String] = merge
            ? (UserDefaults.standard.dictionary(forKey: thresholdsKey) as? [String: String] ?? [:])
            : [:]
        for (key, value) in rawMap {
            target[key] = value
        }
        UserDefaults.standard.set(target, forKey: thresholdsKey)
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: thresholdsKey)
        UserDefaults.standard.removeObject(forKey: notifiedKey)
    }
}
