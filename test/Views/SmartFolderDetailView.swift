import SwiftUI
import SwiftData

private struct LazyView<Content: View>: View {
    let build: () -> Content

    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }

    var body: some View {
        build()
    }
}

struct SmartFolderDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("showPrivateFolders") private var showPrivateFolders: Bool = false

    @Query(filter: #Predicate<Note> { !$0.isDeleted }, sort: \Note.dateCreated, order: .reverse)
    private var activeNotes: [Note]

    @Query(sort: \Folder.name) private var allFolders: [Folder]

    @State private var noteToMove: Note? = nil
    @State private var showMoveDialog = false
    @State private var showingAddNote = false
    @State private var showingAddLink = false
    @State private var linkURL: String = ""
    @State private var isProcessingLink = false
    @State private var addLinkErrorMessage: String? = nil

    let kind: SmartFolderKind

    private var visibleNotes: [Note] {
        activeNotes.filter { note in
            guard let isPrivate = note.folder?.isPrivate else { return true }
            return showPrivateFolders || !isPrivate
        }
    }

    private var filtered: [Note] {
        switch kind {
        case .allNotes:
            return visibleNotes.filter { !isLinkNote($0) }
        case .links:
            return visibleNotes.filter { isLinkNote($0) }
        }
    }

    private var visibleFolders: [Folder] {
        allFolders.filter { showPrivateFolders || !$0.isPrivate }
    }

    var body: some View {
        List {
            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, note in
                NavigationLink(destination: LazyView(NoteDetailView(note: note))) {
                    NoteRowView(note: note)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        noteToMove = note
                        showMoveDialog = true
                    } label: {
                        Label("Move", systemImage: "folder")
                    }
                    .tint(.blue)
                    .labelStyle(.iconOnly)

                    Button(role: .destructive) {
                        note.moveToTrash()
                        try? modelContext.save()
                    } label: {
                        Label("Trash", systemImage: "trash")
                    }
                    .labelStyle(.iconOnly)
                }
                .if(index == 0) { view in
                    view.listRowSeparator(.hidden, edges: .top)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(kind.title)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                addMenuButton
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                overflowMenuButton
            }
        }
        .confirmationDialog("Move to Folder", isPresented: $showMoveDialog) {
            Button("No Folder") { moveSelectedNote(to: nil) }
            ForEach(visibleFolders) { folder in
                Button(folder.name) { moveSelectedNote(to: folder) }
            }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showingAddNote) { AddNoteView() }
        .alert("Add Link", isPresented: $showingAddLink) {
            TextField("Enter URL", text: $linkURL)
                .keyboardType(.URL)
                .autocapitalization(.none)
            Button("Add") {
                Task { await processLinkURL() }
            }
            .disabled(linkURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessingLink)
            Button("Cancel", role: .cancel) {
                linkURL = ""
            }
        } message: {
            if isProcessingLink {
                Text("Creating note...")
            } else {
                Text("Enter a URL to create a note with link preview")
            }
        }
        .alert("Link Error", isPresented: Binding(
            get: { addLinkErrorMessage != nil },
            set: { if !$0 { addLinkErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { addLinkErrorMessage = nil }
        } message: {
            Text(addLinkErrorMessage ?? "Unknown error")
        }
    }

    private func moveSelectedNote(to folder: Folder?) {
        guard let note = noteToMove else { return }
        note.folder = folder
        try? modelContext.save()
        noteToMove = nil
    }

    private var addMenuButton: some View {
        Menu {
            Button { showingAddNote = true } label: { Label("Add Note", systemImage: "note.text.badge.plus") }
            Button { showingAddLink = true } label: { Label("Add Link", systemImage: "link") }
        } label: {
            Image(systemName: "plus")
                .accessibilityLabel("Add")
        }
    }

    private var overflowMenuButton: some View {
        Menu {
            Button {
                showPrivateFolders.toggle()
            } label: {
                Label(showPrivateFolders ? "Hide Private Folders" : "Show Private Folders", systemImage: "eye")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .accessibilityLabel("More")
        }
    }

    private func isLinkNote(_ note: Note) -> Bool {
        if let source = note.sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty {
            return true
        }
        return note.content.range(of: #"https?://"#, options: .regularExpression) != nil
    }

    private func processLinkURL() async {
        let trimmed = linkURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else {
            addLinkErrorMessage = "Please enter a valid URL."
            return
        }

        await MainActor.run { isProcessingLink = true }
        defer {
            Task { await MainActor.run {
                isProcessingLink = false
                linkURL = ""
                showingAddLink = false
            } }
        }

        do {
            let html = try await WebFetcher.fetchHTML(from: url)
            let title = extractHTMLTitle(from: html)?.htmlDecoded.trimmingCharacters(in: .whitespacesAndNewlines) ?? url.absoluteString
            let description = extractHTMLMetaDescription(from: html)
            let metadata = extractLinkMetadata(from: html, baseURL: url)
            let imageURL = extractBestImageURL(from: html, baseURL: url)
            let body = description ?? ""
            let trimmedProductName = metadata.productName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalTitle = (trimmedProductName?.isEmpty == false ? trimmedProductName : nil) ?? title
            let formatted = formatWebContent(title: finalTitle, url: url, content: body, imageURL: imageURL)

            await MainActor.run {
                let note = Note(title: finalTitle, content: formatted)
                note.sourceURL = url.absoluteString
                note.applyLinkMetadata(metadata)
                if let productName = metadata.productName?.trimmingCharacters(in: .whitespacesAndNewlines), !productName.isEmpty {
                    note.title = productName
                }
                if let description, !description.isEmpty { note.summary = description }
                modelContext.insert(note)
                try? modelContext.save()
            }
        } catch {
            await MainActor.run {
                addLinkErrorMessage = error.localizedDescription
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}
