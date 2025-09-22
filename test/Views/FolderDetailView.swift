//
//  FolderDetailView.swift
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

private struct LazyView<Content: View>: View {
    let build: () -> Content
    init(_ build: @autoclosure @escaping () -> Content) { self.build = build }
    var body: some View { build() }
}

struct FolderDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @AppStorage("showPrivateFolders") private var showPrivateFolders: Bool = false

    @State private var showingRename = false
    @State private var showingDeleteConfirm = false
    @State private var showingAddExisting = false
    @State private var showingIconPicker = false
    @State private var showingColorPicker = false

    @State private var newName: String = ""
    @State private var selectedNoteIDs = Set<UUID>()
    
    @State private var isSelecting = false
    @State private var isEditingTitle = false
    @State private var showingPhotosPicker = false
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showMoveSelectedDialog = false
    
    @State private var exportURL: URL? = nil
    @State private var showingShareSheet = false
    
    @State private var searchText = ""
    
    @State private var noteToMove: Note? = nil
    @State private var showMoveDialog = false
    
    @State private var showingAddNote = false
    @State private var showingAddLink = false
    @State private var linkURL = ""
    @State private var isProcessingLink = false

    @State private var showingFileImporter = false
    @State private var importErrorMessage: String? = nil
    
    
    @Query(filter: #Predicate<Note> { !$0.isDeleted }, sort: \Note.dateCreated, order: .reverse)
    private var activeNotes: [Note]
    
    @Query(sort: \Folder.name)
    private var allFolders: [Folder]
    
    private var visibleFolders: [Folder] { allFolders.filter { showPrivateFolders || !$0.isPrivate } }
    
    let folder: Folder
    
    private var notesInFolder: [Note] {
        activeNotes.filter { $0.folder?.id == folder.id }
            .sorted { $0.dateCreated > $1.dateCreated }
    }
    
    private var filteredNotesInFolder: [Note] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return notesInFolder }
        let q = searchText.lowercased()
        return notesInFolder.filter { $0.title.lowercased().contains(q) || $0.content.lowercased().contains(q) }
    }
    
    private var candidateNotesToAdd: [Note] {
        activeNotes.filter { $0.folder?.id != folder.id }
    }
    
    private func colorFromHex(_ hex: String?) -> Color {
        guard let hex = hex else { return .blue }
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let val = UInt64(s, radix: 16) else { return .blue }
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
    
    private func hexFromColor(_ color: Color) -> String? {
        #if canImport(UIKit)
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        let ri = Int(round(r * 255)), gi = Int(round(g * 255)), bi = Int(round(b * 255)), ai = Int(round(a * 255))
        if ai < 255 { return String(format: "%02X%02X%02X%02X", ai, ri, gi, bi) }
        return String(format: "%02X%02X%02X", ri, gi, bi)
        #else
        return nil
        #endif
    }
    
    private struct SelectableRow<Content: View>: View {
        let isSelected: Bool
        let content: () -> Content
        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                content()
            }
            .contentShape(Rectangle())
        }
    }
    
    @ViewBuilder
    private var notesList: some View {
        List {
            ForEach(filteredNotesInFolder) { note in
                if isSelecting {
                    SelectableRow(isSelected: selectedNoteIDs.contains(note.id)) {
                        NoteRowView(note: note)
                    }
                    .onTapGesture { toggleSelection(for: note) }
                } else {
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
                }
            }
        }
        .listStyle(.plain)
    }
    
    var body: some View {
        Group {
            if folder.isPrivate && !showPrivateFolders {
                // If somehow navigated here while hidden, dismiss immediately
                Color.clear.onAppear { dismiss() }
            } else {
                notesList
                    .searchable(text: $searchText, prompt: "Search in folder")
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            HStack(spacing: 8) {
                                Image(systemName: folder.symbolName ?? "folder")
                                    .foregroundColor(colorFromHex(folder.colorHex))
                                Text(folder.name)
                                    .font(.headline)
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            if isSelecting {
                                Button { performTrashSelected() } label: { Image(systemName: "trash") }
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            if isSelecting {
                                Button { showMoveSelectedDialog = true } label: { Image(systemName: "folder") }
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            if !isSelecting { addMenuButton }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            overflowMenuButton
                        }
                        ToolbarItemGroup(placement: .bottomBar) {
                            if isSelecting {
                                Button { performTrashSelected() } label: { Label("Trash", systemImage: "trash") }
                                Button { showMoveSelectedDialog = true } label: { Label("Move", systemImage: "folder") }
                                Button { performRemoveSelectedFromFolder() } label: { Label("Remove", systemImage: "arrow.uturn.left") }
                                Spacer()
                                Button { selectAll() } label: { Text("Select All") }
                                Button { isSelecting = false; selectedNoteIDs.removeAll() } label: { Text("Done") }
                            }
                        }
                    }
                    .alert("Rename Folder", isPresented: $showingRename) {
                        TextField("Folder Name", text: $newName)
                        Button("Cancel", role: .cancel) { }
                        Button("Save") { saveRename() }
                    }
                    .confirmationDialog("Delete Folder", isPresented: $showingDeleteConfirm) {
                        Button("Delete Folder", role: .destructive) { deleteFolder() }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("Notes inside will remain and be removed from this folder.")
                    }
                    .confirmationDialog("Move Selected To", isPresented: $showMoveSelectedDialog) {
                        Button("No Folder") { performMoveSelected(to: nil) }
                        ForEach(visibleFolders) { f in
                            Button(f.name) { performMoveSelected(to: f) }
                        }
                        Button("Cancel", role: .cancel) { }
                    }
                    .confirmationDialog("Move to Folder", isPresented: $showMoveDialog) {
                        Button("No Folder") { moveSelectedNoteInFolder(to: nil) }
                        ForEach(visibleFolders) { destFolder in
                            Button(destFolder.name) { moveSelectedNoteInFolder(to: destFolder) }
                        }
                        Button("Cancel", role: .cancel) { }
                    }
                    .sheet(isPresented: $showingAddExisting) {
                        addExistingNotesSheet
                    }
                    .sheet(isPresented: $showingShareSheet) {
                        if let exportURL = exportURL { ShareSheet(activityItems: [exportURL]) }
                    }
                    .sheet(isPresented: $showingIconPicker) {
                        SymbolPickerView(selectedSymbol: Binding(
                            get: { folder.symbolName ?? "folder" },
                            set: { newValue in
                                folder.symbolName = newValue
                                try? modelContext.save()
                            }
                        ))
                    }
                    .sheet(isPresented: $showingColorPicker) {
                        NavigationView {
                            VStack(spacing: 16) {
                                ColorPicker("Color", selection: Binding(
                                    get: { colorFromHex(folder.colorHex) },
                                    set: { newColor in
                                        folder.colorHex = hexFromColor(newColor)
                                        try? modelContext.save()
                                    }
                                ), supportsOpacity: false)
                                .padding()
                                Spacer()
                            }
                            .navigationTitle("Choose Color")
                            .toolbar {
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    Button("Done") { showingColorPicker = false }
                                }
                            }
                        }
                    }
                    .sheet(isPresented: $showingAddNote) {
                        AddNoteInline(folder: folder)
                    }
                    .alert("Add Link", isPresented: $showingAddLink) {
                        TextField("Enter URL", text: $linkURL)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                        Button("Add") { Task { await processLinkURLIntoFolder() } }
                            .disabled(linkURL.isEmpty || isProcessingLink)
                        Button("Cancel", role: .cancel) { linkURL = "" }
                    } message: {
                        if isProcessingLink { Text("Creating note...") } else { Text("Enter a URL to create a note with link preview") }
                    }
                    .fileImporter(
                        isPresented: $showingFileImporter,
                        allowedContentTypes: [UTType.item],
                        allowsMultipleSelection: true
                    ) { result in
                        switch result {
                        case .success(let urls):
                            handleImportedFiles(urls)
                        case .failure(let error):
                            importErrorMessage = error.localizedDescription
                        }
                    }
                    .alert("Import Error", isPresented: Binding(
                        get: { importErrorMessage != nil },
                        set: { if !$0 { importErrorMessage = nil } }
                    )) {
                        Button("OK", role: .cancel) { importErrorMessage = nil }
                    } message: {
                        Text(importErrorMessage ?? "Unknown error")
                    }
                    .photosPicker(
                        isPresented: $showingPhotosPicker,
                        selection: $photoPickerItems,
                        maxSelectionCount: 0,
                        matching: .images
                    )
                    .onChange(of: photoPickerItems) { newItems in
                        if !newItems.isEmpty {
                            Task { await handleImportedPhotoItems(newItems) }
                    }
                }
            }
        }
    }

    private var addMenuButton: some View {
        Menu {
            Button { showingAddNote = true } label: { Label("Add Note", systemImage: "note.text.badge.plus") }
            Button { showingAddLink = true } label: { Label("Add Link", systemImage: "link") }
            Button { showingPhotosPicker = true } label: { Label("Add Photos…", systemImage: "photo.on.rectangle") }
            Button { showingFileImporter = true } label: { Label("Add Files…", systemImage: "paperclip") }
            Button { showingAddExisting = true } label: { Label("Add Notes…", systemImage: "text.badge.plus") }
        } label: {
            Image(systemName: "plus")
                .accessibilityLabel("Add")
        }
    }

    private var overflowMenuButton: some View {
        Menu {
            Button { startRename() } label: { Label("Edit Title…", systemImage: "text.cursor") }
            Button { showingIconPicker = true } label: { Label("Choose Icon", systemImage: "square.grid.2x2") }
            Button { showingColorPicker = true } label: { Label("Choose Color", systemImage: "paintpalette") }
            Divider()
            Button { moveAllNotesOut() } label: { Label("Move All Notes Out", systemImage: "arrow.uturn.left") }
                .disabled(notesInFolder.isEmpty)
            Button { prepareExportFolder() } label: { Label("Share Folder", systemImage: "square.and.arrow.up") }
            Button { prepareExportFolder() } label: { Label("Export Notes (.md)", systemImage: "tray.and.arrow.down") }
            Divider()
            Button(role: .destructive) { showingDeleteConfirm = true } label: { Label("Delete Folder", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis.circle")
                .accessibilityLabel("More")
        }
    }
    
    private func folderStorageDirectory() -> URL? {
        do {
            let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = docs.appendingPathComponent("Folder_\(folder.id.uuidString)", isDirectory: true)
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            return dir
        } catch {
            return nil
        }
    }

    private func uniqueDestinationURL(for originalURL: URL, in directory: URL) -> URL {
        let baseName = originalURL.deletingPathExtension().lastPathComponent
        let ext = originalURL.pathExtension
        var candidate = directory.appendingPathComponent(originalURL.lastPathComponent)
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = "\(baseName)-\(index)"
            candidate = directory.appendingPathComponent(name).appendingPathExtension(ext)
            index += 1
        }
        return candidate
    }

    private func handleImportedFiles(_ urls: [URL]) {
        guard let destDir = folderStorageDirectory() else {
            importErrorMessage = "Unable to access folder storage."
            return
        }
        for src in urls {
            let accessed = src.startAccessingSecurityScopedResource()
            defer { if accessed { src.stopAccessingSecurityScopedResource() } }
            do {
                let dest = uniqueDestinationURL(for: src, in: destDir)
                // If it's a file on iCloud Drive or elsewhere, copy to our sandbox
                if FileManager.default.fileExists(atPath: dest.path) == false {
                    try FileManager.default.copyItem(at: src, to: dest)
                }
                createNoteForImportedFile(at: dest)
            } catch {
                importErrorMessage = "Failed to import \(src.lastPathComponent): \(error.localizedDescription)"
            }
        }
        try? modelContext.save()
    }

    private func createNoteForImportedFile(at fileURL: URL) {
        let filename = fileURL.lastPathComponent
        let title = fileURL.deletingPathExtension().lastPathComponent
        let isImage = (try? fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .image) ?? false
        let urlString = fileURL.absoluteString
        var content = "# \(title)\n\n"
        if isImage {
            content += "![\(filename)](\(urlString))\n\n"
        } else {
            content += "[\(filename)](\(urlString))\n\n"
        }
        content += "*Imported file attached to this folder.*"
        let note = Note(title: title, content: content, folder: folder)
        modelContext.insert(note)
    }
    
    @MainActor
    private func handleImportedPhotoItems(_ items: [PhotosPickerItem]) async {
        guard let destDir = folderStorageDirectory() else { return }
        for item in items {
            do {
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                if let data = try await item.loadTransferable(type: Data.self) {
                    let url = uniquePhotoURL(in: destDir, ext: ext)
                    try data.write(to: url)
                    createNoteForImportedFile(at: url)
                }
            } catch {
                // Ignore individual item failures
            }
        }
        photoPickerItems.removeAll()
        try? modelContext.save()
    }

    private func uniquePhotoURL(in directory: URL, ext: String) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        var candidate = directory.appendingPathComponent("Photo-\(stamp)").appendingPathExtension(ext)
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("Photo-\(stamp)-\(index)").appendingPathExtension(ext)
            index += 1
        }
        return candidate
    }
    
    private func startRename() {
        newName = folder.name
        showingRename = true
    }
    
    private func saveRename() {
        folder.name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        try? modelContext.save()
    }
    
    private func toggleSelection(for note: Note) {
        if selectedNoteIDs.contains(note.id) {
            selectedNoteIDs.remove(note.id)
        } else {
            selectedNoteIDs.insert(note.id)
        }
    }
    
    private func selectedNotes() -> [Note] {
        notesInFolder.filter { selectedNoteIDs.contains($0.id) }
    }
    
    private func performTrashSelected() {
        let targets = selectedNotes()
        for n in targets {
            n.moveToTrash()
        }
        try? modelContext.save()
        selectedNoteIDs.removeAll()
        isSelecting = false
    }
    
    private func performMoveSelected(to folder: Folder?) {
        let targets = selectedNotes()
        for n in targets {
            n.folder = folder
        }
        try? modelContext.save()
        selectedNoteIDs.removeAll()
        isSelecting = false
    }
    
    private func performRemoveSelectedFromFolder() {
        performMoveSelected(to: nil)
    }
    
    private func selectAll() {
        selectedNoteIDs = Set(notesInFolder.map { $0.id })
    }
    
    private func moveAllNotesOut() {
        for n in notesInFolder {
            n.folder = nil
        }
        try? modelContext.save()
    }
    
    private func addSelectedNotesToFolder() {
        let selected = activeNotes.filter { selectedNoteIDs.contains($0.id) }
        for n in selected {
            n.folder = folder
        }
        try? modelContext.save()
        selectedNoteIDs.removeAll()
        showingAddExisting = false
    }
    
    private func deleteFolder() {
        // Disassociate notes but keep them
        for n in folder.notes {
            n.folder = nil
        }
        modelContext.delete(folder)
        try? modelContext.save()
        dismiss()
    }
    
    private func prepareExportFolder() {
        // Create a temporary directory
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let folderNameSafe = folder.name.replacingOccurrences(of: "/", with: "-")
        let exportDir = tempDir.appendingPathComponent("Export_\(folderNameSafe)_\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

            // Write each note as a .md file
            for note in notesInFolder {
                let baseName: String = {
                    let trimmed = note.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty { return note.id.uuidString }
                    // Sanitize filename characters
                    let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|\n\r")
                    let safe = trimmed.components(separatedBy: invalid).joined(separator: " ")
                    return String(safe.prefix(80))
                }()
                let fileURL = exportDir.appendingPathComponent(baseName).appendingPathExtension("md")

                var contents = "# \(note.displayTitle)\n\n"
                if let summary = note.summary, !summary.isEmpty {
                    contents += "_Summary:_ \(summary)\n\n"
                }
                contents += note.content

                try contents.write(to: fileURL, atomically: true, encoding: .utf8)
            }

            // Set state to present share sheet
            self.exportURL = exportDir
            self.showingShareSheet = true
        } catch {
            // If export fails, do nothing user-visible for now; could add an alert
            print("Export failed: \(error)")
        }
    }
    
    private func moveSelectedNoteInFolder(to folder: Folder?) {
        guard let note = noteToMove else { return }
        note.folder = folder
        try? modelContext.save()
        noteToMove = nil
    }
    
    @MainActor
    private func processLinkURLIntoFolder() async {
        guard !linkURL.isEmpty else { return }
        let urlString = linkURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlString) else { return }
        isProcessingLink = true
        defer { isProcessingLink = false; linkURL = "" }

        let initialTitle = url.host ?? url.absoluteString
        let initialContent = "Loading content from [\(initialTitle)](\(url.absoluteString))...\n\n*This note is being updated with content from the web page.*"

        let note = Note(title: initialTitle, content: initialContent, folder: folder)
        note.sourceURL = url.absoluteString
        modelContext.insert(note)
        try? modelContext.save()

        Task {
            do {
                let html = try await WebFetcher.fetchHTML(from: url)

                let title = extractHTMLTitle(from: html) ?? initialTitle
                let description = extractHTMLMetaDescription(from: html)
                let imageURL = extractBestImageURL(from: html, baseURL: url)
                let metadata = extractLinkMetadata(from: html, baseURL: url)
                let body = description ?? ""

                let trimmedProductName = metadata.productName?.trimmingCharacters(in: .whitespacesAndNewlines)
                let finalTitle = (trimmedProductName?.isEmpty == false ? trimmedProductName : nil) ?? title
                let formatted = formatWebContent(title: finalTitle, url: url, content: body, imageURL: imageURL)

                await MainActor.run {
                    note.title = finalTitle
                    note.content = formatted
                    note.sourceURL = url.absoluteString
                    note.applyLinkMetadata(metadata)
                    if let productName = metadata.productName?.trimmingCharacters(in: .whitespacesAndNewlines), !productName.isEmpty {
                        note.title = productName
                    }
                    try? modelContext.save()
                }
            } catch {
                await MainActor.run {
                    note.content = "Failed to load content from [\(initialTitle)](\(url.absoluteString))\n\nError: \(error.localizedDescription)\n\nYou can still access the link above."
                    try? modelContext.save()
                }
            }
        }
    }
    
    @ViewBuilder
    private var addExistingNotesSheet: some View {
        NavigationView {
            List {
                ForEach(candidateNotesToAdd) { note in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.displayTitle).font(.body).lineLimit(1)
                            if !note.previewText.isEmpty {
                                Text(note.previewText.markdownAttributed)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if selectedNoteIDs.contains(note.id) {
                            Image(systemName: "checkmark").foregroundColor(.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { toggleSelection(for: note) }
                }
            }
            .navigationTitle("Add Notes")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showingAddExisting = false
                        selectedNoteIDs.removeAll()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        addSelectedNotesToFolder()
                    }
                    .disabled(selectedNoteIDs.isEmpty)
                }
            }
        }
    }
    
    private struct AddNoteInline: View {
        @Environment(\.dismiss) private var dismiss
        @Environment(\.modelContext) private var modelContext
        @State private var content = ""
        let folder: Folder

        var body: some View {
            NavigationView {
                VStack {
                    TextEditor(text: $content)
                        .padding()
                    Spacer()
                }
                .navigationTitle("New Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") { saveNote() }.disabled(content.isEmpty)
                    }
                }
            }
        }

        private func saveNote() {
            let newNote = Note(title: "Untitled", content: content.removingLeadingListMarkers.normalizedMarkdown, folder: folder)
            modelContext.insert(newNote)
            try? modelContext.save()
            dismiss()
        }
    }
}
