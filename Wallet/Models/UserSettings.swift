//
//  UserSettings.swift
//  FrugalPilot
//
//  Created by Lee Jun Wei on 27/2/26.
//

import Foundation
import SwiftData

@Model
final class UserSettings {
    @Attribute(.unique) var id: UUID
    
    /// The day of month when a new tracking period starts (1–31).
    /// e.g. 25 means the period runs from the 25th to the 24th of the next month.
    var billingCycleStartDay: Int
    
    init(id: UUID = UUID(), billingCycleStartDay: Int = 1) {
        self.id = id
        self.billingCycleStartDay = billingCycleStartDay
    }
}
