//
//  TrashNoteRow.swift
//

import SwiftUI

struct TrashNoteRow: View {
    let note: Note
    let onDelete: () -> Void
    let onRestore: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.displayTitle)
                .font(.headline)
                .lineLimit(1)
            
            if !note.previewText.isEmpty {
                Text(note.previewText.markdownAttributed)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            if let dateDeleted = note.dateDeleted {
                Text("Deleted: \(dateDeleted, style: .date)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Restore") { onRestore() }.tint(.blue)
        }
    }
}
