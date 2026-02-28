//
//  FixedPayment.swift
//  Wallet
//
//  Created by Codex on 27/2/26.
//

import Foundation
import SwiftData

enum FixedPaymentType: String, CaseIterable, Identifiable, Hashable, Codable {
    case installment = "Installment"
    case subscription = "Subscription"
    case allowance = "Allowance"
    case other = "Other"
    var id: String { rawValue }
}

enum FixedPaymentFrequency: String, CaseIterable, Identifiable, Hashable, Codable {
    case weekly = "Weekly"
    case monthly = "Monthly"
    case yearly = "Yearly"
    var id: String { rawValue }
}

@Model
final class FixedPayment: Identifiable, Hashable {
    @Attribute(.unique) var id: UUID
    var name: String
    var amount: Decimal
    var type: FixedPaymentType
    var typeName: String
    var frequency: FixedPaymentFrequency
    var startDate: Date
    var endDate: Date?
    var cycles: Int?
    var note: String

    init(id: UUID = UUID(),
         name: String,
         amount: Decimal,
         type: FixedPaymentType,
         typeName: String = "",
         frequency: FixedPaymentFrequency,
         startDate: Date = Date(),
         endDate: Date? = nil,
         cycles: Int? = nil,
         note: String = "") {
        self.id = id
        self.name = name
        self.amount = amount
        self.type = type
        self.typeName = typeName
        self.frequency = frequency
        self.startDate = startDate
        self.endDate = endDate
        self.cycles = cycles
        self.note = note
    }

    static func == (lhs: FixedPayment, rhs: FixedPayment) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
