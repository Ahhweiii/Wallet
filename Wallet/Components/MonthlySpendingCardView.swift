//
//  MonthlySpendingCardView.swift
//  LedgerFlow
//

import SwiftUI

struct MonthlySpendingCardView: View {
    @ObservedObject var vm: DashboardViewModel
    @Environment(\.appTheme) private var theme
    @State private var monthOffset: Int = 0
    @Binding var showBreakdown: Bool

    init(vm: DashboardViewModel, showBreakdown: Binding<Bool>) {
        self.vm = vm
        self._showBreakdown = showBreakdown
    }

    let minOffset: Int = -2

    private var canGoBack: Bool { monthOffset > minOffset }
    private var canGoForward: Bool { monthOffset < 0 }
    private var hasCreditAccounts: Bool { vm.accounts.contains { $0.type == .credit } }

    var body: some View {
        VStack(spacing: 12) {
            // MARK: - Header with navigation arrows
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if canGoBack { monthOffset -= 1 }
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(canGoBack ? theme.textPrimary : theme.textTertiary)
                }
                .disabled(!canGoBack)
                .buttonStyle(.plain)

                Spacer()

                VStack(spacing: 2) {
                    Text(periodTitle)
                        .font(.custom("Avenir Next", size: 14).weight(.bold))
                        .foregroundStyle(theme.textPrimary)

                    if hasCreditAccounts {
                        Text("Credit uses billing cycle")
                            .font(.custom("Avenir Next", size: 10).weight(.semibold))
                            .foregroundStyle(theme.textTertiary)
                    }
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if canGoForward { monthOffset += 1 }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(canGoForward ? theme.textPrimary : theme.textTertiary)
                }
                .disabled(!canGoForward)
                .buttonStyle(.plain)
            }

            // MARK: - Totals (Spent & Income)
            HStack(spacing: 24) {
                // Expenses
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.negative)
                        Text("Spent")
                            .font(.custom("Avenir Next", size: 11).weight(.semibold))
                            .foregroundStyle(theme.textSecondary)
                    }

                    Text(CurrencyFormatter.sgd(amount: vm.totalPeriodExpenses(monthOffset: monthOffset)))
                        .font(.custom("Avenir Next", size: 20).weight(.bold))
                        .foregroundStyle(theme.negative)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                // Divider
                Rectangle()
                    .fill(theme.divider)
                    .frame(width: 1, height: 36)

                // Income
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.positive)
                        Text("Income")
                            .font(.custom("Avenir Next", size: 11).weight(.semibold))
                            .foregroundStyle(theme.textSecondary)
                    }

                    Text(CurrencyFormatter.sgd(amount: vm.totalPeriodIncome(monthOffset: monthOffset)))
                        .font(.custom("Avenir Next", size: 20).weight(.bold))
                        .foregroundStyle(theme.positive)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity)

            // MARK: - Per-Account Breakdown Toggle
            if !vm.accounts.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showBreakdown.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(showBreakdown ? "Hide Breakdown" : "Show Breakdown")
                            .font(.custom("Avenir Next", size: 11).weight(.semibold))
                            .foregroundStyle(theme.textSecondary)
                        Image(systemName: showBreakdown ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }

            // MARK: - Per-Account Breakdown List
            if showBreakdown {
                VStack(spacing: 8) {
                    ForEach(vm.accounts) { account in
                        let spent = vm.periodExpenses(for: account.id, monthOffset: monthOffset)
                        let income = vm.periodIncome(for: account.id, monthOffset: monthOffset)
                        let periodLabel = vm.billingPeriodLabel(for: account, monthOffset: monthOffset)

                        HStack(spacing: 10) {
                            // Color dot
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(hex: account.colorHex).opacity(0.95))
                                .frame(width: 10, height: 10)

                            // Account name + period
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.displayName)
                                    .font(.custom("Avenir Next", size: 12).weight(.semibold))
                                    .foregroundStyle(theme.textPrimary)
                                    .lineLimit(1)

                                if account.type == .credit {
                                    Text(periodLabel)
                                        .font(.custom("Avenir Next", size: 10))
                                        .foregroundStyle(theme.textTertiary)
                                }
                            }

                            Spacer()

                            // Spent / Income
                            VStack(alignment: .trailing, spacing: 2) {
                                if spent > 0 {
                                    Text("−\(CurrencyFormatter.sgd(amount: spent))")
                                        .font(.custom("Avenir Next", size: 12).weight(.bold))
                                        .foregroundStyle(theme.negative)
                                        .lineLimit(1)
                                }

                                if income > 0 {
                                    Text("+\(CurrencyFormatter.sgd(amount: income))")
                                        .font(.custom("Avenir Next", size: 12).weight(.bold))
                                        .foregroundStyle(theme.positive)
                                        .lineLimit(1)
                                }

                                if spent == 0 && income == 0 {
                                    Text("No activity")
                                        .font(.custom("Avenir Next", size: 11).weight(.semibold))
                                        .foregroundStyle(theme.textTertiary)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(theme.surfaceAlt)
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.surface)
                .shadow(color: theme.shadow, radius: 10, x: 0, y: 6)
        )
    }

    // MARK: - Helpers

    private var periodTitle: String {
        switch monthOffset {
        case 0:  return "This Period"
        case -1: return "Last Period"
        default: return "\(abs(monthOffset)) Periods Ago"
        }
    }
}
