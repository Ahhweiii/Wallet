//
//  CustomCategory.swift
//  LedgerFlow
//
//  Created by Codex on 27/2/26.
//

import Foundation
import SwiftData

enum CustomCategoryKind: String, CaseIterable, Identifiable, Hashable, Codable {
    case expense = "Expense"
    case income = "Income"
    case fixedPayment = "Fixed Payment"
    var id: String { rawValue }
}

@Model
final class CustomCategory: Identifiable, Hashable {
    @Attribute(.unique) var id: UUID
    var name: String
    var kind: CustomCategoryKind
    var iconSystemName: String

    init(id: UUID = UUID(), name: String, kind: CustomCategoryKind, iconSystemName: String = "tag.fill") {
        self.id = id
        self.name = name
        self.kind = kind
        self.iconSystemName = iconSystemName
    }

    static func == (lhs: CustomCategory, rhs: CustomCategory) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
