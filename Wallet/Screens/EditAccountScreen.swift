//
//  EditAccountScreen.swift
//  Wallet
//
//  Created by Lee Jun Wei on 23/2/26.
//

import SwiftUI

struct EditAccountScreen: View {
    @ObservedObject var vm: DashboardViewModel
    let account: Account

    let onSave: (_ bankName: String,
                 _ accountName: String,
                 _ amount: Decimal,
                 _ type: AccountType,
                 _ currentCredit: Decimal,
                 _ isInCombinedCreditPool: Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var bankName: String
    @State private var accountName: String
    @State private var balanceText: String
    @State private var creditText: String
    @State private var selectedType: AccountType
    @State private var shareBankCreditLimit: Bool

    init(vm: DashboardViewModel,
         account: Account,
         onSave: @escaping (_ bankName: String, _ accountName: String, _ amount: Decimal, _ type: AccountType, _ currentCredit: Decimal, _ isInCombinedCreditPool: Bool) -> Void) {
        self.vm = vm
        self.account = account
        self.onSave = onSave

        _bankName = State(initialValue: account.bankName)
        _accountName = State(initialValue: account.accountName)
        _balanceText = State(initialValue: "\(account.amount)")
        _creditText = State(initialValue: "\(account.currentCredit)")
        _selectedType = State(initialValue: account.type)
        _shareBankCreditLimit = State(initialValue: account.type == .credit ? account.isInCombinedCreditPool : false)
    }

    private var normalizedBankName: String {
        bankName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var bankSharedCredit: Decimal? {
        vm.bankTotalCredit(forBank: normalizedBankName)
    }

    private var bankSharedAvailable: Decimal? {
        vm.bankInitialAvailableCredit(forBank: normalizedBankName)
    }

    private var shouldLockTotalCredit: Bool {
        selectedType == .credit && shareBankCreditLimit && bankSharedCredit != nil
    }

    private var shouldLockAvailableCredit: Bool {
        selectedType == .credit && shareBankCreditLimit && bankSharedAvailable != nil
    }

    private var isValid: Bool {
        let bankOk = !normalizedBankName.isEmpty
        let accountOk = !accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let availableOk: Bool = {
            if selectedType == .cash { return Decimal(string: balanceText) != nil }
            if shouldLockAvailableCredit { return true }
            return Decimal(string: balanceText) != nil
        }()

        let creditOk: Bool = {
            if selectedType == .cash { return true }
            if shouldLockTotalCredit { return true }
            return Decimal(string: creditText) != nil
        }()

        return bankOk && accountOk && availableOk && creditOk
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        field(title: "Bank", placeholder: "e.g. DBS", text: $bankName)
                        field(title: "Account", placeholder: "e.g. Altitude", text: $accountName)

                        availableOrBalanceSection

                        totalCreditSection

                        typeSection

                        if selectedType == .credit {
                            pooledSection
                        }

                        Color.clear.frame(height: 110)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .safeAreaInset(edge: .bottom) { saveBar }
            .onChange(of: selectedType) { _, newType in
                if newType != .credit {
                    shareBankCreditLimit = false
                }
            }
        }
    }

    private var availableOrBalanceSection: some View {
        Group {
            if selectedType == .credit, shouldLockAvailableCredit, let shared = bankSharedAvailable {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Total Available Credit (SGD)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))

                    HStack {
                        Text("Locked (Bank)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.75))
                        Spacer()
                        Text(CurrencyFormatter.sgd(amount: shared))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.14)))
                }
            } else {
                field(title: selectedType == .credit ? "Total Available Credit (SGD)" : "Current Balance (SGD)",
                      placeholder: "e.g. 5000.00",
                      text: $balanceText)
                .keyboardType(.decimalPad)
            }
        }
    }

    private var pooledSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Share credit limit with other cards (same bank)", isOn: $shareBankCreditLimit)
                .tint(.blue)
                .foregroundStyle(.white)

            if shareBankCreditLimit {
                let text: String = {
                    let pieces: [String] = [
                        bankSharedCredit != nil ? "Credit limit locked" : "Set credit limit once",
                        bankSharedAvailable != nil ? "Available locked" : "Set available once"
                    ]
                    return pieces.joined(separator: " • ")
                }()
                Text(text)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }

    private var totalCreditSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Total Credit (SGD)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))

            if selectedType == .credit, shareBankCreditLimit, let shared = bankSharedCredit {
                HStack {
                    Text("Locked (Bank)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    Text(CurrencyFormatter.sgd(amount: shared))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.14)))
            } else {
                TextField("e.g. 12000.00", text: $creditText)
                    .keyboardType(.decimalPad)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.14)))
                    .foregroundStyle(.white)
            }
        }
    }

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Type")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))

            HStack(spacing: 14) {
                ForEach(AccountType.allCases) { type in
                    Button { selectedType = type } label: {
                        HStack(spacing: 8) {
                            Image(systemName: type == .cash ? "banknote" : "creditcard.fill")
                            Text(type.rawValue)
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(selectedType == type ? .white : .white.opacity(0.4))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedType == type ? Color.blue : Color(white: 0.14))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var saveBar: some View {
        Button {
            let b = normalizedBankName
            let a = accountName.trimmingCharacters(in: .whitespacesAndNewlines)

            let amt: Decimal = {
                if selectedType == .cash {
                    return Decimal(string: balanceText) ?? account.amount
                }
                if shareBankCreditLimit, let shared = bankSharedAvailable {
                    return shared // lock to bank
                }
                return Decimal(string: balanceText) ?? account.amount
            }()

            let credit: Decimal = {
                if selectedType != .credit { return Decimal(string: creditText) ?? account.currentCredit }
                if shareBankCreditLimit, let shared = bankSharedCredit {
                    return shared // lock to bank
                }
                return Decimal(string: creditText) ?? account.currentCredit
            }()

            onSave(b, a, amt, selectedType, credit, shareBankCreditLimit)
            dismiss()
        } label: {
            Text("Save Changes")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isValid ? Color.blue : Color.blue.opacity(0.3))
                )
        }
        .disabled(!isValid)
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(Color.black.opacity(0.92))
    }

    private func field(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))

            TextField(placeholder, text: text)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.14)))
                .foregroundStyle(.white)
        }
    }
}
