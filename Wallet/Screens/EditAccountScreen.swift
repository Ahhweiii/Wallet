//
//  EditAccountScreen.swift
//  FrugalPilot
//
//  Created by Lee Jun Wei on 23/2/26.
//

import SwiftUI

struct EditAccountScreen: View {
    @ObservedObject var vm: DashboardViewModel
    let account: Account
    @Environment(\.appTheme) private var theme
    @AppStorage("theme_is_dark") private var themeIsDark: Bool = true

    let onSave: (_ bankName: String,
                 _ accountName: String,
                 _ amount: Decimal,
                 _ type: AccountType,
                 _ currentCredit: Decimal,
                 _ isInCombinedCreditPool: Bool,
                 _ billingCycleStartDay: Int,
                 _ colorHex: String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var bankName: String
    @State private var accountName: String
    @State private var balanceText: String
    @State private var creditText: String
    @State private var selectedType: AccountType
    @State private var shareBankCreditLimit: Bool
    @State private var billingCycleStartDay: Int
    @State private var selectedColorHex: String

    private let colorOptions: [String] = [
        "#0A84FF", "#30D158", "#FF9F0A", "#FF375F",
        "#BF5AF2", "#64D2FF", "#FFD60A", "#FF453A"
    ]

    init(vm: DashboardViewModel,
         account: Account,
         onSave: @escaping (_ bankName: String,
                            _ accountName: String,
                            _ amount: Decimal,
                            _ type: AccountType,
                            _ currentCredit: Decimal,
                            _ isInCombinedCreditPool: Bool,
                            _ billingCycleStartDay: Int,
                            _ colorHex: String) -> Void) {
        self.vm = vm
        self.account = account
        self.onSave = onSave

        _bankName = State(initialValue: account.bankName)
        _accountName = State(initialValue: account.accountName)
        _balanceText = State(initialValue: "\(account.amount)")
        _creditText = State(initialValue: "\(account.currentCredit)")
        _selectedType = State(initialValue: account.type)
        _shareBankCreditLimit = State(initialValue: account.type == .credit ? account.isInCombinedCreditPool : false)
        _billingCycleStartDay = State(initialValue: account.billingCycleStartDay)
        _selectedColorHex = State(initialValue: account.colorHex)
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
                theme.backgroundGradient.ignoresSafeArea()

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

                        colorSection

                        if selectedType == .credit {
                            billingCycleSection
                        }

                        Color.clear.frame(height: 110)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(themeIsDark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(theme.textPrimary)
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

    // MARK: - Billing Cycle Section

    private var billingCycleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Billing Cycle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            Text("The day of the month when spending resets for this account.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(theme.textTertiary)

            HStack {
                Text("Reset Day")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)

                Spacer()

                Picker("Day", selection: $billingCycleStartDay) {
                    ForEach(1...31, id: \.self) { day in
                        Text("\(day)").tag(day)
                    }
                }
                .pickerStyle(.menu)
                .tint(theme.textPrimary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.surfaceAlt)
            )

            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .foregroundStyle(theme.textTertiary)
                    .font(.system(size: 11))
                Text("Current period: \(billingPeriodPreview)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(.leading, 4)
        }
    }

    // MARK: - Existing Sections

    private var availableOrBalanceSection: some View {
        Group {
            if selectedType == .credit, shouldLockAvailableCredit, let shared = bankSharedAvailable {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Total Available Credit (SGD)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)

                    HStack {
                        Text("Locked (Bank)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(theme.textSecondary)
                        Spacer()
                        Text(CurrencyFormatter.sgd(amount: shared))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
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
                .tint(theme.accent)
                .foregroundStyle(theme.textPrimary)

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
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    private var totalCreditSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Total Credit (SGD)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            if selectedType == .credit, shareBankCreditLimit, let shared = bankSharedCredit {
                HStack {
                    Text("Locked (Bank)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.textSecondary)
                    Spacer()
                    Text(CurrencyFormatter.sgd(amount: shared))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.textSecondary)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
            } else {
                TextField("e.g. 12000.00", text: $creditText)
                    .keyboardType(.decimalPad)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
                    .foregroundStyle(theme.textPrimary)
            }
        }
    }

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Type")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            HStack(spacing: 14) {
                ForEach(AccountType.allCases) { type in
                    Button { selectedType = type } label: {
                        HStack(spacing: 8) {
                            Image(systemName: type == .cash ? "banknote" : "creditcard.fill")
                            Text(type.rawValue)
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(selectedType == type ? theme.textPrimary : theme.textTertiary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedType == type ? theme.accent : theme.surfaceAlt)
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

            let amt: Decimal = {
                if selectedType == .cash {
                    return Decimal(string: balanceText) ?? account.amount
                }
                if shareBankCreditLimit, let shared = bankSharedAvailable {
                    return shared
                }
                return Decimal(string: balanceText) ?? account.amount
            }()

            let credit: Decimal = {
                if selectedType != .credit { return Decimal(string: creditText) ?? account.currentCredit }
                if shareBankCreditLimit, let shared = bankSharedCredit {
                    return shared
                }
                return Decimal(string: creditText) ?? account.currentCredit
            }()

            let billingDay = (selectedType == .credit) ? billingCycleStartDay : 1
            onSave(b, a, amt, selectedType, credit, shareBankCreditLimit, billingDay, selectedColorHex)
            dismiss()
        } label: {
            Text("Save Changes")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isValid ? theme.accent : theme.accent.opacity(0.3))
                )
        }
        .disabled(!isValid)
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(theme.surface)
    }

    // MARK: - Helpers

    private func field(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            TextField(placeholder, text: text)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
                .foregroundStyle(theme.textPrimary)
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Icon Color")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            HStack(spacing: 12) {
                ForEach(colorOptions, id: \.self) { hex in
                    Button {
                        selectedColorHex = hex
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle()
                                    .stroke(selectedColorHex == hex ? theme.textPrimary : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
