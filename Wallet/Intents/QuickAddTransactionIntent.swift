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

        let decimalAmount: Decimal? = amount.map { Decimal($0) }
        await MainActor.run {
            let draft = TransactionQuickAddDraft(
                typeRaw: type.rawValue.capitalized,
                amount: decimalAmount,
                note: composedNote,
                date: date,
                categoryName: nil
            )
            TransactionQuickAddDraftStore.savePending(draft)
        }

        return .result(dialog: "Draft prepared. Review and save it in FrugalPilot.")
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
