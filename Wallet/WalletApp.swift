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
    private static let cloudSyncActiveKey = "cloud_sync_active"
    private static let containerInitLogKey = "container_init_log"

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
                guard container == nil else { return }
                let preferCloudSync = SubscriptionManager.hasICloudSync
                container = FrugalPilotApp.makeContainerWithRecovery(preferCloudSync: preferCloudSync)
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
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                Text("Preparing your wallet...")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private static func makeContainerWithRecovery(preferCloudSync: Bool) -> ModelContainer {
        clearContainerInitLog()

        if preferCloudSync {
            do {
                let cloud = try makeContainer(useCloudKit: true)
                UserDefaults.standard.set(true, forKey: cloudSyncActiveKey)
                appendContainerLog("SUCCESS cloud container")
                return cloud
            } catch {
                appendContainerLog("FAIL cloud container: \(String(describing: error))")
            }
        } else {
            appendContainerLog("SKIP cloud container (preferCloudSync=false)")
        }

        UserDefaults.standard.set(false, forKey: cloudSyncActiveKey)
        do {
            let local = try makeContainer(useCloudKit: false)
            appendContainerLog("SUCCESS local container")
            return local
        } catch {
            appendContainerLog("FAIL local container: \(String(describing: error))")
        }

        // Attempt a safe reset by deleting the local store and recreating.
        let didReset = resetLocalStore()
        UserDefaults.standard.set(didReset, forKey: "did_reset_store")
        appendContainerLog("RESET local store: \(didReset ? "done" : "failed")")
        do {
            let localAfterReset = try makeContainer(useCloudKit: false)
            appendContainerLog("SUCCESS local container after reset")
            return localAfterReset
        } catch {
            appendContainerLog("FAIL local container after reset: \(String(describing: error))")
        }

        // Try SwiftData's default storage location as another recovery path.
        do {
            let defaultLocal = try makeDefaultContainer()
            appendContainerLog("SUCCESS default local container")
            return defaultLocal
        } catch {
            appendContainerLog("FAIL default local container: \(String(describing: error))")
        }

        // Final fallback: keep app launchable even if persistent store is corrupted.
        do {
            let memory = try makeInMemoryContainer()
            appendContainerLog("SUCCESS in-memory container")
            return memory
        } catch {
            appendContainerLog("FAIL in-memory container: \(String(describing: error))")
        }

        // Last resort: force reset once more then retry in-memory/default order.
        let didResetAgain = resetLocalStore()
        appendContainerLog("RESET local store again: \(didResetAgain ? "done" : "failed")")
        do {
            let memoryAfterReset = try makeInMemoryContainer()
            appendContainerLog("SUCCESS in-memory container after reset")
            return memoryAfterReset
        } catch {
            appendContainerLog("FAIL in-memory container after reset: \(String(describing: error))")
        }
        do {
            let defaultAfterReset = try makeDefaultContainer()
            appendContainerLog("SUCCESS default local container after reset")
            return defaultAfterReset
        } catch {
            appendContainerLog("FAIL default local container after reset: \(String(describing: error))")
        }

        appendContainerLog("FATAL all container initialization attempts failed")
        fatalError("Failed to create any ModelContainer after all recovery attempts.")
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

    private static func clearContainerInitLog() {
        UserDefaults.standard.removeObject(forKey: containerInitLogKey)
    }

    private static func appendContainerLog(_ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] \(message)"
        var logs = UserDefaults.standard.stringArray(forKey: containerInitLogKey) ?? []
        logs.append(line)
        UserDefaults.standard.set(logs, forKey: containerInitLogKey)
        print("ContainerInit:", line)
    }
}
