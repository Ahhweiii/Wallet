//
//  QuickAddTransactionIntent.swift
//  FrugalPilot
//
//  Created by Codex on 2/3/26.
//

import Foundation
import AppIntents

enum QuickAddTransactionType: String, AppEnum {
    case expense
    case income

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Transaction Type")
    static var caseDisplayRepresentations: [QuickAddTransactionType: DisplayRepresentation] = [
        .expense: DisplayRepresentation(title: "Expense"),
        .income: DisplayRepresentation(title: "Income")
    ]
}

struct QuickAddTransactionIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Add Transaction"
    static var description = IntentDescription("Create a prefilled transaction draft and open FrugalPilot to confirm/save.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Type", default: .expense)
    var type: QuickAddTransactionType

    @Parameter(title: "Amount")
    var amount: Double?

    @Parameter(title: "Merchant")
    var merchant: String?

    @Parameter(title: "Note")
    var note: String?

    @Parameter(title: "Date")
    var date: Date?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let merchantText = merchant?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let noteText = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let composedNote: String = {
            if !merchantText.isEmpty, !noteText.isEmpty { return "\(merchantText) • \(noteText)" }
            if !merchantText.isEmpty { return merchantText }
            return noteText
        }()

        var components = URLComponents()
        components.scheme = "frugalpilot"
        components.host = "add-transaction"
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "type", value: type.rawValue.capitalized)
        ]
        if let amount {
            queryItems.append(URLQueryItem(name: "amount", value: String(amount)))
        }
        if !composedNote.isEmpty {
            queryItems.append(URLQueryItem(name: "note", value: composedNote))
        }
        if let date {
            queryItems.append(URLQueryItem(name: "date", value: ISO8601DateFormatter().string(from: date)))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            return .result(dialog: "Could not open FrugalPilot quick add.")
        }

        return .result(
            opensIntent: OpenURLIntent(url),
            dialog: "Opening FrugalPilot with a prefilled transaction draft."
        )
    }
}

struct FrugalPilotAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickAddTransactionIntent(),
            phrases: [
                "Quick add transaction in \(.applicationName)",
                "Add expense in \(.applicationName)"
            ],
            shortTitle: "Quick Add",
            systemImageName: "plus.circle.fill"
        )
    }
}
