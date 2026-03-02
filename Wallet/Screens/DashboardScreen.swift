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

struct DashboardScreen: View {
    @StateObject private var vm: DashboardViewModel
    @Environment(\.appTheme) private var theme
    @AppStorage("theme_is_dark") private var themeIsDark: Bool = true
    @AppStorage(SubscriptionManager.planKey) private var planRaw: String = SubscriptionPlan.free.rawValue
    @AppStorage("category_preset") private var categoryPresetRaw: String = CategoryPreset.singapore.rawValue
    @AppStorage("tracking_current_profile") private var currentProfileRaw: String = "Personal"
    @AppStorage("tracking_profiles") private var trackingProfilesRaw: String = "Personal"
    private var currentPlan: SubscriptionPlan { SubscriptionPlan(rawValue: planRaw) ?? .free }

    @State private var selectedTab: Int = 0
    @State private var showSidePanel: Bool = false
    @State private var accountPage: Int = 0
    @State private var showAddAccount: Bool = false
    @State private var showAddTransaction: Bool = false
    @State private var showBreakdown: Bool = false
    @State private var selectedAccount: Account? = nil

    @State private var showSettingsSheet = false
    @State private var showBackupSheet = false
    @State private var showSmartToolsSheet = false
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
    @State private var showProInfo = false
    @State private var showICloudInfo = false
    @State private var showAppLockInfo = false
    @State private var showAddProfilePrompt = false
    @State private var showDeleteProfileDialog = false
    @State private var pendingDeleteProfile: String? = nil
    @State private var newProfileName = ""
    @State private var transactionSearchText: String = ""
    @State private var transactionFilterType: TransactionFilterType = .all

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

    private var filteredTransactions: [Transaction] {
        let normalizedQuery = transactionSearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let accountNameById = Dictionary(uniqueKeysWithValues: vm.accounts.map { ($0.id, $0.displayName.lowercased()) })
        return vm.transactions.filter { txn in
            let byType: Bool = {
                switch transactionFilterType {
                case .all: return true
                case .expense: return txn.type == .expense
                case .income: return txn.type == .income
                case .transfer: return txn.type == .transfer
                }
            }()
            guard byType else { return false }

            guard !normalizedQuery.isEmpty else { return true }
            let accountName = accountNameById[txn.accountId] ?? ""
            return txn.categoryName.lowercased().contains(normalizedQuery)
                || txn.note.lowercased().contains(normalizedQuery)
                || accountName.contains(normalizedQuery)
        }
    }

    private var dueReminderCount: Int {
        let reminders = SmartDataStore.loadReminders()
        let calendar = Calendar.current
        let today = calendar.component(.day, from: Date())
        return reminders.filter { reminder in
            guard reminder.isEnabled else { return false }
            guard reminder.profileName.trimmingCharacters(in: .whitespacesAndNewlines) == currentProfileName else { return false }
            return reminder.chargeDay >= today && reminder.chargeDay <= (today + 3)
        }.count
    }

    private var canAddAccount: Bool {
        vm.canAddAccount()
    }

