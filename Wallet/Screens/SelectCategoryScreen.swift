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
    @Environment(\.appTheme) private var theme
    @AppStorage("theme_is_dark") private var themeIsDark: Bool = true
    @Query(sort: [SortDescriptor(\CustomCategory.name)]) private var customCategories: [CustomCategory]
    @State private var showAddCustom: Bool = false

    private var categories: [CategoryItem] {
        let builtIns = (transactionType == .expense
            ? TransactionCategory.expenseCategories
            : TransactionCategory.incomeCategories)
            .map { CategoryItem(id: $0.rawValue, name: $0.rawValue, icon: $0.iconSystemName) }

        if transactionType == .expense {
            let custom = customCategories
                .filter { $0.kind == .expense }
                .map { CategoryItem(id: $0.id.uuidString, name: $0.name, icon: $0.iconSystemName) }
            return custom + builtIns
        }

        let custom = customCategories
            .filter { $0.kind == .income }
            .map { CategoryItem(id: $0.id.uuidString, name: $0.name, icon: $0.iconSystemName) }
        return custom + builtIns
    }

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(categories) { category in
                            Button {
                                onSelect(category)
                                dismiss()
                            } label: {
                                VStack(spacing: 10) {
                                    Circle()
                                        .fill(theme.accentSoft)
                                        .frame(width: 50, height: 50)
                                        .overlay(
                                            Image(systemName: category.icon)
                                                .font(.system(size: 22))
                                                .foregroundStyle(theme.accent)
                                        )

                                    Text(category.name)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(theme.textSecondary)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 14).fill(theme.surfaceAlt))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(18)
                }
            }
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
}
