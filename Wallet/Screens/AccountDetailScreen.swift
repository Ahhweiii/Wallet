//
//  AccountDetailScreen.swift
//  Wallet
//
//  Created by Lee Jun Wei on 23/2/26.
//

import SwiftUI

struct AccountDetailScreen: View {
    @ObservedObject var vm: DashboardViewModel
    let accountId: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @AppStorage("theme_is_dark") private var themeIsDark: Bool = true

    @State private var showEditSheet: Bool = false
    @State private var showDeleteConfirm: Bool = false

    private var account: Account? {
        vm.accounts.first(where: { $0.id == accountId })
    }

    private var accountTransactions: [Transaction] {
        vm.transactions(for: accountId).sorted { $0.date > $1.date }
    }

    private var totalSpentThisAccount: Decimal {
        vm.totalSpent(for: accountId)
    }

    private var totalCreditToDisplay: Decimal {
        guard let acct = account else { return 0 }
        guard acct.type == .credit else { return 0 }
        return acct.isInCombinedCreditPool
            ? (vm.bankTotalCredit(forBank: acct.bankName) ?? acct.currentCredit)
            : acct.currentCredit
    }

    private var availableCreditToDisplay: Decimal {
        vm.sharedAvailableCredit(for: accountId)
    }

    private var pooledInfoText: String? {
        guard let acct = account, acct.type == .credit, acct.isInCombinedCreditPool else { return nil }
        let count = vm.pooledCardCount(for: accountId)
        return "Shared across \(count) card\(count == 1 ? "" : "s") • \(acct.bankName)"
    }

    var body: some View {
        ZStack {
            theme.backgroundGradient.ignoresSafeArea()

            if let account = account {
                List {
                    Section {
                        header(account: account)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }

                    if account.type == .credit {
                        Section {
                            creditCard
                                .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18))
                                .listRowBackground(Color.clear)
                        }
                    }

                    Section {
                        totalSummaryCard
                            .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18))
                            .listRowBackground(Color.clear)
                    }

                    Section {
                        if accountTransactions.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "tray")
                                    .font(.system(size: 34))
                                    .foregroundStyle(theme.textTertiary)
                                Text("No transactions yet")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(theme.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .listRowBackground(Color.clear)
                        } else {
                            ForEach(accountTransactions) { txn in
                                transactionRow(txn)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
                                    .listRowBackground(Color.clear)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            vm.deleteTransaction(txn)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    } header: {
                        Text("Transactions (This Card)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(theme.textPrimary)
                            .textCase(nil)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            } else {
                Text("Account not found")
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(themeIsDark ? .dark : .light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if account != nil {
                    HStack {
                        Button("Edit") { showEditSheet = true }
                            .foregroundStyle(theme.accent)

                        Button {
                            showDeleteConfirm = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .foregroundStyle(theme.negative)
                    }
                }
            }
        }
        .confirmationDialog("Delete this account?",
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) {
                guard let acct = account else { return }
                vm.deleteAccount(acct)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will also delete all transactions under this account.")
        }
        .sheet(isPresented: $showEditSheet) {
            if let account = account {
                EditAccountScreen(vm: vm, account: account) { bank, acctName, amount, type, credit, pooled, billingDay, colorHex in
                    vm.updateAccount(id: accountId,
                                     bankName: bank,
                                     accountName: acctName,
                                     amount: amount,
                                     type: type,
                                     currentCredit: credit,
                                     isInCombinedCreditPool: pooled,
                                     billingCycleStartDay: billingDay,
                                     colorHex: colorHex)
                }
            }
        }
    }

    private func header(account: Account) -> some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: account.colorHex).opacity(0.95))
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: account.iconSystemName)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                )

            Text(account.displayName)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(theme.textPrimary)

            Text(account.type.rawValue)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.textTertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Capsule().fill(theme.surfaceAlt))
        }
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var creditCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Credit")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
            }

            Divider().overlay(theme.divider)

            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Total Credit")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                    Text(CurrencyFormatter.sgd(amount: totalCreditToDisplay))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(theme.textPrimary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text("Available Credit")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                    Text(CurrencyFormatter.sgd(amount: availableCreditToDisplay))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(theme.textPrimary)
                }
            }

            if let info = pooledInfoText {
                Text(info)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.card))
    }

    private var totalSummaryCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Total Summary (This Card)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
            }

            Divider().overlay(theme.divider)

            Text("Total Spent")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            Text(CurrencyFormatter.sgd(amount: totalSpentThisAccount))
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(theme.negative)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.card))
    }

    private func transactionRow(_ txn: Transaction) -> some View {
        let isExpense = txn.type == .expense
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)

                if !txn.note.isEmpty {
                    Text(txn.note)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }

                Text(txn.date, style: .date)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()

            Text("\(isExpense ? "−" : "+")\(CurrencyFormatter.sgd(amount: txn.amount))")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isExpense ? theme.negative : theme.positive)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.card))
    }
}