    private var safeTimestampString: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return df.string(from: Date())
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
                        errorMessage = "Free tier allows up to \(SubscriptionManager.freeAccountLimit) accounts. Upgrade to Pro for unlimited accounts."
                        showErrorAlert = true
                    }
                }
            }
            .sheet(isPresented: $showAddTransaction) {
                AddTransactionScreen(vm: vm) { }
            }
            .sheet(isPresented: $showSettingsSheet) { settingsSheet }
            .sheet(isPresented: $showBackupSheet) { backupSheet }
            .sheet(isPresented: $showSmartToolsSheet) {
                SmartToolsScreen(currentProfileName: currentProfileName)
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
            .alert("Pro", isPresented: $showProInfo) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Subscription management will be available in a future update.")
            }
            .alert("iCloud Sync", isPresented: $showICloudInfo) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("iCloud sync is enabled for Pro users. You may need to restart the app for changes to take effect.")
            }
            .alert("App Lock", isPresented: $showAppLockInfo) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("App Lock is available on Pro and Lifetime.")
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
                if trackingProfilesRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    trackingProfilesRaw = "Personal"
                }
                if currentProfileRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    currentProfileRaw = "Personal"
                }
                if !trackingProfiles.contains(where: { $0.caseInsensitiveCompare(currentProfileName) == .orderedSame }) {
                    currentProfileRaw = trackingProfiles.first ?? "Personal"
                }
                vm.setActiveProfile(currentProfileName)
                vm.fetchAll()
            }
            .onChange(of: currentProfileRaw) { _, newValue in
                vm.setActiveProfile(newValue)
                vm.fetchAll()
            }
            .onChange(of: vm.accounts.count) { _, _ in
                accountPage = min(accountPage, max(0, pagesCount - 1))
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
            StatisticsScreen()
        case 3:
            moreTab
        default:
            placeholderTab
        }
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
                            errorMessage = "Free tier allows up to \(SubscriptionManager.freeAccountLimit) accounts. Upgrade to Pro for unlimited accounts."
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
            sidePanelItem(index: 2, title: "Statistics", icon: "chart.bar")
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

    private func sidePanelItem(index: Int, title: String, icon: String) -> some View {
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

            if filteredTransactions.isEmpty {
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
                LazyVStack(spacing: 10) {
                    ForEach(filteredTransactions.prefix(maxRecentTransactions)) { txn in
                        transactionRow(txn)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    // MARK: - Transaction Row

    private func transactionRow(_ txn: Transaction) -> some View {
        let isTransfer = txn.type == .transfer
        let isTransferOut = isTransfer && txn.categoryName == "Transfer Out"
        let isExpense = txn.type == .expense || isTransferOut
        let amountColor: Color = isTransfer ? (isTransferOut ? theme.negative : theme.positive) : (isExpense ? theme.negative : theme.positive)
        let acct = vm.accounts.first(where: { $0.id == txn.accountId })
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

                if let acct {
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
                    LazyVStack(spacing: 14, pinnedViews: [.sectionHeaders]) {
                        Section {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Dark Mode", isOn: $themeIsDark)
                                    .tint(theme.accent)
                                    .foregroundStyle(theme.textPrimary)
                                Text("Switch between light and dark appearance.")
                                    .font(.custom("Avenir Next", size: 12))
                                    .foregroundStyle(theme.textTertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(theme.surface))
                        } header: {
                            settingsSectionHeader("Appearance")
                        }

                        Section {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("App Lock", isOn: Binding(
                                    get: { UserDefaults.standard.bool(forKey: "app_lock_enabled") },
                                    set: { newValue in
                                        UserDefaults.standard.set(newValue, forKey: "app_lock_enabled")
                                    }
                                ))
                                .tint(theme.accent)
                                .foregroundStyle(theme.textPrimary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(theme.surface))
                        } header: {
                            settingsSectionHeader("Security")
                        }

                        Section {
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
                                            Text(cloudSyncActive ? "iCloud sync is enabled" : "iCloud sync is not active on this build profile")
                                                .font(.custom("Avenir Next", size: 11))
                                                .foregroundStyle(theme.textTertiary)
                                                .lineLimit(2)
                                        }
                                        Spacer(minLength: 8)
                                        Button("Sign Out", role: .destructive) {
                                            appleUserId = ""
                                            appleUserName = ""
                                        }
                                        .font(.custom("Avenir Next", size: 12).weight(.semibold))
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(theme.surface))
                        } header: {
                            settingsSectionHeader("Apple ID")
                        }

                        Section {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Spacer()
                                    Text(currentPlan == .free ? "Free" : "Active")
                                        .font(.custom("Avenir Next", size: 11).weight(.semibold))
                                        .foregroundStyle(currentPlan == .free ? theme.textTertiary : theme.positive)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(theme.surfaceAlt))
                                }

                                Text("Pro Lite: SGD 1.99/month • 19.99/year")
                                    .font(.custom("Avenir Next", size: 12).weight(.semibold))
                                    .foregroundStyle(theme.textTertiary)
                                Text("Pro: SGD 2.99/month • 29.99/year • Lifetime 49.99")
                                    .font(.custom("Avenir Next", size: 12).weight(.semibold))
                                    .foregroundStyle(theme.textTertiary)

                                VStack(spacing: 8) {
                                    planRow(title: "Free", subtitle: "Local only", plan: .free)
                                    planRow(title: "Pro Lite Monthly", subtitle: "Unlimited accounts & transactions", plan: .proLiteMonthly)
                                    planRow(title: "Pro Lite Yearly", subtitle: "Unlimited accounts & transactions", plan: .proLiteYearly)
                                    planRow(title: "Pro Monthly", subtitle: "iCloud, App Lock", plan: .proMonthly)
                                    planRow(title: "Pro Yearly", subtitle: "iCloud, App Lock", plan: .proYearly)
                                    planRow(title: "Lifetime", subtitle: "All Pro features", plan: .lifetime)
                                }

                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("iCloud Sync")
                                            .font(.custom("Avenir Next", size: 13).weight(.semibold))
                                            .foregroundStyle(theme.textPrimary)
                                        Text(cloudSyncActive ? "Enabled" : "Not active")
                                            .font(.custom("Avenir Next", size: 11))
                                            .foregroundStyle(theme.textTertiary)
                                    }
                                    Spacer()
                                    Button(currentPlan == .free ? "Upgrade" : "Manage") {
                                        showProInfo = true
                                    }
                                    .buttonStyle(.plain)
                                    .font(.custom("Avenir Next", size: 12).weight(.semibold))
                                    .foregroundStyle(currentPlan == .free ? .white : theme.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(currentPlan == .free ? theme.accent : theme.surfaceAlt)
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(theme.surface))
                        } header: {
                            settingsSectionHeader("Subscription")
                        }

                        Section {
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
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(theme.surface))
                        } header: {
                            settingsSectionHeader("Categories")
                        }
                    }
                    .padding(20)
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
        }
    }

    private var notificationsSheet: some View {
        let reminders = SmartDataStore.loadReminders()
            .filter {
                $0.isEnabled &&
                $0.profileName.trimmingCharacters(in: .whitespacesAndNewlines) == currentProfileName
            }
            .sorted { $0.chargeDay < $1.chargeDay }

        return NavigationStack {
            ZStack {
                theme.backgroundGradient.ignoresSafeArea()

                if reminders.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 34))
                            .foregroundStyle(theme.textTertiary)
                        Text("No reminders yet")
                            .font(.custom("Avenir Next", size: 14).weight(.semibold))
                            .foregroundStyle(theme.textSecondary)
                    }
                } else {
                    List {
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
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showNotificationsSheet = false }
                        .foregroundStyle(theme.textPrimary)
                }
            }
        }
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

    private func planRow(title: String, subtitle: String, plan: SubscriptionPlan) -> some View {
        Button {
            SubscriptionManager.setPlan(plan)
            planRaw = plan.rawValue
            if SubscriptionManager.hasICloudSync {
                showICloudInfo = true
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.custom("Avenir Next", size: 12).weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(subtitle)
                        .font(.custom("Avenir Next", size: 11))
                        .foregroundStyle(theme.textTertiary)
                }
                Spacer()
                if currentPlan == plan {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.positive)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(theme.surfaceAlt))
        }
        .buttonStyle(.plain)
    }

    private func settingsSectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.custom("Avenir Next", size: 12).weight(.bold))
                .foregroundStyle(theme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
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
        return "Backup imported successfully (\(total) items)."
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

            let formatter = PersonNameComponentsFormatter()
            let name = formatter.string(from: credential.fullName ?? PersonNameComponents())
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                appleUserName = name
            } else if appleUserName.isEmpty {
                appleUserName = "Apple User"
            }
            appleSignInMessage = "Signed in with Apple ID successfully."
            showAppleSignInAlert = true
        case .failure(let error):
            appleSignInMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showAppleSignInAlert = true
        }
    }

    private func presentError(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        showErrorAlert = true
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

            Button {
                showSettingsSheet = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(theme.surfaceAlt))

                    Text("Settings")
                        .font(.custom("Avenir Next", size: 16).weight(.semibold))
                        .foregroundStyle(theme.textPrimary)

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

            Button {
                showBackupSheet = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "externaldrive.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(theme.surfaceAlt))

                    Text("Backups")
                        .font(.custom("Avenir Next", size: 16).weight(.semibold))
                        .foregroundStyle(theme.textPrimary)

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

            Button {
                showSmartToolsSheet = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(theme.surfaceAlt))

                    Text("Smart Tools")
                        .font(.custom("Avenir Next", size: 16).weight(.semibold))
                        .foregroundStyle(theme.textPrimary)

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

            Spacer(minLength: 24)
        }
        .padding(.bottom, 32)
    }
}
