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

    var isProEnabled: Bool { SubscriptionManager.hasPaidLimits }

    func canAddAccount() -> Bool {
        guard !isProEnabled else { return true }
        return accounts.count < SubscriptionManager.freeAccountLimit
    }

    func canAddTransaction(on date: Date) -> Bool {
        guard !isProEnabled else { return true }
        let count = monthlyTransactionCount(on: date)
        return count < SubscriptionManager.freeMonthlyTransactionLimit
    }

    // MARK: - Billing Period Calculations

    /// Returns (startDate, endDate) for a billing period given a specific startDay.
    /// `monthOffset` = 0 means current period, -1 = previous, etc.
    func billingPeriod(startDay: Int, monthOffset: Int = 0) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let now = Date()
        let clampedDay = min(max(startDay, 1), 31)

        let todayDay = cal.component(.day, from: now)
        var baseComps = cal.dateComponents([.year, .month], from: now)

        if todayDay < clampedDay {
            if let shifted = cal.date(byAdding: .month, value: -1, to: now) {
                baseComps = cal.dateComponents([.year, .month], from: shifted)
            }
        }

        baseComps.day = clampedDay
        baseComps.hour = 0
        baseComps.minute = 0
        baseComps.second = 0

        guard var periodStart = cal.date(from: baseComps) else {
            return (now, now)
        }

        if monthOffset != 0 {
            periodStart = cal.date(byAdding: .month, value: monthOffset, to: periodStart) ?? periodStart
        }

        // Clamp start day to actual days in month
        let startMonth = cal.component(.month, from: periodStart)
        let startYear = cal.component(.year, from: periodStart)
        let daysInStartMonth = cal.range(of: .day, in: .month, for: periodStart)?.count ?? 28
        let finalStartDay = min(clampedDay, daysInStartMonth)

        var startComps = DateComponents()
        startComps.year = startYear
        startComps.month = startMonth
        startComps.day = finalStartDay
        startComps.hour = 0
        startComps.minute = 0
        startComps.second = 0

        let finalStart = cal.date(from: startComps) ?? periodStart

        // End = next period start - 1 second
        guard let nextPeriodStart = cal.date(byAdding: .month, value: 1, to: finalStart) else {
            return (finalStart, finalStart)
        }

        let endMonth = cal.component(.month, from: nextPeriodStart)
        let endYear = cal.component(.year, from: nextPeriodStart)
        let daysInEndMonth = cal.range(of: .day, in: .month, for: nextPeriodStart)?.count ?? 28
        let finalEndDay = min(clampedDay, daysInEndMonth)

        var endComps = DateComponents()
        endComps.year = endYear
        endComps.month = endMonth
        endComps.day = finalEndDay
        endComps.hour = 0
        endComps.minute = 0
        endComps.second = 0

        let nextStart = cal.date(from: endComps) ?? nextPeriodStart
        let finalEnd = nextStart.addingTimeInterval(-1)

        return (finalStart, finalEnd)
    }

    /// Returns (startDate, endDate) for a calendar month period.
    /// `monthOffset` = 0 means current month, -1 = previous, etc.
    func calendarMonthPeriod(monthOffset: Int = 0) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let now = Date()
        let baseStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let start = cal.date(byAdding: .month, value: monthOffset, to: baseStart) ?? baseStart
        let nextStart = cal.date(byAdding: .month, value: 1, to: start) ?? start
        let end = nextStart.addingTimeInterval(-1)
        return (start, end)
    }

    /// Period label for a specific account
    func billingPeriodLabel(for account: Account, monthOffset: Int = 0) -> String {
        let period = (account.type == .cash)
            ? calendarMonthPeriod(monthOffset: monthOffset)
            : billingPeriod(startDay: account.billingCycleStartDay, monthOffset: monthOffset)
        let df = DateFormatter()
        df.dateFormat = "d MMM"
        let dfEnd = DateFormatter()
        dfEnd.dateFormat = "d MMM yyyy"
        return "\(df.string(from: period.start)) – \(dfEnd.string(from: period.end))"
    }

    /// Expenses for a specific account within its own billing period
    func periodExpenses(for accountId: UUID, monthOffset: Int = 0) -> Decimal {
        guard let account = accounts.first(where: { $0.id == accountId }) else { return 0 }
        let period = (account.type == .cash)
            ? calendarMonthPeriod(monthOffset: monthOffset)
            : billingPeriod(startDay: account.billingCycleStartDay, monthOffset: monthOffset)
        return transactions
            .filter {
                $0.accountId == accountId &&
                $0.type == .expense &&
                $0.date >= period.start &&
                $0.date <= period.end
            }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }

    /// Income for a specific account within its own billing period
    func periodIncome(for accountId: UUID, monthOffset: Int = 0) -> Decimal {
        guard let account = accounts.first(where: { $0.id == accountId }) else { return 0 }
        let period = (account.type == .cash)
            ? calendarMonthPeriod(monthOffset: monthOffset)
            : billingPeriod(startDay: account.billingCycleStartDay, monthOffset: monthOffset)
        return transactions
            .filter {
                $0.accountId == accountId &&
                $0.type == .income &&
                $0.date >= period.start &&
                $0.date <= period.end
            }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }

    /// Total expenses across ALL accounts, each using its own billing cycle
    func totalPeriodExpenses(monthOffset: Int = 0) -> Decimal {
        accounts.reduce(Decimal.zero) { total, account in
            total + periodExpenses(for: account.id, monthOffset: monthOffset)
        }
    }

    /// Total income across ALL accounts, each using its own billing cycle
    func totalPeriodIncome(monthOffset: Int = 0) -> Decimal {
        accounts.reduce(Decimal.zero) { total, account in
            total + periodIncome(for: account.id, monthOffset: monthOffset)
        }
    }

    // MARK: - Helpers

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
        do {
            transactions = try modelContext.fetch(descriptor)
            var didUpdate = false
            for txn in transactions where txn.categoryName.isEmpty {
                if let legacy = txn.category?.rawValue {
                    txn.categoryName = legacy
                    didUpdate = true
                }
            }
            if didUpdate { save() }
        } catch {
            print("fetchTransactions error:", error)
            transactions = []
        }
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
                    isInCombinedCreditPool: Bool = false,
                    billingCycleStartDay: Int = 1,
                    colorHex: String? = nil) -> Bool {
        if !canAddAccount() { return false }

        let colors = ["#FF2D55", "#00C7BE", "#FF9500", "#AF52DE", "#FF3B30", "#30D158", "#0A84FF"]
        let color = colorHex ?? (colors.randomElement() ?? "#0A84FF")
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
            isInCombinedCreditPool: pooled,
            billingCycleStartDay: min(max(billingCycleStartDay, 1), 31)
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
        return true
    }

    func updateAccount(id: UUID,
                       bankName: String,
                       accountName: String,
                       amount: Decimal,
                       type: AccountType,
                       currentCredit: Decimal,
                       isInCombinedCreditPool: Bool,
                       billingCycleStartDay: Int = 1,
                       colorHex: String? = nil) {
        guard let account = accounts.first(where: { $0.id == id }) else { return }

        let oldBank = account.bankName
        let newBank = bankName.uppercased()

        account.bankName = newBank
        account.accountName = accountName.uppercased()
        account.type = type
        account.iconSystemName = (type == .cash) ? "banknote" : "creditcard.fill"
        account.billingCycleStartDay = min(max(billingCycleStartDay, 1), 31)
        if let colorHex { account.colorHex = colorHex }

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
                        categoryName: String,
                        date: Date,
                        note: String) -> Bool {
        if !canAddTransaction(on: date) { return false }

        let txn = Transaction(
            type: type,
            amount: amount,
            accountId: accountId,
            categoryName: categoryName,
            category: TransactionCategory.from(name: categoryName),
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
        return true
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

    func monthlyTransactionCount(on date: Date) -> Int {
        let cal = Calendar.current
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: date)) else { return 0 }
        guard let nextMonth = cal.date(byAdding: .month, value: 1, to: monthStart) else { return 0 }
        let monthEnd = nextMonth.addingTimeInterval(-1)
        return transactions.filter { $0.date >= monthStart && $0.date <= monthEnd }.count
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
        let latestAccounts = try modelContext.fetch(FetchDescriptor<Account>())
        let latestTransactions = try modelContext.fetch(FetchDescriptor<Transaction>())
        let latestFixed = try modelContext.fetch(FetchDescriptor<FixedPayment>())
        let latestCustom = try modelContext.fetch(FetchDescriptor<CustomCategory>())
        return try WalletBackupService.exportJSON(accounts: latestAccounts,
                                                 transactions: latestTransactions,
                                                 fixedPayments: latestFixed,
                                                 customCategories: latestCustom)
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
