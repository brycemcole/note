//
//  SmartFolderKind.swift
//

import Foundation

enum SmartFolderKind: String, CaseIterable {
    case allNotes = "all_notes"
    case links = "links"
    
    var title: String {
        switch self {
        case .allNotes: return "Notes"
        case .links: return "Links"
        }
    }
    
    var defaultSymbol: String {
        switch self {
        case .allNotes: return "tray.full"
        case .links: return "link"
        }
    }
}