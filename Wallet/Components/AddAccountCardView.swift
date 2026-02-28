//
//  AddAccountCardView.swift
//  Wallet
//
//  Created by Lee Jun Wei on 21/2/26.
//

import SwiftUI

struct AddAccountCardView: View {
    let isEnabled: Bool
    let onTap: () -> Void
    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                Circle()
                    .fill(isEnabled ? theme.accent : theme.surfaceAlt)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(isEnabled ? .white : theme.textTertiary)
                    )

                Text(isEnabled ? "Add account" : "Upgrade for more")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isEnabled ? theme.textSecondary : theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(theme.card)
                    .shadow(color: theme.shadow, radius: 10, x: 0, y: 6)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
