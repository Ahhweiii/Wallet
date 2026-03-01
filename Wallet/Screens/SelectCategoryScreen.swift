//
//  SelectCategoryscreen.swift
//  Wallet
//
//  Created by Lee Jun Wei on 23/2/26.
//

import SwiftUI
import SwiftData

struct CategoryItem: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
}

struct SelectCategoryScreen: View {
    let transactionType: TransactionType
    let onSelect: (CategoryItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme
    @AppStorage("theme_is_dark") private var themeIsDark: Bool = true
    @AppStorage("category_preset") private var categoryPresetRaw: String = CategoryPreset.singapore.rawValue
    @Query(sort: [SortDescriptor(\CustomCategory.name)]) private var customCategories: [CustomCategory]
    @Query(sort: [SortDescriptor(\Transaction.date, order: .reverse)]) private var transactions: [Transaction]
    @State private var showAddCustom: Bool = false
    @State private var searchText: String = ""

    private var categoryPreset: CategoryPreset {
        CategoryPreset(rawValue: categoryPresetRaw) ?? .singapore
    }

    private var customItems: [CustomCategory] {
        customCategories.filter { $0.kind == (transactionType == .expense ? .expense : .income) }
    }

    private var builtInItems: [CategoryItem] {
        let categories: [TransactionCategory]
        if transactionType == .expense {
            categories = uniqueCategories(expenseEssentials + expenseHomeAndFamily + expenseLifestyle + TransactionCategory.legacyExpenseCategories)
        } else {
            categories = uniqueCategories(incomeWork + incomeReturns)
        }
        return categories.map { CategoryItem(id: $0.rawValue, name: $0.rawValue, icon: $0.iconSystemName) }
    }

    private var filteredCustomItems: [CustomCategory] {
        guard searchText.isEmpty == false else { return customItems }
        return customItems.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredBuiltInItems: [CategoryItem] {
        guard searchText.isEmpty == false else { return builtInItems }
        return builtInItems.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredEssentialExpenseItems: [CategoryItem] {
        guard transactionType == .expense else { return [] }
        let source = expenseEssentials.map {
            CategoryItem(id: $0.rawValue, name: $0.rawValue, icon: $0.iconSystemName)
        }
        guard searchText.isEmpty == false else { return source }
        return source.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredLifestyleExpenseItems: [CategoryItem] {
        guard transactionType == .expense else { return [] }
        let source = expenseLifestyle.map {
            CategoryItem(id: $0.rawValue, name: $0.rawValue, icon: $0.iconSystemName)
        }
        guard searchText.isEmpty == false else { return source }
        return source.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredExpenseHomeAndFamilyItems: [CategoryItem] {
        guard transactionType == .expense else { return [] }
        let source = expenseHomeAndFamily.map {
            CategoryItem(id: $0.rawValue, name: $0.rawValue, icon: $0.iconSystemName)
        }
        guard searchText.isEmpty == false else { return source }
        return source.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredIncomeWorkItems: [CategoryItem] {
        guard transactionType == .income else { return [] }
        let source = incomeWork.map {
            CategoryItem(id: $0.rawValue, name: $0.rawValue, icon: $0.iconSystemName)
        }
        guard searchText.isEmpty == false else { return source }
        return source.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredIncomeReturnsItems: [CategoryItem] {
        guard transactionType == .income else { return [] }
        let source = incomeReturns.map {
            CategoryItem(id: $0.rawValue, name: $0.rawValue, icon: $0.iconSystemName)
        }
        guard searchText.isEmpty == false else { return source }
        return source.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredLegacyExpenseItems: [CategoryItem] {
        guard transactionType == .expense else { return [] }
        let active = Set(uniqueCategories(expenseEssentials + expenseHomeAndFamily + expenseLifestyle))
        let source = TransactionCategory.legacyExpenseCategories.filter { !active.contains($0) }.map {
            CategoryItem(id: $0.rawValue, name: $0.rawValue, icon: $0.iconSystemName)
        }
        guard searchText.isEmpty == false else { return source }
        return source.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var expenseEssentials: [TransactionCategory] {
        switch categoryPreset {
        case .singapore:
            return [.hawker, .food, .groceries, .transportPublic, .transportPrivate]
        case .generic:
            return [.food, .groceries, .transport, .housing, .utilities]
        case .minimal:
            return [.food, .groceries, .transportPublic, .housing]
        }
    }

    private var expenseHomeAndFamily: [TransactionCategory] {
        switch categoryPreset {
        case .singapore:
            return [.housing, .utilities, .telco, .insurance, .health, .family, .education]
        case .generic:
            return [.health, .education, .family, .insurance, .telco]
        case .minimal:
            return [.utilities, .health]
        }
    }

    private var expenseLifestyle: [TransactionCategory] {
        switch categoryPreset {
        case .singapore:
            return [.shopping, .entertainment, .subscriptions, .donations, .travel, .other]
        case .generic:
            return [.shopping, .entertainment, .subscriptions, .travel, .donations, .other]
        case .minimal:
            return [.shopping, .other]
        }
    }

    private var incomeWork: [TransactionCategory] {
        switch categoryPreset {
        case .minimal:
            return [.salary, .bonus]
        case .singapore, .generic:
            return [.salary, .bonus, .freelance]
        }
    }

    private var incomeReturns: [TransactionCategory] {
        switch categoryPreset {
        case .minimal:
            return [.other]
        case .singapore, .generic:
            return [.investment, .dividends, .interest, .rental, .gift, .other]
        }
    }

    private func uniqueCategories(_ categories: [TransactionCategory]) -> [TransactionCategory] {
        var seen: Set<TransactionCategory> = []
        var result: [TransactionCategory] = []
        for category in categories where !seen.contains(category) {
            seen.insert(category)
            result.append(category)
        }
        return result
    }

    private var recentBuiltInItems: [CategoryItem] {
        guard searchText.isEmpty else { return [] }
        let allowed = Set(builtInItems.map(\.name))
        var seen: Set<String> = []
        var result: [CategoryItem] = []
        for txn in transactions where txn.type == transactionType {
            let name = txn.categoryName.isEmpty ? (txn.category?.rawValue ?? "") : txn.categoryName
            guard allowed.contains(name), seen.contains(name) == false else { continue }
            seen.insert(name)
            result.append(CategoryItem(id: name, name: name, icon: TransactionCategory.iconSystemName(for: name)))
            if result.count == 6 { break }
        }
        return result
    }

    private var mostUsedBuiltInItems: [CategoryItem] {
        guard searchText.isEmpty else { return [] }
        let allowed = Set(builtInItems.map(\.name))
        let filtered = transactions.filter { $0.type == transactionType }
        let counts: [String: Int] = filtered.reduce(into: [:]) { partial, txn in
            let name = txn.categoryName.isEmpty ? (txn.category?.rawValue ?? "") : txn.categoryName
            guard allowed.contains(name) else { return }
            partial[name, default: 0] += 1
        }
        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .prefix(6)
            .map { CategoryItem(id: $0.key, name: $0.key, icon: TransactionCategory.iconSystemName(for: $0.key)) }
    }

    var body: some View {
        NavigationStack {
            List {
                if searchText.isEmpty == false {
                    Section("Results") {
                        ForEach(filteredBuiltInItems) { category in
                            Button {
                                onSelect(category)
                                dismiss()
                            } label: {
                                categoryRow(name: category.name, icon: category.icon)
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(filteredCustomItems) { category in
                            Button {
                                onSelect(CategoryItem(id: category.id.uuidString, name: category.name, icon: category.iconSystemName))
                                dismiss()
                            } label: {
                                categoryRow(name: category.name, icon: category.iconSystemName)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    if recentBuiltInItems.isEmpty == false {
                        Section("Recent") {
                            ForEach(recentBuiltInItems) { category in
                                Button {
                                    onSelect(category)
                                    dismiss()
                                } label: {
                                    categoryRow(name: category.name, icon: category.icon)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if mostUsedBuiltInItems.isEmpty == false {
                        Section("Most Used") {
                            ForEach(mostUsedBuiltInItems) { category in
                                Button {
                                    onSelect(category)
                                    dismiss()
                                } label: {
                                    categoryRow(name: category.name, icon: category.icon)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if searchText.isEmpty {
                    if filteredCustomItems.isEmpty == false {
                        Section("Custom") {
                            ForEach(filteredCustomItems) { category in
                                Button {
                                    onSelect(CategoryItem(id: category.id.uuidString, name: category.name, icon: category.iconSystemName))
                                    dismiss()
                                } label: {
                                    categoryRow(name: category.name, icon: category.iconSystemName)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        modelContext.delete(category)
                                        try? modelContext.save()
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }

                    if transactionType == .expense {
                        if filteredEssentialExpenseItems.isEmpty == false {
                            Section(expenseEssentialsTitle) {
                                ForEach(filteredEssentialExpenseItems) { category in
                                    Button {
                                        onSelect(category)
                                        dismiss()
                                    } label: {
                                        categoryRow(name: category.name, icon: category.icon)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if filteredExpenseHomeAndFamilyItems.isEmpty == false {
                            Section(expenseHomeTitle) {
                                ForEach(filteredExpenseHomeAndFamilyItems) { category in
                                    Button {
                                        onSelect(category)
                                        dismiss()
                                    } label: {
                                        categoryRow(name: category.name, icon: category.icon)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if filteredLifestyleExpenseItems.isEmpty == false {
                            Section(expenseLifestyleTitle) {
                                ForEach(filteredLifestyleExpenseItems) { category in
                                    Button {
                                        onSelect(category)
                                        dismiss()
                                    } label: {
                                        categoryRow(name: category.name, icon: category.icon)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if filteredLegacyExpenseItems.isEmpty == false {
                            Section("Legacy Categories") {
                                ForEach(filteredLegacyExpenseItems) { category in
                                    Button {
                                        onSelect(category)
                                        dismiss()
                                    } label: {
                                        categoryRow(name: category.name, icon: category.icon)
                                    }
                                    .buttonStyle(.plain)
                                }
                                Text("Shown for compatibility with existing data and backups.")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(theme.textTertiary)
                            }
                        }
                    } else {
                        if filteredIncomeWorkItems.isEmpty == false {
                            Section("Salary & Work") {
                                ForEach(filteredIncomeWorkItems) { category in
                                    Button {
                                        onSelect(category)
                                        dismiss()
                                    } label: {
                                        categoryRow(name: category.name, icon: category.icon)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        if filteredIncomeReturnsItems.isEmpty == false {
                            Section("Returns & Other Income") {
                                ForEach(filteredIncomeReturnsItems) { category in
                                    Button {
                                        onSelect(category)
                                        dismiss()
                                    } label: {
                                        categoryRow(name: category.name, icon: category.icon)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                if searchText.isEmpty == false && filteredBuiltInItems.isEmpty && filteredCustomItems.isEmpty {
                    Section {
                        Text("No categories found")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.backgroundGradient)
            .searchable(text: $searchText, prompt: "Search category")
            .navigationTitle("Select Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(themeIsDark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(theme.textPrimary)
                }
                if transactionType == .expense || transactionType == .income {
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
                AddCustomCategorySheet(kind: transactionType == .expense ? .expense : .income)
            }
        }
    }

    private func categoryRow(name: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(theme.accentSoft)
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(theme.accent)
                )

            Text(name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.textPrimary)

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var expenseEssentialsTitle: String {
        switch categoryPreset {
        case .singapore: return "Daily Essentials (SG)"
        case .generic: return "Essentials"
        case .minimal: return "Core Spending"
        }
    }

    private var expenseHomeTitle: String {
        switch categoryPreset {
        case .singapore: return "Home, Bills & Family"
        case .generic: return "Home & Family"
        case .minimal: return "Home & Health"
        }
    }

    private var expenseLifestyleTitle: String {
        switch categoryPreset {
        case .singapore: return "Lifestyle & Personal"
        case .generic: return "Lifestyle"
        case .minimal: return "Optional"
        }
    }
}
