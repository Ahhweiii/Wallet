//
//  DashboardScreen.swift
//  FrugalPilot
//
//  Created by Lee Jun Wei on 21/2/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AuthenticationServices
import StoreKit
import UIKit
import UserNotifications

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private enum TransactionFilterType: String, CaseIterable, Identifiable {
    case all = "All"
    case expense = "Expense"
    case income = "Income"
    case transfer = "Transfer"
    var id: String { rawValue }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case apple = "Apple"
    case security = "Security"
    case preferences = "Preferences"
    var id: String { rawValue }
}

struct DashboardScreen: View {
    @StateObject private var vm: DashboardViewModel
    @StateObject private var store = StoreSubscriptionStore()
    @Environment(\.appTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("theme_is_dark") private var themeIsDark: Bool = true
    @AppStorage("app_lock_enabled") private var appLockEnabled: Bool = false
    @AppStorage(SubscriptionManager.planKey) private var planRaw: String = SubscriptionPlan.free.rawValue
    @AppStorage("category_preset") private var categoryPresetRaw: String = CategoryPreset.singapore.rawValue
    @AppStorage("tracking_current_profile") private var currentProfileRaw: String = "Personal"
    @AppStorage("tracking_profiles") private var trackingProfilesRaw: String = "Personal"
    private var currentPlan: SubscriptionPlan { SubscriptionPlan(rawValue: planRaw) ?? .free }
    private var hasPremiumAccess: Bool { SubscriptionManager.hasProFeatures }

    @State private var selectedTab: Int = 0
    @State private var showSidePanel: Bool = false
    @State private var accountPage: Int = 0
    @State private var showAddAccount: Bool = false
    @State private var showAddTransaction: Bool = false
    @State private var pendingQuickAddDraft: TransactionQuickAddDraft? = nil
    @State private var showBreakdown: Bool = false
    @State private var selectedAccount: Account? = nil

    @State private var showSettingsSheet = false
    @State private var showBackupSheet = false
    @State private var showSmartToolsSheet = false
    @State private var showAutomationSetupSheet = false
    @State private var showProfileOverviewSheet = false
    @State private var showNotificationsSheet = false
    @State private var showBackupExporter = false
    @State private var showBackupImporter = false
    @State private var exportBackupDocument = FrugalPilotBackupDocument()
    @State private var exportFilename = "FrugalPilotBackup.json"
    @State private var pendingImportURL: URL? = nil
    @State private var showImportStrategyDialog = false
    @State private var isImportingBackup = false
    @State private var importOutcomeTitle = "Import Backup"
    @State private var importOutcomeMessage = ""
    @State private var showImportOutcomeAlert = false
    @State private var appleSignInMessage = ""
    @State private var showAppleSignInAlert = false
    @AppStorage("apple_user_id") private var appleUserId: String = ""
    @AppStorage("apple_user_name") private var appleUserName: String = ""
    @AppStorage("cloud_sync_active") private var cloudSyncActive: Bool = false

    @State private var errorMessage: String? = nil
    @State private var showErrorAlert = false
    @State private var selectedSettingsTab: SettingsTab = .apple
    @State private var storeStatusMessage: String = ""
    @State private var showStoreStatusAlert: Bool = false
    @State private var showAddProfilePrompt = false
    @State private var showDeleteProfileDialog = false
    @State private var pendingDeleteProfile: String? = nil
    @State private var newProfileName = ""
    @State private var transactionSearchText: String = ""
    @State private var transactionFilterType: TransactionFilterType = .all
    @State private var filteredTransactionsCache: [Transaction] = []
    @State private var dueReminderCount: Int = 0
    @State private var remindersCache: [BillReminderData] = []
    @State private var spendingAlertThresholds: [UUID: Decimal] = [:]
    @State private var spendingAlertInputByAccountID: [UUID: String] = [:]

    private let maxPerPage: Int = 4
    private let maxRecentTransactions: Int = 20
    private let sidePanelWidth: CGFloat = 260
    private let dashboardHeaderHeight: CGFloat = 84

    private var currentProfileName: String {
        let trimmed = currentProfileRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Personal" : trimmed
    }

    private var trackingProfiles: [String] {
        let base = trackingProfilesRaw
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if base.isEmpty { return ["Personal"] }
        var seen = Set<String>()
        var result: [String] = []
        for name in base where !seen.contains(name.lowercased()) {
            seen.insert(name.lowercased())
            result.append(name)
        }
        return result
    }

    private var currentProfileAccounts: [Account] {
        vm.accounts.filter {
            $0.profileName.trimmingCharacters(in: .whitespacesAndNewlines) == currentProfileName
        }
    }

    init(modelContext: ModelContext) {
        _vm = StateObject(wrappedValue: DashboardViewModel(modelContext: modelContext))
    }

    // Each account card shows spending within its own billing cycle (current period)
    private var totalSpentByAccountId: [UUID: Decimal] {
        var dict: [UUID: Decimal] = [:]
        for acct in vm.accounts {
            if acct.type == .cash {
                dict[acct.id] = acct.amount
            } else {
                dict[acct.id] = vm.periodExpenses(for: acct.id, monthOffset: 0)
            }
        }
        return dict
    }

    // Subtitle shows the billing period date range
    private var subtitleByAccountId: [UUID: String] {
        var dict: [UUID: String] = [:]
        for acct in vm.accounts {
            if acct.type == .cash {
                dict[acct.id] = "Total Cash Available"
            } else {
                dict[acct.id] = vm.billingPeriodLabel(for: acct, monthOffset: 0)
            }
        }
        return dict
    }

    private var totalCards: Int { vm.accounts.count + 1 }

    private var pagesCount: Int {
        AccountsPagerView.pageCount(totalCards: totalCards, maxPerPage: maxPerPage)
    }

    private var canAddAccount: Bool {
        vm.canAddAccount()
    }

    private var safeTimestampString: String {
        DashboardFormatterCache.backupFilenameTimestamp.string(from: Date())
    }

    var body: some View {
        let nav = NavigationStack {
            mainStack
                .navigationDestination(item: $selectedAccount) { acct in
                    AccountDetailScreen(vm: vm, accountId: acct.id)
                }
        }
        return applyLifecycle(
            applyDialogs(
                applySheets(nav)
            )
        )
    }

    private func applySheets<V: View>(_ view: V) -> some View {
        view
            .sheet(isPresented: $showAddAccount) {
                AddAccountScreen(vm: vm) { bank, account, amount, type, credit, pooled, billingDay, colorHex in
                    let added = vm.addAccount(bankName: bank,
                                              accountName: account,
                                              amount: amount,
                                              type: type,
                                              currentCredit: credit,
                                              isInCombinedCreditPool: pooled,
                                              billingCycleStartDay: billingDay,
                                              profileName: currentProfileName,
                                              colorHex: colorHex)
                    if !added {
                        errorMessage = "Free tier allows up to \(SubscriptionManager.accountLimitText) accounts. Upgrade to Pro for unlimited accounts."
                        showErrorAlert = true
                    }
                }
            }
            .sheet(isPresented: $showAddTransaction) {
                AddTransactionScreen(vm: vm, initialDraft: pendingQuickAddDraft) {
                    pendingQuickAddDraft = nil
                }
            }
            .sheet(isPresented: $showSettingsSheet) { settingsSheet }
            .sheet(isPresented: $showBackupSheet) { backupSheet }
            .sheet(isPresented: $showSmartToolsSheet) {
                SmartToolsScreen(currentProfileName: currentProfileName)
            }
            .sheet(isPresented: $showAutomationSetupSheet) {
                AutomationSetupScreen()
            }
            .sheet(isPresented: $showProfileOverviewSheet) {
                ProfileOverviewScreen()
            }
            .sheet(isPresented: $showNotificationsSheet) {
                notificationsSheet
            }
    }

    private func applyDialogs<V: View>(_ view: V) -> some View {
        view
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
            .alert("Subscription", isPresented: $showStoreStatusAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(storeStatusMessage)
            }
            .alert(importOutcomeTitle, isPresented: $showImportOutcomeAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(importOutcomeMessage)
            }
            .alert("Apple ID", isPresented: $showAppleSignInAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(appleSignInMessage)
            }
            .alert("New Profile", isPresented: $showAddProfilePrompt) {
                TextField("e.g. Side Hustle", text: $newProfileName)
                Button("Add") { addProfile() }
                Button("Cancel", role: .cancel) { newProfileName = "" }
            } message: {
                Text("Create a separate profile to track a different set of accounts and expenses.")
            }
            .confirmationDialog("Delete Profile",
                                isPresented: $showDeleteProfileDialog,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    guard let profile = pendingDeleteProfile else { return }
                    deleteProfile(profile)
                    pendingDeleteProfile = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteProfile = nil
                }
            } message: {
                if let profile = pendingDeleteProfile {
                    Text("Delete profile '\(profile)' and all its accounts, transactions, and fixed plans?")
                }
            }
    }

