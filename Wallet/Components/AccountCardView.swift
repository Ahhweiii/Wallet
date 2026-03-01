//
//  AccountCardView.swift
//  FrugalPilot
//
//  Created by Lee Jun Wei on 21/2/26.
//

import SwiftUI

struct AccountCardView: View {
    let account: Account
    let totalSpent: Decimal
    let subtitle: String
    let onTap: () -> Void
    @Environment(\.appTheme) private var theme
    private let headerHeight: CGFloat = 34

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: account.colorHex).opacity(0.95))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: account.iconSystemName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(account.displayName)
                        .font(.custom("Avenir Next", size: 12).weight(.semibold))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.custom("Avenir Next", size: 10).weight(.semibold))
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                    }

                    Text(CurrencyFormatter.sgd(amount: totalSpent))
                        .font(.custom("Avenir Next", size: 20).weight(.bold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(theme.card)
                    .shadow(color: theme.shadow, radius: 10, x: 0, y: 6)
            )
        }
        .buttonStyle(.plain)
    }
}
