//
//  ContentView.swift
//  Wallet
//
//  Created by Lee Jun Wei on 21/2/26.
//

import SwiftUI
import SwiftData
import LocalAuthentication

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("theme_is_dark") private var themeIsDark: Bool = true
    @AppStorage("did_reset_store") private var didResetStore: Bool = false
    @AppStorage("app_lock_enabled") private var appLockEnabled: Bool = false
    @Environment(\.scenePhase) private var scenePhase

    @State private var isUnlocked: Bool = true
    @State private var showLockError: Bool = false

    private var theme: AppTheme {
        AppTheme.palette(isDark: themeIsDark)
    }

    var body: some View {
        ZStack {
            DashboardScreen(modelContext: modelContext)
                .environment(\.appTheme, theme)
                .preferredColorScheme(themeIsDark ? .dark : .light)
                .alert("Data Reset", isPresented: $didResetStore) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("We had to reset local data to complete a migration.")
                }

            if appLockEnabled && !isUnlocked {
                VStack(spacing: 16) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.white)
                    Text("Unlock to continue")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Button("Unlock") {
                        authenticate()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.15)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.85).ignoresSafeArea())
            }
        }
        .onAppear {
            if appLockEnabled {
                isUnlocked = false
                authenticate()
            }
        }
        .onChange(of: appLockEnabled) { _, enabled in
            if enabled {
                isUnlocked = false
                authenticate()
            } else {
                isUnlocked = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if !appLockEnabled { return }
            if phase == .background {
                isUnlocked = false
            } else if phase == .active, !isUnlocked {
                authenticate()
            }
        }
        .alert("Unlock Failed", isPresented: $showLockError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Unable to verify your identity. Please try again.")
        }
    }

    private func authenticate() {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Wallet") { success, _ in
                DispatchQueue.main.async {
                    if success {
                        isUnlocked = true
                    } else {
                        showLockError = true
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                showLockError = true
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Account.self, Transaction.self, configurations: config)
    ContentView()
        .modelContainer(container)
}
