//
//  SmartDataStore.swift
//  FrugalPilot
//
//  Created by Codex on 1/3/26.
//

import Foundation

struct AutoCategoryRuleData: Identifiable, Codable, Hashable {
    var id: UUID
    var keyword: String
    var categoryName: String
    var transactionTypeRaw: String
    var profileName: String

    init(id: UUID = UUID(),
         keyword: String,
         categoryName: String,
         transactionTypeRaw: String,
         profileName: String = "Personal") {
        self.id = id
        self.keyword = keyword
        self.categoryName = categoryName
        self.transactionTypeRaw = transactionTypeRaw
        self.profileName = profileName
    }
}

struct BudgetEnvelopeData: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var categoryName: String
    var monthlyLimit: Decimal
    var profileName: String

    init(id: UUID = UUID(),
         name: String,
         categoryName: String,
         monthlyLimit: Decimal,
         profileName: String = "Personal") {
        self.id = id
        self.name = name
        self.categoryName = categoryName
        self.monthlyLimit = monthlyLimit
        self.profileName = profileName
    }
}

struct SavingsGoalData: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var targetAmount: Decimal
    var savedAmount: Decimal
    var targetDate: Date?
    var profileName: String

    init(id: UUID = UUID(),
         name: String,
         targetAmount: Decimal,
         savedAmount: Decimal,
         targetDate: Date? = nil,
         profileName: String = "Personal") {
        self.id = id
        self.name = name
        self.targetAmount = targetAmount
        self.savedAmount = savedAmount
        self.targetDate = targetDate
        self.profileName = profileName
    }
}

struct BillReminderData: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var amount: Decimal
    var chargeDay: Int
    var accountId: UUID?
    var isEnabled: Bool
    var profileName: String

    init(id: UUID = UUID(),
         title: String,
         amount: Decimal,
         chargeDay: Int,
         accountId: UUID? = nil,
         isEnabled: Bool = true,
         profileName: String = "Personal") {
        self.id = id
        self.title = title
        self.amount = amount
        self.chargeDay = min(max(chargeDay, 1), 31)
        self.accountId = accountId
        self.isEnabled = isEnabled
        self.profileName = profileName
    }
}

enum SmartDataStore {
    private static let rulesKey = "smart_auto_category_rules_v1"
    private static let budgetsKey = "smart_budget_envelopes_v1"
    private static let goalsKey = "smart_savings_goals_v1"
    private static let remindersKey = "smart_bill_reminders_v1"

    private static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()

    private static let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    static func loadRules() -> [AutoCategoryRuleData] {
        decode([AutoCategoryRuleData].self, key: rulesKey) ?? []
    }

    static func saveRules(_ rules: [AutoCategoryRuleData]) {
        encode(rules, key: rulesKey)
    }

    static func loadBudgets() -> [BudgetEnvelopeData] {
        decode([BudgetEnvelopeData].self, key: budgetsKey) ?? []
    }

    static func saveBudgets(_ budgets: [BudgetEnvelopeData]) {
        encode(budgets, key: budgetsKey)
    }

    static func loadGoals() -> [SavingsGoalData] {
        decode([SavingsGoalData].self, key: goalsKey) ?? []
    }

    static func saveGoals(_ goals: [SavingsGoalData]) {
        encode(goals, key: goalsKey)
    }

    static func loadReminders() -> [BillReminderData] {
        decode([BillReminderData].self, key: remindersKey) ?? []
    }

    static func saveReminders(_ reminders: [BillReminderData]) {
        encode(reminders, key: remindersKey)
    }

    private static func encode<T: Encodable>(_ value: T, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
