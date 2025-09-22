//
//  TrashView.swift
//

import SwiftUI
import SwiftData

struct TrashView: View {
    let trashedNotes: [Note]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    private var filteredTrashedNotes: [Note] {
        if searchText.isEmpty {
            return trashedNotes
        }
        return trashedNotes.filter { note in
            note.title.localizedCaseInsensitiveContains(searchText) ||
            note.content.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationView {
            if trashedNotes.isEmpty {
                ContentUnavailableView(
                    "No Deleted Notes",
                    systemImage: "trash",
                    description: Text("Notes you delete will appear here.")
                )
            } else {
                List {
                    ForEach(filteredTrashedNotes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(note.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                if let deleteDate = note.dateDeleted {
                                    Text("Deleted \(deleteDate, style: .relative)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if !note.previewText.isEmpty {
                                Text(note.previewText)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 2)
                        .swipeActions(edge: .leading) {
                            Button {
                                restoreNote(note)
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                permanentlyDeleteNote(note)
                            } label: {
                                Label("Delete Forever", systemImage: "trash.fill")
                            }
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Search deleted notes")
            }
        }
        .navigationTitle("Trash")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") {
                    dismiss()
                }
            }
            
            if !trashedNotes.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Empty Trash") {
                        emptyTrash()
                    }
                    .foregroundColor(.red)
                }
            }
        }
    }
    
    private func restoreNote(_ note: Note) {
        note.restore()
        try? modelContext.save()
    }
    
    private func permanentlyDeleteNote(_ note: Note) {
        modelContext.delete(note)
        try? modelContext.save()
    }
    
    private func emptyTrash() {
        for note in trashedNotes {
            modelContext.delete(note)
        }
        try? modelContext.save()
    }
}

#Preview {
    TrashView(trashedNotes: [])
        .modelContainer(for: [Note.self, Folder.self], inMemory: true)
}