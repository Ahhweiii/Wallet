//
//  AccountSettingsStore.swift
//  FrugalPilot
//
//  Created by Codex on 2/3/26.
//

import Foundation

struct AccountSettingsSnapshot: Codable {
    var themeIsDark: Bool
    var appLockEnabled: Bool
    var categoryPresetRaw: String
    var currentProfileRaw: String
    var trackingProfilesRaw: String
}

enum AccountSettingsStore {
    private static let storagePrefix = "account_settings_v1_"

    private static let themeKey = "theme_is_dark"
    private static let appLockKey = "app_lock_enabled"
    private static let categoryPresetKey = "category_preset"
    private static let currentProfileKey = "tracking_current_profile"
    private static let trackingProfilesKey = "tracking_profiles"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func saveCurrentSettings(for appleUserId: String) {
        let trimmed = appleUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let defaults = UserDefaults.standard
        let snapshot = AccountSettingsSnapshot(
            themeIsDark: defaults.object(forKey: themeKey) as? Bool ?? true,
            appLockEnabled: defaults.object(forKey: appLockKey) as? Bool ?? false,
            categoryPresetRaw: defaults.string(forKey: categoryPresetKey) ?? "Singapore",
            currentProfileRaw: defaults.string(forKey: currentProfileKey) ?? "Personal",
            trackingProfilesRaw: defaults.string(forKey: trackingProfilesKey) ?? "Personal"
        )

        guard let data = try? encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: storagePrefix + trimmed)
    }

    static func restoreSettings(for appleUserId: String) {
        let trimmed = appleUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: storagePrefix + trimmed),
              let snapshot = try? decoder.decode(AccountSettingsSnapshot.self, from: data) else {
            return
        }

        defaults.set(snapshot.themeIsDark, forKey: themeKey)
        defaults.set(snapshot.appLockEnabled, forKey: appLockKey)
        defaults.set(snapshot.categoryPresetRaw, forKey: categoryPresetKey)
        defaults.set(snapshot.currentProfileRaw, forKey: currentProfileKey)
        defaults.set(snapshot.trackingProfilesRaw, forKey: trackingProfilesKey)
    }
}
