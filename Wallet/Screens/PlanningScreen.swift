//
//  PlanningScreen.swift
//  Wallet
//
//  Created by Codex on 27/2/26.
//

import SwiftUI
import SwiftData

private enum InsurancePaymentMode: String, CaseIterable, Identifiable, Hashable {
    case annual = "Annual"
    case monthly = "Monthly"
    var id: String { rawValue }
}

struct PlanningScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme
    @AppStorage("tracking_current_profile") private var currentProfileRaw: String = "Personal"

    @Query(sort: [SortDescriptor(\FixedPayment.startDate, order: .reverse)])
    private var allFixedPayments: [FixedPayment]

    @Query(sort: [SortDescriptor(\Account.bankName), SortDescriptor(\Account.accountName)])
    private var allAccounts: [Account]

    @State private var showAdd: Bool = false
    @State private var editingFixedPayment: FixedPayment? = nil
    @State private var sortOption: FixedPlanningSortOption = .lastPaymentDateAscending

    private enum FixedPlanningSortOption: String, CaseIterable, Identifiable {
        case planName = "Plan Name"
        case chargeAccount = "Account to Charge"
        case lastPaymentDateAscending = "Last Payment Date (Ascending)"
        var id: String { rawValue }
    }

    private var currentProfileName: String {
        let trimmed = currentProfileRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Personal" : trimmed
    }

    private var accounts: [Account] {
        allAccounts.filter {
            let profile = $0.profileName.trimmingCharacters(in: .whitespacesAndNewlines)
            return (profile.isEmpty ? "Personal" : profile) == currentProfileName
        }
    }

    private var fixedPayments: [FixedPayment] {
        allFixedPayments.filter {
            let profile = $0.profileName.trimmingCharacters(in: .whitespacesAndNewlines)
            return (profile.isEmpty ? "Personal" : profile) == currentProfileName
        }
    }

    private var displayedFixedPayments: [FixedPayment] {
        switch sortOption {
        case .planName:
            return fixedPayments.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .chargeAccount:
            return fixedPayments.sorted {
                let lhs = chargeAccountName(for: $0).lowercased()
                let rhs = chargeAccountName(for: $1).lowercased()
                if lhs == rhs {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return lhs < rhs
            }
        case .lastPaymentDateAscending:
            return fixedPayments.sorted {
                let lhs = $0.endDate ?? Date.distantFuture
                let rhs = $1.endDate ?? Date.distantFuture
                if lhs == rhs {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return lhs < rhs
            }
        }
    }

    private var groupedFixedPayments: [(type: FixedPaymentType, items: [FixedPayment])] {
        FixedPaymentType.allCases.compactMap { type in
            let items = displayedFixedPayments.filter { $0.type == type }
            return items.isEmpty ? nil : (type, items)
        }
    }

    var body: some View {
        ZStack {
            theme.backgroundGradient.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Planning")
                        .font(.custom("Avenir Next", size: 22).weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Menu {
                        Picker("Sort", selection: $sortOption) {
                            ForEach(FixedPlanningSortOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(theme.textPrimary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(theme.surfaceAlt))
                    }
                    .buttonStyle(.plain)

                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(theme.accent))
                    }
                    .buttonStyle(.plain)

                }
                .padding(.horizontal, 18)
                .padding(.top, 6)

                if fixedPayments.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 34))
                            .foregroundStyle(theme.textTertiary)
                        Text("No fixed payments yet")
                            .font(.custom("Avenir Next", size: 14).weight(.semibold))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    Spacer(minLength: 0)
                } else {
                    List {
                        ForEach(groupedFixedPayments, id: \.type) { group in
                            Section {
                                ForEach(group.items) { item in
                                    fixedRow(item)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            editingFixedPayment = item
                                        }
                                        .listRowInsets(EdgeInsets(top: 5, leading: 18, bottom: 5, trailing: 18))
                                        .listRowBackground(Color.clear)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                modelContext.delete(item)
                                                try? modelContext.save()
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                            } header: {
                                HStack(spacing: 8) {
                                    Image(systemName: icon(for: group.type))
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(typeColor(for: group.type))
                                    Text(group.type.rawValue)
                                        .font(.custom("Avenir Next", size: 12).weight(.bold))
                                        .foregroundStyle(theme.textSecondary)
                                }
                                .textCase(nil)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            FixedPaymentEditorSheet(currentProfileName: currentProfileName)
        }
        .sheet(item: $editingFixedPayment) { item in
            FixedPaymentEditorSheet(item: item, currentProfileName: currentProfileName)
        }
    }

    private func fixedRow(_ item: FixedPayment) -> some View {
        let chargeAccountName = chargeAccountName(for: item)
        let typeLabel = item.type == .other && !item.typeName.isEmpty ? item.typeName : item.type.rawValue
        let typeColor = typeColor(for: item.type)
        let chargeDayLabel = item.chargeDay.map { "Day \($0)" } ?? "Not set"
        let lastPaymentMonthLabel = item.endDate?.formatted(.dateTime.month(.abbreviated).year()) ?? "No end"
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(typeColor.opacity(0.15))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: icon(for: item.type))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(typeColor)
                )

            VStack(alignment: .leading, spacing: 8) {
                Text(item.name)
                    .font(.custom("Avenir Next", size: 15).weight(.semibold))
                    .foregroundStyle(theme.textPrimary)

                HStack(spacing: 6) {
                    tag(text: typeLabel, foreground: typeColor, background: typeColor.opacity(0.13))
                    tag(text: item.frequency.rawValue)
                    if let months = item.cycles {
                        tag(text: "\(months)m")
                    }
                }

                Text("Charge \(chargeAccountName) • \(chargeDayLabel)")
                    .font(.custom("Avenir Next", size: 11))
                    .foregroundStyle(theme.textTertiary)

                if let outstanding = item.outstandingAmount {
                    Text("Outstanding \(CurrencyFormatter.sgd(amount: outstanding))")
                        .font(.custom("Avenir Next", size: 11).weight(.semibold))
                        .foregroundStyle(theme.textSecondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(CurrencyFormatter.sgd(amount: item.amount))
                    .font(.custom("Avenir Next", size: 16).weight(.bold))
                    .foregroundStyle(theme.textPrimary)
                Text("Monthly")
                    .font(.custom("Avenir Next", size: 10).weight(.semibold))
                    .foregroundStyle(theme.textTertiary)
                Text("Last: \(lastPaymentMonthLabel)")
                    .font(.custom("Avenir Next", size: 10))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.card))
    }

    private func tag(text: String, foreground: Color? = nil, background: Color? = nil) -> some View {
        Text(text)
            .font(.custom("Avenir Next", size: 10).weight(.semibold))
            .foregroundStyle(foreground ?? theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(background ?? theme.surfaceAlt))
    }

    private func chargeAccountName(for item: FixedPayment) -> String {
        accounts.first(where: { $0.id == item.chargeAccountId })?.displayName ?? "Not set"
    }

    private func icon(for type: FixedPaymentType) -> String {
        switch type {
        case .installment: return "creditcard"
        case .subscription: return "arrow.triangle.2.circlepath.circle.fill"
        case .insurance: return "shield.lefthalf.filled"
        case .allowance: return "banknote"
        case .other: return "calendar"
        }
    }

    private func typeColor(for type: FixedPaymentType) -> Color {
        switch type {
        case .installment: return .orange
        case .subscription: return .blue
        case .insurance: return .green
        case .allowance: return .mint
        case .other: return theme.accent
        }
    }
}


private struct FixedPaymentEditorSheet: View {
    let item: FixedPayment?
    let currentProfileName: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme

    @Query(sort: [SortDescriptor(\Account.bankName), SortDescriptor(\Account.accountName)])
    private var allAccounts: [Account]

    @State private var name: String = ""
    @State private var totalAmountText: String = ""
    @State private var outstandingAmountText: String = ""
    @State private var monthsLeftText: String = ""
    @State private var insuranceAnnualAmountText: String = ""
    @State private var insuranceMonthlyAmountText: String = ""
    @State private var insuranceYearsText: String = ""
    @State private var insuranceStartDate: Date = Date()
    @State private var insurancePaymentMode: InsurancePaymentMode = .monthly
    @State private var type: FixedPaymentType = .subscription
    @State private var typeName: String = ""
    @State private var frequency: FixedPaymentFrequency = .monthly
    @State private var isNeverEnding: Bool = false
    @State private var chargeDay: Int = max(1, min(31, Calendar.current.component(.day, from: Date())))
    @State private var selectedChargeAccount: Account? = nil
    @State private var note: String = ""
    @State private var showTypePicker: Bool = false
    @State private var showChargeAccountPicker: Bool = false
    @State private var showValidation: Bool = false
    @State private var calculatedChargeAmount: Decimal? = nil

    init(item: FixedPayment? = nil, currentProfileName: String) {
        self.item = item
        self.currentProfileName = currentProfileName

        guard let item else { return }

        _name = State(initialValue: item.name)
        _type = State(initialValue: item.type)
        _typeName = State(initialValue: item.typeName)
        _frequency = State(initialValue: item.frequency)
        _isNeverEnding = State(initialValue: item.endDate == nil)
        _note = State(initialValue: item.note)
        _chargeDay = State(initialValue: min(max(item.chargeDay ?? 1, 1), 31))
        _monthsLeftText = State(initialValue: item.cycles.map(String.init) ?? "")

        let initialPaymentMode: InsurancePaymentMode = item.frequency == .yearly ? .annual : .monthly
        _insurancePaymentMode = State(initialValue: initialPaymentMode)

        let initialAnnual: Decimal = (initialPaymentMode == .annual) ? item.amount : item.amount * 12
        let initialMonthly: Decimal = (initialPaymentMode == .monthly)
            ? item.amount
            : NSDecimalNumber(decimal: item.amount).dividing(by: 12).decimalValue
        _insuranceAnnualAmountText = State(initialValue: "\(initialAnnual)")
        _insuranceMonthlyAmountText = State(initialValue: "\(initialMonthly)")

        let yearsFromCycles: Int = {
            let cycles = max(item.cycles ?? 12, 1)
            return max((cycles + 11) / 12, 1)
        }()
        _insuranceYearsText = State(initialValue: "\(yearsFromCycles)")
        _insuranceStartDate = State(initialValue: item.startDate)

        let baseTotal: Decimal = {
            if let outstanding = item.outstandingAmount, outstanding > 0 { return outstanding }
            let cycles = max(item.cycles ?? 1, 1)
            return item.amount * Decimal(cycles)
        }()
        _totalAmountText = State(initialValue: "\(baseTotal)")
        _outstandingAmountText = State(initialValue: item.outstandingAmount.map { "\($0)" } ?? "")
    }

    private var accounts: [Account] {
        allAccounts.filter {
            let profile = $0.profileName.trimmingCharacters(in: .whitespacesAndNewlines)
            return (profile.isEmpty ? "Personal" : profile) == currentProfileName
        }
    }

    private var isEditing: Bool { item != nil }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        calculatedChargeAmount != nil &&
        selectedChargeAccount != nil
    }

    private var totalAmount: Decimal? {
        guard let value = Decimal(string: totalAmountText), value > 0 else { return nil }
        return value
    }

    private var outstandingAmount: Decimal? {
        guard let value = Decimal(string: outstandingAmountText), value > 0 else { return nil }
        return value
    }

    private var insuranceYears: Int? {
        guard let years = Int(insuranceYearsText), years > 0 else { return nil }
        return years
    }

    private var monthsLeft: Int? {
        if type == .insurance {
            guard !isNeverEnding else { return nil }
            guard let years = insuranceYears, years > 0 else { return nil }
            return years * 12
        }
        guard !isNeverEnding else { return nil }
        guard let months = Int(monthsLeftText), months > 0 else { return nil }
        return months
    }

    private var repaymentMonths: Decimal? {
        guard let monthsLeft else { return nil }
        return Decimal(monthsLeft)
    }

    private var insuranceAnnualAmount: Decimal? {
        guard let value = Decimal(string: insuranceAnnualAmountText), value > 0 else { return nil }
        return value
    }

    private var insuranceMonthlyAmount: Decimal? {
        guard let value = Decimal(string: insuranceMonthlyAmountText), value > 0 else { return nil }
        return value
    }

    private var twoDecimalRounding: NSDecimalNumberHandler {
        NSDecimalNumberHandler(roundingMode: .plain,
                               scale: 2,
                               raiseOnExactness: false,
                               raiseOnOverflow: false,
                               raiseOnUnderflow: false,
                               raiseOnDivideByZero: false)
    }

    private func computeChargeAmount() -> Decimal? {
        if type == .insurance {
            if insurancePaymentMode == .annual {
                guard let annual = insuranceAnnualAmount else { return nil }
                return NSDecimalNumber(decimal: annual)
                    .rounding(accordingToBehavior: twoDecimalRounding)
                    .decimalValue
            }
            guard let monthly = insuranceMonthlyAmount else { return nil }
            return NSDecimalNumber(decimal: monthly)
                .rounding(accordingToBehavior: twoDecimalRounding)
                .decimalValue
        }

        guard let baseAmount = outstandingAmount ?? totalAmount else { return nil }
        if isNeverEnding {
            return NSDecimalNumber(decimal: baseAmount)
                .rounding(accordingToBehavior: twoDecimalRounding)
                .decimalValue
        }
        guard let months = repaymentMonths, months > 0 else { return nil }
        let raw = NSDecimalNumber(decimal: baseAmount).dividing(by: NSDecimalNumber(decimal: months))
        return raw.rounding(accordingToBehavior: twoDecimalRounding).decimalValue
    }

    private func recalculateChargeAmount() {
        calculatedChargeAmount = computeChargeAmount()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionCard {
                            sectionHeader("1. Type")
                            typeSection
                        }

                        sectionCard {
                            sectionHeader("2. Plan Details")
                            field(title: "Name", placeholder: "e.g. Car Loan", text: $name)
                            if showValidation && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                validationText("Enter a plan name.")
                            }

                            if type == .insurance {
                                insurancePlanSection
                                wholeLifeInsuranceSection
                            } else {
                                field(title: "Total Amount (SGD)", placeholder: "e.g. 1200.00", text: $totalAmountText)
                                    .keyboardType(.decimalPad)
                                field(title: "Outstanding Amount (Optional)", placeholder: "e.g. 650.00", text: $outstandingAmountText)
                                    .keyboardType(.decimalPad)
                                if showValidation && totalAmount == nil && outstandingAmount == nil {
                                    validationText("Enter a total amount or outstanding amount.")
                                }
                                neverEndingSection
                                if !isNeverEnding {
                                    monthsLeftSection
                                    if showValidation && monthsLeft == nil {
                                        validationText("Enter valid months left.")
                                    }
                                }
                            }

                            monthlyRepaySection
                        }

                        sectionCard {
                            sectionHeader("3. Charge Setup")
                            if type != .insurance {
                                pickerSection(title: "Frequency", selection: $frequency, values: FixedPaymentFrequency.allCases)
                            }
                            chargeDaySection
                            chargeAccountSection
                            noteSection
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(isEditing ? "Edit Fixed Payment" : "Fixed Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(theme.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        showValidation = true
                        save()
                    }
                    .foregroundStyle(isValid ? theme.accent : theme.textTertiary)
                    .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showChargeAccountPicker) {
                SelectAccountScreen(accounts: accounts) { selectedChargeAccount = $0 }
            }
            .onAppear {
                if let accountId = item?.chargeAccountId {
                    selectedChargeAccount = accounts.first(where: { $0.id == accountId })
                }
                recalculateChargeAmount()
            }
            .onChange(of: type) { _, _ in recalculateChargeAmount() }
            .onChange(of: insurancePaymentMode) { _, _ in recalculateChargeAmount() }
            .onChange(of: insuranceAnnualAmountText) { _, _ in recalculateChargeAmount() }
            .onChange(of: insuranceMonthlyAmountText) { _, _ in recalculateChargeAmount() }
            .onChange(of: insuranceYearsText) { _, _ in recalculateChargeAmount() }
            .onChange(of: totalAmountText) { _, _ in recalculateChargeAmount() }
            .onChange(of: outstandingAmountText) { _, _ in recalculateChargeAmount() }
            .onChange(of: monthsLeftText) { _, _ in recalculateChargeAmount() }
            .onChange(of: isNeverEnding) { _, _ in recalculateChargeAmount() }
        }
    }

    private func save() {
        guard let amount = calculatedChargeAmount else { return }
        guard let selectedChargeAccount else { return }

        let startDate = (type == .insurance) ? insuranceStartDate : Date()
        let finalFrequency: FixedPaymentFrequency = {
            guard type == .insurance else { return frequency }
            return insurancePaymentMode == .annual ? .yearly : .monthly
        }()
        let computedEndDate: Date? = {
            guard !isNeverEnding, let monthsLeft else { return nil }
            return Calendar.current.date(byAdding: .month,
                                         value: max(monthsLeft - 1, 0),
                                         to: startDate)
        }()

        if let item {
            item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            item.amount = amount
            item.outstandingAmount = outstandingAmount
            item.type = type
            item.typeName = type == .other ? typeName : ""
            item.frequency = finalFrequency
            item.startDate = startDate
            item.endDate = computedEndDate
            item.cycles = isNeverEnding ? nil : monthsLeft
            item.chargeAccountId = selectedChargeAccount.id
            item.chargeDay = min(max(chargeDay, 1), 31)
            item.profileName = currentProfileName
            item.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let newItem = FixedPayment(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: amount,
                outstandingAmount: outstandingAmount,
                type: type,
                typeName: type == .other ? typeName : "",
                frequency: finalFrequency,
                startDate: startDate,
                endDate: computedEndDate,
                cycles: isNeverEnding ? nil : monthsLeft,
                chargeAccountId: selectedChargeAccount.id,
                chargeDay: chargeDay,
                profileName: currentProfileName,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            modelContext.insert(newItem)
        }

        try? modelContext.save()
        dismiss()
    }

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

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(theme.card))
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(theme.textTertiary)
            .textCase(.uppercase)
    }

    private func validationText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(theme.negative)
    }

    private func pickerSection<T: CaseIterable & Identifiable & Hashable & RawRepresentable>(
        title: String,
        selection: Binding<T>,
        values: [T]
    ) -> some View where T.RawValue == String {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            Picker(title, selection: selection) {
                ForEach(values, id: \.self) { val in
                    Text(val.rawValue).tag(val)
                }
            }
            .pickerStyle(.menu)
            .tint(theme.textPrimary)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
        }
    }

    private var monthsLeftSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Number of Months Left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            TextField("e.g. 12", text: $monthsLeftText)
                .keyboardType(.numberPad)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
                .foregroundStyle(theme.textPrimary)
        }
    }

    private var neverEndingSection: some View {
        Toggle("Never Ending Subscription", isOn: $isNeverEnding)
            .tint(theme.accent)
            .foregroundStyle(theme.textPrimary)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
    }

    private var chargeAccountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Charge Account")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            Button {
                showChargeAccountPicker = true
            } label: {
                HStack {
                    if let selectedChargeAccount {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: selectedChargeAccount.colorHex).opacity(0.95))
                            .frame(width: 24, height: 24)
                        Text(selectedChargeAccount.displayName)
                            .foregroundStyle(theme.textPrimary)
                    } else {
                        Text("Select account")
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

            if showValidation && selectedChargeAccount == nil {
                validationText("Select an account to charge.")
            }
        }
    }

    private var chargeDaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Charge Day")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            Picker("Charge Day", selection: $chargeDay) {
                ForEach(1...31, id: \.self) { day in
                    Text("\(day)").tag(day)
                }
            }
            .pickerStyle(.menu)
            .tint(theme.textPrimary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Note (optional)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            TextField("e.g. Auto debit on 15th", text: $note)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
                .foregroundStyle(theme.textPrimary)
        }
    }

    private var monthlyRepaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Calculated Charge Amount")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            Text(monthlyRepayLabel)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(calculatedChargeAmount == nil ? theme.textTertiary : theme.textPrimary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))

            if type == .insurance {
                if insurancePaymentMode == .annual, let annual = insuranceAnnualAmount {
                    Text("Charged annually • Annual \(CurrencyFormatter.sgd(amount: annual))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                } else if let monthly = insuranceMonthlyAmount {
                    Text("Charged monthly • Monthly \(CurrencyFormatter.sgd(amount: monthly))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                }
            } else if let months = repaymentMonths {
                let sourceLabel = outstandingAmount != nil ? "outstanding amount" : "total amount"
                Text("Based on \(sourceLabel) over \(NSDecimalNumber(decimal: months).stringValue) month(s)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
            } else if isNeverEnding {
                Text("Never ending: total/outstanding is treated as the recurring amount.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
            } else {
                Text("Enter total or outstanding amount and months left.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
            }

            if showValidation && calculatedChargeAmount == nil {
                let hint = if type == .insurance {
                    insurancePaymentMode == .annual ? "Enter a valid annual amount." : "Enter a valid monthly amount."
                } else {
                    "Complete amount details to calculate charge."
                }
                validationText(hint)
            }
        }
    }

    private var monthlyRepayLabel: String {
        guard let calculatedChargeAmount else {
            return type == .insurance
                ? (insurancePaymentMode == .annual ? "Set annual amount" : "Set monthly amount")
                : "Set total amount and months left"
        }
        return CurrencyFormatter.sgd(amount: calculatedChargeAmount)
    }

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Type")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            Button {
                showTypePicker = true
            } label: {
                HStack {
                    Text(type == .other ? (typeName.isEmpty ? "Custom" : typeName) : type.rawValue)
                        .foregroundStyle(theme.textPrimary)
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
        .sheet(isPresented: $showTypePicker) {
            FixedPaymentTypePickerSheet(selectedType: $type, selectedName: $typeName)
        }
    }

    private var insurancePlanSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Insurance Plan")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            pickerSection(title: "Payment", selection: $insurancePaymentMode, values: InsurancePaymentMode.allCases)

            if insurancePaymentMode == .annual {
                field(title: "Annual Amount (SGD)", placeholder: "e.g. 2400.00", text: $insuranceAnnualAmountText)
                    .keyboardType(.decimalPad)
                if showValidation && insuranceAnnualAmount == nil {
                    validationText("Enter a valid annual amount.")
                }
            } else {
                field(title: "Monthly Amount (SGD)", placeholder: "e.g. 200.00", text: $insuranceMonthlyAmountText)
                    .keyboardType(.decimalPad)
                if showValidation && insuranceMonthlyAmount == nil {
                    validationText("Enter a valid monthly amount.")
                }
            }

            if !isNeverEnding {
                field(title: "Duration (Years)", placeholder: "e.g. 10", text: $insuranceYearsText)
                    .keyboardType(.numberPad)
                if showValidation && insuranceYears == nil {
                    validationText("Enter valid duration in years.")
                }
            }

            DatePicker("Plan Start Date", selection: $insuranceStartDate, displayedComponents: [.date])
                .tint(theme.accent)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
                .foregroundStyle(theme.textPrimary)
        }
    }

    private var wholeLifeInsuranceSection: some View {
        Toggle("Whole Life (Never Ending)", isOn: $isNeverEnding)
            .tint(theme.accent)
            .foregroundStyle(theme.textPrimary)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
    }
}
private struct FixedPaymentTypePickerSheet: View {
    @Binding var selectedType: FixedPaymentType
    @Binding var selectedName: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme
    @Query(sort: [SortDescriptor(\CustomCategory.name)])
    private var customCategories: [CustomCategory]
    @State private var showAddCustom: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundGradient.ignoresSafeArea()

                List {
                    Section("Built-in") {
                        ForEach(FixedPaymentType.allCases.filter { $0 != .other }) { type in
                            Button {
                                selectedType = type
                                selectedName = ""
                                dismiss()
                            } label: {
                                Text(type.rawValue)
                            }
                        }
                    }

                    Section("Custom") {
                        ForEach(customCategories.filter { $0.kind == .fixedPayment }) { cat in
                            Button {
                                selectedType = .other
                                selectedName = cat.name
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: cat.iconSystemName)
                                    Text(cat.name)
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    if selectedType == .other && selectedName == cat.name {
                                        selectedType = .subscription
                                        selectedName = ""
                                    }
                                    modelContext.delete(cat)
                                    try? modelContext.save()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Select Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(theme.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showAddCustom = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(theme.textPrimary)
                    }
                }
            }
        }
        .sheet(isPresented: $showAddCustom) {
            AddCustomCategorySheet(kind: .fixedPayment)
        }
    }
}
