//
//  FrugalPilotApp.swift
//  FrugalPilot
//
//  Created by Lee Jun Wei on 21/2/26.
//

import SwiftUI
import SwiftData

@main
struct FrugalPilotApp: App {
    @State private var container: ModelContainer?
    @State private var startupErrorMessage: String?
    private static let cloudSyncActiveKey = "cloud_sync_active"
    private static let cloudSyncLastErrorKey = "cloud_sync_last_error"

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    ContentView()
                        .modelContainer(container)
                } else {
                    startupView
                }
            }
            .task {
                SubscriptionManager.startTransactionUpdatesListener()
                await initializeContainerIfNeeded()
            }
        }
    }

    private var startupView: some View {
        ZStack {
            LinearGradient(colors: [Color.black, Color.gray.opacity(0.6)],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
            .ignoresSafeArea()

            VStack(spacing: 12) {
                if let startupErrorMessage {
                    Text("Could not start wallet storage.")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(startupErrorMessage)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 20)
                    Button {
                        Task { await retryContainerInitialization() }
                    } label: {
                        Text("Retry")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.2))
                            )
                    }
                    .buttonStyle(.plain)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                    Text("Preparing your wallet...")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
    }

    private func initializeContainerIfNeeded() async {
        guard container == nil else { return }
        startupErrorMessage = nil
        let preferCloudSync = SubscriptionManager.hasICloudSync
        let result = FrugalPilotApp.makeContainerWithRecovery(preferCloudSync: preferCloudSync)
        container = result.container
        startupErrorMessage = result.errorMessage
    }

    private func retryContainerInitialization() async {
        container = nil
        startupErrorMessage = nil
        await initializeContainerIfNeeded()
    }

    private static func makeContainerWithRecovery(preferCloudSync: Bool) -> (container: ModelContainer?, errorMessage: String?) {
        UserDefaults.standard.removeObject(forKey: cloudSyncLastErrorKey)
        var errors: [String] = []

        if preferCloudSync {
            do {
                let cloud = try makeContainer(useCloudKit: true)
                UserDefaults.standard.set(true, forKey: cloudSyncActiveKey)
                UserDefaults.standard.removeObject(forKey: cloudSyncLastErrorKey)
                return (cloud, nil)
            } catch {
                UserDefaults.standard.set(String(describing: error), forKey: cloudSyncLastErrorKey)
                errors.append("Cloud sync store unavailable.")
            }
        }

        UserDefaults.standard.set(false, forKey: cloudSyncActiveKey)
        do {
            let local = try makeContainer(useCloudKit: false)
            return (local, nil)
        } catch {
            errors.append("Local store unavailable.")
        }

        // Attempt a safe reset by deleting the local store and recreating.
        let didReset = resetLocalStore()
        UserDefaults.standard.set(didReset, forKey: "did_reset_store")
        do {
            let localAfterReset = try makeContainer(useCloudKit: false)
            return (localAfterReset, nil)
        } catch {
            errors.append("Local recovery failed.")
        }

        // Try SwiftData's default storage location as another recovery path.
        do {
            let defaultLocal = try makeDefaultContainer()
            return (defaultLocal, nil)
        } catch {
            errors.append("Default store unavailable.")
        }

        // Final fallback: keep app launchable even if persistent store is corrupted.
        do {
            let memory = try makeInMemoryContainer()
            return (memory, nil)
        } catch {
            errors.append("In-memory store unavailable.")
        }

        // Last resort: force reset once more then retry in-memory/default order.
        _ = resetLocalStore()
        do {
            let memoryAfterReset = try makeInMemoryContainer()
            return (memoryAfterReset, nil)
        } catch {
            errors.append("In-memory recovery failed.")
        }
        do {
            let defaultAfterReset = try makeDefaultContainer()
            return (defaultAfterReset, nil)
        } catch {
            errors.append("Default recovery failed.")
        }

        let message = errors.isEmpty
            ? "All storage initialization attempts failed."
            : errors.joined(separator: " ")
        return (nil, message)
    }

    private static func makeContainer(useCloudKit: Bool) throws -> ModelContainer {
        let schema = Schema([Account.self, Transaction.self, FixedPayment.self, CustomCategory.self])
        let config = useCloudKit
            ? ModelConfiguration(schema: schema, url: storeURL(), cloudKitDatabase: .automatic)
            : ModelConfiguration(schema: schema, url: storeURL(), cloudKitDatabase: .none)
        return try ModelContainer(
            for: schema,
            configurations: [config]
        )
    }

    private static func makeDefaultContainer() throws -> ModelContainer {
        let schema = Schema([Account.self, Transaction.self, FixedPayment.self, CustomCategory.self])
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([Account.self, Transaction.self, FixedPayment.self, CustomCategory.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private static func storeURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = dir.appendingPathComponent("FrugalPilot", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("FrugalPilot.store")
    }

    private static func resetLocalStore() -> Bool {
        let url = storeURL()
        let fm = FileManager.default
        do {
            // Remove SQLite store and sidecar files to recover from migration/corruption issues.
            let candidates = [
                url,
                URL(fileURLWithPath: url.path + "-shm"),
                URL(fileURLWithPath: url.path + "-wal")
            ]
            for fileURL in candidates where fm.fileExists(atPath: fileURL.path) {
                try fm.removeItem(at: fileURL)
            }
            return true
        } catch {
            return false
        }
    }

}
