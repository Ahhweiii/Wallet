//
//  Transaction.swift
//  Wallet
//
//  Created by Lee Jun Wei on 23/2/26.
//

import Foundation
import SwiftData

enum TransactionType: String, CaseIterable, Identifiable, Hashable, Codable {
    case expense = "Expense"
    case income = "Income"
    var id: String { rawValue }
}

enum TransactionCategory: String, CaseIterable, Identifiable, Hashable, Codable {
    case food = "Food & Drinks"
    case transport = "Transport"
    case shopping = "Shopping"
    case entertainment = "Entertainment"
    case bills = "Bills & Utilities"
    case health = "Health"
    case education = "Education"
    case travel = "Travel"
    case groceries = "Groceries"
    case salary = "Salary"
    case freelance = "Freelance"
    case investment = "Investment"
    case gift = "Gift"
    case other = "Other"

    var id: String { rawValue }

    var iconSystemName: String {
        switch self {
        case .food: return "fork.knife"
        case .transport: return "car.fill"
        case .shopping: return "bag.fill"
        case .entertainment: return "tv.fill"
        case .bills: return "bolt.fill"
        case .health: return "heart.fill"
        case .education: return "book.fill"
        case .travel: return "airplane"
        case .groceries: return "cart.fill"
        case .salary: return "banknote"
        case .freelance: return "laptopcomputer"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .gift: return "gift.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }

    static var expenseCategories: [TransactionCategory] {
        [.food, .transport, .shopping, .entertainment, .bills, .health, .education, .travel, .groceries, .other]
    }

    static var incomeCategories: [TransactionCategory] {
        [.salary, .freelance, .investment, .gift, .other]
    }
}

@Model
final class Transaction: Identifiable, Hashable {
    @Attribute(.unique) var id: UUID
    var type: TransactionType
    var amount: Decimal
    var accountId: UUID
    var category: TransactionCategory
    var date: Date
    var note: String

    init(id: UUID = UUID(),
         type: TransactionType,
         amount: Decimal,
         accountId: UUID,
         category: TransactionCategory,
         date: Date,
         note: String = "") {
        self.id = id
        self.type = type
        self.amount = amount
        self.accountId = accountId
        self.category = category
        self.date = date
        self.note = note
    }

    static func == (lhs: Transaction, rhs: Transaction) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
