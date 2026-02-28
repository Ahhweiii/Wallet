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
    @State private var container: ModelContainer

    init() {
        let isPro = SubscriptionManager.hasICloudSync
        _container = State(initialValue: WalletApp.makeContainerWithRecovery(proEnabled: isPro))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }

    private static func makeContainerWithRecovery(proEnabled: Bool) -> ModelContainer {
        do {
            return try makeContainer(proEnabled: proEnabled)
        } catch {
            // Attempt a safe reset by deleting the local store and recreating.
            let didReset = resetLocalStore()
            UserDefaults.standard.set(didReset, forKey: "did_reset_store")
            do {
                return try makeContainer(proEnabled: proEnabled)
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }
    }

    private static func makeContainer(proEnabled: Bool) throws -> ModelContainer {
        let schema = Schema([Account.self, Transaction.self, FixedPayment.self, CustomCategory.self])
        let config = proEnabled
            ? ModelConfiguration(schema: schema, url: storeURL(), cloudKitDatabase: .automatic)
            : ModelConfiguration(schema: schema, url: storeURL())
        return try ModelContainer(
            for: schema,
            configurations: [config]
        )
    }

    private static func storeURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = dir.appendingPathComponent("Wallet", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("Wallet.store")
    }

    private static func resetLocalStore() -> Bool {
        let url = storeURL()
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return true
        } catch {
            return false
        }
    }
}
