//
//  DashboardScreen.swift
//  Wallet
//
//  Created by Lee Jun Wei on 21/2/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct DashboardScreen: View {
    @StateObject private var vm: DashboardViewModel
    @Environment(\.appTheme) private var theme
    @AppStorage("theme_is_dark") private var themeIsDark: Bool = true
    @AppStorage(SubscriptionManager.planKey) private var planRaw: String = SubscriptionPlan.free.rawValue
    private var currentPlan: SubscriptionPlan { SubscriptionPlan(rawValue: planRaw) ?? .free }

    @State private var selectedTab: Int = 0
    @State private var accountPage: Int = 0
    @State private var showAddAccount: Bool = false
    @State private var showAddTransaction: Bool = false
    @State private var showBreakdown: Bool = false
    @State private var selectedAccount: Account? = nil

    // Backup UI state
    @State private var showBackupSheet = false
    @State private var showSettingsSheet = false
    @State private var showSubscriptionSheet = false
    @State private var showExporter = false
    @State private var showCSVExporter = false
    @State private var showImporter = false
    @State private var showBackupExporter = false
    @State private var showBackupCSVExporter = false
    @State private var showBackupImporter = false
    @State private var exportDocument = WalletBackupDocument()
    @State private var exportCSVDocument = WalletCSVDocument()
    @State private var exportFilename = "WalletBackup.json"

    @State private var pendingImportData: Data? = nil
    @State private var showImportStrategyDialog = false

    @State private var errorMessage: String? = nil
    @State private var showErrorAlert = false
    @State private var showProInfo = false
    @State private var showICloudInfo = false
    @State private var showCSVInfo = false
    @State private var showAppLockInfo = false

    private let maxPerPage: Int = 4

    init(modelContext: ModelContext) {
        _vm = StateObject(wrappedValue: DashboardViewModel(modelContext: modelContext))
    }

    // Each account card shows spending within its own billing cycle (current period)
    private var totalSpentByAccountId: [UUID: Decimal] {
        var dict: [UUID: Decimal] = [:]
        for acct in vm.accounts {
            dict[acct.id] = vm.periodExpenses(for: acct.id, monthOffset: 0)
        }
        return dict
    }

    // Subtitle shows the billing period date range
    private var subtitleByAccountId: [UUID: String] {
        var dict: [UUID: String] = [:]
        for acct in vm.accounts {
            if acct.type == .cash {
                dict[acct.id] = ""
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
        vm.transactions.sorted { $0.date > $1.date }
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
        let nav = NavigationStack { mainStack }
            .navigationDestination(item: $selectedAccount) { acct in
                AccountDetailScreen(vm: vm, accountId: acct.id)
            }
        return applyLifecycle(
            applyDialogs(
                applyExporters(
                    applySheets(nav)
                )
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
            .sheet(isPresented: $showBackupSheet) { backupSheet }
            .sheet(isPresented: $showSettingsSheet) { settingsSheet }
            .sheet(isPresented: $showSubscriptionSheet) { subscriptionSheet }
    }

    private func applyExporters<V: View>(_ view: V) -> some View {
        view
            .fileExporter(isPresented: $showExporter,
                          document: exportDocument,
                          contentType: .json,
                          defaultFilename: exportFilename) { result in
                if case .failure(let err) = result {
                    presentError(err)
                }
            }
            .fileExporter(isPresented: $showCSVExporter,
                          document: exportCSVDocument,
                          contentType: .commaSeparatedText,
                          defaultFilename: exportFilename) { result in
                if case .failure(let err) = result {
                    presentError(err)
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.json],
                          allowsMultipleSelection: false) { result in
                do {
                    let urls = try result.get()
                    guard let url = urls.first else { return }

                    let didStart = url.startAccessingSecurityScopedResource()
                    defer {
                        if didStart { url.stopAccessingSecurityScopedResource() }
                    }

                    let data = try Data(contentsOf: url)
                    pendingImportData = data
                    showImportStrategyDialog = true
                } catch {
                    presentError(error)
                }
            }
    }

    private func applyDialogs<V: View>(_ view: V) -> some View {
        view
            .confirmationDialog("Import backup",
                                isPresented: $showImportStrategyDialog,
                                titleVisibility: .visible) {
                Button("Merge (keep existing, update duplicates)") {
                    runImport(strategy: .merge)
                }
                Button("Replace All (delete existing then import)", role: .destructive) {
                    runImport(strategy: .replaceAll)
                }
                Button("Cancel", role: .cancel) { pendingImportData = nil }
            } message: {
                Text("Choose how you want to import this backup.")
            }
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
            .alert("CSV Export", isPresented: $showCSVInfo) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("CSV export is available on Pro and Lifetime.")
            }
            .alert("App Lock", isPresented: $showAppLockInfo) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("App Lock is available on Pro and Lifetime.")
            }
    }

    private func applyLifecycle<V: View>(_ view: V) -> some View {
        view
            .onAppear { vm.fetchAll() }
            .onChange(of: vm.accounts.count) { _, _ in
                accountPage = min(accountPage, max(0, pagesCount - 1))
            }
            .onChange(of: showBackupSheet) { _, _ in }
    }

    private var mainStack: some View {
        ZStack(alignment: .bottomTrailing) {
            theme.backgroundGradient.ignoresSafeArea()

            tabContent

            if selectedTab == 0 {
                FloatingAddButton { showAddTransaction = true }
                    .padding(.trailing, 22)
                    .padding(.bottom, 90)
            }

            BottomTabBarView(selectedTab: $selectedTab)
                .padding(.horizontal, 18)
                .padding(.bottom, 22)
        }
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
                topBar

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

                Spacer(minLength: 90)
            }
            .padding(.bottom, 110)
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

    private var topBar: some View {
        HStack {
            Text("Wallet")
                .font(.custom("Avenir Next", size: 22).weight(.semibold))
                .foregroundStyle(theme.textPrimary)
            Spacer()
            HStack(spacing: 12) {
                iconButton(systemName: themeIsDark ? "sun.max" : "moon.stars", size: 16) {
                    withAnimation(.easeInOut(duration: 0.2)) { themeIsDark.toggle() }
                }

                iconButton(systemName: "bell", size: 18) { }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
    }

    private func iconButton(systemName: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(theme.surfaceAlt)
                    .frame(width: 32, height: 32)
                Image(systemName: systemName)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
            }
            .frame(width: 32, height: 32)
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
                Text("All accounts")
                    .font(.custom("Avenir Next", size: 11).weight(.semibold))
                    .foregroundStyle(theme.textTertiary)
            }
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
                    ForEach(filteredTransactions.prefix(50)) { txn in
                        transactionRow(txn)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    // MARK: - Transaction Row

    private func transactionRow(_ txn: Transaction) -> some View {
        let isExpense = txn.type == .expense
        let acct = vm.accounts.first(where: { $0.id == txn.accountId })
        let categoryName = txn.categoryName.isEmpty ? (txn.category?.rawValue ?? "Other") : txn.categoryName

        return HStack(spacing: 14) {
            Circle()
                .fill((isExpense ? theme.negative : theme.positive).opacity(0.12))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: TransactionCategory.iconSystemName(for: categoryName))
                        .font(.system(size: 16))
                        .foregroundStyle(isExpense ? theme.negative : theme.positive)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(categoryName)
                    .font(.custom("Avenir Next", size: 15).weight(.semibold))
                    .foregroundStyle(theme.textPrimary)

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
                    .foregroundStyle(isExpense ? theme.negative : theme.positive)

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

    // MARK: - Backup Sheet

    private var backupSheet: some View {
        NavigationStack {
            ZStack {
                theme.backgroundGradient.ignoresSafeArea()

                VStack(spacing: 14) {
                    Button {
                        do {
                            let data = try vm.exportBackupJSON()
                            guard data.isEmpty == false else {
                                errorMessage = "Export failed: no data found. Try adding an account or transaction, then export again."
                                showErrorAlert = true
                                return
                            }
                            exportDocument = WalletBackupDocument(data: data)
                            exportFilename = "WalletBackup-\(safeTimestampString).json"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                showBackupExporter = true
                            }
                        } catch {
                            errorMessage = "Export failed. If this keeps happening, try restarting the app or exporting again after adding a new account/transaction.\n\nDetails: \(error.localizedDescription)"
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
                        guard SubscriptionManager.hasCSVExport else {
                            showCSVInfo = true
                            return
                        }
                        do {
                            let csvData: Data = try vm.exportTransactionsCSV()
                            guard csvData.isEmpty == false else {
                                errorMessage = "Export failed: no transactions found. Add a transaction and try again."
                                showErrorAlert = true
                                return
                            }
                            exportCSVDocument = WalletCSVDocument(data: csvData)
                            exportFilename = "Wallet-Transactions-\(safeTimestampString).csv"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                showBackupCSVExporter = true
                            }
                        } catch {
                            errorMessage = "CSV export failed. Try again after adding a transaction.\n\nDetails: \(error.localizedDescription)"
                            showErrorAlert = true
                        }
                    } label: {
                        Text("Export Transactions (CSV)")
                            .font(.custom("Avenir Next", size: 18).weight(.bold))
                            .foregroundStyle(theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(theme.surfaceAlt))
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

                    Text("Import will ask whether to Merge or Replace All.")
                        .font(.custom("Avenir Next", size: 12).weight(.semibold))
                        .foregroundStyle(theme.textTertiary)
                        .padding(.top, 6)

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Backup")
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
                      document: exportDocument,
                      contentType: .json,
                      defaultFilename: exportFilename) { result in
            if case .failure(let err) = result {
                presentError(err)
            }
        }
        .fileExporter(isPresented: $showBackupCSVExporter,
                      document: exportCSVDocument,
                      contentType: .commaSeparatedText,
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

                let didStart = url.startAccessingSecurityScopedResource()
                defer {
                    if didStart { url.stopAccessingSecurityScopedResource() }
                }

                let data = try Data(contentsOf: url)
                pendingImportData = data
                showImportStrategyDialog = true
            } catch {
                presentError(error)
            }
        }
    }

    private var settingsSheet: some View {
        NavigationStack {
            ZStack {
                theme.backgroundGradient.ignoresSafeArea()

                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Appearance")
                                .font(.custom("Avenir Next", size: 16).weight(.semibold))
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { themeIsDark.toggle() }
                            } label: {
                                Image(systemName: themeIsDark ? "sun.max" : "moon.stars")
                                    .foregroundStyle(theme.textPrimary)
                                    .font(.system(size: 16, weight: .semibold))
                                    .padding(8)
                                    .background(Circle().fill(theme.surfaceAlt))
                            }
                            .buttonStyle(.plain)
                        }

                        Text(themeIsDark ? "Dark mode" : "Light mode")
                            .font(.custom("Avenir Next", size: 12).weight(.semibold))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(theme.surface)
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("App Lock", isOn: Binding(
                            get: { UserDefaults.standard.bool(forKey: "app_lock_enabled") },
                            set: { newValue in
                                if !SubscriptionManager.hasAppLock {
                                    showAppLockInfo = true
                                    return
                                }
                                UserDefaults.standard.set(newValue, forKey: "app_lock_enabled")
                            }
                        ))
                        .tint(theme.accent)
                        .foregroundStyle(theme.textPrimary)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(theme.surface)
                    )

                    Spacer()
                }
                .padding(20)
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

    private var subscriptionSheet: some View {
        NavigationStack {
            ZStack {
                theme.backgroundGradient.ignoresSafeArea()

                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Subscription")
                                .font(.custom("Avenir Next", size: 16).weight(.semibold))
                                .foregroundStyle(theme.textPrimary)
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
                            planRow(title: "Free",
                                    subtitle: "Local only",
                                    plan: .free)
                            planRow(title: "Pro Lite Monthly",
                                    subtitle: "Unlimited accounts & transactions",
                                    plan: .proLiteMonthly)
                            planRow(title: "Pro Lite Yearly",
                                    subtitle: "Unlimited accounts & transactions",
                                    plan: .proLiteYearly)
                            planRow(title: "Pro Monthly",
                                    subtitle: "iCloud, CSV export, App Lock",
                                    plan: .proMonthly)
                            planRow(title: "Pro Yearly",
                                    subtitle: "iCloud, CSV export, App Lock",
                                    plan: .proYearly)
                            planRow(title: "Lifetime",
                                    subtitle: "All Pro features",
                                    plan: .lifetime)
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("iCloud Sync")
                                    .font(.custom("Avenir Next", size: 13).weight(.semibold))
                                    .foregroundStyle(theme.textPrimary)
                                Text(SubscriptionManager.hasICloudSync ? "Enabled" : "Pro required")
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
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(theme.surface)
                    )

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(themeIsDark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showSubscriptionSheet = false }
                        .foregroundStyle(theme.textPrimary)
                }
            }
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

    // MARK: - Helpers

    private func runImport(strategy: WalletImportStrategy) {
        guard let data = pendingImportData else { return }
        pendingImportData = nil

        do {
            try vm.importBackupJSON(data: data, strategy: strategy)
        } catch {
            presentError(error)
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
                showSubscriptionSheet = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "creditcard")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(theme.surfaceAlt))

                    Text("Subscription")
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
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(theme.surfaceAlt))

                    Text("Backup")
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

            Spacer(minLength: 90)
        }
        .padding(.bottom, 110)
    }
}
