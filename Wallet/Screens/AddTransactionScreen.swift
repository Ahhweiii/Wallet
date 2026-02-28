//
//  AddTransactionScreen.swift
//  Wallet
//
//  Created by Lee Jun Wei on 23/2/26.
//

import SwiftUI

struct AddTransactionScreen: View {
    @ObservedObject var vm: DashboardViewModel
    let onDone: () -> Void
    @Environment(\.appTheme) private var theme
    @AppStorage("theme_is_dark") private var themeIsDark: Bool = true

    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: TransactionType = .expense
    @State private var amountText: String = ""
    @State private var selectedAccount: Account? = nil
    @State private var selectedCategory: CategoryItem? = nil
    @State private var selectedDate: Date = Date()
    @State private var note: String = ""

    @State private var showSelectAccount: Bool = false
    @State private var showSelectCategory: Bool = false
    @State private var showLimitAlert: Bool = false

    private var isValid: Bool {
        guard let amt = Decimal(string: amountText), amt > 0 else { return false }
        return selectedAccount != nil && selectedCategory != nil
    }

    private var displayColor: Color { selectedType == .expense ? theme.negative : theme.positive }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundGradient.ignoresSafeArea()

                VStack(spacing: 0) {
                    typeTabs.padding(.top, 10)

                    ScrollView {
                        VStack(spacing: 24) {
                            amountSection
                            accountSection
                            categorySection
                            dateSection
                            noteSection

                            // Space so content isn't hidden behind save bar
                            Color.clear.frame(height: 110)
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("New Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(themeIsDark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(theme.textPrimary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                saveBar
            }
            .alert("Limit Reached", isPresented: $showLimitAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Free tier allows \(SubscriptionManager.freeMonthlyTransactionLimit) transactions per month. Upgrade to Pro for unlimited transactions.")
            }
            .sheet(isPresented: $showSelectAccount) {
                SelectAccountScreen(accounts: vm.accounts) { selectedAccount = $0 }
            }
            .sheet(isPresented: $showSelectCategory) {
                SelectCategoryScreen(transactionType: selectedType) { selectedCategory = $0 }
            }
            .onChange(of: selectedType) { _, _ in selectedCategory = nil }
        }
    }

    private var typeTabs: some View {
        HStack(spacing: 0) {
            ForEach(TransactionType.allCases) { type in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedType = type }
                } label: {
                    VStack(spacing: 8) {
                        Text(type.rawValue)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(selectedType == type ? theme.textPrimary : theme.textTertiary)

                        Rectangle()
                            .fill(selectedType == type ? (type == .expense ? theme.negative : theme.positive) : .clear)
                            .frame(height: 3)
                            .cornerRadius(2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    private var amountSection: some View {
        VStack(spacing: 12) {
            Text(selectedType == .expense ? "How much did you spend?" : "How much did you receive?")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            HStack(spacing: 6) {
                Text(selectedType == .expense ? "−" : "+")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(displayColor)

                Text("S$")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(displayColor.opacity(0.7))

                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(displayColor)
            }
            .padding(.vertical, 10)
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Account")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            Button { showSelectAccount = true } label: {
                HStack {
                    if let acct = selectedAccount {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: acct.colorHex).opacity(0.95))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: acct.iconSystemName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                            )
                        Text(acct.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                    } else {
                        Image(systemName: "creditcard").foregroundStyle(theme.textTertiary)
                        Text("Select Account")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
            }
            .buttonStyle(.plain)
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Category")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            Button { showSelectCategory = true } label: {
                HStack {
                    if let cat = selectedCategory {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: cat.icon)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.blue)
                            )
                        Text(cat.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                    } else {
                        Image(systemName: "square.grid.2x2").foregroundStyle(theme.textTertiary)
                        Text("Select Category")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
            }
            .buttonStyle(.plain)
        }
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Date & Time")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            DatePicker("", selection: $selectedDate, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .tint(theme.accent)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
                .colorScheme(themeIsDark ? .dark : .light)
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Note (optional)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            TextField("e.g. Lunch", text: $note)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
                .foregroundStyle(theme.textPrimary)
        }
    }

    private var saveBar: some View {
        Button {
            guard let amt = Decimal(string: amountText),
                  let acct = selectedAccount,
                  let cat = selectedCategory else { return }

            let added = vm.addTransaction(type: selectedType,
                                          amount: amt,
                                          accountId: acct.id,
                                          categoryName: cat.name,
                                          date: selectedDate,
                                          note: note.trimmingCharacters(in: .whitespacesAndNewlines))
            if added {
                onDone()
                dismiss()
            } else {
                showLimitAlert = true
            }
        } label: {
            Text("Save Transaction")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isValid ? displayColor : displayColor.opacity(0.3))
                )
        }
        .disabled(!isValid)
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(theme.surface)
    }
}
