//
//  SmartFolderDetailView.swift
//

import SwiftUI
import SwiftData

struct SmartFolderDetailView: View {
    let kind: SmartFolderKind
    @Environment(\.modelContext) private var modelContext
    @Query private var allNotes: [Note]
    @State private var searchText = ""
    
    init(kind: SmartFolderKind) {
        self.kind = kind
        self._allNotes = Query(
            filter: #Predicate<Note> { !$0.isDeleted },
            sort: \Note.dateCreated,
            order: .reverse
        )
    }
    
    private var filteredNotes: [Note] {
        var notes = allNotes
        
        // Apply smart folder filtering
        switch kind {
        case .allNotes:
            break // Show all notes
        case .links:
            notes = notes.filter { note in
                note.content.range(of: #"https?://"#, options: .regularExpression) != nil
            }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            notes = notes.filter { note in
                note.title.localizedCaseInsensitiveContains(searchText) ||
                note.content.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return notes
    }
    
    var body: some View {
        List {
            ForEach(filteredNotes) { note in
                NavigationLink(destination: NoteDetailView(note: note)) {
                    NoteRowView(note: note)
                }
            }
        }
        .navigationTitle(kind.title)
        .searchable(text: $searchText, prompt: "Search \(kind.title.lowercased())")
    }
}

#Preview {
    NavigationView {
        SmartFolderDetailView(kind: .allNotes)
    }
    .modelContainer(for: [Note.self, Folder.self], inMemory: true)
}