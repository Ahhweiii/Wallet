//
//  StatisticsScreen.swift
//  Wallet
//
//  Created by Codex on 27/2/26.
//

import SwiftUI
import SwiftData
import Charts

struct StatisticsScreen: View {
    @Environment(\.appTheme) private var theme
    @Query(sort: [SortDescriptor(\Transaction.date, order: .reverse)])
    private var transactions: [Transaction]

    private var expenseByCategory: [(String, Decimal)] {
        let txns = transactions.filter { $0.type == .expense }
        let grouped = Dictionary(grouping: txns) { txn in
            txn.categoryName.isEmpty ? (txn.category?.rawValue ?? "Other") : txn.categoryName
        }
        return grouped.map { key, values in
            (key, values.reduce(Decimal.zero) { $0 + $1.amount })
        }
        .sorted { $0.1 > $1.1 }
    }

    private var monthlySeries: [(Date, Decimal, Decimal)] {
        let cal = Calendar.current
        let now = Date()
        let months = (0..<6).compactMap { cal.date(byAdding: .month, value: -$0, to: now) }
        return months.reversed().map { date in
            let comps = cal.dateComponents([.year, .month], from: date)
            let start = cal.date(from: comps) ?? date
            let end = cal.date(byAdding: .month, value: 1, to: start)?.addingTimeInterval(-1) ?? start
            let monthly = transactions.filter { $0.date >= start && $0.date <= end }
            let expense = monthly.filter { $0.type == .expense }.reduce(Decimal.zero) { $0 + $1.amount }
            let income = monthly.filter { $0.type == .income }.reduce(Decimal.zero) { $0 + $1.amount }
            return (start, expense, income)
        }
    }

    private var topCategories: [(String, Decimal)] {
        Array(expenseByCategory.prefix(5))
    }

    var body: some View {
        ZStack {
            theme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Statistics")
                            .font(.custom("Avenir Next", size: 22).weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)

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
                                        x: .value("Month", row.0),
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
                                        x: .value("Month", row.0),
                                        y: .value("Income", (row.2 as NSDecimalNumber).doubleValue)
                                    )
                                    .foregroundStyle(theme.positive)
                                    BarMark(
                                        x: .value("Month", row.0),
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
}
