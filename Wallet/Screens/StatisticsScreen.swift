//
//  StatisticsScreen.swift
//  Wallet
//
//  Created by Codex on 27/2/26.
//

import SwiftUI
import SwiftData
import Charts

private enum StatisticsAutoMetric: String, CaseIterable, Identifiable {
    case spendingByCategory = "Spending by Category"
    case monthlySpending = "Monthly Spending Trend"
    case incomeVsExpense = "Income vs Expense"
    case fixedPlanned = "Fixed Planned Per Month"
    var id: String { rawValue }
}

private enum StatisticsPeriod: String, CaseIterable, Identifiable {
    case threeMonths = "3 Months"
    case sixMonths = "6 Months"
    case twelveMonths = "12 Months"
    var id: String { rawValue }
    var monthCount: Int {
        switch self {
        case .threeMonths: return 3
        case .sixMonths: return 6
        case .twelveMonths: return 12
        }
    }
}

struct StatisticsScreen: View {
    @Environment(\.appTheme) private var theme
    @AppStorage("tracking_current_profile") private var currentProfileRaw: String = "Personal"
    @Query(sort: [SortDescriptor(\Transaction.date, order: .reverse)])
    private var allTransactions: [Transaction]
    @Query(sort: [SortDescriptor(\FixedPayment.startDate)])
    private var allFixedPayments: [FixedPayment]
    @Query(sort: [SortDescriptor(\Account.bankName), SortDescriptor(\Account.accountName)])
    private var allAccounts: [Account]
    @State private var selectedAutoMetric: StatisticsAutoMetric = .monthlySpending
    @State private var selectedPeriod: StatisticsPeriod = .sixMonths

    private var currentProfileName: String {
        let trimmed = currentProfileRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Personal" : trimmed
    }

    private var profileAccountIds: Set<UUID> {
        Set(allAccounts.filter {
            let profile = $0.profileName.trimmingCharacters(in: .whitespacesAndNewlines)
            return (profile.isEmpty ? "Personal" : profile) == currentProfileName
        }.map(\.id))
    }

    private var transactions: [Transaction] {
        allTransactions.filter { profileAccountIds.contains($0.accountId) }
    }

    private var fixedPayments: [FixedPayment] {
        allFixedPayments.filter {
            let profile = $0.profileName.trimmingCharacters(in: .whitespacesAndNewlines)
            return (profile.isEmpty ? "Personal" : profile) == currentProfileName
        }
    }

    private var expenseByCategory: [(String, Decimal)] {
        expenseByCategory(monthCount: 6)
    }

    private var monthlySeries: [(Date, Decimal, Decimal)] {
        transactionMonthlySeries(monthCount: 6)
    }

    private var topCategories: [(String, Decimal)] {
        Array(expenseByCategory.prefix(5))
    }

    private var fixedPlannedSeries: [(Date, Decimal)] {
        fixedPlannedSeries(monthCount: 6)
    }

    private var currentMonthPlannedTotal: Decimal {
        fixedPlannedSeries(monthCount: 1).first?.1 ?? .zero
    }

