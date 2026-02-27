//
//  MonthlySpendingCardView.swift
//  Wallet
//

import SwiftUI

struct MonthlySpendingCardView: View {
    @ObservedObject var vm: DashboardViewModel
    @State private var monthOffset: Int = 0
    @State private var showBreakdown: Bool = false

    let minOffset: Int = -2

    private var canGoBack: Bool { monthOffset > minOffset }
    private var canGoForward: Bool { monthOffset < 0 }

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
                        .foregroundStyle(canGoBack ? .white : .white.opacity(0.2))
                }
                .disabled(!canGoBack)
                .buttonStyle(.plain)

                Spacer()

                VStack(spacing: 2) {
                    Text(periodTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Each account uses its own billing cycle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if canGoForward { monthOffset += 1 }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(canGoForward ? .white : .white.opacity(0.2))
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
                            .foregroundStyle(.red)
                        Text("Spent")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Text(CurrencyFormatter.sgd(amount: vm.totalPeriodExpenses(monthOffset: monthOffset)))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                // Divider
                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 1, height: 36)

                // Income
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                        Text("Income")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Text(CurrencyFormatter.sgd(amount: vm.totalPeriodIncome(monthOffset: monthOffset)))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.green)
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
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                        Image(systemName: showBreakdown ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.45))
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
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .lineLimit(1)

                                Text(periodLabel)
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundStyle(.white.opacity(0.35))
                            }

                            Spacer()

                            // Spent / Income
                            VStack(alignment: .trailing, spacing: 2) {
                                if spent > 0 {
                                    Text("−\(CurrencyFormatter.sgd(amount: spent))")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.red)
                                        .lineLimit(1)
                                }

                                if income > 0 {
                                    Text("+\(CurrencyFormatter.sgd(amount: income))")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.green)
                                        .lineLimit(1)
                                }

                                if spent == 0 && income == 0 {
                                    Text("No activity")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.25))
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(white: 0.18))
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(white: 0.14).opacity(0.95))
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
