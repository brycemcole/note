//
//  TrashView.swift
//

import SwiftUI
import SwiftData

struct TrashView: View {
    @Environment(\.modelContext) private var modelContext
    let trashedNotes: [Note]
    @Environment(\.dismiss) private var dismiss
    @State private var showEmptyTrashConfirm = false
    
    var body: some View {
        NavigationView {
            trashList
                .navigationTitle("Trash")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) { doneButton }
                    ToolbarItem(placement: .navigationBarTrailing) { emptyTrashButton }
                }
        }
    }
    
    private var trashList: some View {
        List {
            ForEach(trashedNotes) { note in
                TrashNoteRow(note: note) {
                    permanentlyDeleteNote(note)
                } onRestore: {
                    restoreNote(note)
                }
            }
        }
    }
    
    private var doneButton: some View { Button("Done") { dismiss() } }
    
    private var emptyTrashButton: some View {
        Button("Empty Trash") { showEmptyTrashConfirm = true }
            .disabled(trashedNotes.isEmpty)
            .foregroundColor(.red)
            .alert("Empty Trash", isPresented: $showEmptyTrashConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Empty Trash", role: .destructive) { emptyTrash() }
            } message: {
                Text("Are you sure you want to permanently delete all items in trash?")
            }
    }
    
    private func restoreNote(_ note: Note) { note.restore(); try? modelContext.save() }
    private func permanentlyDeleteNote(_ note: Note) {
        note.deleteAttachmentsInTrash()
        modelContext.delete(note)
        try? modelContext.save()
    }
    private func emptyTrash() {
        for note in trashedNotes {
            note.deleteAttachmentsInTrash()
            modelContext.delete(note)
        }
        try? modelContext.save()
    }
}
