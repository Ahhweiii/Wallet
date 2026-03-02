//
//  Account.swift
//  FrugalPilot
//
//  Created by Lee Jun Wei on 21/2/26.
//

import Foundation
import SwiftData

enum AccountType: String, CaseIterable, Identifiable, Hashable, Codable {
    case cash = "Cash"
    case credit = "Credit"
    var id: String { rawValue }
}

@Model
final class Account: Identifiable, Hashable {
    var id: UUID = UUID()

    var bankName: String = ""
    var accountName: String = ""

    var currentCredit: Decimal = 0
    var amount: Decimal = 0

    var type: AccountType = AccountType.cash
    var colorHex: String = "#9CA3AF"
    var iconSystemName: String = "creditcard.fill"

    var isInCombinedCreditPool: Bool = false
    var profileName: String = "Personal"

    /// The day of month (1–31) when this account's tracking period resets.
    var billingCycleStartDay: Int = 1

    init(id: UUID = UUID(),
         bankName: String,
         accountName: String,
         currentCredit: Decimal,
         amount: Decimal,
         type: AccountType,
         colorHex: String,
         iconSystemName: String,
         isInCombinedCreditPool: Bool = false,
         profileName: String = "Personal",
         billingCycleStartDay: Int = 1) {
        self.id = id
        self.bankName = bankName
        self.accountName = accountName
        self.currentCredit = currentCredit
        self.amount = amount
        self.type = type
        self.colorHex = colorHex
        self.iconSystemName = iconSystemName
        self.isInCombinedCreditPool = isInCombinedCreditPool
        self.profileName = profileName
        self.billingCycleStartDay = billingCycleStartDay
    }

    var displayName: String {
        let b = bankName.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        if b.isEmpty { return a }
        if a.isEmpty { return b }
        return "\(b) \(a)"
    }

    static func == (lhs: Account, rhs: Account) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
