//
//  AddTransactionScreen.swift
//  FrugalPilot
//
//  Created by Lee Jun Wei on 23/2/26.
//

import SwiftUI

struct AddTransactionScreen: View {
    @ObservedObject var vm: DashboardViewModel
    let fixedAccountId: UUID?
    let onDone: () -> Void
    @Environment(\.appTheme) private var theme
    @AppStorage("theme_is_dark") private var themeIsDark: Bool = true
    @AppStorage("tracking_current_profile") private var currentProfileRaw: String = "Personal"

    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: TransactionType = .expense
    @State private var amountText: String = ""
    @State private var selectedAccount: Account? = nil
    @State private var selectedCategory: CategoryItem? = nil
    @State private var selectedDate: Date = Date()
    @State private var note: String = ""

    @State private var showSelectAccount: Bool = false
    @State private var showSelectTargetAccount: Bool = false
    @State private var showSelectCategory: Bool = false
    @State private var showLimitAlert: Bool = false
    @State private var showInsufficientCashAlert: Bool = false
    @State private var isCreditCardPayment: Bool = false
    @State private var selectedTargetAccount: Account? = nil
    @State private var hasAppliedAutoCategorySuggestion: Bool = false
    @State private var showDuplicateConfirm: Bool = false
    @State private var isRecurringIncome: Bool = false
    @State private var recurringIncomeName: String = ""
    @State private var recurringIncomeFrequency: FixedPaymentFrequency = .monthly
    @State private var recurringIncomeChargeDay: Int = max(1, min(31, Calendar.current.component(.day, from: Date())))

    init(vm: DashboardViewModel,
         fixedAccountId: UUID? = nil,
         onDone: @escaping () -> Void) {
        self.vm = vm
        self.fixedAccountId = fixedAccountId
        self.onDone = onDone
    }

    private var availableTargetAccounts: [Account] {
        guard let source = selectedAccount else { return [] }
        return vm.accounts.filter { account in
            guard account.id != source.id else { return false }
            if selectedType == .transfer {
                return true
            }
            return account.type == .credit
        }
    }

    private var isValid: Bool {
        guard let amt = Decimal(string: amountText), amt > 0 else { return false }
        guard selectedAccount != nil else { return false }

        if selectedType == .transfer {
            return selectedTargetAccount != nil
        }
        if selectedType == .income, isRecurringIncome {
            return !recurringIncomeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if isCreditCardPayment {
            return selectedTargetAccount?.type == .credit
        }
        return selectedCategory != nil
    }

    private var isAccountLocked: Bool {
        fixedAccountId != nil
    }

    private var displayColor: Color {
        switch selectedType {
        case .expense: return theme.negative
        case .income: return theme.positive
        case .transfer: return theme.accent
        }
    }

    private var currentProfileName: String {
        let trimmed = currentProfileRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Personal" : trimmed
    }

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
                            if selectedType == .expense { creditPaymentSection }
                            if isCreditCardPayment || selectedType == .transfer {
                                targetAccountSection
                            }
                            categorySection
                            dateSection
                            noteSection
                            if selectedType == .income { recurringIncomeSection }

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
            .sheet(isPresented: $showSelectTargetAccount) {
                SelectAccountScreen(accounts: availableTargetAccounts) { selectedTargetAccount = $0 }
            }
            .sheet(isPresented: $showSelectCategory) {
                SelectCategoryScreen(transactionType: selectedType) { selectedCategory = $0 }
            }
            .onChange(of: selectedType) { _, newType in
                selectedCategory = nil
                hasAppliedAutoCategorySuggestion = false
                if newType != .expense {
                    isCreditCardPayment = false
                }
                if newType != .income {
                    isRecurringIncome = false
                    recurringIncomeName = ""
                    recurringIncomeFrequency = .monthly
                }
                if newType != .transfer {
                    selectedTargetAccount = nil
                }
            }
            .onChange(of: selectedAccount) { _, acct in
                if acct?.type != .cash {
                    isCreditCardPayment = false
                }
                if selectedTargetAccount?.id == acct?.id {
                    selectedTargetAccount = nil
                }
            }
            .onChange(of: note) { _, newNote in
                guard selectedType != .transfer else { return }
                guard hasAppliedAutoCategorySuggestion == false || selectedCategory == nil else { return }
                guard let suggested = vm.suggestedCategory(type: selectedType,
                                                           note: newNote,
                                                           currentProfile: currentProfileName) else { return }
                selectedCategory = CategoryItem(id: suggested,
                                                name: suggested,
                                                icon: TransactionCategory.iconSystemName(for: suggested))
                hasAppliedAutoCategorySuggestion = true
            }
            .onAppear {
                guard let fixedAccountId else { return }
                selectedAccount = vm.accounts.first(where: { $0.id == fixedAccountId })
            }
            .onChange(of: vm.accounts.count) { _, _ in
                guard let fixedAccountId else { return }
                selectedAccount = vm.accounts.first(where: { $0.id == fixedAccountId })
            }
            .alert("Insufficient Cash", isPresented: $showInsufficientCashAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("The selected cash account does not have enough balance for this payment.")
            }
            .alert("Possible Duplicate", isPresented: $showDuplicateConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Save Anyway") {
                    persistTransaction(skipDuplicateCheck: true)
                }
            } message: {
                Text("A similar transaction exists within the last 2 days. Save anyway?")
            }
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
                            .fill(selectedType == type ? tabColor(for: type) : .clear)
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
            Text(amountPrompt)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            HStack(spacing: 6) {
                Text(amountSign)
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

            Button {
                if !isAccountLocked {
                    showSelectAccount = true
                }
            } label: {
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
                    if !isAccountLocked {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
            }
            .buttonStyle(.plain)
            .disabled(isAccountLocked)
        }
    }

