//
//  StatisticsScreen.swift
//  FrugalPilot
//
//  Created by Codex on 27/2/26.
//

import SwiftUI
import SwiftData
import Charts

private enum StatisticsWidgetMetric: String, CaseIterable, Identifiable, Codable {
    case spendingByCategory = "Spending by Category"
    case monthlySpending = "Monthly Spending Trend"
    case incomeVsExpense = "Income vs Expense"
    case fixedPlanned = "Fixed Planned Per Month"
    case netWorthTrend = "Estimated Net Worth Trend"
    case topCategories = "Top Categories"
    case instalment = "Instalment (Fixed Payments)"
    case forecast = "Forecast (Next Month)"
    case debtPayoff = "Debt Payoff (Using Instalment)"
    var id: String { rawValue }
}

private enum StatisticsChartStyle: String, CaseIterable, Identifiable, Codable {
    case pie = "Pie"
    case line = "Line"
    case bar = "Bar"
    case card = "Card"
    var id: String { rawValue }
}

private enum StatisticsPeriod: String, CaseIterable, Identifiable, Codable {
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

private struct StatisticsWidgetConfig: Identifiable, Codable, Equatable {
    let id: UUID
    var metric: StatisticsWidgetMetric
    var style: StatisticsChartStyle
    var period: StatisticsPeriod

    init(id: UUID = UUID(),
         metric: StatisticsWidgetMetric,
         style: StatisticsChartStyle,
         period: StatisticsPeriod) {
        self.id = id
        self.metric = metric
        self.style = style
        self.period = period
    }

    static let defaults: [StatisticsWidgetConfig] = []
}

struct StatisticsScreen: View {
    @Environment(\.appTheme) private var theme
    @AppStorage("tracking_current_profile") private var currentProfileRaw: String = "Personal"
    @AppStorage("statistics_widgets_v1") private var widgetsRaw: String = ""
    @AppStorage("statistics_debt_repayment_monthly_v1") private var debtRepaymentMonthlyRaw: String = ""
    @Query(sort: [SortDescriptor(\Transaction.date, order: .reverse)])
    private var allTransactions: [Transaction]
    @Query(sort: [SortDescriptor(\FixedPayment.startDate)])
    private var allFixedPayments: [FixedPayment]
    @Query(sort: [SortDescriptor(\Account.bankName), SortDescriptor(\Account.accountName)])
    private var allAccounts: [Account]
    @State private var widgets: [StatisticsWidgetConfig] = []
    @State private var didLoadWidgets: Bool = false
    @State private var showAddWidgetSheet = false
    @State private var showDebtRepaymentSheet = false
    @State private var draftMetric: StatisticsWidgetMetric = .spendingByCategory
    @State private var draftStyle: StatisticsChartStyle = .pie
    @State private var draftPeriod: StatisticsPeriod = .sixMonths
    @State private var debtRepaymentInputText: String = ""

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

    private var instalmentPayments: [FixedPayment] {
        fixedPayments.filter { $0.type == .installment }
    }

    private var currentMonthPlannedTotal: Decimal {
        fixedPlannedSeries(monthCount: 1).first?.1 ?? .zero
    }

    private var totalInstalmentPrincipal: Decimal {
        instalmentPayments.reduce(.zero) { partial, payment in
            partial + installmentPrincipal(for: payment)
        }
    }

    private var monthlyRepaymentInput: Decimal {
        let normalized = debtRepaymentMonthlyRaw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard let value = Decimal(string: normalized), value > 0 else { return .zero }
        return value
    }

    private var nextMonthForecast: Decimal {
        forecastNetForNextMonth()
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

                    sectionHeader("Statistics Widgets")
                    chartCard(title: "Chart Widgets",
                              subtitle: "Add only what you want to see. Pick metric first, then chart/card format.") {
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                showAddWidgetSheet = true
                            } label: {
                                Label("Add Widget", systemImage: "plus.circle.fill")
                                    .font(.custom("Avenir Next", size: 13).weight(.semibold))
                                    .foregroundStyle(theme.accent)
                            }
                            .buttonStyle(.plain)

                            if widgets.isEmpty {
                                emptyState
                            } else {
                                ForEach(widgets) { widget in
                                    statisticsWidgetCard(widget)
                                }
                            }
                        }
                    }

