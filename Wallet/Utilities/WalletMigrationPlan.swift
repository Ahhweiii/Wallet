//
//  WalletMigrationPlan.swift
//  Wallet
//
//  Created by Lee Jun Wei on 26/2/26.
//

import SwiftData

enum WalletMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [WalletSchemaV1.self, WalletSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: WalletSchemaV1.self, toVersion: WalletSchemaV2.self)
        ]
    }
}

// MARK: - V1
enum WalletSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version = .init(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Account.self, Transaction.self] }
}

// MARK: - V2 (same models, bump when you change models)
enum WalletSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version = .init(2, 0, 0)
    static var models: [any PersistentModel.Type] { [Account.self, Transaction.self] }
}
