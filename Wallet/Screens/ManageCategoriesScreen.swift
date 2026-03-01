//
//  ManageCategoriesScreen.swift
//  Wallet
//
//  Created by Codex on 27/2/26.
//

import SwiftUI
import SwiftData

struct ManageCategoriesScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme
    @AppStorage("theme_is_dark") private var themeIsDark: Bool = true

    @Query(sort: [SortDescriptor(\CustomCategory.name)])
    private var customCategories: [CustomCategory]

    @State private var selectedCategory: CustomCategory?

    var body: some View {
        NavigationStack {
            List {
                section(title: "Expense", kind: .expense)
                section(title: "Income", kind: .income)
                section(title: "Fixed Payment", kind: .fixedPayment)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.backgroundGradient)
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(themeIsDark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(theme.textPrimary)
                }
            }
        }
        .sheet(item: $selectedCategory) { category in
            EditCustomCategorySheet(category: category)
        }
    }

    private func section(title: String, kind: CustomCategoryKind) -> some View {
        Section {
            let items = customCategories.filter { $0.kind == kind }
            if items.isEmpty {
                Text("No categories yet")
                    .foregroundStyle(theme.textTertiary)
            } else {
                ForEach(items) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.iconSystemName)
                            .foregroundStyle(theme.textSecondary)
                        Text(item.name)
                            .foregroundStyle(theme.textPrimary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedCategory = item
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            modelContext.delete(item)
                            try? modelContext.save()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            Text(title)
                .foregroundStyle(theme.textSecondary)
        }
    }
}
