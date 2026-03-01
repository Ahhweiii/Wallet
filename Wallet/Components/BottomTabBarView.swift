//
//  BottomTabBarView.swift
//  LedgerFlow
//
//  Created by Lee Jun Wei on 21/2/26.
//

import SwiftUI

struct BottomTabBarView: View {
    @Binding var selectedTab: Int
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            tabItem(index: 0, title: "Dashboard", icon: "dollarsign.circle")
            tabItem(index: 1, title: "Planning", icon: "clock")
            tabItem(index: 2, title: "Statistics", icon: "chart.bar")
            tabItem(index: 3, title: "More", icon: "ellipsis")
        }
        .padding(10)
        .background(
            Capsule(style: .continuous)
                .fill(theme.surface)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(theme.divider, lineWidth: 1)
        )
    }

    private func tabItem(index: Int, title: String, icon: String) -> some View {
        Button {
            selectedTab = index
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(selectedTab == index ? theme.accent : theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
