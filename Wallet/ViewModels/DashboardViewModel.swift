//
//  DashboardViewModel.swift
//  Wallet
//
//  Created by Lee Jun Wei on 22/2/26.
//

import Foundation
import Combine
import SwiftData

@MainActor
final class DashboardViewModel: ObservableObject {
    private let modelContext: ModelContext

    @Published var accounts: [Account] = []
    @Published var transactions: [Transaction] = []

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchAll()
    }

    private func bankKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func fetchAll() {
        fetchAccounts()
        fetchTransactions()
    }

    private func fetchAccounts() {
        let descriptor = FetchDescriptor<Account>(
            sortBy: [SortDescriptor(\.bankName), SortDescriptor(\.accountName)]
        )
        do { accounts = try modelContext.fetch(descriptor) }
        catch { print("fetchAccounts error:", error); accounts = [] }
    }

    private func fetchTransactions() {
        let descriptor = FetchDescriptor<Transaction>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        do { transactions = try modelContext.fetch(descriptor) }
        catch { print("fetchTransactions error:", error); transactions = [] }
    }

    // MARK: - Bank pooled values

    func bankTotalCredit(forBank bankName: String) -> Decimal? {
        let key = bankKey(bankName)
        return accounts.first(where: {
            $0.type == .credit &&
            $0.isInCombinedCreditPool &&
            bankKey($0.bankName) == key &&
            $0.currentCredit > 0
        })?.currentCredit
    }

    func bankInitialAvailableCredit(forBank bankName: String) -> Decimal? {
        let key = bankKey(bankName)
        return accounts.first(where: {
            $0.type == .credit &&
            $0.isInCombinedCreditPool &&
            bankKey($0.bankName) == key &&
            $0.amount > 0
        })?.amount
    }

    func syncBankCreditPool(bankName: String) {
        let key = bankKey(bankName)

        guard let shared = accounts.first(where: {
            $0.type == .credit &&
            $0.isInCombinedCreditPool &&
            bankKey($0.bankName) == key &&
            $0.currentCredit > 0
        })?.currentCredit else { return }

        for a in accounts where a.type == .credit && a.isInCombinedCreditPool && bankKey(a.bankName) == key {
            a.currentCredit = shared
        }
    }

    func syncBankInitialAvailableCredit(bankName: String) {
        let key = bankKey(bankName)

        guard let shared = accounts.first(where: {
            $0.type == .credit &&
            $0.isInCombinedCreditPool &&
            bankKey($0.bankName) == key &&
            $0.amount > 0
        })?.amount else { return }

        for a in accounts where a.type == .credit && a.isInCombinedCreditPool && bankKey(a.bankName) == key {
            a.amount = shared
        }
    }

    // MARK: - Account

    func addAccount(bankName: String,
                    accountName: String,
                    amount: Decimal,
                    type: AccountType,
                    currentCredit: Decimal,
                    isInCombinedCreditPool: Bool = false) {
        let colors = ["#FF2D55", "#00C7BE", "#FF9500", "#AF52DE", "#FF3B30", "#30D158", "#0A84FF"]
        let color = colors.randomElement() ?? "#0A84FF"
        let icon = (type == .cash) ? "banknote" : "creditcard.fill"

        let bank = bankName.uppercased()
        let acctName = accountName.uppercased()

        let pooled = (type == .credit) ? isInCombinedCreditPool : false

        var creditToStore = currentCredit
        var amountToStore = amount

        if type == .credit && pooled {
            creditToStore = bankTotalCredit(forBank: bank) ?? currentCredit
            amountToStore = bankInitialAvailableCredit(forBank: bank) ?? amount
        }

        let account = Account(
            bankName: bank,
            accountName: acctName,
            currentCredit: creditToStore,
            amount: amountToStore,
            type: type,
            colorHex: color,
            iconSystemName: icon,
            isInCombinedCreditPool: pooled
        )

        modelContext.insert(account)
        save()
        fetchAccounts()

        if type == .credit && pooled {
            syncBankCreditPool(bankName: bank)
            syncBankInitialAvailableCredit(bankName: bank)
            save()
            fetchAccounts()
        }
    }

    func updateAccount(id: UUID,
                       bankName: String,
                       accountName: String,
                       amount: Decimal,
                       type: AccountType,
                       currentCredit: Decimal,
                       isInCombinedCreditPool: Bool) {
        guard let account = accounts.first(where: { $0.id == id }) else { return }

        let oldBank = account.bankName
        let newBank = bankName.uppercased()

        account.bankName = newBank
        account.accountName = accountName.uppercased()
        account.type = type
        account.iconSystemName = (type == .cash) ? "banknote" : "creditcard.fill"

        if type != .credit {
            account.isInCombinedCreditPool = false
            account.currentCredit = currentCredit
            account.amount = amount
        } else {
            account.isInCombinedCreditPool = isInCombinedCreditPool

            if isInCombinedCreditPool {
                account.currentCredit = bankTotalCredit(forBank: newBank) ?? currentCredit
                account.amount = bankInitialAvailableCredit(forBank: newBank) ?? amount
            } else {
                account.currentCredit = currentCredit
                account.amount = amount
            }
        }

        syncBankCreditPool(bankName: oldBank)
        syncBankCreditPool(bankName: newBank)
        syncBankInitialAvailableCredit(bankName: oldBank)
        syncBankInitialAvailableCredit(bankName: newBank)

        save()
        fetchAccounts()
    }

    func deleteAccount(_ account: Account) {
        let txns = transactions.filter { $0.accountId == account.id }
        for t in txns { modelContext.delete(t) }

        let bank = account.bankName
        modelContext.delete(account)

        save()
        fetchAll()

        syncBankCreditPool(bankName: bank)
        syncBankInitialAvailableCredit(bankName: bank)
        save()
        fetchAll()
    }

    // MARK: - Transaction

    func addTransaction(type: TransactionType,
                        amount: Decimal,
                        accountId: UUID,
                        category: TransactionCategory,
                        date: Date,
                        note: String) {
        let txn = Transaction(
            type: type,
            amount: amount,
            accountId: accountId,
            category: category,
            date: date,
            note: note
        )
        modelContext.insert(txn)

        if let account = accounts.first(where: { $0.id == accountId }), account.type == .cash {
            switch type {
            case .expense: account.amount -= amount
            case .income:  account.amount += amount
            }
        }

        save()
        fetchAll()
    }

    func deleteTransaction(_ txn: Transaction) {
        if let account = accounts.first(where: { $0.id == txn.accountId }), account.type == .cash {
            switch txn.type {
            case .expense: account.amount += txn.amount
            case .income:  account.amount -= txn.amount
            }
        }

        modelContext.delete(txn)
        save()
        fetchAll()
    }

    // MARK: - Queries / Calculations

    func transactions(for accountId: UUID) -> [Transaction] {
        transactions.filter { $0.accountId == accountId }
    }

    func totalSpent(for accountId: UUID) -> Decimal {
        transactions(for: accountId)
            .filter { $0.type == .expense }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }

    func creditPoolAccountIds(for accountId: UUID) -> [UUID] {
        guard let acct = accounts.first(where: { $0.id == accountId }) else { return [accountId] }
        guard acct.type == .credit, acct.isInCombinedCreditPool else { return [acct.id] }

        let key = bankKey(acct.bankName)
        let pooled = accounts
            .filter { $0.type == .credit && $0.isInCombinedCreditPool && bankKey($0.bankName) == key }
            .map(\.id)

        if pooled.contains(acct.id) { return pooled }
        return pooled + [acct.id]
    }

    func sharedAvailableCredit(for accountId: UUID) -> Decimal {
        guard let acct = accounts.first(where: { $0.id == accountId }) else { return 0 }
        guard acct.type == .credit else { return 0 }

        let ids = Set(creditPoolAccountIds(for: accountId))

        let baseline: Decimal = {
            if acct.isInCombinedCreditPool {
                return bankInitialAvailableCredit(forBank: acct.bankName) ?? acct.amount
            } else {
                return acct.amount
            }
        }()

        let spent = transactions
            .filter { ids.contains($0.accountId) && $0.type == .expense }
            .reduce(Decimal.zero) { $0 + $1.amount }

        return max(0, baseline - spent)
    }

    func pooledCardCount(for accountId: UUID) -> Int {
        creditPoolAccountIds(for: accountId).count
    }

    // MARK: - Backup (Export/Import)

    func exportBackupJSON() throws -> Data {
        try WalletBackupService.exportJSON(accounts: accounts, transactions: transactions)
    }

    func importBackupJSON(data: Data, strategy: WalletImportStrategy) throws {
        let file = try WalletBackupService.decodeBackup(from: data)
        try WalletBackupService.import(file, into: modelContext, strategy: strategy)
        fetchAll()
    }

    // MARK: - Save

    private func save() {
        do { try modelContext.save() }
        catch { print("save error:", error) }
    }
}
