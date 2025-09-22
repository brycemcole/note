//
//  FoldersView.swift
//

import SwiftUI
import SwiftData

struct FoldersView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Folder.name) private var folders: [Folder]
    @State private var showingAddFolder = false
    
    var body: some View {
        NavigationView {
            List {
                ForEach(folders) { folder in
                    NavigationLink(destination: FolderDetailView(folder: folder)) {
                        HStack {
                            Image(systemName: folder.symbolName ?? "folder.fill")
                                .foregroundColor(colorFromHex(folder.colorHex) ?? .blue)
                            
                            VStack(alignment: .leading) {
                                Text(folder.name)
                                    .font(.headline)
                                
                                Text("\(folder.notes.filter { !$0.isDeleted }.count) notes")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                    }
                }
                .onDelete(perform: deleteFolders)
            }
            .navigationTitle("Folders")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddFolder = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddFolder) {
            AddFolderView()
        }
    }
    
    private func deleteFolders(offsets: IndexSet) {
        for index in offsets {
            let folder = folders[index]
            
            // Move all notes in this folder back to ungrouped
            for note in folder.notes {
                note.folder = nil
            }
            
            modelContext.delete(folder)
        }
        
        try? modelContext.save()
    }
    
    private func colorFromHex(_ hex: String?) -> Color? {
        guard let hex = hex else { return nil }
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let val = UInt64(s, radix: 16) else { return nil }
        let a, r, g, b: Double
        if s.count == 8 {
            a = Double((val >> 24) & 0xFF) / 255.0
            r = Double((val >> 16) & 0xFF) / 255.0
            g = Double((val >> 8) & 0xFF) / 255.0
            b = Double(val & 0xFF) / 255.0
        } else {
            a = 1.0
            r = Double((val >> 16) & 0xFF) / 255.0
            g = Double((val >> 8) & 0xFF) / 255.0
            b = Double(val & 0xFF) / 255.0
        }
        return Color(red: r, green: g, blue: b, opacity: a)
    }
}

#Preview {
    FoldersView()
        .modelContainer(for: [Note.self, Folder.self], inMemory: true)
}