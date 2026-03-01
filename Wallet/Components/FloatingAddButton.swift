//
//  FloatingAddButton.swift
//  FrugalPilot
//
//  Created by Lee Jun Wei on 23/2/26.
//

import SwiftUI

struct FloatingAddButton: View {
    let onTap: () -> Void
    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(theme.accent)
                .clipShape(Circle())
                .shadow(color: theme.accent.opacity(0.35), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}