                    Spacer(minLength: 90)
                }
                .padding(.bottom, 110)
            }
        }
        .onAppear {
            guard !didLoadWidgets else { return }
            didLoadWidgets = true
            loadWidgets()
        }
        .sheet(isPresented: $showAddWidgetSheet) {
            addWidgetSheet
        }
        .sheet(isPresented: $showDebtRepaymentSheet) {
            debtRepaymentSheet
        }
    }

    private var addWidgetSheet: some View {
        NavigationStack {
            Form {
                Section("What would you like to see?") {
                    Picker("Metric", selection: $draftMetric) {
                        ForEach(StatisticsWidgetMetric.allCases) { metric in
                            Text(metric.rawValue).tag(metric)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("How should it be shown?") {
                    Picker("Chart Type", selection: $draftStyle) {
                        ForEach(allowedStyles(for: draftMetric), id: \.self) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if supportsPeriod(for: draftMetric) {
                    Section("Which period?") {
                        Picker("Period", selection: $draftPeriod) {
                            ForEach(StatisticsPeriod.allCases) { period in
                                Text(period.rawValue).tag(period)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .onChange(of: draftMetric) { _, metric in
                let allowed = allowedStyles(for: metric)
                if !allowed.contains(draftStyle), let first = allowed.first {
                    draftStyle = first
                }
                if !supportsPeriod(for: metric) {
                    draftPeriod = .sixMonths
                }
            }
            .navigationTitle("Add Widget")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddWidgetSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addWidget()
                        showAddWidgetSheet = false
                    }
                }
            }
        }
    }

    private func statisticsWidgetCard(_ widget: StatisticsWidgetConfig) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(widget.metric.rawValue)
                        .font(.custom("Avenir Next", size: 14).weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(widgetSubtitle(for: widget))
                        .font(.custom("Avenir Next", size: 11))
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer()
                Button(role: .destructive) {
                    removeWidget(widget.id)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(theme.negative)
                }
                .buttonStyle(.plain)
            }

            renderWidgetChart(widget)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.surface))
    }

    @ViewBuilder
    private func renderWidgetChart(_ widget: StatisticsWidgetConfig) -> some View {
        switch widget.metric {
        case .spendingByCategory:
            let categories = expenseByCategory(monthCount: widget.period.monthCount)
            categoryChart(categories, style: widget.style)
        case .monthlySpending:
            let series = transactionMonthlySeries(monthCount: widget.period.monthCount)
            monthlySpendingChart(series, style: widget.style)
        case .incomeVsExpense:
            let series = transactionMonthlySeries(monthCount: widget.period.monthCount)
            incomeExpenseChart(series, style: widget.style)
        case .fixedPlanned:
            let series = fixedPlannedSeries(monthCount: widget.period.monthCount)
            fixedPlannedChart(series, style: widget.style)
        case .netWorthTrend:
            let series = estimatedNetWorthSeries(monthCount: widget.period.monthCount)
            netWorthChart(series, style: widget.style)
        case .topCategories:
            let categories = Array(expenseByCategory(monthCount: widget.period.monthCount).prefix(5))
            categoryChart(categories, style: widget.style == .line ? .bar : widget.style)
        case .instalment:
            infoWidgetCard(title: "Instalment",
                           value: CurrencyFormatter.sgd(amount: currentMonthPlannedTotal),
                           subtitle: "Value sourced from fixed payments for this month.")
        case .forecast:
            infoWidgetCard(title: "Forecast (Next Month)",
                           value: CurrencyFormatter.sgd(amount: nextMonthForecast),
                           subtitle: "Trailing 3-month average cashflow minus next month fixed payments.")
        case .debtPayoff:
            let payoffData = debtPayoffEstimate()
            Button {
                debtRepaymentInputText = debtRepaymentMonthlyRaw
                showDebtRepaymentSheet = true
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    infoWidgetCard(title: "Total Instalment Debt",
                                   value: CurrencyFormatter.sgd(amount: payoffData.totalDebt),
                                   subtitle: "Installment total derived from fixed payments.")
                    infoWidgetCard(title: "Your Repayment / Month",
                                   value: payoffData.monthlyRepayment > 0
                                   ? CurrencyFormatter.sgd(amount: payoffData.monthlyRepayment)
                                   : "Not Set",
                                   subtitle: "Tap to set monthly repayment and calculate payoff months.")
                    infoWidgetCard(title: "Estimated Months To Pay Off",
                                   value: payoffData.months > 0 ? "\(payoffData.months)" : "-",
                                   subtitle: "Ceiling(total installment debt / monthly repayment).")
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var debtRepaymentSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                infoWidgetCard(title: "Total Instalment Debt",
                               value: CurrencyFormatter.sgd(amount: totalInstalmentPrincipal),
                               subtitle: "Sum of installment principal from Fixed Payments.")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Repayment Per Month")
                        .font(.custom("Avenir Next", size: 12).weight(.semibold))
                        .foregroundStyle(theme.textSecondary)
                    TextField("e.g. 300.00", text: $debtRepaymentInputText)
                        .keyboardType(.decimalPad)
                        .font(.custom("Avenir Next", size: 16))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(theme.surfaceAlt))
                    Text("Enter how much you plan to repay monthly.")
                        .font(.custom("Avenir Next", size: 11))
                        .foregroundStyle(theme.textTertiary)
                }

                infoWidgetCard(title: "Estimated Months",
                               value: "\(estimatedPayoffMonths(totalDebt: totalInstalmentPrincipal, monthlyRepayment: draftMonthlyRepayment))",
                               subtitle: "Based on your entered monthly repayment.")

                Spacer(minLength: 0)
            }
            .padding(16)
            .background(theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Debt Repayment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showDebtRepaymentSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        debtRepaymentMonthlyRaw = debtRepaymentInputText
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: ",", with: "")
                        showDebtRepaymentSheet = false
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.custom("Avenir Next", size: 12).weight(.bold))
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 18)
    }

    private func allowedStyles(for metric: StatisticsWidgetMetric) -> [StatisticsChartStyle] {
        switch metric {
        case .spendingByCategory, .topCategories:
            return [.pie, .bar]
        case .monthlySpending, .incomeVsExpense, .fixedPlanned, .netWorthTrend:
            return [.line, .bar]
        case .instalment, .forecast, .debtPayoff:
            return [.card]
        }
    }

    private func supportsPeriod(for metric: StatisticsWidgetMetric) -> Bool {
        switch metric {
        case .spendingByCategory, .monthlySpending, .incomeVsExpense, .fixedPlanned, .netWorthTrend, .topCategories:
            return true
        case .instalment, .forecast, .debtPayoff:
            return false
        }
    }

    private func widgetSubtitle(for widget: StatisticsWidgetConfig) -> String {
        if supportsPeriod(for: widget.metric) {
            return "\(widget.style.rawValue) • \(widget.period.rawValue)"
        }
        return widget.style.rawValue
    }

    private func addWidget() {
        let style = allowedStyles(for: draftMetric).contains(draftStyle)
            ? draftStyle
            : (allowedStyles(for: draftMetric).first ?? .bar)
        let period: StatisticsPeriod = supportsPeriod(for: draftMetric) ? draftPeriod : .sixMonths
        widgets.append(StatisticsWidgetConfig(metric: draftMetric, style: style, period: period))
        saveWidgets()
    }

    private func removeWidget(_ id: UUID) {
        widgets.removeAll { $0.id == id }
        saveWidgets()
    }

    private func loadWidgets() {
        guard !widgetsRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            widgets = StatisticsWidgetConfig.defaults
            return
        }
        guard let data = widgetsRaw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([StatisticsWidgetConfig].self, from: data),
              !decoded.isEmpty else {
            widgets = StatisticsWidgetConfig.defaults
            return
        }
        widgets = decoded
    }

    private func saveWidgets() {
        guard let data = try? JSONEncoder().encode(widgets),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        widgetsRaw = json
    }

    private func colorForChartIndex(_ index: Int) -> Color {
        let palette: [Color] = [.blue, .teal, .orange, .pink, .indigo, .green, .cyan, .mint, .red]
        return palette[index % palette.count]
    }

    @ViewBuilder
    private func categoryChart(_ categories: [(String, Decimal)], style: StatisticsChartStyle) -> some View {
        if categories.isEmpty {
            emptyState
        } else if style == .pie {
            Chart {
                ForEach(Array(categories.enumerated()), id: \.element.0) { index, item in
                    SectorMark(angle: .value("Amount", item.1))
                        .foregroundStyle(colorForChartIndex(index))
                }
            }
            .chartLegend(.hidden)
            .frame(height: 180)
            categoryLegend(categories)
        } else {
            Chart {
                ForEach(Array(categories.enumerated()), id: \.element.0) { index, item in
                    BarMark(
                        x: .value("Amount", (item.1 as NSDecimalNumber).doubleValue),
                        y: .value("Category", item.0)
                    )
                    .foregroundStyle(colorForChartIndex(index))
                }
            }
            .frame(height: 180)
        }
    }

    @ViewBuilder
    private func monthlySpendingChart(_ series: [(Date, Decimal, Decimal)], style: StatisticsChartStyle) -> some View {
        if series.isEmpty {
            emptyState
        } else if style == .line {
            Chart {
                ForEach(series, id: \.0) { row in
                    LineMark(
                        x: .value("Month", row.0, unit: .month),
                        y: .value("Spent", (row.1 as NSDecimalNumber).doubleValue)
                    )
                    .foregroundStyle(theme.negative)
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) }
            .frame(height: 170)
        } else {
            Chart {
                ForEach(series, id: \.0) { row in
                    BarMark(
                        x: .value("Month", row.0, unit: .month),
                        y: .value("Spent", (row.1 as NSDecimalNumber).doubleValue)
                    )
                    .foregroundStyle(theme.negative)
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) }
            .frame(height: 170)
        }
    }

    @ViewBuilder
    private func incomeExpenseChart(_ series: [(Date, Decimal, Decimal)], style: StatisticsChartStyle) -> some View {
        if series.isEmpty {
            emptyState
        } else if style == .line {
            Chart {
                ForEach(series, id: \.0) { row in
                    LineMark(
                        x: .value("Month", row.0, unit: .month),
                        y: .value("Income", (row.2 as NSDecimalNumber).doubleValue)
                    )
                    .foregroundStyle(theme.positive)
                    LineMark(
                        x: .value("Month", row.0, unit: .month),
                        y: .value("Expense", (row.1 as NSDecimalNumber).doubleValue)
                    )
                    .foregroundStyle(theme.negative)
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) }
            .frame(height: 170)
        } else {
            Chart {
                ForEach(series, id: \.0) { row in
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
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) }
            .frame(height: 170)
        }
    }

    @ViewBuilder
    private func fixedPlannedChart(_ series: [(Date, Decimal)], style: StatisticsChartStyle) -> some View {
        if series.allSatisfy({ $0.1 == .zero }) {
            emptyState
        } else if style == .line {
            Chart {
                ForEach(series, id: \.0) { row in
                    LineMark(
                        x: .value("Month", row.0, unit: .month),
                        y: .value("Planned", (row.1 as NSDecimalNumber).doubleValue)
                    )
                    .foregroundStyle(theme.accent)
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) }
            .frame(height: 170)
        } else {
            Chart {
                ForEach(series, id: \.0) { row in
                    BarMark(
                        x: .value("Month", row.0, unit: .month),
                        y: .value("Planned", (row.1 as NSDecimalNumber).doubleValue)
                    )
                    .foregroundStyle(theme.accent)
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) }
            .frame(height: 170)
        }
    }

    @ViewBuilder
    private func netWorthChart(_ series: [(Date, Decimal)], style: StatisticsChartStyle) -> some View {
        if series.isEmpty {
            emptyState
        } else if style == .bar {
            Chart {
                ForEach(series, id: \.0) { row in
                    BarMark(
                        x: .value("Month", row.0, unit: .month),
                        y: .value("Net Worth", (row.1 as NSDecimalNumber).doubleValue)
                    )
                    .foregroundStyle(theme.accent)
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) }
            .frame(height: 170)
        } else {
            Chart {
                ForEach(series, id: \.0) { row in
                    LineMark(
                        x: .value("Month", row.0, unit: .month),
                        y: .value("Net Worth", (row.1 as NSDecimalNumber).doubleValue)
                    )
                    .foregroundStyle(theme.accent)
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) }
            .frame(height: 170)
        }
    }

    private func categoryLegend(_ categories: [(String, Decimal)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(categories.enumerated()), id: \.element.0) { index, item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(colorForChartIndex(index))
                        .frame(width: 8, height: 8)
                    Text(item.0)
                        .font(.custom("Avenir Next", size: 11).weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Text(CurrencyFormatter.sgd(amount: item.1))
                        .font(.custom("Avenir Next", size: 11))
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
        .padding(.top, 8)
    }

    private func infoWidgetCard(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.custom("Avenir Next", size: 12).weight(.semibold))
                .foregroundStyle(theme.textSecondary)
            Text(value)
                .font(.custom("Avenir Next", size: 20).weight(.bold))
                .foregroundStyle(theme.textPrimary)
            Text(subtitle)
                .font(.custom("Avenir Next", size: 11))
                .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.surfaceAlt))
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

    private func chartCard<Content: View>(title: String,
                                          subtitle: String? = nil,
                                          @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.custom("Avenir Next", size: 16).weight(.semibold))
                .foregroundStyle(theme.textPrimary)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.custom("Avenir Next", size: 11))
                    .foregroundStyle(theme.textSecondary)
            }

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

    private func forecastNetForNextMonth() -> Decimal {
        let monthly = transactionMonthlySeries(monthCount: 3)
        guard monthly.isEmpty == false else { return .zero }
        let averageNet = monthly.reduce(Decimal.zero) { partial, row in
            partial + (row.2 - row.1)
        } / Decimal(monthly.count)

        let nextFixed = fixedPlannedSeries(monthCount: 2).last?.1 ?? .zero
        return averageNet - nextFixed
    }

    private func estimatedNetWorthSeries(monthCount: Int) -> [(Date, Decimal)] {
        let monthly = transactionMonthlySeries(monthCount: monthCount)
        var running: Decimal = .zero
        return monthly.map { row in
            running += (row.2 - row.1)
            return (row.0, running)
        }
    }

    private var draftMonthlyRepayment: Decimal {
        let normalized = debtRepaymentInputText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard let value = Decimal(string: normalized), value > 0 else { return .zero }
        return value
    }

    private func installmentPrincipal(for payment: FixedPayment) -> Decimal {
        if let outstanding = payment.outstandingAmount, outstanding > 0 {
            return outstanding
        }
        if let cycles = payment.cycles, cycles > 0 {
            return payment.amount * Decimal(cycles)
        }
        return max(payment.amount, .zero)
    }

    private func estimatedPayoffMonths(totalDebt: Decimal, monthlyRepayment: Decimal) -> Int {
        guard totalDebt > 0, monthlyRepayment > 0 else { return 0 }
        let months = NSDecimalNumber(decimal: totalDebt)
            .dividing(by: NSDecimalNumber(decimal: monthlyRepayment))
            .doubleValue
        return Int(ceil(months))
    }

    private func debtPayoffEstimate() -> (totalDebt: Decimal, monthlyRepayment: Decimal, months: Int) {
        let totalDebt = totalInstalmentPrincipal
        let monthlyRepayment = monthlyRepaymentInput
        let months = estimatedPayoffMonths(totalDebt: totalDebt, monthlyRepayment: monthlyRepayment)
        return (totalDebt, monthlyRepayment, months)
    }
}

private extension Decimal {
    static func amountIfActive(on monthStart: Date, payment: FixedPayment, calendar: Calendar) -> Decimal {
        let paymentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: payment.startDate)) ?? payment.startDate
        if paymentMonth > monthStart { return .zero }
        return payment.amount
    }
}
