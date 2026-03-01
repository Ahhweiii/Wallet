//
//  PageDotsView.swift
//  LedgerFlow
//
//  Created by Lee Jun Wei on 21/2/26.
//

import SwiftUI

struct PageDotsView: View {
    let count: Int
    let index: Int
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<max(count, 1), id: \.self) { i in
                Circle()
                    .fill(i == index ? theme.textPrimary : theme.textTertiary)
                    .frame(width: 6, height: 6)
            }
        }
        .opacity(count <= 1 ? 0 : 1)
    }
}
