//
//  Item.swift
//  Wallet
//
//  Created by Lee Jun Wei on 21/2/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
