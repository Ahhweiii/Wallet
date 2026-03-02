//
//  ContentView.swift
//  FrugalPilot
//
//  Created by Lee Jun Wei on 21/2/26.
//

import SwiftUI
import SwiftData
import LocalAuthentication
import AuthenticationServices

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("theme_is_dark") private var themeIsDark: Bool = true
    @AppStorage("did_reset_store") private var didResetStore: Bool = false
    @AppStorage("app_lock_enabled") private var appLockEnabled: Bool = false
    @AppStorage("apple_user_id") private var appleUserId: String = ""
    @AppStorage("apple_user_name") private var appleUserName: String = ""
    @Environment(\.scenePhase) private var scenePhase

    @State private var isUnlocked: Bool = true
    @State private var showLockError: Bool = false
    @State private var showAppleSignInError: Bool = false
    @State private var appleSignInErrorMessage: String = "Unable to sign in with Apple ID."
    @State private var biometryType: LABiometryType = .none

    private var theme: AppTheme {
        AppTheme.palette(isDark: themeIsDark)
    }

    var body: some View {
        ZStack {
            if appleUserId.isEmpty {
                appleSignInGate
                    .preferredColorScheme(themeIsDark ? .dark : .light)
            } else {
                DashboardScreen(modelContext: modelContext)
                    .environment(\.appTheme, theme)
                    .preferredColorScheme(themeIsDark ? .dark : .light)
                    .alert("Data Reset", isPresented: $didResetStore) {
                        Button("OK", role: .cancel) { }
                    } message: {
                        Text("We had to reset local data to complete a migration.")
                    }
            }

            if appLockEnabled && !isUnlocked {
                VStack(spacing: 16) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.white)
                    Text("Unlock to continue")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Button(unlockButtonTitle) {
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
            refreshBiometryType()
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
        .alert("Apple ID Sign-In Failed", isPresented: $showAppleSignInError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(appleSignInErrorMessage)
        }
    }

    private func authenticate() {
        let context = LAContext()
        var error: NSError?
        let reason = biometryType == .faceID ? "Unlock FrugalPilot with Face ID" : "Unlock FrugalPilot"

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                DispatchQueue.main.async {
                    if success {
                        isUnlocked = true
                    } else {
                        showLockError = true
                    }
                }
            }
        } else if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
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

    private var unlockButtonTitle: String {
        switch biometryType {
        case .faceID: return "Unlock with Face ID"
        case .touchID: return "Unlock with Touch ID"
        default: return "Unlock"
        }
    }

    private func refreshBiometryType() {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        biometryType = context.biometryType
    }

    private var appleSignInGate: some View {
        ZStack {
            theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)

                Text("Sign In Required")
                    .font(.custom("Avenir Next", size: 22).weight(.bold))
                    .foregroundStyle(theme.textPrimary)

                Text("Sign in with Apple to continue to FrugalPilot.")
                    .font(.custom("Avenir Next", size: 13).weight(.medium))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                SignInWithAppleButton(.signIn, onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                }, onCompletion: handleAppleSignInResult)
                .signInWithAppleButtonStyle(themeIsDark ? .white : .black)
                .frame(height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.top, 6)
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(theme.surface)
            )
            .padding(.horizontal, 24)
        }
    }

    private func handleAppleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                appleSignInErrorMessage = "Unable to sign in with Apple ID."
                showAppleSignInError = true
                return
            }
            appleUserId = credential.user

            let formatter = PersonNameComponentsFormatter()
            let name = formatter.string(from: credential.fullName ?? PersonNameComponents())
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                appleUserName = name
            } else if appleUserName.isEmpty {
                appleUserName = "Apple User"
            }
        case .failure(let error):
            appleSignInErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showAppleSignInError = true
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Account.self, Transaction.self, configurations: config)
    ContentView()
        .modelContainer(container)
}
