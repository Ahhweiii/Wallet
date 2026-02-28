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
    var fixedPayments: [FixedPaymentDTO]?
    var customCategories: [CustomCategoryDTO]?

    init(exportedAt: Date = Date(),
         accounts: [AccountDTO],
         transactions: [TransactionDTO],
         fixedPayments: [FixedPaymentDTO]? = nil,
         customCategories: [CustomCategoryDTO]? = nil) {
        self.version = Self.currentVersion
        self.exportedAt = exportedAt
        self.accounts = accounts
        self.transactions = transactions
        self.fixedPayments = fixedPayments
        self.customCategories = customCategories
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
    var billingCycleStartDay: Int

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
        self.billingCycleStartDay = model.billingCycleStartDay
    }
}

struct TransactionDTO: Codable, Hashable {
    var id: UUID
    var type: TransactionType
    var amount: Decimal
    var accountId: UUID
    var categoryName: String
    var date: Date
    var note: String

    init(from model: Transaction) {
        self.id = model.id
        self.type = model.type
        self.amount = model.amount
        self.accountId = model.accountId
        self.categoryName = model.categoryName.isEmpty ? (model.category?.rawValue ?? "Other") : model.categoryName
        self.date = model.date
        self.note = model.note
    }

    enum CodingKeys: String, CodingKey {
        case id, type, amount, accountId, categoryName, category, date, note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.type = try container.decode(TransactionType.self, forKey: .type)
        self.amount = try container.decode(Decimal.self, forKey: .amount)
        self.accountId = try container.decode(UUID.self, forKey: .accountId)
        if let name = try container.decodeIfPresent(String.self, forKey: .categoryName) {
            self.categoryName = name
        } else if let legacy = try container.decodeIfPresent(TransactionCategory.self, forKey: .category) {
            self.categoryName = legacy.rawValue
        } else {
            self.categoryName = "Other"
        }
        self.date = try container.decode(Date.self, forKey: .date)
        self.note = try container.decode(String.self, forKey: .note)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(amount, forKey: .amount)
        try container.encode(accountId, forKey: .accountId)
        try container.encode(categoryName, forKey: .categoryName)
        try container.encode(date, forKey: .date)
        try container.encode(note, forKey: .note)
    }
}

struct FixedPaymentDTO: Codable, Hashable {
    var id: UUID
    var name: String
    var amount: Decimal
    var type: FixedPaymentType
    var typeName: String
    var frequency: FixedPaymentFrequency
    var startDate: Date
    var endDate: Date?
    var cycles: Int?
    var note: String

    init(from model: FixedPayment) {
        self.id = model.id
        self.name = model.name
        self.amount = model.amount
        self.type = model.type
        self.typeName = model.typeName
        self.frequency = model.frequency
        self.startDate = model.startDate
        self.endDate = model.endDate
        self.cycles = model.cycles
        self.note = model.note
    }

    enum CodingKeys: String, CodingKey {
        case id, name, amount, type, typeName, frequency, startDate, endDate, cycles, note, categoryName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.amount = try container.decode(Decimal.self, forKey: .amount)
        self.type = try container.decode(FixedPaymentType.self, forKey: .type)
        self.typeName = try container.decodeIfPresent(String.self, forKey: .typeName) ?? ""
        self.frequency = try container.decode(FixedPaymentFrequency.self, forKey: .frequency)
        self.startDate = try container.decode(Date.self, forKey: .startDate)
        self.endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        _ = try container.decodeIfPresent(String.self, forKey: .categoryName)
        self.cycles = try container.decodeIfPresent(Int.self, forKey: .cycles)
        self.note = try container.decode(String.self, forKey: .note)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(amount, forKey: .amount)
        try container.encode(type, forKey: .type)
        try container.encode(typeName, forKey: .typeName)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(startDate, forKey: .startDate)
        try container.encodeIfPresent(endDate, forKey: .endDate)
        try container.encodeIfPresent(cycles, forKey: .cycles)
        try container.encode(note, forKey: .note)
    }
}

struct CustomCategoryDTO: Codable, Hashable {
    var id: UUID
    var name: String
    var kind: CustomCategoryKind
    var iconSystemName: String

    init(from model: CustomCategory) {
        self.id = model.id
        self.name = model.name
        self.kind = model.kind
        self.iconSystemName = model.iconSystemName
    }

    enum CodingKeys: String, CodingKey {
        case id, name, kind, iconSystemName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.kind = try container.decode(CustomCategoryKind.self, forKey: .kind)
        self.iconSystemName = try container.decodeIfPresent(String.self, forKey: .iconSystemName) ?? "tag.fill"
    }
}
