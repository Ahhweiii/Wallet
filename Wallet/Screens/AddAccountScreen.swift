//
//  AddAccountScreen.swift
//  Wallet
//
//  Created by Lee Jun Wei on 22/2/26.
//

import SwiftUI

struct AddAccountScreen: View {
    @ObservedObject var vm: DashboardViewModel

    let onSave: (_ bankName: String,
                 _ accountName: String,
                 _ amount: Decimal,
                 _ type: AccountType,
                 _ currentCredit: Decimal,
                 _ isInCombinedCreditPool: Bool,
                 _ billingCycleStartDay: Int) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var bankName: String = ""
    @State private var accountName: String = ""
    @State private var balanceText: String = ""
    @State private var creditText: String = ""
    @State private var selectedType: AccountType = .cash
    @State private var shareBankCreditLimit: Bool = false
    @State private var billingCycleStartDay: Int = 1

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
        let balanceOk: Bool = {
            if selectedType == .cash { return Decimal(string: balanceText) != nil }
            if shouldLockAvailableCredit { return true }
            return Decimal(string: balanceText) != nil
        }()

        let creditOk: Bool = {
            if selectedType == .cash { return true }
            if shouldLockTotalCredit { return true }
            return Decimal(string: creditText) != nil
        }()

        return bankOk && accountOk && balanceOk && creditOk
    }

    /// Preview of the billing period based on the selected day
    private var billingPeriodPreview: String {
        let cal = Calendar.current
        let now = Date()
        let todayDay = cal.component(.day, from: now)

        var startComps = cal.dateComponents([.year, .month], from: now)
        if todayDay < billingCycleStartDay {
            if let shifted = cal.date(byAdding: .month, value: -1, to: now) {
                startComps = cal.dateComponents([.year, .month], from: shifted)
            }
        }

        let daysInMonth = cal.range(of: .day, in: .month,
            for: cal.date(from: startComps) ?? now)?.count ?? 28
        startComps.day = min(billingCycleStartDay, daysInMonth)
        startComps.hour = 0
        startComps.minute = 0
        startComps.second = 0

        guard let start = cal.date(from: startComps),
              let nextStart = cal.date(byAdding: .month, value: 1, to: start) else {
            return "—"
        }

        let end = nextStart.addingTimeInterval(-1)

        let df = DateFormatter()
        df.dateFormat = "d MMM"
        let dfEnd = DateFormatter()
        dfEnd.dateFormat = "d MMM yyyy"

        return "\(df.string(from: start)) – \(dfEnd.string(from: end))"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        field(title: "Bank", placeholder: "e.g. DBS", text: $bankName)
                            .textInputAutocapitalization(.words)

                        field(title: "Account", placeholder: "e.g. Altitude", text: $accountName)
                            .textInputAutocapitalization(.words)

                        availableOrBalanceSection

                        if selectedType == .credit {
                            totalCreditSection
                            pooledSection
                        }

                        typeSection

                        billingCycleSection

                        Color.clear.frame(height: 110)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Add Account")
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
                if newType == .cash {
                    creditText = ""
                    shareBankCreditLimit = false
                }
            }
        }
    }

    // MARK: - Billing Cycle Section

    private var billingCycleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Billing Cycle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))

            Text("The day of the month when spending resets for this account.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.white.opacity(0.4))

            HStack {
                Text("Reset Day")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Picker("Day", selection: $billingCycleStartDay) {
                    ForEach(1...31, id: \.self) { day in
                        Text("\(day)").tag(day)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(white: 0.14))
            )

            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .foregroundStyle(.white.opacity(0.4))
                    .font(.system(size: 11))
                Text("Current period: \(billingPeriodPreview)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.leading, 4)
        }
    }

    // MARK: - Existing Sections (unchanged logic, just reformatted)

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
                field(
                    title: selectedType == .credit ? "Total Available Credit (SGD)" : "Current Balance (SGD)",
                    placeholder: "e.g. 5000.00",
                    text: $balanceText
                )
                .keyboardType(.decimalPad)
            }
        }
    }

    private var totalCreditSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Total Credit (SGD)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))

            if shouldLockTotalCredit, let shared = bankSharedCredit {
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

    // MARK: - Save Bar

    private var saveBar: some View {
        Button {
            let b = normalizedBankName
            let a = accountName.trimmingCharacters(in: .whitespacesAndNewlines)

            let pooled = (selectedType == .credit) ? shareBankCreditLimit : false

            let availableOrBalance: Decimal = {
                if selectedType == .cash {
                    return Decimal(string: balanceText) ?? 0
                }
                if pooled, let shared = bankSharedAvailable { return shared }
                return Decimal(string: balanceText) ?? 0
            }()

            let credit: Decimal = {
                guard selectedType == .credit else { return 0 }
                if pooled, let shared = bankSharedCredit { return shared }
                return Decimal(string: creditText) ?? 0
            }()

            onSave(b, a, availableOrBalance, selectedType, credit, pooled, billingCycleStartDay)
            dismiss()
        } label: {
            Text("Add Account")
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

    // MARK: - Helpers

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
