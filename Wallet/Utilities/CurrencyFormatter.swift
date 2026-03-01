//
//  CurrencyFormatter.swift
//  LedgerFlow
//
//  Created by Lee Jun Wei on 21/2/26.
//

import Foundation

enum CurrencyFormatter {
    static let sgdFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "SGD"
        formatter.locale = Locale(identifier: "en_SG")
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }()

    static func sgd(amount: Decimal) -> String {
        sgdFormatter.string(from: amount as NSDecimalNumber) ?? "S$0.00"
    }
}

