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

    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: TransactionType = .expense
    @State private var amountText: String = ""
    @State private var selectedAccount: Account? = nil
    @State private var selectedCategory: TransactionCategory? = nil
    @State private var selectedDate: Date = Date()
    @State private var note: String = ""

    @State private var showSelectAccount: Bool = false
    @State private var showSelectCategory: Bool = false

    private var isValid: Bool {
        guard let amt = Decimal(string: amountText), amt > 0 else { return false }
        return selectedAccount != nil && selectedCategory != nil
    }

    private var displayColor: Color { selectedType == .expense ? .red : .green }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

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
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .safeAreaInset(edge: .bottom) {
                saveBar
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
                            .foregroundStyle(selectedType == type ? .white : .white.opacity(0.4))

                        Rectangle()
                            .fill(selectedType == type ? (type == .expense ? .red : .green) : .clear)
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
                .foregroundStyle(.white.opacity(0.5))

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
                .foregroundStyle(.white.opacity(0.6))

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
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: "creditcard").foregroundStyle(.white.opacity(0.4))
                        Text("Select Account")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.14)))
            }
            .buttonStyle(.plain)
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Category")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))

            Button { showSelectCategory = true } label: {
                HStack {
                    if let cat = selectedCategory {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: cat.iconSystemName)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.blue)
                            )
                        Text(cat.rawValue)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: "square.grid.2x2").foregroundStyle(.white.opacity(0.4))
                        Text("Select Category")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.14)))
            }
            .buttonStyle(.plain)
        }
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Date & Time")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))

            DatePicker("", selection: $selectedDate, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .tint(.blue)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.14)))
                .colorScheme(.dark)
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Note (optional)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))

            TextField("e.g. Lunch", text: $note)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.14)))
                .foregroundStyle(.white)
        }
    }

    private var saveBar: some View {
        Button {
            guard let amt = Decimal(string: amountText),
                  let acct = selectedAccount,
                  let cat = selectedCategory else { return }

            vm.addTransaction(type: selectedType,
                              amount: amt,
                              accountId: acct.id,
                              category: cat,
                              date: selectedDate,
                              note: note.trimmingCharacters(in: .whitespacesAndNewlines))
            onDone()
            dismiss()
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
        .background(Color.black.opacity(0.92))
    }
}