    private func applyLifecycle<V: View>(_ view: V) -> some View {
        view
            .onAppear {
                restoreSettingsIfSignedIn()
                if trackingProfilesRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    trackingProfilesRaw = "Personal"
                }
                if currentProfileRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    currentProfileRaw = "Personal"
                }
                if !trackingProfiles.contains(where: { $0.caseInsensitiveCompare(currentProfileName) == .orderedSame }) {
                    currentProfileRaw = trackingProfiles.first ?? "Personal"
                }
                planRaw = SubscriptionManager.currentPlan.rawValue
                refreshSubscriptionState()
                vm.setActiveProfile(currentProfileName)
                vm.fetchAll()
                refreshDerivedDashboardData()
                loadSpendingAlertEditorState()
                evaluateAccountSpendingAlerts()
                consumePendingQuickAddDraftIfNeeded()
            }
            .onChange(of: currentProfileRaw) { _, newValue in
                vm.setActiveProfile(newValue)
                vm.fetchAll()
                persistCurrentSettingsIfSignedIn()
                refreshDueReminderCount()
                loadSpendingAlertEditorState()
                evaluateAccountSpendingAlerts()
            }
            .onChange(of: trackingProfilesRaw) { _, _ in
                persistCurrentSettingsIfSignedIn()
            }
            .onChange(of: categoryPresetRaw) { _, _ in
                persistCurrentSettingsIfSignedIn()
            }
            .onChange(of: vm.accounts.count) { _, _ in
                accountPage = min(accountPage, max(0, pagesCount - 1))
                refreshFilteredTransactions()
                loadSpendingAlertEditorState()
                evaluateAccountSpendingAlerts()
            }
            .onChange(of: vm.transactions.count) { _, _ in
                refreshFilteredTransactions()
                evaluateAccountSpendingAlerts()
            }
            .onChange(of: transactionSearchText) { _, _ in
                refreshFilteredTransactions()
            }
            .onChange(of: transactionFilterType) { _, _ in
                refreshFilteredTransactions()
            }
            .onChange(of: store.statusMessage) { _, message in
                guard let message, !message.isEmpty else { return }
                storeStatusMessage = message
                showStoreStatusAlert = true
            }
            .onChange(of: showAddTransaction) { _, isPresented in
                if !isPresented {
                    pendingQuickAddDraft = nil
                }
            }
            .onChange(of: showNotificationsSheet) { _, isPresented in
                if isPresented {
                    refreshRemindersCache()
                    loadSpendingAlertEditorState()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                refreshSubscriptionState()
                consumePendingQuickAddDraftIfNeeded()
                refreshRemindersCache()
                evaluateAccountSpendingAlerts()
            }
            .onReceive(NotificationCenter.default.publisher(for: .quickAddDraftUpdated)) { _ in
                consumePendingQuickAddDraftIfNeeded()
            }
    }

    private var mainStack: some View {
        ZStack(alignment: .topLeading) {
            theme.backgroundGradient.ignoresSafeArea()

            tabContent

            if selectedTab == 0 {
                FloatingAddButton { showAddTransaction = true }
                    .padding(.trailing, 22)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }

            if showSidePanel {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSidePanel = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(15)
            }

            sidePanel
                .offset(x: showSidePanel ? 0 : -sidePanelWidth - 24)
                .allowsHitTesting(showSidePanel)
                .zIndex(20)

            if selectedTab == 0 {
                dashboardFixedHeader
                    .zIndex(12)
            } else {
                HStack {
                    menuButton
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .zIndex(12)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: showSidePanel)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case 0:
            dashboardTab
        case 1:
            PlanningScreen()
        case 2:
            if hasPremiumAccess {
                StatisticsScreen()
            } else {
                premiumLockedView(
                    title: "Pro Feature",
                    message: "Advanced statistics and debt planner are available in Pro or Lifetime."
                )
            }
        case 3:
            moreTab
        default:
            placeholderTab
        }
    }

    private func premiumLockedView(title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(theme.accent)
            Text(title)
                .font(.custom("Avenir Next", size: 18).weight(.bold))
                .foregroundStyle(theme.textPrimary)
            Text(message)
                .font(.custom("Avenir Next", size: 13).weight(.medium))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("View Plans") {
                selectedSettingsTab = .apple
                showSettingsSheet = true
            }
            .font(.custom("Avenir Next", size: 13).weight(.semibold))
            .foregroundStyle(theme.accent)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dashboardTab: some View {
        ScrollView {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: ScrollOffsetKey.self,
                                value: proxy.frame(in: .named("dashboard-scroll")).minY)
            }
            .frame(height: 0)

            LazyVStack(spacing: 18) {
                // ── Monthly Spending Card ──
                MonthlySpendingCardView(vm: vm, showBreakdown: $showBreakdown)
                    .padding(.horizontal, 18)

                AccountsPagerView(
                    accounts: vm.accounts,
                    totalSpentByAccountId: totalSpentByAccountId,
                    subtitleByAccountId: subtitleByAccountId,
                    pageIndex: $accountPage,
                    maxPerPage: maxPerPage,
                    canAddAccount: canAddAccount,
                    onAddAccount: {
                        if canAddAccount {
                            showAddAccount = true
                        } else {
                            errorMessage = "Free tier allows up to \(SubscriptionManager.accountLimitText) accounts. Upgrade to Pro for unlimited accounts."
                            showErrorAlert = true
                        }
                    },
                    onTapAccount: { selectedAccount = $0 }
                )
                .padding(.horizontal, 18)

                PageDotsView(count: pagesCount, index: accountPage)
                    .padding(.top, 2)

                recentTransactions

                Spacer(minLength: 24)
            }
            .padding(.top, dashboardHeaderHeight)
            .padding(.bottom, 32)
        }
        .coordinateSpace(name: "dashboard-scroll")
        .onPreferenceChange(ScrollOffsetKey.self) { offset in
            if showBreakdown && offset < -20 {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showBreakdown = false
                }
            }
        }
    }

    // MARK: - Top Bar

    private var dashboardFixedHeader: some View {
        HStack {
            menuButton

            VStack(alignment: .leading, spacing: 2) {
                Text("FrugalPilot")
                    .font(.custom("Avenir Next", size: 22).weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Menu {
                    ForEach(trackingProfiles, id: \.self) { profile in
                        Button {
                            currentProfileRaw = profile
                        } label: {
                            Label(profile, systemImage: profile == currentProfileName ? "checkmark" : "person.crop.circle")
                        }
                    }
                    let deletable = trackingProfiles.filter { $0.caseInsensitiveCompare("Personal") != .orderedSame }
                    if deletable.isEmpty == false {
                        Divider()
                        ForEach(deletable, id: \.self) { profile in
                            Button(role: .destructive) {
                                pendingDeleteProfile = profile
                                showDeleteProfileDialog = true
                            } label: {
                                Label("Delete \(profile)", systemImage: "trash")
                            }
                        }
                    }
                    Divider()
                    Button {
                        newProfileName = ""
                        showAddProfilePrompt = true
                    } label: {
                        Label("Add Profile", systemImage: "plus")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(currentProfileName)
                            .font(.custom("Avenir Next", size: 12).weight(.semibold))
                            .foregroundStyle(theme.textSecondary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()

            Button {
                showNotificationsSheet = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                    if dueReminderCount > 0 {
                        Text("\(min(dueReminderCount, 9))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Circle().fill(theme.negative))
                            .offset(x: 8, y: -7)
                    }
                }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(theme.surfaceAlt.opacity(0.95)))
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    themeIsDark.toggle()
                }
            } label: {
                Image(systemName: themeIsDark ? "sun.max" : "moon.stars")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(theme.surfaceAlt.opacity(0.95)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(theme.backgroundGradient)
    }

    private var menuButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showSidePanel.toggle()
            }
        } label: {
            Image(systemName: showSidePanel ? "xmark" : "line.3.horizontal")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(theme.textPrimary)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(theme.surfaceAlt.opacity(0.95))
                )
        }
        .buttonStyle(.plain)
    }

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Navigation")
                .font(.custom("Avenir Next", size: 18).weight(.bold))
                .foregroundStyle(theme.textPrimary)
                .padding(.bottom, 6)

            sidePanelItem(index: 0, title: "Dashboard", icon: "dollarsign.circle")
            sidePanelItem(index: 1, title: "Planning", icon: "clock")
            sidePanelItem(index: 2, title: "Statistics", icon: "chart.bar", isLocked: !hasPremiumAccess)
            sidePanelItem(index: 3, title: "More", icon: "ellipsis")

            Divider()
                .padding(.vertical, 6)

            Text("Profile")
                .font(.custom("Avenir Next", size: 13).weight(.bold))
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 12)

            ForEach(trackingProfiles, id: \.self) { profile in
                HStack(spacing: 8) {
                    Button {
                        currentProfileRaw = profile
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSidePanel = false
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: profile == currentProfileName ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 14, weight: .semibold))
                            Text(profile)
                                .font(.custom("Avenir Next", size: 15).weight(.semibold))
                            Spacer()
                        }
                        .foregroundStyle(profile == currentProfileName ? theme.accent : theme.textPrimary)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(profile == currentProfileName ? theme.surfaceAlt : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)

                    if profile.caseInsensitiveCompare("Personal") != .orderedSame {
                        Button(role: .destructive) {
                            pendingDeleteProfile = profile
                            showDeleteProfileDialog = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(theme.negative)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(theme.surfaceAlt))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button {
                newProfileName = ""
                showAddProfilePrompt = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle")
                    Text("Add Profile")
                        .font(.custom("Avenir Next", size: 15).weight(.semibold))
                    Spacer()
                }
                .foregroundStyle(theme.textSecondary)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 64)
        .frame(width: sidePanelWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(
            Rectangle()
                .fill(theme.surface)
                .ignoresSafeArea()
                .shadow(color: theme.shadow.opacity(0.35), radius: 16, x: 6, y: 0)
        )
    }

    private func sidePanelItem(index: Int, title: String, icon: String, isLocked: Bool = false) -> some View {
        Button {
            selectedTab = index
            withAnimation(.easeInOut(duration: 0.2)) {
                showSidePanel = false
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 24)

                Text(title)
                    .font(.custom("Avenir Next", size: 16).weight(.semibold))

                Spacer()

                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .foregroundStyle(selectedTab == index ? theme.accent : theme.textPrimary)
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selectedTab == index ? theme.surfaceAlt : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent Transactions

    private var recentTransactions: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recent Transactions")
                    .font(.custom("Avenir Next", size: 20).weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Menu {
                    Picker("Type", selection: $transactionFilterType) {
                        ForEach(TransactionFilterType.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text(transactionFilterType.rawValue)
                            .font(.custom("Avenir Next", size: 11).weight(.semibold))
                    }
                    .foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme.textTertiary)
                TextField("Search by note, category, account", text: $transactionSearchText)
                    .font(.custom("Avenir Next", size: 13).weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
            .padding(.horizontal, 18)

            if filteredTransactionsCache.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundStyle(theme.textTertiary.opacity(0.6))
                    Text("No transactions yet")
                        .font(.custom("Avenir Next", size: 14).weight(.semibold))
                        .foregroundStyle(theme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)

            } else {
                let accountMap = Dictionary(uniqueKeysWithValues: vm.accounts.map { ($0.id, $0) })
                LazyVStack(spacing: 10) {
                    ForEach(filteredTransactionsCache.prefix(maxRecentTransactions)) { txn in
                        transactionRow(txn, account: accountMap[txn.accountId])
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    // MARK: - Transaction Row

    private func transactionRow(_ txn: Transaction, account: Account?) -> some View {
        let isTransfer = txn.type == .transfer
        let isTransferOut = isTransfer && txn.categoryName == "Transfer Out"
        let isExpense = txn.type == .expense || isTransferOut
        let amountColor: Color = isTransfer ? (isTransferOut ? theme.negative : theme.positive) : (isExpense ? theme.negative : theme.positive)
        let categoryName = txn.categoryName.isEmpty ? (txn.category?.rawValue ?? "Other") : txn.categoryName
        let iconName = isTransfer ? "arrow.left.arrow.right.circle.fill" : TransactionCategory.iconSystemName(for: categoryName)
        let transferCounterparty = isTransfer ? txn.note : ""

        return HStack(spacing: 14) {
            Circle()
                .fill(amountColor.opacity(0.12))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: iconName)
                        .font(.system(size: 16))
                        .foregroundStyle(amountColor)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(categoryName)
                    .font(.custom("Avenir Next", size: 15).weight(.semibold))
                    .foregroundStyle(theme.textPrimary)

                if !transferCounterparty.isEmpty {
                    Text(transferCounterparty)
                        .font(.custom("Avenir Next", size: 12).weight(.semibold))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }

                if let acct = account {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: acct.colorHex).opacity(0.95))
                            .frame(width: 10, height: 10)

                        Text(acct.displayName)
                            .font(.custom("Avenir Next", size: 12).weight(.semibold))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("Unknown account")
                        .font(.custom("Avenir Next", size: 12).weight(.semibold))
                        .foregroundStyle(theme.textTertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(isExpense ? "−" : "+")\(CurrencyFormatter.sgd(amount: txn.amount))")
                    .font(.custom("Avenir Next", size: 16).weight(.bold))
                    .foregroundStyle(amountColor)

                Text(txn.date, style: .date)
                    .font(.custom("Avenir Next", size: 11))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.card)
                .shadow(color: theme.shadow, radius: 8, x: 0, y: 4)
        )
    }

    private var backupSheet: some View {
        NavigationStack {
            ZStack {
                theme.backgroundGradient.ignoresSafeArea()

                VStack(spacing: 14) {
                    Button {
                        do {
                            let data = try vm.exportBackupJSON()
                            guard data.isEmpty == false else {
                                errorMessage = "Export failed: no data found. Try again after adding data."
                                showErrorAlert = true
                                return
                            }

                            exportBackupDocument = FrugalPilotBackupDocument(data: data)
                            exportFilename = "FrugalPilotBackup-\(safeTimestampString).json"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                showBackupExporter = true
                            }
                        } catch {
                            errorMessage = "Backup export failed.\n\nDetails: \(error.localizedDescription)"
                            showErrorAlert = true
                        }
                    } label: {
                        Text("Export Backup (JSON)")
                            .font(.custom("Avenir Next", size: 18).weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(theme.accent))
                    }
                    .buttonStyle(.plain)

                    Button {
                        showBackupImporter = true
                    } label: {
                        Text("Import Backup (JSON)")
                            .font(.custom("Avenir Next", size: 18).weight(.bold))
                            .foregroundStyle(theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(theme.surfaceAlt))
                    }
                    .buttonStyle(.plain)

                    Text("Import supports Merge or Replace All.")
                        .font(.custom("Avenir Next", size: 12).weight(.semibold))
                        .foregroundStyle(theme.textTertiary)
                        .padding(.top, 6)

                    Text("Backups include accounts, transactions, fixed plans, custom categories, smart tools data, spending alerts, and app settings.")
                        .font(.custom("Avenir Next", size: 11))
                        .foregroundStyle(theme.textTertiary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Export Packs")
                            .font(.custom("Avenir Next", size: 13).weight(.bold))
                            .foregroundStyle(theme.textSecondary)

                        packExportButton(label: "Current Profile (All Time)") {
                            do {
                                let data = try vm.exportBackupJSON(profileName: currentProfileName,
                                                                   from: nil,
                                                                   to: nil)
                                exportBackupDocument = FrugalPilotBackupDocument(data: data)
                                exportFilename = "FrugalPilotPack-\(currentProfileName)-All-\(safeTimestampString).json"
                                showBackupExporter = true
                            } catch {
                                presentError(error)
                            }
                        }

                        packExportButton(label: "Current Profile (Last 90 Days)") {
                            do {
                                let end = Date()
                                let start = Calendar.current.date(byAdding: .day, value: -90, to: end)
                                let data = try vm.exportBackupJSON(profileName: currentProfileName,
                                                                   from: start,
                                                                   to: end)
                                exportBackupDocument = FrugalPilotBackupDocument(data: data)
                                exportFilename = "FrugalPilotPack-\(currentProfileName)-90d-\(safeTimestampString).json"
                                showBackupExporter = true
                            } catch {
                                presentError(error)
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Backups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(themeIsDark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showBackupSheet = false }
                        .foregroundStyle(theme.textPrimary)
                }
            }
        }
        .fileExporter(isPresented: $showBackupExporter,
                      document: exportBackupDocument,
                      contentType: .json,
                      defaultFilename: exportFilename) { result in
            if case .failure(let err) = result {
                presentError(err)
            }
        }
        .fileImporter(isPresented: $showBackupImporter,
                      allowedContentTypes: [.json],
                      allowsMultipleSelection: false) { result in
            do {
                let urls = try result.get()
                guard let url = urls.first else { return }
                pendingImportURL = url
                showImportStrategyDialog = true
            } catch {
                presentError(error)
            }
        }
        .confirmationDialog("Import backup",
                            isPresented: $showImportStrategyDialog,
                            titleVisibility: .visible) {
            Button("Merge (keep existing, update duplicates)") {
                runImport(strategy: .merge)
            }
            Button("Replace All (delete existing then import)", role: .destructive) {
                runImport(strategy: .replaceAll)
            }
            Button("Cancel", role: .cancel) { pendingImportURL = nil }
        } message: {
            Text("Choose how you want to import this backup.")
        }
        .overlay {
            if isImportingBackup {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    VStack(spacing: 10) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(theme.textPrimary)
                        Text("Importing backup...")
                            .font(.custom("Avenir Next", size: 13).weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(theme.surface)
                    )
                }
            }
        }
        .disabled(isImportingBackup)
    }

    private func packExportButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.custom("Avenir Next", size: 12).weight(.semibold))
                Spacer()
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(theme.textPrimary)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private var settingsSheet: some View {
        NavigationStack {
            ZStack {
                theme.backgroundGradient.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        Picker("Settings Tabs", selection: $selectedSettingsTab) {
                            ForEach(SettingsTab.allCases) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(theme.surface))

                        if selectedSettingsTab == .apple {
                            settingsSectionHeader("Apple Account")
                            VStack(alignment: .leading, spacing: 12) {
                                if appleUserId.isEmpty {
                                    SignInWithAppleButton(.signIn, onRequest: { request in
                                        request.requestedScopes = [.fullName, .email]
                                    }, onCompletion: handleAppleSignInResult)
                                    .signInWithAppleButtonStyle(themeIsDark ? .white : .black)
                                    .frame(height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                } else {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(appleUserName.isEmpty ? "Signed in with Apple ID" : appleUserName)
                                                .font(.custom("Avenir Next", size: 13).weight(.semibold))
                                                .foregroundStyle(theme.textPrimary)
                                                .lineLimit(1)
                                            Text(cloudSyncActive ? "iCloud sync is active." : "iCloud sync is currently unavailable. Check Profile for the last sync error.")
                                                .font(.custom("Avenir Next", size: 11))
                                                .foregroundStyle(theme.textTertiary)
                                                .lineLimit(2)
                                        }
                                        Spacer(minLength: 8)
                                        Button("Sign Out", role: .destructive) {
                                            persistCurrentSettingsIfSignedIn()
                                            appleUserId = ""
                                            appleUserName = ""
                                        }
                                        .font(.custom("Avenir Next", size: 12).weight(.semibold))
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(theme.surface))

                            settingsSectionHeader("Subscription")
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Current Plan")
                                        .font(.custom("Avenir Next", size: 13).weight(.semibold))
                                        .foregroundStyle(theme.textSecondary)
                                    Spacer()
                                    Text(SubscriptionManager.displayName(for: currentPlan))
                                        .font(.custom("Avenir Next", size: 11).weight(.semibold))
                                        .foregroundStyle(currentPlan == .free ? theme.textTertiary : theme.positive)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(theme.surfaceAlt))
                                }

                                VStack(spacing: 8) {
                                    ForEach(SubscriptionManager.planCatalog) { descriptor in
                                        subscriptionProductRow(descriptor: descriptor)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Pro includes:")
                                        .font(.custom("Avenir Next", size: 11).weight(.bold))
                                        .foregroundStyle(theme.textSecondary)
                                    Text("• Unlimited accounts and transactions")
                                    Text("• Smart Tools and Automation")
                                    Text("• Advanced statistics and receipt scan")
                                    Text("• Face ID Unlock")
                                }
                                .font(.custom("Avenir Next", size: 11).weight(.medium))
                                .foregroundStyle(theme.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(theme.surfaceAlt))

                                HStack {
                                    Button("Reload Plans") {
                                        Task {
                                            await store.loadProducts()
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .font(.custom("Avenir Next", size: 12).weight(.semibold))
                                    .foregroundStyle(theme.accent)

                                    Spacer()

                                    Button("Restore Purchases") {
                                        Task {
                                            await store.restorePurchases()
                                            planRaw = SubscriptionManager.currentPlan.rawValue
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .font(.custom("Avenir Next", size: 12).weight(.semibold))
                                    .foregroundStyle(theme.accent)

                                    if store.isLoading {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Voucher Redemption Corner")
                                        .font(.custom("Avenir Next", size: 11).weight(.bold))
                                        .foregroundStyle(theme.textSecondary)
                                    Button {
                                        redeemVoucher()
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "ticket.fill")
                                                .font(.system(size: 12, weight: .semibold))
                                            Text("Redeem Voucher")
                                                .font(.custom("Avenir Next", size: 12).weight(.semibold))
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 11, weight: .semibold))
                                        }
                                        .foregroundStyle(theme.accent)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(RoundedRectangle(cornerRadius: 8).fill(theme.surfaceAlt))
                                    }
                                    .buttonStyle(.plain)
                                    Text("Use Apple offer codes to unlock subscription benefits.")
                                        .font(.custom("Avenir Next", size: 11))
                                        .foregroundStyle(theme.textTertiary)
                                }

                                Text("Purchases are processed by Apple App Store for billing and sales reporting.")
                                    .font(.custom("Avenir Next", size: 11))
                                    .foregroundStyle(theme.textTertiary)

                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(theme.surface))
                        } else if selectedSettingsTab == .security {
                            settingsSectionHeader("Face ID")
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Face ID Unlock", isOn: $appLockEnabled)
                                    .tint(theme.accent)
                                    .foregroundStyle(theme.textPrimary)
                                    .disabled(!SubscriptionManager.hasAppLock)
                                Text("Require Face ID (or device passcode fallback) before accessing your wallet.")
                                    .font(.custom("Avenir Next", size: 12))
                                    .foregroundStyle(theme.textTertiary)
                                if !SubscriptionManager.hasAppLock {
                                    Text("Face ID Unlock is available on Pro and Lifetime.")
                                        .font(.custom("Avenir Next", size: 11).weight(.semibold))
                                        .foregroundStyle(theme.negative)
                                    Button("View Plans") {
                                        selectedSettingsTab = .apple
                                    }
                                    .buttonStyle(.plain)
                                    .font(.custom("Avenir Next", size: 11).weight(.semibold))
                                    .foregroundStyle(theme.accent)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(theme.surface))
                        } else {
                            settingsSectionHeader("Appearance")
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Dark Mode", isOn: $themeIsDark)
                                    .tint(theme.accent)
                                    .foregroundStyle(theme.textPrimary)
                                Text("Switch between light and dark appearance.")
                                    .font(.custom("Avenir Next", size: 12))
                                    .foregroundStyle(theme.textTertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(theme.surface))

                            settingsSectionHeader("Categories")
                            VStack(alignment: .leading, spacing: 10) {
                                Picker("Preset", selection: Binding(
                                    get: { CategoryPreset(rawValue: categoryPresetRaw) ?? .singapore },
                                    set: { categoryPresetRaw = $0.rawValue }
                                )) {
                                    ForEach(CategoryPreset.allCases) { preset in
                                        Text(preset.rawValue).tag(preset)
                                    }
                                }
                                .pickerStyle(.segmented)

                                Text("Singapore: local-first • Generic: broad standard • Minimal: fewer choices")
                                    .font(.custom("Avenir Next", size: 12))
                                    .foregroundStyle(theme.textTertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(theme.surface))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(themeIsDark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showSettingsSheet = false }
                        .foregroundStyle(theme.textPrimary)
                }
            }
            .task {
                await store.prepareIfNeeded()
                planRaw = SubscriptionManager.currentPlan.rawValue
            }
        }
    }

    private var notificationsSheet: some View {
        let reminders = remindersCache
            .filter {
                $0.isEnabled &&
                $0.profileName.trimmingCharacters(in: .whitespacesAndNewlines) == currentProfileName
            }
            .sorted { $0.chargeDay < $1.chargeDay }
        let accounts = currentProfileAccounts

        return NavigationStack {
            ZStack {
                theme.backgroundGradient.ignoresSafeArea()
                List {
                    Section {
                        Text("Get notified when an account's current cycle spending reaches your amount. This feature is available on Free.")
                            .font(.custom("Avenir Next", size: 12))
                            .foregroundStyle(theme.textSecondary)
                            .listRowBackground(Color.clear)
                    } header: {
                        Text("Account Spending Alerts")
                            .font(.custom("Avenir Next", size: 12).weight(.bold))
                    }

                    if accounts.isEmpty {
                        Text("No accounts yet. Add an account to set alerts.")
                            .font(.custom("Avenir Next", size: 12))
                            .foregroundStyle(theme.textTertiary)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(accounts) { account in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(account.displayName)
                                        .font(.custom("Avenir Next", size: 14).weight(.semibold))
                                        .foregroundStyle(theme.textPrimary)
                                    Spacer()
                                    let spent = currentCycleSpent(for: account)
                                    Text("Spent \(CurrencyFormatter.sgd(amount: spent))")
                                        .font(.custom("Avenir Next", size: 11))
                                        .foregroundStyle(theme.textSecondary)
                                }

                                HStack(spacing: 8) {
                                    TextField("Alert amount", text: spendingAlertBinding(for: account.id))
                                        .keyboardType(.decimalPad)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled(true)
                                        .font(.custom("Avenir Next", size: 13).weight(.semibold))
                                        .foregroundStyle(theme.textPrimary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(theme.surfaceAlt))

                                    Button("Save") {
                                        saveSpendingAlertThreshold(for: account)
                                    }
                                    .font(.custom("Avenir Next", size: 12).weight(.semibold))

                                    Button("Clear") {
                                        clearSpendingAlertThreshold(for: account)
                                    }
                                    .font(.custom("Avenir Next", size: 12).weight(.semibold))
                                    .foregroundStyle(theme.negative)
                                }

                                if let threshold = spendingAlertThresholds[account.id] {
                                    Text("Alert at \(CurrencyFormatter.sgd(amount: threshold))")
                                        .font(.custom("Avenir Next", size: 11))
                                        .foregroundStyle(theme.textTertiary)
                                }
                            }
                            .listRowBackground(Color.clear)
                        }
                    }

                    Section {
                        if reminders.isEmpty {
                            Text("No reminders yet")
                                .font(.custom("Avenir Next", size: 12))
                                .foregroundStyle(theme.textTertiary)
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach(reminders) { reminder in
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(theme.surfaceAlt)
                                        .frame(width: 30, height: 30)
                                        .overlay(
                                            Image(systemName: "calendar.badge.clock")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(theme.accent)
                                        )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(reminder.title)
                                            .font(.custom("Avenir Next", size: 14).weight(.semibold))
                                            .foregroundStyle(theme.textPrimary)
                                        Text("Day \(reminder.chargeDay) • \(CurrencyFormatter.sgd(amount: reminder.amount))")
                                            .font(.custom("Avenir Next", size: 11))
                                            .foregroundStyle(theme.textSecondary)
                                    }
                                    Spacer()
                                }
                                .listRowBackground(Color.clear)
                            }
                        }
                    } header: {
                        Text("Bill Reminders")
                            .font(.custom("Avenir Next", size: 12).weight(.bold))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showNotificationsSheet = false }
                        .foregroundStyle(theme.textPrimary)
                }
            }
            .onAppear {
                loadSpendingAlertEditorState()
            }
        }
    }

    private func spendingAlertBinding(for accountID: UUID) -> Binding<String> {
        Binding(
            get: { spendingAlertInputByAccountID[accountID] ?? "" },
            set: { spendingAlertInputByAccountID[accountID] = $0 }
        )
    }

    private func loadSpendingAlertEditorState() {
        spendingAlertThresholds = AccountSpendingAlertStore.loadThresholds()
        var inputs: [UUID: String] = [:]
        for account in currentProfileAccounts {
            if let threshold = spendingAlertThresholds[account.id] {
                inputs[account.id] = NSDecimalNumber(decimal: threshold).stringValue
            }
        }
        spendingAlertInputByAccountID = inputs
    }

    private func saveSpendingAlertThreshold(for account: Account) {
        let rawValue = (spendingAlertInputByAccountID[account.id] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if rawValue.isEmpty {
            clearSpendingAlertThreshold(for: account)
            return
        }

        let normalized = rawValue.replacingOccurrences(of: ",", with: "")
        guard let threshold = Decimal(string: normalized), threshold > 0 else {
            storeStatusMessage = "Enter a valid alert amount greater than 0."
            showStoreStatusAlert = true
            return
        }

        AccountSpendingAlertStore.setThreshold(threshold, for: account.id)
        AccountSpendingAlertStore.setNotified(false, for: account.id)
        spendingAlertThresholds[account.id] = threshold
        spendingAlertInputByAccountID[account.id] = NSDecimalNumber(decimal: threshold).stringValue

        requestLocalNotificationPermissionIfNeeded()
        evaluateAccountSpendingAlerts()

        storeStatusMessage = "Spending alert saved for \(account.displayName)."
        showStoreStatusAlert = true
    }

    private func clearSpendingAlertThreshold(for account: Account) {
        AccountSpendingAlertStore.setThreshold(nil, for: account.id)
        AccountSpendingAlertStore.setNotified(false, for: account.id)
        spendingAlertThresholds[account.id] = nil
        spendingAlertInputByAccountID[account.id] = ""
        storeStatusMessage = "Spending alert cleared for \(account.displayName)."
        showStoreStatusAlert = true
    }

    private func evaluateAccountSpendingAlerts() {
        let thresholds = AccountSpendingAlertStore.loadThresholds()
        spendingAlertThresholds = thresholds

        for account in currentProfileAccounts {
            guard let threshold = thresholds[account.id], threshold > 0 else { continue }
            let spent = currentCycleSpent(for: account)

            if spent >= threshold {
                if !AccountSpendingAlertStore.isNotified(for: account.id) {
                    scheduleSpendingAlertNotification(account: account, spent: spent, threshold: threshold)
                    AccountSpendingAlertStore.setNotified(true, for: account.id)
                }
            } else {
                AccountSpendingAlertStore.setNotified(false, for: account.id)
            }
        }
    }

    private func requestLocalNotificationPermissionIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                return
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                    guard granted == false else { return }
                    DispatchQueue.main.async {
                        storeStatusMessage = "Notifications are disabled. Enable notifications in iOS Settings to receive spending alerts."
                        showStoreStatusAlert = true
                    }
                }
            default:
                DispatchQueue.main.async {
                    storeStatusMessage = "Notifications are disabled. Enable notifications in iOS Settings to receive spending alerts."
                    showStoreStatusAlert = true
                }
            }
        }
    }

    private func scheduleSpendingAlertNotification(account: Account, spent: Decimal, threshold: Decimal) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = "Spending Alert"
            content.body = "\(account.displayName) reached \(CurrencyFormatter.sgd(amount: spent)). Your alert was \(CurrencyFormatter.sgd(amount: threshold))."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "spending-alert-\(account.id.uuidString)-\(Int(Date().timeIntervalSince1970))",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            )
            center.add(request)
        }
    }

    private func currentCycleSpent(for account: Account) -> Decimal {
        vm.periodExpenses(for: account.id, monthOffset: 0)
    }

    private func addProfile() {
        let trimmed = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trackingProfiles.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) == false else {
            currentProfileRaw = trackingProfiles.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) ?? currentProfileRaw
            newProfileName = ""
            return
        }
        let updated = trackingProfiles + [trimmed]
        trackingProfilesRaw = updated.joined(separator: "|")
        currentProfileRaw = trimmed
        newProfileName = ""
    }

    private func deleteProfile(_ profile: String) {
        guard profile.caseInsensitiveCompare("Personal") != .orderedSame else { return }
        vm.deleteProfile(named: profile)
        let remaining = trackingProfiles.filter { $0.caseInsensitiveCompare(profile) != .orderedSame }
        trackingProfilesRaw = remaining.isEmpty ? "Personal" : remaining.joined(separator: "|")
        if currentProfileRaw.caseInsensitiveCompare(profile) == .orderedSame {
            currentProfileRaw = "Personal"
        }
    }

    private func subscriptionProductRow(descriptor: SubscriptionPlanDescriptor) -> some View {
        Button {
            Task {
                await store.purchase(plan: descriptor.plan)
                planRaw = SubscriptionManager.currentPlan.rawValue
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.title)
                        .font(.custom("Avenir Next", size: 12).weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(descriptor.subtitle)
                        .font(.custom("Avenir Next", size: 11))
                        .foregroundStyle(theme.textTertiary)
                }
                Spacer()
                if let product = store.product(for: descriptor.plan) {
                    Text(product.displayPrice)
                        .font(.custom("Avenir Next", size: 12).weight(.bold))
                        .foregroundStyle(theme.textPrimary)
                } else if store.isLoading {
                    ProgressView()
                        .scaleEffect(0.75)
                } else {
                    Text("Not available")
                        .font(.custom("Avenir Next", size: 11).weight(.semibold))
                        .foregroundStyle(theme.textTertiary)
                }
                if currentPlan == descriptor.plan {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.positive)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(theme.surfaceAlt))
        }
        .buttonStyle(.plain)
        .disabled(store.isPurchasing || store.product(for: descriptor.plan) == nil)
    }

    private func settingsSectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.custom("Avenir Next", size: 11).weight(.bold))
                .textCase(.uppercase)
                .tracking(0.3)
                .foregroundStyle(theme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(theme.surface.opacity(0.95))
        )
    }

    // MARK: - Helpers

    private func runImport(strategy: FrugalPilotImportStrategy) {
        guard let url = pendingImportURL else { return }
        pendingImportURL = nil
        isImportingBackup = true

        Task {
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    let didStart = url.startAccessingSecurityScopedResource()
                    defer {
                        if didStart { url.stopAccessingSecurityScopedResource() }
                    }
                    return try Data(contentsOf: url)
                }.value

                let result = try vm.importBackupJSON(data: data, strategy: strategy)
                importOutcomeTitle = "Import Successful"
                importOutcomeMessage = importSuccessMessage(for: result)
                showImportOutcomeAlert = true
            } catch {
                importOutcomeTitle = "Import Failed"
                importOutcomeMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                showImportOutcomeAlert = true
            }
            isImportingBackup = false
        }
    }

    private func importSuccessMessage(for result: FrugalPilotImportResult) -> String {
        let total = result.accountCount
            + result.transactionCount
            + result.fixedPaymentCount
            + result.customCategoryCount
            + result.autoCategoryRuleCount
            + result.budgetCount
            + result.savingsGoalCount
            + result.billReminderCount
            + result.spendingAlertThresholdCount
        let settingsText = result.restoredAppSettings ? " App settings restored." : ""
        return "Backup imported successfully (\(total) items).\(settingsText)"
    }

    private func refreshDerivedDashboardData() {
        refreshRemindersCache()
        refreshFilteredTransactions()
        refreshDueReminderCount()
    }

    private func refreshFilteredTransactions() {
        let normalizedQuery = transactionSearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let accountNameById = Dictionary(uniqueKeysWithValues: vm.accounts.map { ($0.id, $0.displayName.lowercased()) })

        let typeFilter = transactionFilterType

        filteredTransactionsCache = vm.transactions.filter { txn in
            switch typeFilter {
            case .all: break
            case .expense where txn.type != .expense: return false
            case .income where txn.type != .income: return false
            case .transfer where txn.type != .transfer: return false
            default: break
            }

            guard !normalizedQuery.isEmpty else { return true }
            let accountName = accountNameById[txn.accountId] ?? ""
            return txn.categoryName.lowercased().contains(normalizedQuery)
                || txn.note.lowercased().contains(normalizedQuery)
                || accountName.contains(normalizedQuery)
        }
    }

    private func refreshDueReminderCount() {
        let calendar = Calendar.current
        let today = calendar.component(.day, from: Date())
        dueReminderCount = remindersCache.filter { reminder in
            guard reminder.isEnabled else { return false }
            guard reminder.profileName.trimmingCharacters(in: .whitespacesAndNewlines) == currentProfileName else { return false }
            return reminder.chargeDay >= today && reminder.chargeDay <= (today + 3)
        }.count
    }

    private func refreshRemindersCache() {
        remindersCache = SmartDataStore.loadReminders()
    }

    private func handleAppleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                appleSignInMessage = "Apple ID sign in failed."
                showAppleSignInAlert = true
                return
            }
            appleUserId = credential.user

            let name = DashboardFormatterCache.personName.string(from: credential.fullName ?? PersonNameComponents())
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                appleUserName = name
            } else if appleUserName.isEmpty {
                appleUserName = "Apple User"
            }
            Task {
                let plan = await SubscriptionManager.refreshPlanFromStoreKit()
                await MainActor.run {
                    planRaw = plan.rawValue
                    appleSignInMessage = "Signed in with Apple ID successfully. Current plan: \(SubscriptionManager.displayName(for: plan))."
                    showAppleSignInAlert = true
                }
            }
        case .failure(let error):
            appleSignInMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showAppleSignInAlert = true
        }
    }

    private func refreshSubscriptionState() {
        Task {
            let plan = await SubscriptionManager.refreshPlanFromStoreKit()
            await MainActor.run {
                planRaw = plan.rawValue
            }
        }
    }

    private func presentError(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        showErrorAlert = true
    }

    private func consumePendingQuickAddDraftIfNeeded() {
        guard !showAddTransaction else { return }
        guard let draft = TransactionQuickAddDraftStore.consumePending() else { return }
        pendingQuickAddDraft = draft
        selectedTab = 0
        showAddTransaction = true
    }

    private func persistCurrentSettingsIfSignedIn() {
        guard !appleUserId.isEmpty else { return }
        AccountSettingsStore.saveCurrentSettings(for: appleUserId)
    }

    private func restoreSettingsIfSignedIn() {
        guard !appleUserId.isEmpty else { return }
        AccountSettingsStore.restoreSettings(for: appleUserId)
    }

    private var placeholderTab: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 30))
                .foregroundStyle(theme.textTertiary)
            Text("Coming soon")
                .font(.custom("Avenir Next", size: 14).weight(.semibold))
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var moreTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Color.clear
                    .frame(width: 34, height: 34)
                Text("More")
                    .font(.custom("Avenir Next", size: 22).weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)

            Text("General")
                .font(.custom("Avenir Next", size: 12).weight(.bold))
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 18)

            moreActionRow(
                title: "Settings",
                subtitle: "Apple account, subscription, security, and appearance",
                icon: "gearshape"
            ) {
                showSettingsSheet = true
            }

            moreActionRow(
                title: "Profile & Usage",
                subtitle: "View account status and usage summary",
                icon: "person.crop.circle"
            ) {
                showProfileOverviewSheet = true
            }

            Text("Tools")
                .font(.custom("Avenir Next", size: 12).weight(.bold))
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 18)
                .padding(.top, 4)

            moreActionRow(
                title: "Backups",
                subtitle: "Export and import wallet backups",
                icon: "externaldrive.badge.plus",
                isPremium: false
            ) {
                showBackupSheet = true
            }

            moreActionRow(
                title: "Smart Tools",
                subtitle: "Budgets, savings goals, reminders, and auto rules",
                icon: "wand.and.stars",
                isPremium: true
            ) {
                guard hasPremiumAccess else { openSubscriptionPlans(for: "Smart Tools"); return }
                showSmartToolsSheet = true
            }

            moreActionRow(
                title: "Automation Setup",
                subtitle: "Shortcuts and quick-add transaction automation",
                icon: "bolt.horizontal.circle",
                isPremium: true
            ) {
                guard hasPremiumAccess else { openSubscriptionPlans(for: "Automation Setup"); return }
                showAutomationSetupSheet = true
            }

            Spacer(minLength: 24)
        }
        .padding(.bottom, 32)
    }

    private func moreActionRow(title: String,
                               subtitle: String,
                               icon: String,
                               isPremium: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(theme.surfaceAlt))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.custom("Avenir Next", size: 16).weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                        if isPremium && !hasPremiumAccess {
                            Text("Pro")
                                .font(.custom("Avenir Next", size: 10).weight(.bold))
                                .foregroundStyle(theme.negative)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(theme.surfaceAlt))
                        }
                    }
                    Text(subtitle)
                        .font(.custom("Avenir Next", size: 11).weight(.medium))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(theme.card))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
    }

    private func openSubscriptionPlans(for feature: String) {
        selectedSettingsTab = .apple
        showSettingsSheet = true
        storeStatusMessage = "\(feature) requires Pro or Lifetime."
        showStoreStatusAlert = true
    }

    private func redeemVoucher() {
        if #available(iOS 18.0, *) {
            guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first else {
                storeStatusMessage = "Could not open voucher sheet: no active window scene."
                showStoreStatusAlert = true
                return
            }
            Task {
                do {
                    try await AppStore.presentOfferCodeRedeemSheet(in: windowScene)
                    await MainActor.run {
                        storeStatusMessage = "Apple voucher sheet opened. Complete redemption, then tap Restore Purchases if your plan does not update automatically."
                        showStoreStatusAlert = true
                    }
                } catch {
                    await MainActor.run {
                        let nsError = error as NSError
                        storeStatusMessage = "Voucher redemption failed. Native=\(nsError.domain)(\(nsError.code)) Desc=\(nsError.localizedDescription)"
                        showStoreStatusAlert = true
                    }
                }
            }
        } else {
            SKPaymentQueue.default().presentCodeRedemptionSheet()
            storeStatusMessage = "Apple voucher sheet opened. Complete redemption, then tap Restore Purchases if your plan does not update automatically."
            showStoreStatusAlert = true
        }
    }
}

private enum DashboardFormatterCache {
    static let personName = PersonNameComponentsFormatter()
    static let backupFilenameTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}
