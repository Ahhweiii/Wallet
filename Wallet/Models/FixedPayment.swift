//
//  FixedPayment.swift
//  FrugalPilot
//
//  Created by Codex on 27/2/26.
//

import Foundation
import SwiftData

enum FixedPaymentType: String, CaseIterable, Identifiable, Hashable, Codable {
    case installment = "Installment"
    case subscription = "Subscription"
    case insurance = "Insurance"
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
    var id: UUID = UUID()
    var name: String = ""
    var amount: Decimal = 0
    var outstandingAmount: Decimal?
    var type: FixedPaymentType = FixedPaymentType.other
    var typeName: String = ""
    var frequency: FixedPaymentFrequency = FixedPaymentFrequency.monthly
    var startDate: Date = Date()
    var endDate: Date?
    var cycles: Int?
    var chargeAccountId: UUID?
    var chargeDay: Int?
    var chargeDate: Date?
    var lastChargedAt: Date?
    var profileName: String = "Personal"
    var note: String = ""

    init(id: UUID = UUID(),
         name: String,
         amount: Decimal,
         outstandingAmount: Decimal? = nil,
         type: FixedPaymentType,
         typeName: String = "",
         frequency: FixedPaymentFrequency,
         startDate: Date = Date(),
         endDate: Date? = nil,
         cycles: Int? = nil,
         chargeAccountId: UUID? = nil,
         chargeDay: Int? = nil,
         chargeDate: Date? = nil,
         lastChargedAt: Date? = nil,
         profileName: String = "Personal",
         note: String = "") {
        self.id = id
        self.name = name
        self.amount = amount
        self.outstandingAmount = outstandingAmount
        self.type = type
        self.typeName = typeName
        self.frequency = frequency
        self.startDate = startDate
        self.endDate = endDate
        self.cycles = cycles
        self.chargeAccountId = chargeAccountId
        self.chargeDay = chargeDay
        self.chargeDate = chargeDate
        self.lastChargedAt = lastChargedAt
        self.profileName = profileName
        self.note = note
    }

    static func == (lhs: FixedPayment, rhs: FixedPayment) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
