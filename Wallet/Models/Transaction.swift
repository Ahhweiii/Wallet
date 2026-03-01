//
//  Transaction.swift
//  LedgerFlow
//
//  Created by Lee Jun Wei on 23/2/26.
//

import Foundation
import SwiftData

enum TransactionType: String, CaseIterable, Identifiable, Hashable, Codable {
    case expense = "Expense"
    case income = "Income"
    case transfer = "Transfer"
    var id: String { rawValue }
}

enum CategoryPreset: String, CaseIterable, Identifiable, Hashable, Codable {
    case singapore = "Singapore"
    case generic = "Generic"
    case minimal = "Minimal"
    var id: String { rawValue }
}

enum TransactionCategory: String, CaseIterable, Identifiable, Hashable, Codable {
    case food = "Food & Drinks"
    case hawker = "Hawker & Kopitiam"
    case groceries = "Groceries"
    case transportPublic = "MRT/Bus"
    case transportPrivate = "Car/Taxi/Grab"
    case housing = "Housing (Rent/Mortgage)"
    case utilities = "Utilities"
    case telco = "Telco/Internet"
    case insurance = "Insurance"
    case family = "Family/Children"
    case subscriptions = "Subscriptions"
    case donations = "Donations"
    case transport = "Transport"
    case shopping = "Shopping"
    case entertainment = "Entertainment"
    case bills = "Bills & Utilities"
    case health = "Health"
    case education = "Education"
    case travel = "Travel"
    case salary = "Salary"
    case bonus = "Bonus"
    case freelance = "Freelance"
    case investment = "Investment"
    case dividends = "Dividends"
    case interest = "Interest"
    case rental = "Rental Income"
    case gift = "Gift"
    case other = "Other"

    var id: String { rawValue }

    var iconSystemName: String {
        switch self {
        case .food: return "fork.knife"
        case .hawker: return "fork.knife"
        case .groceries: return "cart.fill"
        case .transportPublic: return "bus.fill"
        case .transportPrivate: return "car.fill"
        case .housing: return "house.fill"
        case .utilities: return "bolt.fill"
        case .telco: return "antenna.radiowaves.left.and.right"
        case .insurance: return "shield.fill"
        case .family: return "figure.2.and.child.holdinghands"
        case .subscriptions: return "arrow.triangle.2.circlepath.circle.fill"
        case .donations: return "hand.raised.fill"
        case .transport: return "car.fill"
        case .shopping: return "bag.fill"
        case .entertainment: return "tv.fill"
        case .bills: return "bolt.fill"
        case .health: return "heart.fill"
        case .education: return "book.fill"
        case .travel: return "airplane"
        case .salary: return "banknote"
        case .bonus: return "star.fill"
        case .freelance: return "laptopcomputer"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .dividends: return "chart.bar.fill"
        case .interest: return "percent"
        case .rental: return "house.fill"
        case .gift: return "gift.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }

    static func iconSystemName(for name: String) -> String {
        if let match = TransactionCategory.from(name: name) {
            return match.iconSystemName
        }
        return "tag.fill"
    }

    static func from(name: String) -> TransactionCategory? {
        TransactionCategory.allCases.first(where: { $0.rawValue == name })
    }

    static var expenseCategories: [TransactionCategory] {
        [
            .hawker,
            .food,
            .groceries,
            .transportPublic,
            .transportPrivate,
            .housing,
            .utilities,
            .telco,
            .insurance,
            .health,
            .education,
            .family,
            .shopping,
            .entertainment,
            .subscriptions,
            .donations,
            .travel,
            .other,
            .transport,
            .bills
        ]
    }

    static var incomeCategories: [TransactionCategory] {
        [.salary, .bonus, .freelance, .investment, .dividends, .interest, .rental, .gift, .other]
    }

    static var sgEssentialExpenseCategories: [TransactionCategory] {
        [
            .hawker,
            .food,
            .groceries,
            .transportPublic,
            .transportPrivate,
            .housing,
            .utilities,
            .telco,
            .insurance,
            .health,
            .family,
            .education
        ]
    }

    static var lifestyleExpenseCategories: [TransactionCategory] {
        [
            .shopping,
            .entertainment,
            .subscriptions,
            .donations,
            .travel,
            .other
        ]
    }

    // Keep legacy categories selectable to preserve compatibility with older data/backups.
    static var legacyExpenseCategories: [TransactionCategory] {
        [.transport, .bills]
    }
}

@Model
final class Transaction: Identifiable, Hashable {
    @Attribute(.unique) var id: UUID
    var type: TransactionType
    var amount: Decimal
    var accountId: UUID
    var category: TransactionCategory?
    var categoryName: String
    var date: Date
    var note: String

    init(id: UUID = UUID(),
         type: TransactionType,
         amount: Decimal,
         accountId: UUID,
         categoryName: String,
         category: TransactionCategory? = nil,
         date: Date,
         note: String = "") {
        self.id = id
        self.type = type
        self.amount = amount
        self.accountId = accountId
        self.categoryName = categoryName
        self.category = category
        self.date = date
        self.note = note
    }

    static func == (lhs: Transaction, rhs: Transaction) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
