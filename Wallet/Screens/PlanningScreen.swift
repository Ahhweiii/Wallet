//
//  PlanningScreen.swift
//  Wallet
//
//  Created by Codex on 27/2/26.
//

import SwiftUI
import SwiftData

struct PlanningScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme
    @AppStorage("theme_is_dark") private var themeIsDark: Bool = true

    @Query(sort: [SortDescriptor(\FixedPayment.startDate, order: .reverse)])
    private var fixedPayments: [FixedPayment]

    @Query(sort: [SortDescriptor(\CustomCategory.name)])
    private var customCategories: [CustomCategory]

    @State private var showAdd: Bool = false

    var body: some View {
        ZStack {
            theme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Planning")
                            .font(.custom("Avenir Next", size: 22).weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
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
                    } else {
            VStack(spacing: 10) {
                ForEach(fixedPayments) { item in
                    fixedRow(item)
                }
            }
            .padding(.horizontal, 18)
                    }

                    Spacer(minLength: 90)
                }
                .padding(.bottom, 110)
            }
        }
        .sheet(isPresented: $showAdd) {
            AddFixedPaymentSheet()
        }
    }

    private func fixedRow(_ item: FixedPayment) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.accentSoft)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: icon(for: item.type))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.accent)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.custom("Avenir Next", size: 14).weight(.semibold))
                    .foregroundStyle(theme.textPrimary)

                Text("\(item.type.rawValue) • \(item.frequency.rawValue)")
                    .font(.custom("Avenir Next", size: 11).weight(.semibold))
                    .foregroundStyle(theme.textTertiary)
                let typeLabel = item.type == .other && !item.typeName.isEmpty
                    ? item.typeName
                    : item.type.rawValue
                Text(typeLabel)
                    .font(.custom("Avenir Next", size: 10).weight(.semibold))
                    .foregroundStyle(theme.textTertiary)
                if let end = item.endDate {
                    Text("Ends \(end, style: .date)")
                        .font(.custom("Avenir Next", size: 10))
                        .foregroundStyle(theme.textTertiary)
                } else {
                    Text("Never ending")
                        .font(.custom("Avenir Next", size: 10))
                        .foregroundStyle(theme.textTertiary)
                }
                if let cycles = item.cycles, item.type == .installment {
                    Text("Cycles: \(cycles)")
                        .font(.custom("Avenir Next", size: 10))
                        .foregroundStyle(theme.textTertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(CurrencyFormatter.sgd(amount: item.amount))
                    .font(.custom("Avenir Next", size: 14).weight(.bold))
                    .foregroundStyle(theme.textPrimary)
                Text(item.startDate, style: .date)
                    .font(.custom("Avenir Next", size: 10))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.card))
    }

    private func icon(for type: FixedPaymentType) -> String {
        switch type {
        case .installment: return "creditcard"
        case .subscription: return "arrow.triangle.2.circlepath.circle.fill"
        case .allowance: return "banknote"
        case .other: return "calendar"
        }
    }
}

private struct AddFixedPaymentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme

    @Query(sort: [SortDescriptor(\CustomCategory.name)])
    private var customCategories: [CustomCategory]

    @State private var name: String = ""
    @State private var amountText: String = ""
    @State private var type: FixedPaymentType = .subscription
    @State private var typeName: String = ""
    @State private var frequency: FixedPaymentFrequency = .monthly
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date()
    @State private var cyclesText: String = ""
    @State private var note: String = ""
    @State private var showTypePicker: Bool = false
    @State private var endMode: EndMode = .none

    private enum EndMode: String, CaseIterable, Identifiable {
        case none = "Never ending"
        case endDate = "End date"
        case cycles = "Number of cycles"
        var id: String { rawValue }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Decimal(string: amountText) != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        field(title: "Name", placeholder: "e.g. Spotify, Car Loan", text: $name)

                        field(title: "Amount (SGD)", placeholder: "e.g. 19.90", text: $amountText)
                            .keyboardType(.decimalPad)

                        typeSection
                        pickerSection(title: "Frequency", selection: $frequency, values: FixedPaymentFrequency.allCases)

                        dateSection
                        endModeSection
                        cyclesSection
                        calculatedEndDateSection
                        noteSection
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Fixed Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(theme.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .foregroundStyle(isValid ? theme.accent : theme.textTertiary)
                        .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        guard let amount = Decimal(string: amountText) else { return }
        let cycles: Int? = {
            guard endMode == .cycles else { return nil }
            return Int(cyclesText)
        }()
        let finalTypeName = type == .other ? typeName : ""
        let computedEndDate = endMode == .cycles ? endDateFromCycles() : nil
        let item = FixedPayment(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amount,
            type: type,
            typeName: finalTypeName,
            frequency: frequency,
            startDate: startDate,
            endDate: endMode == .endDate ? endDate : computedEndDate,
            cycles: cycles,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        modelContext.insert(item)
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

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Start Date")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            DatePicker("", selection: $startDate, displayedComponents: [.date])
                .labelsHidden()
                .tint(theme.accent)
                .padding(14)
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

    private var endModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ends")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            Picker("Ends", selection: $endMode) {
                ForEach(EndMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .tint(theme.textPrimary)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))

            if endMode == .endDate {
                Text("End Date")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)

                DatePicker("", selection: $endDate, displayedComponents: [.date])
                    .labelsHidden()
                    .tint(theme.accent)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
            }
        }
    }

    private var cyclesSection: some View {
        Group {
            if endMode == .cycles {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Number of Cycles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)

                    TextField("e.g. 12", text: $cyclesText)
                        .keyboardType(.numberPad)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
                        .foregroundStyle(theme.textPrimary)
                }
            }
        }
    }

    private var calculatedEndDateSection: some View {
        Group {
            if endMode == .cycles, let end = endDateFromCycles() {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Calculated End Date")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)

                    Text(end, style: .date)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
                }
            }
        }
    }

    private func endDateFromCycles() -> Date? {
        guard let cycles = Int(cyclesText), cycles > 0 else { return nil }
        let cal = Calendar.current
        let offset = max(cycles - 1, 0)
        switch frequency {
        case .weekly:
            return cal.date(byAdding: .weekOfYear, value: offset, to: startDate)
        case .monthly:
            return cal.date(byAdding: .month, value: offset, to: startDate)
        case .yearly:
            return cal.date(byAdding: .year, value: offset, to: startDate)
        }
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
}

private struct FixedPaymentTypePickerSheet: View {
    @Binding var selectedType: FixedPaymentType
    @Binding var selectedName: String

    @Environment(\.dismiss) private var dismiss
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
