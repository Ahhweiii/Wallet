//
//  AppTheme.swift
//  Wallet
//
//  Created by Codex on 27/2/26.
//

import SwiftUI

struct AppTheme: Equatable {
    let isDark: Bool

    let background: Color
    let backgroundAlt: Color
    let surface: Color
    let surfaceAlt: Color
    let card: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let accent: Color
    let accentSoft: Color
    let divider: Color
    let positive: Color
    let negative: Color
    let shadow: Color

    var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [background, backgroundAlt],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func palette(isDark: Bool) -> AppTheme {
        if isDark {
            return AppTheme(
                isDark: true,
                background: Color(hex: "#0E0F11"),
                backgroundAlt: Color(hex: "#15161A"),
                surface: Color(hex: "#15161A"),
                surfaceAlt: Color(hex: "#1B1D22"),
                card: Color(hex: "#1C1D21"),
                textPrimary: Color(hex: "#F5F5F5"),
                textSecondary: Color(hex: "#C3C6CC"),
                textTertiary: Color(hex: "#8B9099"),
                accent: Color(hex: "#2A6F6A"),
                accentSoft: Color(hex: "#2A6F6A").opacity(0.18),
                divider: Color.white.opacity(0.08),
                positive: Color(hex: "#2BB673"),
                negative: Color(hex: "#E2554F"),
                shadow: Color.black.opacity(0.35)
            )
        }

        return AppTheme(
            isDark: false,
            background: Color(hex: "#F6F5F2"),
            backgroundAlt: Color(hex: "#EEECE7"),
            surface: Color.white,
            surfaceAlt: Color(hex: "#F2F1EE"),
            card: Color.white,
            textPrimary: Color(hex: "#141414"),
            textSecondary: Color(hex: "#4F545B"),
            textTertiary: Color(hex: "#80868F"),
            accent: Color(hex: "#2A6F6A"),
            accentSoft: Color(hex: "#2A6F6A").opacity(0.12),
            divider: Color.black.opacity(0.06),
            positive: Color(hex: "#1E8E5A"),
            negative: Color(hex: "#C03D36"),
            shadow: Color.black.opacity(0.08)
        )
    }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.palette(isDark: true)
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}
