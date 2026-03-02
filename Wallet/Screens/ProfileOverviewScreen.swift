//
//  ProfileOverviewScreen.swift
//  FrugalPilot
//
//  Created by Codex on 2/3/26.
//

import SwiftUI
import SwiftData

struct ProfileOverviewScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @AppStorage("theme_is_dark") private var themeIsDark: Bool = true
    @AppStorage("apple_user_id") private var appleUserId: String = ""
    @AppStorage("apple_user_name") private var appleUserName: String = ""
    @AppStorage("app_lock_enabled") private var appLockEnabled: Bool = false
    @AppStorage("category_preset") private var categoryPresetRaw: String = CategoryPreset.singapore.rawValue
    @AppStorage("tracking_current_profile") private var currentProfileRaw: String = "Personal"
    @AppStorage("cloud_sync_active") private var cloudSyncActive: Bool = false
    @AppStorage(SubscriptionManager.planKey) private var planRaw: String = SubscriptionPlan.free.rawValue

    @Query(sort: [SortDescriptor(\Account.bankName), SortDescriptor(\Account.accountName)])
    private var allAccounts: [Account]
    @Query(sort: [SortDescriptor(\Transaction.date, order: .reverse)])
    private var allTransactions: [Transaction]
    @Query(sort: [SortDescriptor(\FixedPayment.startDate, order: .reverse)])
    private var allFixedPayments: [FixedPayment]
    @Query(sort: [SortDescriptor(\CustomCategory.name)])
    private var allCustomCategories: [CustomCategory]

    @State private var budgets: [BudgetEnvelopeData] = []
    @State private var goals: [SavingsGoalData] = []
    @State private var reminders: [BillReminderData] = []
    @State private var rules: [AutoCategoryRuleData] = []

    private var currentPlan: SubscriptionPlan {
        SubscriptionPlan(rawValue: planRaw) ?? .free
    }

    private var currentProfileName: String {
        let trimmed = currentProfileRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Personal" : trimmed
    }

    private var profileAccounts: [Account] {
        allAccounts.filter { normalizedProfile($0.profileName) == currentProfileName }
    }

    private var profileAccountIds: Set<UUID> {
        Set(profileAccounts.map(\.id))
    }

    private var profileTransactions: [Transaction] {
        allTransactions.filter { profileAccountIds.contains($0.accountId) }
    }

    private var profileFixedPayments: [FixedPayment] {
        allFixedPayments.filter { normalizedProfile($0.profileName) == currentProfileName }
    }

    private var profileCustomCategories: [CustomCategory] {
        allCustomCategories.filter { category in
            let key = category.name.lowercased()
            return profileTransactions.contains(where: { $0.categoryName.lowercased() == key })
        }
    }

    private var profileBudgets: [BudgetEnvelopeData] {
        budgets.filter { normalizedProfile($0.profileName) == currentProfileName }
    }

    private var profileGoals: [SavingsGoalData] {
        goals.filter { normalizedProfile($0.profileName) == currentProfileName }
    }

    private var profileReminders: [BillReminderData] {
        reminders.filter { normalizedProfile($0.profileName) == currentProfileName }
    }

    private var profileRules: [AutoCategoryRuleData] {
        rules.filter { normalizedProfile($0.profileName) == currentProfileName }
    }

    private var spentThisMonth: Decimal {
        let monthStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
        return profileTransactions
            .filter { $0.type == .expense && $0.date >= monthStart }
            .reduce(.zero) { $0 + $1.amount }
    }

    private var incomeThisMonth: Decimal {
        let monthStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
        return profileTransactions
            .filter { $0.type == .income && $0.date >= monthStart }
            .reduce(.zero) { $0 + $1.amount }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundGradient.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionCard("Profile") {
                            infoRow("Current Profile", currentProfileName)
                            infoRow("Apple Account", appleUserId.isEmpty ? "Not signed in" : (appleUserName.isEmpty ? "Apple User" : appleUserName))
                            infoRow("Subscription", currentPlan.rawValue)
                            infoRow("All Features on Free", SubscriptionManager.allFeaturesFree ? "Enabled" : "Disabled")
                        }

                        sectionCard("Sync & Security") {
                            infoRow("iCloud Sync Active", cloudSyncActive ? "Yes" : "No")
                            infoRow("Face ID Unlock", appLockEnabled ? "Enabled" : "Disabled")
                            infoRow("Dark Mode", themeIsDark ? "On" : "Off")
                            infoRow("Category Preset", categoryPresetRaw)
                        }

                        sectionCard("Usage Summary") {
                            infoRow("Accounts", "\(profileAccounts.count)")
                            infoRow("Transactions", "\(profileTransactions.count)")
                            infoRow("Fixed Plans", "\(profileFixedPayments.count)")
                            infoRow("Custom Categories", "\(profileCustomCategories.count)")
                            infoRow("Spent This Month", CurrencyFormatter.sgd(amount: spentThisMonth))
                            infoRow("Income This Month", CurrencyFormatter.sgd(amount: incomeThisMonth))
                        }

                        sectionCard("Smart Tools") {
                            infoRow("Budgets", "\(profileBudgets.count)")
                            infoRow("Savings Goals", "\(profileGoals.count)")
                            infoRow("Bill Reminders", "\(profileReminders.count)")
                            infoRow("Auto Rules", "\(profileRules.count)")
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Profile & Usage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(themeIsDark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(theme.textPrimary)
                }
            }
            .onAppear(perform: reloadSmartData)
        }
    }

    private func normalizedProfile(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Personal" : trimmed
    }

    private func reloadSmartData() {
        budgets = SmartDataStore.loadBudgets()
        goals = SmartDataStore.loadGoals()
        reminders = SmartDataStore.loadReminders()
        rules = SmartDataStore.loadRules()
    }

    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.custom("Avenir Next", size: 14).weight(.bold))
                .foregroundStyle(theme.textPrimary)
            content()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.surface))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.custom("Avenir Next", size: 12).weight(.semibold))
                .foregroundStyle(theme.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.custom("Avenir Next", size: 12).weight(.medium))
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}
