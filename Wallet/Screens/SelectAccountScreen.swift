//
//  SelectAccountScreen.swift
//  FrugalPilot
//
//  Created by Lee Jun Wei on 23/2/26.
//

import SwiftUI

struct SelectAccountScreen: View {
    let accounts: [Account]
    let onSelect: (Account) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @AppStorage("theme_is_dark") private var themeIsDark: Bool = true

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundGradient.ignoresSafeArea()

                if accounts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "creditcard")
                            .font(.system(size: 40))
                            .foregroundStyle(theme.textTertiary)
                        Text("No accounts yet")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(accounts) { account in
                                Button {
                                    onSelect(account)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 14) {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color(hex: account.colorHex).opacity(0.95))
                                            .frame(width: 40, height: 40)
                                            .overlay(
                                                Image(systemName: account.iconSystemName)
                                                    .font(.system(size: 18, weight: .semibold))
                                                    .foregroundStyle(.white)
                                            )

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(account.displayName)
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundStyle(theme.textPrimary)

                                            Text(account.type.rawValue)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(theme.textTertiary)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(theme.textTertiary)
                                    }
                                    .padding(14)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(theme.surfaceAlt))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(18)
                    }
                }
            }
            .navigationTitle("Select Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(themeIsDark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(theme.textPrimary)
                }
            }
        }
    }
}