    private var categorySection: some View {
        if isCreditCardPayment || selectedType == .transfer {
            return AnyView(EmptyView())
        }

        return AnyView(
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
        )
    }

    private var creditPaymentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Payment to Credit Card", isOn: Binding(
                get: { isCreditCardPayment },
                set: { enabled in
                    if enabled, selectedAccount?.type != .cash {
                        isCreditCardPayment = false
                        return
                    }
                    isCreditCardPayment = enabled
                    if !enabled { selectedTargetAccount = nil }
                }
            ))
            .tint(theme.accent)
            .foregroundStyle(theme.textPrimary)

            if selectedAccount?.type != .cash {
                Text("Select a cash account first to enable credit card payment.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
    }

    private var targetAccountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(selectedType == .transfer ? "Transfer To" : "Pay To")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            Button { showSelectTargetAccount = true } label: {
                HStack {
                    if let acct = selectedTargetAccount {
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
                        Text(selectedType == .transfer ? "Select Destination Account" : "Select Credit Card")
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
            HStack {
                Text("Note (optional)")
                Spacer()
                Button("Smart Parse") {
                    let parsed = vm.parseTransactionHints(from: note)
                    if amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       let amount = parsed.amount {
                        amountText = NSDecimalNumber(decimal: amount).stringValue
                    }
                    if let date = parsed.date {
                        selectedDate = date
                    }
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(theme.accent)
            }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            TextField("e.g. Lunch", text: $note)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
                .foregroundStyle(theme.textPrimary)
        }
    }

    private var recurringIncomeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Make this recurring income", isOn: $isRecurringIncome)
                .tint(theme.accent)
                .foregroundStyle(theme.textPrimary)

            if isRecurringIncome {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Plan Name")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                    TextField("e.g. Salary, Allowance, Rental", text: $recurringIncomeName)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(theme.card))
                        .foregroundStyle(theme.textPrimary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Frequency")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                    Picker("Frequency", selection: $recurringIncomeFrequency) {
                        Text("Monthly").tag(FixedPaymentFrequency.monthly)
                        Text("Yearly").tag(FixedPaymentFrequency.yearly)
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Charge Day")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                    Picker("Charge Day", selection: $recurringIncomeChargeDay) {
                        ForEach(1...31, id: \.self) { day in
                            Text("\(day)").tag(day)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(theme.card))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
    }

    private var saveBar: some View {
        Button {
            persistTransaction(skipDuplicateCheck: false)
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

    private func persistTransaction(skipDuplicateCheck: Bool) {
        guard let amt = Decimal(string: amountText) else { return }
        let acct: Account
        if let fixedAccountId {
            guard let fixedAccount = vm.accounts.first(where: { $0.id == fixedAccountId }) else { return }
            acct = fixedAccount
        } else {
            guard let selectedAccount else { return }
            acct = selectedAccount
        }

        if !skipDuplicateCheck && selectedType != .transfer {
            let exists = vm.hasPotentialDuplicate(type: selectedType,
                                                  amount: amt,
                                                  accountId: acct.id,
                                                  date: selectedDate)
            if exists {
                showDuplicateConfirm = true
                return
            }
        }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let added: Bool

        if selectedType == .transfer {
            guard let target = selectedTargetAccount else { return }
            if acct.type == .cash, acct.amount < amt {
                showInsufficientCashAlert = true
                return
            }
            added = vm.transferBetweenAccounts(fromAccountId: acct.id,
                                               toAccountId: target.id,
                                               amount: amt,
                                               date: selectedDate,
                                               note: trimmedNote)
        } else if isCreditCardPayment {
            guard let target = selectedTargetAccount else { return }
            if acct.amount < amt {
                showInsufficientCashAlert = true
                return
            }
            added = vm.payCreditCard(fromCashAccountId: acct.id,
                                     toCreditAccountId: target.id,
                                     amount: amt,
                                     date: selectedDate,
                                     note: trimmedNote)
        } else {
            guard let cat = selectedCategory else { return }
            added = vm.addTransaction(type: selectedType,
                                      amount: amt,
                                      accountId: acct.id,
                                      categoryName: cat.name,
                                      date: selectedDate,
                                      note: trimmedNote)
        }
        if added {
            if selectedType == .income && isRecurringIncome {
                vm.addRecurringIncomePlan(name: recurringIncomeName,
                                          amount: amt,
                                          frequency: recurringIncomeFrequency,
                                          chargeDay: recurringIncomeChargeDay,
                                          accountId: acct.id,
                                          startDate: selectedDate,
                                          note: trimmedNote,
                                          profileName: currentProfileName)
            }
            onDone()
            dismiss()
        } else {
            showLimitAlert = true
        }
    }

    private var amountPrompt: String {
        switch selectedType {
        case .expense: return "How much did you spend?"
        case .income: return "How much did you receive?"
        case .transfer: return "How much do you want to transfer?"
        }
    }

    private var amountSign: String {
        switch selectedType {
        case .expense: return "−"
        case .income: return "+"
        case .transfer: return "⇄"
        }
    }

    private func tabColor(for type: TransactionType) -> Color {
        switch type {
        case .expense: return theme.negative
        case .income: return theme.positive
        case .transfer: return theme.accent
        }
    }
}
