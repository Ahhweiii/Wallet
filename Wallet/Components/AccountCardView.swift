//
//  AccountCardView.swift
//  Wallet
//
//  Created by Lee Jun Wei on 21/2/26.
//

import SwiftUI

struct AccountCardView: View {
    let account: Account
    let totalSpent: Decimal
    let subtitle: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: account.colorHex).opacity(0.95))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: account.iconSystemName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        )

                    Spacer()

                    Text(account.type.rawValue)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }

                Text(account.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)

                Text(CurrencyFormatter.sgd(amount: totalSpent))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(white: 0.14).opacity(0.95))
            )
        }
        .buttonStyle(.plain)
    }
}
