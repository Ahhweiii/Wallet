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
    private typealias PeriodTotals = (expense: Decimal, income: Decimal)
    private var periodTotalsCache: [String: PeriodTotals] = [:]
    private static let billingStartFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "d MMM"
        return df
    }()
    private static let billingEndFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "d MMM yyyy"
        return df
    }()

    @Published var accounts: [Account] = []
    @Published var transactions: [Transaction] = []
    private var activeProfileName: String = "Personal"

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    var isProEnabled: Bool { SubscriptionManager.hasPaidLimits }

    func setActiveProfile(_ profileName: String) {
        activeProfileName = Self.normalizedProfileName(profileName)
    }

    func deleteProfile(named profileName: String) {
        let normalized = Self.normalizedProfileName(profileName)
        guard normalized.caseInsensitiveCompare("Personal") != .orderedSame else { return }

        let allAccounts = (try? modelContext.fetch(FetchDescriptor<Account>())) ?? []
        let accountIds = Set(
            allAccounts
                .filter { Self.normalizedProfileName($0.profileName) == normalized }
                .map(\.id)
        )

        if accountIds.isEmpty {
            if activeProfileName == normalized {
                activeProfileName = "Personal"
                fetchAll()
            }
            return
        }

        let allTransactions = (try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? []
        for txn in allTransactions where accountIds.contains(txn.accountId) {
            modelContext.delete(txn)
        }

        for account in allAccounts where accountIds.contains(account.id) {
            modelContext.delete(account)
        }

        let allFixed = (try? modelContext.fetch(FetchDescriptor<FixedPayment>())) ?? []
        for fixed in allFixed where Self.normalizedProfileName(fixed.profileName) == normalized {
            modelContext.delete(fixed)
        }

        save()

        if activeProfileName == normalized {
            activeProfileName = "Personal"
        }
        fetchAll()
    }

    private static func normalizedProfileName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Personal" : trimmed
    }

    func canAddAccount() -> Bool {
        guard !isProEnabled else { return true }
        let totalAccounts = (try? modelContext.fetch(FetchDescriptor<Account>()).count) ?? accounts.count
        return totalAccounts < SubscriptionManager.freeAccountLimit
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
        return "\(Self.billingStartFormatter.string(from: period.start)) – \(Self.billingEndFormatter.string(from: period.end))"
    }

    private func periodCacheKey(accountId: UUID, monthOffset: Int) -> String {
        let dayStamp = Int(Date().timeIntervalSince1970 / 86_400)
        return "\(accountId.uuidString)|\(monthOffset)|\(dayStamp)"
    }

    private func invalidateComputedCaches() {
        periodTotalsCache.removeAll(keepingCapacity: true)
    }

    private func periodTotals(for accountId: UUID, monthOffset: Int) -> PeriodTotals {
        guard let account = accounts.first(where: { $0.id == accountId }) else { return (.zero, .zero) }
        let cacheKey = periodCacheKey(accountId: accountId, monthOffset: monthOffset)
        if let cached = periodTotalsCache[cacheKey] {
            return cached
        }

        let period = (account.type == .cash)
            ? calendarMonthPeriod(monthOffset: monthOffset)
            : billingPeriod(startDay: account.billingCycleStartDay, monthOffset: monthOffset)

        var expense: Decimal = .zero
        var income: Decimal = .zero
        for txn in transactions where txn.accountId == accountId && txn.date >= period.start && txn.date <= period.end {
            if txn.type == .expense {
                expense += txn.amount
            } else if txn.type == .income {
                income += txn.amount
            }
        }

        let totals: PeriodTotals = (expense, income)
        periodTotalsCache[cacheKey] = totals
        return totals
    }

    /// Expenses for a specific account within its own billing period
    func periodExpenses(for accountId: UUID, monthOffset: Int = 0) -> Decimal {
        periodTotals(for: accountId, monthOffset: monthOffset).expense
    }

    /// Income for a specific account within its own billing period
    func periodIncome(for accountId: UUID, monthOffset: Int = 0) -> Decimal {
        periodTotals(for: accountId, monthOffset: monthOffset).income
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
        invalidateComputedCaches()
        fetchAccounts()
        fetchTransactions()
        if applyDueFixedPaymentsIfNeeded() {
            invalidateComputedCaches()
            fetchAccounts()
            fetchTransactions()
        }
    }

    private func fetchAccounts() {
        let descriptor = FetchDescriptor<Account>(
            sortBy: [SortDescriptor(\.bankName), SortDescriptor(\.accountName)]
        )
        do {
            let allAccounts = try modelContext.fetch(descriptor)
            var didNormalize = false
            for account in allAccounts where account.profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                account.profileName = "Personal"
                didNormalize = true
            }
            if didNormalize { save() }
            accounts = allAccounts.filter { Self.normalizedProfileName($0.profileName) == activeProfileName }
        } catch {
            print("fetchAccounts error:", error)
            accounts = []
        }
        invalidateComputedCaches()
    }

    private func fetchTransactions() {
        let descriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        do {
            let allTransactions = try modelContext.fetch(descriptor)
            let accountIds = Set(accounts.map(\.id))
            transactions = allTransactions.filter { accountIds.contains($0.accountId) }
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
        invalidateComputedCaches()
    }

    private func fixedPaymentTxnKey(accountId: UUID, amount: Decimal, date: Date, note: String) -> String {
        let amountText = NSDecimalNumber(decimal: amount).stringValue
        let dayStamp = Int(date.timeIntervalSince1970 / 86_400)
        return "\(accountId.uuidString)|\(amountText)|\(dayStamp)|\(note)"
    }

    private func applyDueFixedPaymentsIfNeeded() -> Bool {
        let cal = Calendar.current
        let now = Date()
        let year = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)

        var monthComps = DateComponents()
        monthComps.year = year
        monthComps.month = month
        monthComps.day = 1
        let firstOfMonth = cal.date(from: monthComps) ?? now
        let daysInMonth = cal.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 31

        let fixedDescriptor = FetchDescriptor<FixedPayment>()
        guard let fixedPayments = try? modelContext.fetch(fixedDescriptor).filter({ Self.normalizedProfileName($0.profileName) == activeProfileName }) else { return false }

        let accountMap: [UUID: Account] = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        var existingFixedPaymentTxnKeys = Set(
            transactions
                .filter {
                    $0.type == .expense &&
                    $0.categoryName == "Fixed Payment" &&
                    cal.component(.year, from: $0.date) == year &&
                    cal.component(.month, from: $0.date) == month
                }
                .map { fixedPaymentTxnKey(accountId: $0.accountId, amount: $0.amount, date: $0.date, note: $0.note) }
        )
        var didMutate = false
        var fixedToDeleteIds = Set<UUID>()
        var fixedToDelete: [FixedPayment] = []

        func normalizedChargeDay(for item: FixedPayment) -> Int {
            if let day = item.chargeDay, (1...31).contains(day) {
                return day
            }
            if let dayFromDate = item.chargeDate.map({ cal.component(.day, from: $0) }), (1...31).contains(dayFromDate) {
                item.chargeDay = dayFromDate
                didMutate = true
                return dayFromDate
            }
            let startDay = min(max(cal.component(.day, from: item.startDate), 1), 31)
            item.chargeDay = startDay
            didMutate = true
            return startDay
        }

        func monthlyDueDate(rawDay: Int) -> Date {
            let clampedDay = min(max(rawDay, 1), daysInMonth)
            var dueComps = DateComponents()
            dueComps.year = year
            dueComps.month = month
            dueComps.day = clampedDay
            dueComps.hour = 9
            dueComps.minute = 0
            dueComps.second = 0
            return cal.date(from: dueComps) ?? now
        }

        func yearlyDueDate(startDate: Date, rawDay: Int) -> Date {
            let dueMonth = cal.component(.month, from: startDate)
            var dueMonthComps = DateComponents()
            dueMonthComps.year = year
            dueMonthComps.month = dueMonth
            dueMonthComps.day = 1
            let dueMonthFirst = cal.date(from: dueMonthComps) ?? now
            let dueMonthDays = cal.range(of: .day, in: .month, for: dueMonthFirst)?.count ?? 31
            let clampedDay = min(max(rawDay, 1), dueMonthDays)

            var dueComps = DateComponents()
            dueComps.year = year
            dueComps.month = dueMonth
            dueComps.day = clampedDay
            dueComps.hour = 9
            dueComps.minute = 0
            dueComps.second = 0
            return cal.date(from: dueComps) ?? now
        }

        for item in fixedPayments {
            if let endDate = item.endDate,
               cal.compare(now, to: endDate, toGranularity: .day) == .orderedDescending {
                fixedToDeleteIds.insert(item.id)
                fixedToDelete.append(item)
                didMutate = true
                continue
            }

            guard let accountId = item.chargeAccountId,
                  let account = accountMap[accountId] else { continue }
            guard item.amount > 0 else { continue }
            guard now >= item.startDate else { continue }

            let rawDay = normalizedChargeDay(for: item)

            let dueDate: Date
            switch item.frequency {
            case .monthly:
                dueDate = monthlyDueDate(rawDay: rawDay)
                guard now >= dueDate else { continue }
                if let last = item.lastChargedAt,
                   cal.isDate(last, equalTo: dueDate, toGranularity: .month) {
                    continue
                }
            case .yearly:
                dueDate = yearlyDueDate(startDate: item.startDate, rawDay: rawDay)
                guard now >= dueDate else { continue }
                if let last = item.lastChargedAt,
                   cal.isDate(last, equalTo: dueDate, toGranularity: .year) {
                    continue
                }
            case .weekly:
                let base = item.lastChargedAt ?? item.startDate
                let nextDue = cal.date(byAdding: .day, value: item.lastChargedAt == nil ? 0 : 7, to: base) ?? base
                guard now >= nextDue else { continue }
                dueDate = nextDue
            }

            let baseNote = item.note.trimmingCharacters(in: .whitespacesAndNewlines)
            let autoNote = baseNote.isEmpty ? item.name : "\(item.name) • \(baseNote)"

            let key = fixedPaymentTxnKey(accountId: accountId, amount: item.amount, date: dueDate, note: autoNote)
            let exists = existingFixedPaymentTxnKeys.contains(key)
            if exists {
                item.lastChargedAt = dueDate
                if let endDate = item.endDate,
                   cal.compare(dueDate, to: endDate, toGranularity: .day) != .orderedAscending,
                   !fixedToDeleteIds.contains(item.id) {
                    fixedToDeleteIds.insert(item.id)
                    fixedToDelete.append(item)
                }
                didMutate = true
                continue
            }

            let txn = Transaction(
                type: .expense,
                amount: item.amount,
                accountId: accountId,
                categoryName: "Fixed Payment",
                category: .other,
                date: dueDate,
                note: autoNote
            )
            modelContext.insert(txn)
            existingFixedPaymentTxnKeys.insert(key)

            if account.type == .cash {
                account.amount -= item.amount
            }

            if let outstanding = item.outstandingAmount {
                item.outstandingAmount = max(Decimal.zero, outstanding - item.amount)
                if item.outstandingAmount == Decimal.zero,
                   !fixedToDeleteIds.contains(item.id) {
                    fixedToDeleteIds.insert(item.id)
                    fixedToDelete.append(item)
                }
            }

            item.lastChargedAt = dueDate
            if let endDate = item.endDate,
               cal.compare(dueDate, to: endDate, toGranularity: .day) != .orderedAscending,
               !fixedToDeleteIds.contains(item.id) {
                fixedToDeleteIds.insert(item.id)
                fixedToDelete.append(item)
            }
            didMutate = true
        }

        for item in fixedToDelete {
            modelContext.delete(item)
        }

        if didMutate {
            save()
        }
        return didMutate
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
                    profileName: String = "Personal",
                    colorHex: String? = nil) -> Bool {
        if !canAddAccount() { return false }

        let colors = ["#FF2D55", "#00C7BE", "#FF9500", "#AF52DE", "#FF3B30", "#30D158", "#0A84FF"]
        let color = colorHex ?? (colors.randomElement() ?? "#0A84FF")
        let icon = (type == .cash) ? "banknote" : "creditcard.fill"

        let bank = bankName.uppercased()
        let acctName = accountName.uppercased()

        let pooled = (type == .credit) ? isInCombinedCreditPool : false
        let normalizedProfile = Self.normalizedProfileName(profileName)
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
            profileName: normalizedProfile,
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
            case .transfer: break
            }
        }

        save()
        fetchAll()
        return true
    }

    func payCreditCard(fromCashAccountId cashAccountId: UUID,
                       toCreditAccountId creditAccountId: UUID,
                       amount: Decimal,
                       date: Date,
                       note: String) -> Bool {
        guard amount > 0 else { return false }
        guard canAddTransaction(on: date) else { return false }
        guard let cashAccount = accounts.first(where: { $0.id == cashAccountId && $0.type == .cash }) else { return false }
        guard accounts.contains(where: { $0.id == creditAccountId && $0.type == .credit }) else { return false }
        guard cashAccount.amount >= amount else { return false }

        let cashName = accounts.first(where: { $0.id == cashAccountId })?.displayName ?? "Cash"
        let creditName = accounts.first(where: { $0.id == creditAccountId })?.displayName ?? "Credit Card"

        let outNote = note.isEmpty ? "To \(creditName)" : "To \(creditName) • \(note)"
        let cashSide = Transaction(
            type: .transfer,
            amount: amount,
            accountId: cashAccountId,
            categoryName: "Transfer Out",
            category: .other,
            date: date,
            note: outNote
        )
        modelContext.insert(cashSide)

        let inNote = note.isEmpty ? "From \(cashName)" : "From \(cashName) • \(note)"
        let creditSide = Transaction(
            type: .transfer,
            amount: amount,
            accountId: creditAccountId,
            categoryName: "Transfer In",
            category: .other,
            date: date,
            note: inNote
        )
        modelContext.insert(creditSide)

        cashAccount.amount -= amount

        save()
        fetchAll()
        return true
    }

    func transferBetweenAccounts(fromAccountId: UUID,
                                 toAccountId: UUID,
                                 amount: Decimal,
                                 date: Date,
                                 note: String) -> Bool {
        guard amount > 0 else { return false }
        guard fromAccountId != toAccountId else { return false }
        guard canAddTransaction(on: date) else { return false }
        guard let from = accounts.first(where: { $0.id == fromAccountId }) else { return false }
        guard let to = accounts.first(where: { $0.id == toAccountId }) else { return false }

        if from.type == .cash, from.amount < amount {
            return false
        }

        if from.type == .cash, to.type == .credit {
            return payCreditCard(fromCashAccountId: fromAccountId,
                                 toCreditAccountId: toAccountId,
                                 amount: amount,
                                 date: date,
                                 note: note)
        }

        let fromNote: String = {
            if note.isEmpty { return "To \(to.displayName)" }
            return "To \(to.displayName) • \(note)"
        }()

        let toNote: String = {
            if note.isEmpty { return "From \(from.displayName)" }
            return "From \(from.displayName) • \(note)"
        }()

        let outTxn = Transaction(
            type: .transfer,
            amount: amount,
            accountId: fromAccountId,
            categoryName: "Transfer Out",
            category: .other,
            date: date,
            note: fromNote
        )
        modelContext.insert(outTxn)

        let inTxn = Transaction(
            type: .transfer,
            amount: amount,
            accountId: toAccountId,
            categoryName: "Transfer In",
            category: .other,
            date: date,
            note: toNote
        )
        modelContext.insert(inTxn)

        if from.type == .cash {
            from.amount -= amount
        }
        if to.type == .cash {
            to.amount += amount
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
            case .transfer:
                if txn.categoryName == "Transfer Out" {
                    account.amount += txn.amount
                } else if txn.categoryName == "Transfer In" {
                    account.amount -= txn.amount
                }
            }
        }

        modelContext.delete(txn)
        save()
        fetchAll()
    }

    func updateTransaction(id: UUID,
                           type: TransactionType,
                           amount: Decimal,
                           accountId: UUID,
                           categoryName: String,
                           date: Date,
                           note: String) -> Bool {
        guard amount > 0 else { return false }
        guard let txn = transactions.first(where: { $0.id == id }) else { return false }
        guard txn.type != .transfer else { return false }

        let oldType = txn.type
        let oldAmount = txn.amount
        let oldAccountId = txn.accountId
        let oldCategoryName = txn.categoryName

        if let oldAccount = accounts.first(where: { $0.id == oldAccountId }), oldAccount.type == .cash {
            switch oldType {
            case .expense:
                oldAccount.amount += oldAmount
            case .income:
                oldAccount.amount -= oldAmount
            case .transfer:
                if oldCategoryName == "Transfer Out" {
                    oldAccount.amount += oldAmount
                } else if oldCategoryName == "Transfer In" {
                    oldAccount.amount -= oldAmount
                }
            }
        }

        txn.type = type
        txn.amount = amount
        txn.accountId = accountId
        txn.categoryName = categoryName
        txn.category = TransactionCategory.from(name: categoryName)
        txn.date = date
        txn.note = note

        if let newAccount = accounts.first(where: { $0.id == accountId }), newAccount.type == .cash {
            switch type {
            case .expense:
                newAccount.amount -= amount
            case .income:
                newAccount.amount += amount
            case .transfer:
                if categoryName == "Transfer Out" {
                    newAccount.amount -= amount
                } else if categoryName == "Transfer In" {
                    newAccount.amount += amount
                }
            }
        }

        save()
        fetchAll()
        return true
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
        let allTransactions = (try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? transactions
        return allTransactions.filter { $0.date >= monthStart && $0.date <= monthEnd }.count
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

        let expenses = transactions
            .filter { ids.contains($0.accountId) && $0.type == .expense }
            .reduce(Decimal.zero) { $0 + $1.amount }

        let incomes = transactions
            .filter {
                ids.contains($0.accountId) &&
                ($0.type == .income || ($0.type == .transfer && $0.categoryName == "Transfer In"))
            }
            .reduce(Decimal.zero) { $0 + $1.amount }

        let netSpent = max(Decimal.zero, expenses - incomes)
        return max(0, baseline - netSpent)
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
