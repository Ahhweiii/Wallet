//
//  AutomationSetupScreen.swift
//  FrugalPilot
//
//  Created by Codex on 2/3/26.
//

import SwiftUI
import UIKit

struct AutomationSetupScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @AppStorage("theme_is_dark") private var themeIsDark: Bool = true

    @State private var copiedMessage: String?

    private let deepLinks: [(title: String, url: String)] = [
        (
            "Expense with amount + note",
            "frugalpilot://add-transaction?type=Expense&amount=264.87&note=Clinic%20payment"
        ),
        (
            "Expense with date",
            "frugalpilot://add-transaction?type=Expense&amount=12.30&note=Coffee&date=2026-03-02"
        ),
        (
            "Income example",
            "frugalpilot://add-transaction?type=Income&amount=1200&note=Freelance%20payout"
        )
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundGradient.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionCard("Quick Add Links") {
                            Text("Reusable links for quick transaction entry.")
                                .font(.custom("Avenir Next", size: 12))
                                .foregroundStyle(theme.textSecondary)

                            ForEach(deepLinks, id: \.title) { item in
                                copyableURLRow(title: item.title, url: item.url)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Automation Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(themeIsDark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(theme.textPrimary)
                }
            }
        }
        .alert("Copied", isPresented: Binding(
            get: { copiedMessage != nil },
            set: { if !$0 { copiedMessage = nil } }
        )) {
            Button("OK", role: .cancel) { copiedMessage = nil }
        } message: {
            Text(copiedMessage ?? "")
        }
    }

    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.custom("Avenir Next", size: 14).weight(.bold))
                .foregroundStyle(theme.textPrimary)
            content()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.surface))
    }

    private func copyableURLRow(title: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.custom("Avenir Next", size: 12).weight(.semibold))
                .foregroundStyle(theme.textPrimary)
            Text(url)
                .font(.custom("Menlo", size: 11))
                .foregroundStyle(theme.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(theme.surfaceAlt))

            Button {
                UIPasteboard.general.string = url
                copiedMessage = "Deep link copied to clipboard."
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                    Text("Copy Link")
                        .font(.custom("Avenir Next", size: 12).weight(.semibold))
                }
                .foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }
}
