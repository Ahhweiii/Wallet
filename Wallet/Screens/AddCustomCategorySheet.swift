//
//  AddCustomCategorySheet.swift
//  FrugalPilot
//
//  Created by Codex on 27/2/26.
//

import SwiftUI
import SwiftData

struct AddCustomCategorySheet: View {
    let kind: CustomCategoryKind

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme

    @State private var name: String = ""
    @State private var iconSystemName: String = "tag.fill"

    private let iconOptions: [String] = [
        "tag.fill", "cart.fill", "fork.knife", "bus.fill", "car.fill",
        "bolt.fill", "heart.fill", "house.fill", "gift.fill", "airplane",
        "book.fill", "tv.fill", "bag.fill", "music.note", "creditcard",
        "banknote", "calendar", "percent", "chart.bar.fill"
    ]

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundGradient.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 12) {
                    Text("New Category")
                        .font(.custom("Avenir Next", size: 18).weight(.semibold))
                        .foregroundStyle(theme.textPrimary)

                    TextField("Category name", text: $name)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(theme.surfaceAlt))
                        .foregroundStyle(theme.textPrimary)

                    Text("Icon")
                        .font(.custom("Avenir Next", size: 13).weight(.semibold))
                        .foregroundStyle(theme.textSecondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], spacing: 10) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button {
                                iconSystemName = icon
                            } label: {
                                Circle()
                                    .fill(theme.surfaceAlt)
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Image(systemName: icon)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(theme.textPrimary)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(iconSystemName == icon ? theme.accent : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer()
                }
                .padding(20)
            }
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
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = CustomCategory(name: trimmed, kind: kind, iconSystemName: iconSystemName)
        modelContext.insert(item)
        try? modelContext.save()
        dismiss()
    }
}
