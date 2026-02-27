//
//  WalletBackupService.swift
//  Wallet
//
//  Created by Lee Jun Wei on 26/2/26.
//

import Foundation
import SwiftData

enum WalletImportStrategy {
    case merge
    case replaceAll
}

enum WalletBackupError: Error, LocalizedError {
    case unsupportedVersion(Int)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let v):
            return "Unsupported backup version: \(v)"
        case .invalidData:
            return "Invalid backup file."
        }
    }
}

enum WalletBackupService {

    // ✅ MainActor because we read SwiftData @Model objects
    @MainActor
    static func exportJSON(accounts: [Account], transactions: [Transaction]) throws -> Data {
        let file = WalletBackupFile(
            accounts: accounts.map(AccountDTO.init(from:)),
            transactions: transactions.map(TransactionDTO.init(from:))
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }

    static func decodeBackup(from data: Data) throws -> WalletBackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(WalletBackupFile.self, from: data)

        guard file.version == WalletBackupFile.currentVersion else {
            throw WalletBackupError.unsupportedVersion(file.version)
        }
        return file
    }

    @MainActor
    static func `import`(_ file: WalletBackupFile,
                        into modelContext: ModelContext,
                        strategy: WalletImportStrategy) throws {
        if case .replaceAll = strategy {
            try deleteAll(modelContext: modelContext)
        }

        let existingAccounts = try modelContext.fetch(FetchDescriptor<Account>())
        let existingTransactions = try modelContext.fetch(FetchDescriptor<Transaction>())

        var accountById: [UUID: Account] = Dictionary(uniqueKeysWithValues: existingAccounts.map { ($0.id, $0) })
        var txnById: [UUID: Transaction] = Dictionary(uniqueKeysWithValues: existingTransactions.map { ($0.id, $0) })

        for dto in file.accounts {
            if let existing = accountById[dto.id] {
                existing.bankName = dto.bankName
                existing.accountName = dto.accountName
                existing.currentCredit = dto.currentCredit
                existing.amount = dto.amount
                existing.type = dto.type
                existing.colorHex = dto.colorHex
                existing.iconSystemName = dto.iconSystemName
                existing.isInCombinedCreditPool = dto.isInCombinedCreditPool
            } else {
                let new = Account(
                    id: dto.id,
                    bankName: dto.bankName,
                    accountName: dto.accountName,
                    currentCredit: dto.currentCredit,
                    amount: dto.amount,
                    type: dto.type,
                    colorHex: dto.colorHex,
                    iconSystemName: dto.iconSystemName,
                    isInCombinedCreditPool: dto.isInCombinedCreditPool
                )
                modelContext.insert(new)
                accountById[dto.id] = new
            }
        }

        for dto in file.transactions {
            if let existing = txnById[dto.id] {
                existing.type = dto.type
                existing.amount = dto.amount
                existing.accountId = dto.accountId
                existing.category = dto.category
                existing.date = dto.date
                existing.note = dto.note
            } else {
                let new = Transaction(
                    id: dto.id,
                    type: dto.type,
                    amount: dto.amount,
                    accountId: dto.accountId,
                    category: dto.category,
                    date: dto.date,
                    note: dto.note
                )
                modelContext.insert(new)
                txnById[dto.id] = new
            }
        }

        try modelContext.save()
    }

    @MainActor
    private static func deleteAll(modelContext: ModelContext) throws {
        let txns = try modelContext.fetch(FetchDescriptor<Transaction>())
        for t in txns { modelContext.delete(t) }

        let accts = try modelContext.fetch(FetchDescriptor<Account>())
        for a in accts { modelContext.delete(a) }

        try modelContext.save()
    }
}
