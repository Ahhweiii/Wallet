//
//  FrugalPilotBackupDocument.swift
//  FrugalPilot
//
//  Created by Lee Jun Wei on 26/2/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct FrugalPilotBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let d = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = d
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
