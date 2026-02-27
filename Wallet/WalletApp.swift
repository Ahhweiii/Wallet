//
//  WalletApp.swift
//  Wallet
//
//  Created by Lee Jun Wei on 21/2/26.
//

import SwiftUI
import SwiftData

@main
struct WalletApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(makeContainer())
    }

    private func makeContainer() -> ModelContainer {
        do {
            let schema = Schema([Account.self, Transaction.self])
            let config = ModelConfiguration(schema: schema)
            return try ModelContainer(
                for: schema,
                configurations: [config]
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
