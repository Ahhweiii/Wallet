//
//  BottomTabBarView.swift
//  Wallet
//
//  Created by Lee Jun Wei on 21/2/26.
//

import SwiftUI

struct BottomTabBarView: View {
    @Binding var selectedTab: Int

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
                .fill(Color(white: 0.10).opacity(0.95))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
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
            .foregroundStyle(selectedTab == index ? Color.blue : Color.white.opacity(0.75))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
