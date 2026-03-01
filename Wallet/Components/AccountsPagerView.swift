//
//  AccountsPagerView.swift
//  LedgerFlow
//
//  Created by Lee Jun Wei on 21/2/26.
//

import SwiftUI

struct AccountsPagerView: View {
    enum Card: Identifiable, Hashable {
        case account(Account)
        case addAccount

        var id: String {
            switch self {
            case .account(let a): return "account-\(a.id.uuidString)"
            case .addAccount: return "add-account"
            }
        }
    }

    let accounts: [Account]
    let totalSpentByAccountId: [UUID: Decimal]
    let subtitleByAccountId: [UUID: String]
    @Binding var pageIndex: Int
    let maxPerPage: Int
    let canAddAccount: Bool
    let onAddAccount: () -> Void
    let onTapAccount: (Account) -> Void

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    private let cardHeight: CGFloat = 92
    private let gridSpacing: CGFloat = 14

    static func pageCount(totalCards: Int, maxPerPage: Int) -> Int {
        Int(ceil(Double(totalCards) / Double(maxPerPage)))
    }

    var body: some View {
        let accountCards: [Card] = accounts.map { .account($0) }
        let cards: [Card] = accountCards + [.addAccount]
        let pages = cards.chunked(into: maxPerPage)

        TabView(selection: $pageIndex) {
            ForEach(Array(pages.enumerated()), id: \.offset) { page, items in
                LazyVGrid(columns: columns, spacing: gridSpacing) {
                    ForEach(items, id: \.id) { item in
                        switch item {
                        case .account(let acct):
                            let spent = totalSpentByAccountId[acct.id] ?? 0
                            let subtitle = subtitleByAccountId[acct.id] ?? ""

                            AccountCardView(account: acct,
                                            totalSpent: spent,
                                            subtitle: subtitle) {
                                onTapAccount(acct)
                            }

                        case .addAccount:
                            AddAccountCardView(isEnabled: canAddAccount, onTap: onAddAccount)
                                .frame(height: cardHeight)
                        }
                    }

                    let placeholders = max(0, maxPerPage - items.count)
                    ForEach(0..<placeholders, id: \.self) { _ in
                        Color.clear.frame(height: cardHeight)
                    }
                }
                .tag(page)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: cardHeight * 2 + gridSpacing)
        .onChange(of: pages.count) { _, newCount in
            pageIndex = min(pageIndex, max(0, newCount - 1))
        }
    }
}
