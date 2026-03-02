//
//  TransactionQuickAddDraftStore.swift
//  FrugalPilot
//
//  Created by Codex on 2/3/26.
//

import Foundation

struct TransactionQuickAddDraft: Codable {
    var typeRaw: String
    var amount: Decimal?
    var note: String
    var date: Date?
    var categoryName: String?
    var createdAt: Date

    init(typeRaw: String,
         amount: Decimal?,
         note: String,
         date: Date?,
         categoryName: String?,
         createdAt: Date = Date()) {
        self.typeRaw = typeRaw
        self.amount = amount
        self.note = note
        self.date = date
        self.categoryName = categoryName
        self.createdAt = createdAt
    }
}

enum TransactionQuickAddDraftStore {
    private static let pendingDraftKey = "pending_quick_add_transaction_draft_v1"
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func savePending(_ draft: TransactionQuickAddDraft) {
        guard let data = try? encoder.encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: pendingDraftKey)
    }

    static func consumePending() -> TransactionQuickAddDraft? {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: pendingDraftKey),
              let draft = try? decoder.decode(TransactionQuickAddDraft.self, from: data) else {
            return nil
        }
        defaults.removeObject(forKey: pendingDraftKey)
        return draft
    }
}
