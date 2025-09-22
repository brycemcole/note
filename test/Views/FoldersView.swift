//
//  FoldersView.swift
//

import SwiftUI
import SwiftData

struct FoldersView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Folder.name) private var folders: [Folder]
    @State private var showingAddFolder = false
    
    var body: some View {
        List {
            ForEach(folders) { folder in
                NavigationLink(destination: FolderDetailView(folder: folder)) {
                    HStack {
                        Image(systemName: "folder").foregroundColor(.blue)
                        Text(folder.name)
                        Spacer()
                        Text("\(folder.notes.filter { !$0.isDeleted }.count)").foregroundColor(.secondary)
                    }
                }
            }
            .onDelete(perform: deleteFolders)
        }
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button(action: { showingAddFolder = true }) { Image(systemName: "folder.badge.plus") } } }
        .sheet(isPresented: $showingAddFolder) { AddFolderView() }
    }
    
    private func deleteFolders(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(folders[index]) }
        try? modelContext.save()
    }
}
