//
//  Folder.swift
//

import Foundation
import SwiftData

@Model
final class Folder {
    @Attribute(.unique) var id: UUID
    var name: String
    @Relationship(inverse: \Note.folder) var notes: [Note] = []
    var symbolName: String?
    var colorHex: String?
    var isPrivate: Bool = false

    init(name: String, symbolName: String? = nil, colorHex: String? = nil, isPrivate: Bool = false) {
        self.id = UUID()
        self.name = name
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.isPrivate = isPrivate
    }
}
