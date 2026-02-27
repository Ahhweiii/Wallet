//
//  WalletBackupFile.swift
//  Wallet
//
//  Created by Lee Jun Wei on 26/2/26.
//

import Foundation

/// Backup file format (Codable) independent of SwiftData.
/// Preserves UUIDs so re-import keeps identity.
struct WalletBackupFile: Codable {
    static let currentVersion = 1

    var version: Int
    var exportedAt: Date
    var accounts: [AccountDTO]
    var transactions: [TransactionDTO]

    init(exportedAt: Date = Date(),
         accounts: [AccountDTO],
         transactions: [TransactionDTO]) {
        self.version = Self.currentVersion
        self.exportedAt = exportedAt
        self.accounts = accounts
        self.transactions = transactions
    }
}

struct AccountDTO: Codable, Hashable {
    var id: UUID
    var bankName: String
    var accountName: String
    var currentCredit: Decimal
    var amount: Decimal
    var type: AccountType
    var colorHex: String
    var iconSystemName: String
    var isInCombinedCreditPool: Bool

    init(from model: Account) {
        self.id = model.id
        self.bankName = model.bankName
        self.accountName = model.accountName
        self.currentCredit = model.currentCredit
        self.amount = model.amount
        self.type = model.type
        self.colorHex = model.colorHex
        self.iconSystemName = model.iconSystemName
        self.isInCombinedCreditPool = model.isInCombinedCreditPool
    }
}

struct TransactionDTO: Codable, Hashable {
    var id: UUID
    var type: TransactionType
    var amount: Decimal
    var accountId: UUID
    var category: TransactionCategory
    var date: Date
    var note: String

    init(from model: Transaction) {
        self.id = model.id
        self.type = model.type
        self.amount = model.amount
        self.accountId = model.accountId
        self.category = model.category
        self.date = model.date
        self.note = model.note
    }
}
