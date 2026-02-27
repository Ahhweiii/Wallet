//
//  DashboardScreen.swift
//  Wallet
//
//  Created by Lee Jun Wei on 21/2/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DashboardScreen: View {
    @StateObject private var vm: DashboardViewModel

    @State private var selectedTab: Int = 0
    @State private var accountPage: Int = 0
    @State private var showAddAccount: Bool = false
    @State private var showAddTransaction: Bool = false
    @State private var selectedAccount: Account? = nil

    // Backup UI state
    @State private var showBackupSheet = false
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportDocument = WalletBackupDocument()
    @State private var exportFilename = "WalletBackup.json"

    // Present exporter/importer AFTER closing backup sheet
    @State private var pendingExportAfterSheetDismiss = false
    @State private var pendingImportAfterSheetDismiss = false

    @State private var pendingImportData: Data? = nil
    @State private var showImportStrategyDialog = false

    @State private var errorMessage: String? = nil
    @State private var showErrorAlert = false

    private let maxPerPage: Int = 4

    init(modelContext: ModelContext) {
        _vm = StateObject(wrappedValue: DashboardViewModel(modelContext: modelContext))
    }

    // CREDIT: total spent (this account only)
    private var totalSpentByAccountId: [UUID: Decimal] {
        var dict: [UUID: Decimal] = [:]

        let creditAccountIds = Set(vm.accounts.filter { $0.type == .credit }.map(\.id))

        for txn in vm.transactions where txn.type == .expense && creditAccountIds.contains(txn.accountId) {
            dict[txn.accountId, default: 0] += txn.amount
        }

        for acct in vm.accounts {
            dict[acct.id] = dict[acct.id] ?? 0
        }

        return dict
    }

    // Subtitle removed (per your request)
    private var subtitleByAccountId: [UUID: String] {
        Dictionary(uniqueKeysWithValues: vm.accounts.map { ($0.id, "") })
    }

    private var totalCards: Int { vm.accounts.count + 1 }

    private var pagesCount: Int {
        AccountsPagerView.pageCount(totalCards: totalCards, maxPerPage: maxPerPage)
    }

    // Recent Transactions: show ALL
    private var filteredTransactions: [Transaction] {
        vm.transactions.sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Color.black.ignoresSafeArea()

                VStack(spacing: 18) {
                    topBar

                    AccountsPagerView(
                        accounts: vm.accounts,
                        totalSpentByAccountId: totalSpentByAccountId,
                        subtitleByAccountId: subtitleByAccountId,
                        pageIndex: $accountPage,
                        maxPerPage: maxPerPage,
                        onAddAccount: { showAddAccount = true },
                        onTapAccount: { selectedAccount = $0 }
                    )
                    .padding(.horizontal, 18)

                    PageDotsView(count: pagesCount, index: accountPage)
                        .padding(.top, 2)

                    recentTransactions

                    Spacer(minLength: 90)
                }

                FloatingAddButton { showAddTransaction = true }
                    .padding(.trailing, 22)
                    .padding(.bottom, 90)

                BottomTabBarView(selectedTab: $selectedTab)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 22)
            }
            .navigationDestination(item: $selectedAccount) { acct in
                AccountDetailScreen(vm: vm, accountId: acct.id)
            }
            .sheet(isPresented: $showAddAccount) {
                AddAccountScreen(vm: vm) { bank, account, amount, type, credit, pooled in
                    vm.addAccount(bankName: bank,
                                  accountName: account,
                                  amount: amount,
                                  type: type,
                                  currentCredit: credit,
                                  isInCombinedCreditPool: pooled)
                }
            }
            .sheet(isPresented: $showAddTransaction) {
                AddTransactionScreen(vm: vm) { }
            }
            .sheet(isPresented: $showBackupSheet) {
                backupSheet
            }

            // Exporter / Importer must be attached to the main screen (not inside the sheet)
            .fileExporter(isPresented: $showExporter,
                          document: exportDocument,
                          contentType: .json,
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
            .onAppear { vm.fetchAll() }
            .onChange(of: vm.accounts.count) { _, _ in
                accountPage = min(accountPage, max(0, pagesCount - 1))
            }

            .onChange(of: showBackupSheet) { _, isPresented in
                guard isPresented == false else { return }

                if pendingExportAfterSheetDismiss {
                    pendingExportAfterSheetDismiss = false
                    showExporter = true
                }

                if pendingImportAfterSheetDismiss {
                    pendingImportAfterSheetDismiss = false
                    showImporter = true
                }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Spacer()
            HStack(spacing: 18) {
                Image(systemName: "bell")
                    .foregroundStyle(.white)
                    .font(.system(size: 18, weight: .semibold))

                Button {
                    showBackupSheet = true
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.white)
                        .font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
    }

    private var recentTransactions: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recent Transactions")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("All accounts")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.horizontal, 18)

            if filteredTransactions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundStyle(.white.opacity(0.2))
                    Text("No transactions yet")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)

            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredTransactions.prefix(50)) { txn in
                            transactionRow(txn)
                        }
                    }
                    .padding(.horizontal, 18)
                }
            }
        }
    }

    private func transactionRow(_ txn: Transaction) -> some View {
        let isExpense = txn.type == .expense
        let acct = vm.accounts.first(where: { $0.id == txn.accountId })

        return HStack(spacing: 14) {
            Circle()
                .fill((isExpense ? Color.red : Color.green).opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: txn.category.iconSystemName)
                        .font(.system(size: 16))
                        .foregroundStyle(isExpense ? .red : .green)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(txn.category.rawValue)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                if let acct {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: acct.colorHex).opacity(0.95))
                            .frame(width: 10, height: 10)

                        Text(acct.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                } else {
                    Text("Unknown account")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(isExpense ? "−" : "+")\(CurrencyFormatter.sgd(amount: txn.amount))")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isExpense ? .red : .green)

                Text(txn.date, style: .date)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.14)))
    }

    private var backupSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 14) {
                    Button {
                        do {
                            let data = try vm.exportBackupJSON()
                            exportDocument = WalletBackupDocument(data: data)
                            exportFilename = "WalletBackup-\(ISO8601DateFormatter().string(from: Date())).json"

                            pendingExportAfterSheetDismiss = true
                            showBackupSheet = false
                        } catch {
                            presentError(error)
                        }
                    } label: {
                        Text("Export Backup (JSON)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.blue))
                    }
                    .buttonStyle(.plain)

                    Button {
                        pendingImportAfterSheetDismiss = true
                        showBackupSheet = false
                    } label: {
                        Text("Import Backup (JSON)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.14)))
                    }
                    .buttonStyle(.plain)

                    Text("Import will ask whether to Merge or Replace All.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.top, 6)

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showBackupSheet = false }
                        .foregroundStyle(.white)
                }
            }
        }
    }

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
}