    var body: some View {
        ZStack {
            theme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Color.clear
                            .frame(width: 34, height: 34)
                        Text("Statistics")
                            .font(.custom("Avenir Next", size: 22).weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)

                    totalAmountCard

                    chartCard(title: "Auto Generate") {
                        customChartControls
                    }

                    chartCard(title: "Spending by Category") {
                        if expenseByCategory.isEmpty {
                            emptyState
                        } else {
                            Chart {
                                ForEach(expenseByCategory, id: \.0) { item in
                                    SectorMark(
                                        angle: .value("Amount", item.1)
                                    )
                                    .foregroundStyle(by: .value("Category", item.0))
                                }
                            }
                            .chartLegend(.hidden)
                            .frame(height: 180)
                        }
                    }

                    chartCard(title: "Monthly Spending Trend") {
                        if monthlySeries.isEmpty {
                            emptyState
                        } else {
                            Chart {
                                ForEach(monthlySeries, id: \.0) { row in
                                    LineMark(
                                        x: .value("Month", row.0, unit: .month),
                                        y: .value("Spent", (row.1 as NSDecimalNumber).doubleValue)
                                    )
                                    .foregroundStyle(theme.negative)
                                }
                            }
                            .chartXAxis {
                                AxisMarks(values: .automatic(desiredCount: 6))
                            }
                            .frame(height: 160)
                        }
                    }

                    chartCard(title: "Income vs Expense") {
                        if monthlySeries.isEmpty {
                            emptyState
                        } else {
                            Chart {
                                ForEach(monthlySeries, id: \.0) { row in
                                    BarMark(
                                        x: .value("Month", row.0, unit: .month),
                                        y: .value("Income", (row.2 as NSDecimalNumber).doubleValue)
                                    )
                                    .foregroundStyle(theme.positive)
                                    BarMark(
                                        x: .value("Month", row.0, unit: .month),
                                        y: .value("Expense", (row.1 as NSDecimalNumber).doubleValue)
                                    )
                                    .foregroundStyle(theme.negative)
                                }
                            }
                            .chartXAxis {
                                AxisMarks(values: .automatic(desiredCount: 6))
                            }
                            .frame(height: 160)
                        }
                    }

                    chartCard(title: "Fixed Planned Per Month") {
                        if fixedPlannedSeries.allSatisfy({ $0.1 == .zero }) {
                            emptyState
                        } else {
                            Chart {
                                ForEach(fixedPlannedSeries, id: \.0) { row in
                                    BarMark(
                                        x: .value("Month", row.0, unit: .month),
                                        y: .value("Planned", (row.1 as NSDecimalNumber).doubleValue)
                                    )
                                    .foregroundStyle(theme.accent)
                                }
                            }
                            .chartXAxis {
                                AxisMarks(values: .automatic(desiredCount: 6))
                            }
                            .frame(height: 160)
                        }
                    }

                    chartCard(title: "Top Categories") {
                        if topCategories.isEmpty {
                            emptyState
                        } else {
                            Chart {
                                ForEach(topCategories, id: \.0) { item in
                                    BarMark(
                                        x: .value("Amount", (item.1 as NSDecimalNumber).doubleValue),
                                        y: .value("Category", item.0)
                                    )
                                    .foregroundStyle(theme.accent)
                                }
                            }
                            .chartXAxis(.hidden)
                            .frame(height: 160)
                        }
                    }

                    Spacer(minLength: 90)
                }
                .padding(.bottom, 110)
            }
        }
    }

    private var totalAmountCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Total Amount (This Month)")
                .font(.custom("Avenir Next", size: 13).weight(.semibold))
                .foregroundStyle(theme.textSecondary)
            Text(CurrencyFormatter.sgd(amount: currentMonthPlannedTotal))
                .font(.custom("Avenir Next", size: 28).weight(.bold))
                .foregroundStyle(theme.textPrimary)
            Text("Planned fixed payments for this month")
                .font(.custom("Avenir Next", size: 11))
                .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.card))
        .padding(.horizontal, 18)
    }

    private var customChartControls: some View {
        let customMonthlySeries = transactionMonthlySeries(monthCount: selectedPeriod.monthCount)
        let customCategorySeries = expenseByCategory(monthCount: selectedPeriod.monthCount)
        let customFixedSeries = fixedPlannedSeries(monthCount: selectedPeriod.monthCount)

        return VStack(alignment: .leading, spacing: 12) {
            Picker("What to show", selection: $selectedAutoMetric) {
                ForEach(StatisticsAutoMetric.allCases) { metric in
                    Text(metric.rawValue).tag(metric)
                }
            }
            .pickerStyle(.menu)

            Picker("Period", selection: $selectedPeriod) {
                ForEach(StatisticsPeriod.allCases) { period in
                    Text(period.rawValue).tag(period)
                }
            }
            .pickerStyle(.segmented)

            switch selectedAutoMetric {
            case .spendingByCategory:
                if customCategorySeries.isEmpty {
                    emptyState
                } else {
                    Chart {
                        ForEach(customCategorySeries, id: \.0) { item in
                            SectorMark(angle: .value("Amount", item.1))
                                .foregroundStyle(by: .value("Category", item.0))
                        }
                    }
                    .chartLegend(.hidden)
                    .frame(height: 180)
                }
            case .monthlySpending:
                if customMonthlySeries.isEmpty {
                    emptyState
                } else {
                    Chart {
                        ForEach(customMonthlySeries, id: \.0) { row in
                            LineMark(
                                x: .value("Month", row.0, unit: .month),
                                y: .value("Spent", (row.1 as NSDecimalNumber).doubleValue)
                            )
                            .foregroundStyle(theme.negative)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: selectedPeriod.monthCount))
                    }
                    .frame(height: 170)
                }
            case .incomeVsExpense:
                if customMonthlySeries.isEmpty {
                    emptyState
                } else {
                    Chart {
                        ForEach(customMonthlySeries, id: \.0) { row in
                            BarMark(
                                x: .value("Month", row.0, unit: .month),
                                y: .value("Income", (row.2 as NSDecimalNumber).doubleValue)
                            )
                            .foregroundStyle(theme.positive)
                            BarMark(
                                x: .value("Month", row.0, unit: .month),
                                y: .value("Expense", (row.1 as NSDecimalNumber).doubleValue)
                            )
                            .foregroundStyle(theme.negative)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: selectedPeriod.monthCount))
                    }
                    .frame(height: 170)
                }
            case .fixedPlanned:
                if customFixedSeries.allSatisfy({ $0.1 == .zero }) {
                    emptyState
                } else {
                    Chart {
                        ForEach(customFixedSeries, id: \.0) { row in
                            BarMark(
                                x: .value("Month", row.0, unit: .month),
                                y: .value("Planned", (row.1 as NSDecimalNumber).doubleValue)
                            )
                            .foregroundStyle(theme.accent)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: selectedPeriod.monthCount))
                    }
                    .frame(height: 170)
                }
            }
        }
    }

    private func expenseByCategory(monthCount: Int) -> [(String, Decimal)] {
        let calendar = Calendar.current
        let startMonth = calendar.date(byAdding: .month, value: -(monthCount - 1), to: Date()) ?? Date()
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: startMonth)) ?? startMonth
        let end = Date()

        let txns = transactions.filter { $0.type == .expense && $0.date >= start && $0.date <= end }
        let grouped = Dictionary(grouping: txns) { txn in
            txn.categoryName.isEmpty ? (txn.category?.rawValue ?? "Other") : txn.categoryName
        }
        return grouped.map { key, values in
            (key, values.reduce(Decimal.zero) { $0 + $1.amount })
        }
        .sorted { $0.1 > $1.1 }
    }

    private func transactionMonthlySeries(monthCount: Int) -> [(Date, Decimal, Decimal)] {
        let calendar = Calendar.current
        let now = Date()
        let months = (0..<monthCount).compactMap { calendar.date(byAdding: .month, value: -$0, to: now) }

        return months.reversed().map { date in
            let comps = calendar.dateComponents([.year, .month], from: date)
            let monthStart = calendar.date(from: comps) ?? date
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)?.addingTimeInterval(-1) ?? monthStart

            let monthly = transactions.filter { $0.date >= monthStart && $0.date <= monthEnd }
            let expense = monthly.filter { $0.type == .expense }.reduce(Decimal.zero) { $0 + $1.amount }
            let income = monthly.filter { $0.type == .income }.reduce(Decimal.zero) { $0 + $1.amount }
            return (monthStart, expense, income)
        }
    }

    private func fixedPlannedSeries(monthCount: Int) -> [(Date, Decimal)] {
        let calendar = Calendar.current
        let now = Date()
        let months = (0..<monthCount).compactMap { calendar.date(byAdding: .month, value: $0, to: now) }

        return months.map { date in
            let comps = calendar.dateComponents([.year, .month], from: date)
            let monthStart = calendar.date(from: comps) ?? date
            let monthEnd = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: monthStart) ?? monthStart
            let total = fixedPayments.reduce(Decimal.zero) { partial, payment in
                partial + plannedAmount(for: payment, monthStart: monthStart, monthEnd: monthEnd, calendar: calendar)
            }
            return (monthStart, total)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .font(.system(size: 28))
                .foregroundStyle(theme.textTertiary)
            Text("Not enough data yet")
                .font(.custom("Avenir Next", size: 12).weight(.semibold))
                .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func chartCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.custom("Avenir Next", size: 16).weight(.semibold))
                .foregroundStyle(theme.textPrimary)

            content()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.card))
        .padding(.horizontal, 18)
    }

    private func plannedAmount(for payment: FixedPayment,
                               monthStart: Date,
                               monthEnd: Date,
                               calendar: Calendar) -> Decimal {
        if payment.startDate > monthEnd { return .zero }
        if let endDate = payment.endDate, endDate < monthStart { return .zero }

        switch payment.frequency {
        case .monthly:
            return .amountIfActive(on: monthStart, payment: payment, calendar: calendar)
        case .yearly:
            let startMonth = calendar.component(.month, from: payment.startDate)
            let targetMonth = calendar.component(.month, from: monthStart)
            if startMonth == targetMonth {
                return .amountIfActive(on: monthStart, payment: payment, calendar: calendar)
            }
            return .zero
        case .weekly:
            let start = max(payment.startDate, monthStart)
            let end = min(payment.endDate ?? monthEnd, monthEnd)
            if start > end { return .zero }

            let requestedWeekday = max(1, min(7, payment.chargeDay ?? calendar.component(.weekday, from: payment.startDate)))
            let startWeekday = calendar.component(.weekday, from: start)
            let forwardDays = (requestedWeekday - startWeekday + 7) % 7
            guard let firstMatch = calendar.date(byAdding: .day, value: forwardDays, to: start) else { return .zero }
            if firstMatch > end { return .zero }

            let dayDelta = calendar.dateComponents([.day], from: firstMatch, to: end).day ?? 0
            let occurrenceCount = (dayDelta / 7) + 1
            let multiplier = Decimal(occurrenceCount)
            return payment.amount * multiplier
        }
    }
}

private extension Decimal {
    static func amountIfActive(on monthStart: Date, payment: FixedPayment, calendar: Calendar) -> Decimal {
        let paymentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: payment.startDate)) ?? payment.startDate
        if paymentMonth > monthStart { return .zero }
        return payment.amount
    }
}
