//
//  ContentView.swift (refactored with Folders)
//

import SwiftUI
import SwiftData
import Foundation
import FoundationModels
import UniformTypeIdentifiers

enum SmartFolderKind: Equatable, Hashable {
    case allNotes
    case links

    var title: String {
        switch self {
        case .allNotes: return "Notes"
        case .links: return "Links"
        }
    }
}

private enum HomeLayoutMode: String, CaseIterable {
    case list
    case detail

    var label: String {
        switch self {
        case .list: return "List"
        case .detail: return "Details"
        }
    }

    var systemImage: String {
        switch self {
        case .list: return "list.bullet"
        case .detail: return "square.grid.2x2"
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<Note> { !$0.isDeleted }, sort: \Note.dateCreated, order: .reverse) private var activeNotes: [Note]
    @Query(filter: #Predicate<Note> { $0.isDeleted }, sort: \Note.dateDeleted, order: .reverse) private var trashedNotes: [Note]
    @Query(sort: \Folder.name) private var folders: [Folder]

    @AppStorage("smartNotesSymbol") private var smartNotesSymbol: String = "tray.full"
    @AppStorage("smartNotesColorHex") private var smartNotesColorHex: String = ""
    @AppStorage("smartLinksSymbol") private var smartLinksSymbol: String = "link"
    @AppStorage("smartLinksColorHex") private var smartLinksColorHex: String = ""
    @AppStorage("showPrivateFolders") private var showPrivateFolders: Bool = false

    @State private var showingAddNote = false
    @State private var showingAddLink = false
    @State private var showingAddFolder = false
    @State private var showingTrash = false
    @State private var showingFolders = false
    @State private var searchText = ""
    @State private var isSyncing = false
    @State private var hideStatusAfterSync = false
    @State private var syncMessage: String? = nil
    @State private var noteToMove: Note? = nil
    @State private var showMoveDialog: Bool = false
    @State private var linkURL = ""
    @State private var isProcessingLink = false
    @State private var showAllFolders = false

    @State private var selectedSmartFolder: SmartFolderKind? = nil
    @State private var selectedFolder: Folder? = nil

    @State private var showingSmartIconPicker: SmartFolderKind? = nil
    @State private var showingSmartColorPicker: SmartFolderKind? = nil
    @State private var tempSelectedSymbol: String = ""
    @State private var tempSelectedColor: Color = .blue

    @State private var showingSyncAlert = false
    @State private var showingSettings = false

    @State private var showingAddFilesFolderDialog = false
    @State private var showingFileImporter = false
    @State private var selectedAddFilesFolder: Folder? = nil
    @State private var importErrorMessage: String? = nil

    @State private var iCloudAvailable = false
    @State private var currentSyncNoteTitle: String? = nil
    @State private var syncHadFailures = false
    @State private var syncTask: Task<Void, Never>? = nil
    @State private var syncStatusDetail: String = ""

    private let syncStalenessInterval: TimeInterval = 60 * 60 * 24 * 3

    @AppStorage("homeLayoutMode") private var homeLayoutModeRawValue: String = HomeLayoutMode.list.rawValue

    private var homeLayoutMode: HomeLayoutMode {
        HomeLayoutMode(rawValue: homeLayoutModeRawValue) ?? .list
    }

    private var homeLayoutModeBinding: Binding<HomeLayoutMode> {
        Binding(
            get: { HomeLayoutMode(rawValue: homeLayoutModeRawValue) ?? .list },
            set: { homeLayoutModeRawValue = $0.rawValue }
        )
    }
    

    private var visibleFolders: [Folder] {
        folders.filter { showPrivateFolders || !$0.isPrivate }
    }

    private var visibleActiveNotes: [Note] {
        activeNotes.filter { note in
            // Do not show notes from private folders on Home, regardless of setting
            note.folder?.isPrivate != true
        }
    }

    private var visibleLinkNotes: [Note] {
        visibleActiveNotes.filter { isLinkNote($0) }
    }

    private var visibleRegularNotes: [Note] {
        visibleActiveNotes.filter { !isLinkNote($0) }
    }

    private var homeNotes: [Note] {
        let combined = visibleRegularNotes + visibleLinkNotes
        return combined.sorted { $0.dateCreated > $1.dateCreated }
    }

    private var filteredNotes: [Note] {
        guard !searchText.isEmpty else { return homeNotes }
        let query = searchText
        return homeNotes.filter { note in
            note.displayTitle.localizedCaseInsensitiveContains(query) ||
            note.content.localizedCaseInsensitiveContains(query)
        }
    }

    private func isLinkNote(_ note: Note) -> Bool {
        if let source = note.sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty {
            return true
        }
        return note.content.range(of: #"https?://"#, options: .regularExpression) != nil
    }

    var body: some View {
        NavigationStack {
            notesTab
            .navigationTitle("Notes")
            .searchable(text: $searchText, prompt: "Search notes")
            .navigationDestination(item: $selectedSmartFolder) { kind in
                SmartFolderDetailView(kind: kind)
            }
            .navigationDestination(item: $selectedFolder) { folder in
                FolderDetailView(folder: folder)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .accessibilityLabel("Settings")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSyncAlert = true
                    } label: {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(syncIndicatorColor)
                            .accessibilityLabel("Sync Status")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) { addMenuButton }
                ToolbarItem(placement: .navigationBarTrailing) { menuButton }
            }
            .sheet(isPresented: $showingAddNote) { AddNoteView() }
            .sheet(isPresented: $showingAddFolder) { AddFolderView() }
            .sheet(isPresented: $showingFolders) { FoldersView() }
            .sheet(isPresented: $showingTrash) { TrashView(trashedNotes: trashedNotes) }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .alert("Add Link", isPresented: $showingAddLink) {
                TextField("Enter URL", text: $linkURL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                Button("Add") {
                    Task { await processLinkURL() }
                }
                .disabled(linkURL.isEmpty || isProcessingLink)
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
            .alert("Sync Status", isPresented: $showingSyncAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                if !syncStatusDetail.isEmpty {
                    Text(syncStatusDetail)
                } else {
                    Text(syncStatusText ?? "Notes are up to date.")
                }
            }
            .confirmationDialog("Add Files To", isPresented: $showingAddFilesFolderDialog, titleVisibility: .visible) {
                ForEach(visibleFolders) { folder in
                    Button(folder.name) {
                        selectedAddFilesFolder = folder
                        showingFileImporter = true
                    }
                }
                Button("Cancel", role: .cancel) { }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [UTType.item],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    if let destFolder = selectedAddFilesFolder {
                        handleImportedFiles(urls, to: destFolder)
                    }
                    selectedAddFilesFolder = nil
                case .failure(let error):
                    importErrorMessage = error.localizedDescription
                    selectedAddFilesFolder = nil
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
            .sheet(item: $showingSmartIconPicker) { kind in
                let current = (kind == .allNotes) ? smartNotesSymbol : smartLinksSymbol
                SymbolPickerView(selectedSymbol: Binding(
                    get: { current },
                    set: { newValue in
                        if kind == .allNotes { smartNotesSymbol = newValue } else { smartLinksSymbol = newValue }
                    }
                ))
            }
            .sheet(item: $showingSmartColorPicker) { kind in
                NavigationView {
                    VStack(spacing: 16) {
                        ColorPicker("Color", selection: Binding(
                            get: {
                                if kind == .allNotes { return colorFromHex(smartNotesColorHex.isEmpty ? nil : smartNotesColorHex) ?? .blue }
                                else { return colorFromHex(smartLinksColorHex.isEmpty ? nil : smartLinksColorHex) ?? .blue }
                            },
                            set: { newColor in
                                if let hex = hexFromColor(newColor) {
                                    if kind == .allNotes { smartNotesColorHex = hex } else { smartLinksColorHex = hex }
                                } else {
                                    if kind == .allNotes { smartNotesColorHex = "" } else { smartLinksColorHex = "" }
                                }
                            }
                        ), supportsOpacity: false)
                        .padding()
                        Spacer()
                    }
                    .navigationTitle("Choose Color")
                    .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { showingSmartColorPicker = nil } } }
                }
            }
            .onAppear { startSyncStatus() }
            .onChange(of: activeNotes.count) { _, newCount in handleNotesCountChange(newCount) }
            .onDisappear {
                syncTask?.cancel()
                syncTask = nil
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                startSyncStatus()
            case .inactive, .background:
                syncTask?.cancel()
                syncTask = nil
            @unknown default:
                break
            }
        }
    }

    private var syncIndicatorColor: Color {
        if isSyncing { return .yellow }
        if syncHadFailures { return .red }
        if iCloudAvailable { return .green }
        return .gray
    }

    private var notesTab: some View {
        Group {
            switch homeLayoutMode {
            case .list: listNotesView
            case .detail: detailNotesView
            }
        }
        .confirmationDialog("Move to Folder", isPresented: $showMoveDialog, titleVisibility: .visible) {
            Button("No Folder") { moveSelectedNote(to: nil) }
            ForEach(visibleFolders) { folder in Button(folder.name) { moveSelectedNote(to: folder) } }
            Button("New Folder…") { showingAddFolder = true }
            Button("Cancel", role: .cancel) { }
        }
    }

    private var listNotesView: some View {
        List {
            VStack(alignment: .leading, spacing: 0) {
                foldersOverlayHeader
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))

            Section { listNotesSection }
        }
        .listStyle(.plain)
    }

    private var detailNotesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                foldersOverlayHeader
                    .padding(.horizontal)

                LazyVGrid(columns: detailColumns, spacing: 16) {
                    ForEach(filteredNotes) { note in
                        NavigationLink(destination: NoteDetailView(note: note)) {
                            NoteDetailCardView(
                                note: note,
                                previewURL: previewImageURL(for: note),
                                summary: cardSummary(for: note)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Move to Folder") { noteToMove = note; showMoveDialog = true }
                            Button("Move to Trash", role: .destructive) {
                                note.moveToTrash()
                                try? modelContext.save()
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
    }

    private var listNotesSection: some View {
        ForEach(filteredNotes) { note in
            NavigationLink(destination: NoteDetailView(note: note)) {
                NoteRowView(note: note)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    noteToMove = note; showMoveDialog = true
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

    private var addMenuButton: some View {
        Menu {
            Button(action: { showingAddNote = true }) { Label("Add Note", systemImage: "note.text.badge.plus") }
            Button(action: { showingAddLink = true }) { Label("Add Link", systemImage: "link") }
            Button(action: { showingAddFolder = true }) { Label("Add Folder", systemImage: "folder.badge.plus") }
            Button(action: { showingAddFilesFolderDialog = true }) { Label("Add Files…", systemImage: "paperclip") }
        } label: {
            Image(systemName: "plus")
                .accessibilityLabel("Add")
        }
    }

    private var menuButton: some View {
        Menu {
            Section("Layout") {
                ForEach(HomeLayoutMode.allCases, id: \.rawValue) { mode in
                    Button {
                        homeLayoutModeBinding.wrappedValue = mode
                    } label: {
                        HStack {
                            Image(systemName: mode.systemImage)
                            Text(mode.label)
                            if homeLayoutMode == mode {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Divider()
            Button(action: { showingFolders = true }) { Label("Folders", systemImage: "folder") }
            Button(action: { showingTrash = true }) { Label("Trash", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis.circle")
                .accessibilityLabel("More")
        }
    }

    private func handleNotesCountChange(_ newCount: Int) {
        if newCount == 0 { return }
        startSyncStatus()
    }

    // Sync status helpers (kept in-type for access to private state)
    private func startSyncStatus() {
        hideStatusAfterSync = false
        syncTask?.cancel()
        syncTask = nil
        syncHadFailures = false
        syncStatusDetail = ""

        let candidates = notesNeedingResync()

        guard !candidates.isEmpty else {
            isSyncing = false
            currentSyncNoteTitle = nil
            iCloudAvailable = true
            syncMessage = "Notes are up to date."
            return
        }

        isSyncing = true
        iCloudAvailable = false
        currentSyncNoteTitle = nil
        let countLabel = candidates.count == 1 ? "note" : "notes"
        syncMessage = "Preparing to refresh \(candidates.count) \(countLabel)…"

        syncTask = Task {
            for note in candidates {
                if Task.isCancelled { break }

                await MainActor.run {
                    currentSyncNoteTitle = note.displayTitle
                    syncMessage = "Refreshing \(note.displayTitle)…"
                }

                await refreshNoteIfNeeded(note)

                if Task.isCancelled { break }
            }

            await MainActor.run {
                isSyncing = false
                currentSyncNoteTitle = nil
                let succeeded = !syncHadFailures
                iCloudAvailable = succeeded
                syncMessage = succeeded ? "Notes are up to date." : (syncStatusDetail.isEmpty ? "Some notes could not be refreshed." : syncStatusDetail)
                syncTask = nil
            }
        }
    }

    private var syncStatusText: String? {
        if hideStatusAfterSync { return nil }
        if isSyncing, let current = currentSyncNoteTitle, !current.isEmpty {
            return "Refreshing \(current)…"
        }
        return syncMessage
    }

    private func notesNeedingResync() -> [Note] {
        let cutoff = Date().addingTimeInterval(-syncStalenessInterval)
        return activeNotes.filter { note in
            guard isLinkPreviewNote(note), primaryURL(for: note) != nil else { return false }

            let lastFetch = note.lastContentFetch
            let isStale = lastFetch.map { $0 < cutoff } ?? true

            if !noteHasPreviewImage(note) {
                return isStale
            }

            return isStale
        }
        .sorted { ( $0.lastContentFetch ?? .distantPast ) < ( $1.lastContentFetch ?? .distantPast ) }
    }

    private func isLinkPreviewNote(_ note: Note) -> Bool {
        if note.sourceURL != nil { return true }
        if note.content.contains("**Source:**") { return true }
        if note.content.contains("![Preview Image]") { return true }
        return note.content.range(of: #"https?://"#, options: .regularExpression) != nil
    }

    private func noteHasPreviewImage(_ note: Note) -> Bool {
        return note.content.range(of: #"!\[[^\]]*\]\((https?://[^)]+)\)"#, options: .regularExpression) != nil
    }

    private func primaryURL(for note: Note) -> URL? {
        if let source = note.sourceURL, let url = URL(string: source) {
            return upgradedToHTTPS(url)
        }
        if let inline = firstURLString(in: note.content), let url = URL(string: inline) {
            return upgradedToHTTPS(url)
        }
        return nil
    }

    private func firstURLString(in text: String) -> String? {
        let pattern = #"https?:\/\/[^\s)]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        guard let matchRange = Range(match.range(at: 0), in: text) else { return nil }
        return String(text[matchRange])
    }

    private func refreshNoteIfNeeded(_ note: Note) async {
        let now = Date()
        guard let originalURL = primaryURL(for: note) else {
            await MainActor.run {
                note.lastContentFetch = now
                note.isContentFetched = true
                try? modelContext.save()
            }
            return
        }

        let secureURL = upgradedToHTTPS(originalURL)
        let urlsToTry = secureURL == originalURL ? [secureURL] : [secureURL, originalURL]

        var html: String?
        var lastError: Error?

        for candidate in urlsToTry {
            do {
                html = try await WebFetcher.fetchHTML(from: candidate)
                break
            } catch {
                lastError = error
            }
        }

        guard let html else {
            let failureDescription = lastError?.localizedDescription ?? "Unable to load page"
            await MainActor.run {
                note.lastContentFetch = now
                note.isContentFetched = false
                syncHadFailures = true
                let failureMessage = "Failed to refresh \(note.displayTitle): \(failureDescription)"
                syncStatusDetail = syncStatusDetail.isEmpty ? failureMessage : syncStatusDetail + "\n" + failureMessage
                syncMessage = failureMessage
            }
            return
        }

        let title = extractTitle(from: html) ?? note.displayTitle
        let description = extractMetaDescription(from: html)
        let metadata = extractLinkMetadata(from: html, baseURL: secureURL)

        var candidates = previewImageCandidates(from: html, baseURL: secureURL, pageURL: secureURL)
        if let fallback = fallbackFaviconURL(for: secureURL) { candidates.append(fallback) }
        candidates = dedupeURLs(candidates)

        let selectedImageURL = await chooseFirstWorkingImage(from: candidates, timeoutSeconds: 6)
        if selectedImageURL == nil {
            await MainActor.run {
                syncMessage = "No preview image found for \(note.displayTitle); will retry later."
            }
        }

        let trimmedProductName = metadata.productName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = (trimmedProductName?.isEmpty == false ? trimmedProductName : nil) ?? title
        let body = description ?? ""
        let formatted = formatWebContent(title: finalTitle, url: secureURL, content: body, imageURL: selectedImageURL?.absoluteString)

        let existingSummary = note.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var summaryText: String? = nil
        if let description, !description.isEmpty {
            if existingSummary.isEmpty || existingSummary == description {
                summaryText = description
            }
        } else if existingSummary.isEmpty && !body.isEmpty {
            let aiSummary = await generateAISummary(for: body, title: title, url: secureURL)
            summaryText = aiSummary.isEmpty ? nil : aiSummary
        }

        await MainActor.run {
            note.title = finalTitle
            if isLinkPreviewNote(note) { note.content = formatted }
            note.sourceURL = secureURL.absoluteString
            note.applyLinkMetadata(metadata)
            if let productName = metadata.productName?.trimmingCharacters(in: .whitespacesAndNewlines), !productName.isEmpty {
                note.title = productName
            }
            if let summaryText, !summaryText.isEmpty { note.summary = summaryText }
            note.lastContentFetch = now
            note.isContentFetched = selectedImageURL != nil
            try? modelContext.save()
        }
    }

    private func moveNotesToTrash(offsets: IndexSet) {
        for index in offsets { filteredNotes[index].moveToTrash() }
    }

    private func moveSelectedNote(to folder: Folder?) {
        guard let note = noteToMove else { return }
        note.folder = folder
        try? modelContext.save()
        noteToMove = nil
    }
    
    private func upgradedToHTTPS(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if components?.scheme?.lowercased() == "http" {
            components?.scheme = "https"
        }
        return components?.url ?? url
    }

    private var detailColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
    }

    private func previewImageURL(for note: Note) -> URL? {
        let pattern = #"!\[[^\]]*\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(location: 0, length: note.content.utf16.count)
        guard let match = regex.firstMatch(in: note.content, options: [], range: range),
              let urlRange = Range(match.range(at: 1), in: note.content) else { return nil }
        let rawURL = String(note.content[urlRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        if rawURL.hasPrefix("data:") { return nil }
        if let direct = URL(string: rawURL), direct.scheme != nil {
            if direct.isFileURL || direct.scheme?.lowercased().hasPrefix("http") == true { return direct }
        }
        if let encoded = rawURL.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
           let url = URL(string: encoded), url.scheme != nil {
            if url.isFileURL || url.scheme?.lowercased().hasPrefix("http") == true { return url }
        }
        if let source = note.sourceURL, let url = URL(string: source), let fallback = fallbackFaviconURL(for: url) {
            return fallback
        }
        return nil
    }

    private func cardSummary(for note: Note) -> String {
        let summary = note.summary.trimmedNonEmpty ?? note.previewText
        return summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    @MainActor
    private func processLinkURL() async {
        guard !linkURL.isEmpty else { return }
        
        let urlString = linkURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlString) else { return }
        let secureURL = upgradedToHTTPS(url)
        
        isProcessingLink = true
        defer {
            isProcessingLink = false
            linkURL = ""
        }
        
        // Create note immediately with basic info
        let initialTitle = url.host ?? url.absoluteString
        let initialContent = "Loading content from [\(initialTitle)](\(url.absoluteString))...\n\n*This note is being updated with content from the web page.*"
        
        let note = Note(title: initialTitle, content: initialContent)
        note.sourceURL = secureURL.absoluteString
        modelContext.insert(note)
        try? modelContext.save()
        
        // Fetch and update content in the background
        Task {
            do {
                let html = try await WebFetcher.fetchHTML(from: secureURL)
                
                let title = extractTitle(from: html) ?? initialTitle
                let description = extractMetaDescription(from: html)
                let metadata = extractLinkMetadata(from: html, baseURL: secureURL)
                var candidates = previewImageCandidates(from: html, baseURL: secureURL, pageURL: secureURL)
                if let fallback = fallbackFaviconURL(for: secureURL) { candidates.append(fallback) }
                candidates = dedupeURLs(candidates)

                let selectedImageURL = await chooseFirstWorkingImage(from: candidates, timeoutSeconds: 6)
                let body = description ?? ""

                let trimmedProductName = metadata.productName?.trimmingCharacters(in: .whitespacesAndNewlines)
                let finalTitle = (trimmedProductName?.isEmpty == false ? trimmedProductName : nil) ?? title
                let formatted = formatWebContent(title: finalTitle, url: secureURL, content: body, imageURL: selectedImageURL?.absoluteString)
                let aiSummary = await generateAISummary(for: body, title: title, url: secureURL)
                
                // Update the note with fetched content
                await MainActor.run {
                    note.title = finalTitle
                    note.content = formatted
                    note.applyLinkMetadata(metadata)
                    if let productName = metadata.productName?.trimmingCharacters(in: .whitespacesAndNewlines), !productName.isEmpty {
                        note.title = productName
                    }
                    if !aiSummary.isEmpty { note.summary = aiSummary }
                    try? modelContext.save()
                }
            } catch {
                // Update with error message if fetch fails
                await MainActor.run {
                    note.content = "Failed to load content from [\(initialTitle)](\(url.absoluteString))\n\nError: \(error.localizedDescription)\n\nYou can still access the link above."
                    try? modelContext.save()
                }
            }
        }
    }
    
    private func extractTitle(from html: String) -> String? {
        let pattern = #"<title[^>]*>(.*?)</title>"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        let range = NSRange(location: 0, length: html.utf16.count)
        guard let match = regex?.firstMatch(in: html, options: [], range: range) else { return nil }
        if let titleRange = Range(match.range(at: 1), in: html) {
            let raw = String(html[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.htmlDecoded.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
    
    private func extractMetaDescription(from html: String) -> String? {
        let range = NSRange(location: 0, length: html.utf16.count)
        let metaPattern = #"<meta[^>]*name=[\"']description[\"'][^>]*content=[\"'](.*?)[\"'][^>]*>"#
        let metaRegex = try? NSRegularExpression(pattern: metaPattern, options: [.caseInsensitive])

        if let match = metaRegex?.firstMatch(in: html, options: [], range: range) {
            let descRange = Range(match.range(at: 1), in: html)
            if let descRange = descRange {
                let description = String(html[descRange])
                    .htmlDecoded
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !description.isEmpty { return description }
            }
        }
        
        let pPattern = #"<p[^>]*>(.*?)</p>"#
        let pRegex = try? NSRegularExpression(pattern: pPattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        if let match = pRegex?.firstMatch(in: html, options: [], range: range) {
            let pRange = Range(match.range(at: 1), in: html)
            if let pRange = pRange {
                let paragraph = String(html[pRange])
                    .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                    .htmlDecoded
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !paragraph.isEmpty && paragraph.count > 50 { return paragraph }
            }
        }
        return nil
    }

    private func previewImageCandidates(from html: String, baseURL: URL, pageURL: URL) -> [URL] {
        var urls: [URL] = []

        if let bestString = extractBestImageURL(from: html, baseURL: baseURL), let bestURL = URL(string: bestString) {
            urls.append(upgradedToHTTPS(bestURL))
        }

        urls.append(contentsOf: metaImageCandidates(from: html, baseURL: baseURL))
        urls.append(contentsOf: imgTagCandidates(from: html, baseURL: baseURL))
        urls.append(contentsOf: videoThumbnailCandidates(from: html, baseURL: baseURL, pageURL: pageURL))

        return dedupeURLs(urls)
    }

    private func metaImageCandidates(from html: String, baseURL: URL) -> [URL] {
        let patterns = [
            #"<meta[^>]*property=[\"']og:image(:url)?[\"'][^>]*content=[\"'](.*?)[\"'][^>]*>"#,
            #"<meta[^>]*name=[\"']twitter:image(:src)?[\"'][^>]*content=[\"'](.*?)[\"'][^>]*>"#,
            #"<link[^>]*rel=[\"']image_src[\"'][^>]*href=[\"'](.*?)[\"'][^>]*>"#
        ]
        var results: [URL] = []
        let range = NSRange(location: 0, length: html.utf16.count)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { continue }
            let matches = regex.matches(in: html, options: [], range: range)
            for match in matches {
                let captureIndex = match.numberOfRanges - 1
                if captureIndex >= 1, let r = Range(match.range(at: captureIndex), in: html) {
                    let raw = String(html[r])
                    if let url = resolvedURL(from: raw, baseURL: baseURL) { results.append(upgradedToHTTPS(url)) }
                }
            }
        }
        return results
    }

    private func imgTagCandidates(from html: String, baseURL: URL) -> [URL] {
        var urls: [URL] = []
        let range = NSRange(location: 0, length: html.utf16.count)

        // srcset support: pick largest descriptor
        let srcsetPattern = #"<img[^>]*srcset=[\"']([^\"']+)[\"'][^>]*>"#
        if let regex = try? NSRegularExpression(pattern: srcsetPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            regex.enumerateMatches(in: html, options: [], range: range) { match, _, _ in
                guard let match = match, let srcsetRange = Range(match.range(at: 1), in: html) else { return }
                let srcset = String(html[srcsetRange])
                let components = srcset.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                var best: (url: URL, width: Int)? = nil
                for component in components {
                    let parts = component.split(separator: " ")
                    guard let urlPart = parts.first else { continue }
                    let width = parts.dropFirst().compactMap { token -> Int? in
                        if token.hasSuffix("w"), let value = Int(token.dropLast()) { return value }
                        return nil
                    }.first ?? 0
                    if let url = resolvedURL(from: String(urlPart), baseURL: baseURL) {
                        if best == nil || width > (best?.width ?? 0) {
                            best = (upgradedToHTTPS(url), width)
                        }
                    }
                }
                if let bestURL = best?.url { urls.append(bestURL) }
            }
        }

        // data-src / src fallback
        let imgPattern = #"<img[^>]*(data-src|data-original|src)=[\"'](.*?)[\"'][^>]*>"#
        if let regex = try? NSRegularExpression(pattern: imgPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let matches = regex.matches(in: html, options: [], range: range)
            for match in matches {
                if match.numberOfRanges >= 3, let r = Range(match.range(at: 2), in: html) {
                    let raw = String(html[r])
                    if let url = resolvedURL(from: raw, baseURL: baseURL) { urls.append(upgradedToHTTPS(url)) }
                }
            }
        }

        return urls
    }

    private func videoThumbnailCandidates(from html: String, baseURL: URL, pageURL: URL) -> [URL] {
        var results: [URL] = []
        let range = NSRange(location: 0, length: html.utf16.count)
        let posterPattern = #"<video[^>]*poster=[\"'](.*?)[\"'][^>]*>"#
        if let regex = try? NSRegularExpression(pattern: posterPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let matches = regex.matches(in: html, options: [], range: range)
            for match in matches {
                if let r = Range(match.range(at: 1), in: html), let url = resolvedURL(from: String(html[r]), baseURL: baseURL) {
                    results.append(upgradedToHTTPS(url))
                }
            }
        }
        if let ytThumbs = youtubeThumbnailURLs(from: pageURL) {
            results.append(contentsOf: ytThumbs)
        }
        return results
    }

    private func youtubeThumbnailURLs(from pageURL: URL) -> [URL]? {
        func make(_ id: String, file: String) -> URL? { URL(string: "https://i.ytimg.com/vi/\(id)/\(file)") }
        let host = pageURL.host?.lowercased() ?? ""
        var videoID: String?
        if host.contains("youtube.com") {
            if let comps = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) {
                if let v = comps.queryItems?.first(where: { $0.name == "v" })?.value { videoID = v }
                else if let last = pageURL.pathComponents.last, last != "/" { videoID = last }
            }
        } else if host.contains("youtu.be") {
            let comps = pageURL.pathComponents.filter { $0 != "/" }
            if let id = comps.last { videoID = id }
        }
        guard let id = videoID else { return nil }
        var urls: [URL] = []
        if let u = make(id, file: "maxresdefault.jpg") { urls.append(u) }
        if let u = make(id, file: "hqdefault.jpg") { urls.append(u) }
        if let u = make(id, file: "mqdefault.jpg") { urls.append(u) }
        if let u = make(id, file: "default.jpg") { urls.append(u) }
        return urls
    }

    private func resolvedURL(from raw: String, baseURL: URL) -> URL? {
        if let u = URL(string: raw, relativeTo: baseURL)?.absoluteURL { return u }
        if let u = URL(string: raw) { return u }
        return nil
    }

    private func dedupeURLs(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        var result: [URL] = []
        for u in urls {
            let key = u.absoluteString
            if !seen.contains(key) { seen.insert(key); result.append(u) }
        }
        return result
    }

    private func chooseFirstWorkingImage(from candidates: [URL], timeoutSeconds: TimeInterval) async -> URL? {
        for url in candidates {
            if await validateImageURL(url, timeoutSeconds: timeoutSeconds) { return url }
        }
        return nil
    }

    private func validateImageURL(_ url: URL, timeoutSeconds: TimeInterval) async -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeoutSeconds
        request.httpMethod = "HEAD"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) {
                // Basic content-type check if available
                if let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() {
                    if type.contains("image/") { return true }
                } else {
                    return true
                }
            }
        } catch {
            // Fall back to a tiny GET if HEAD fails or is blocked
            var getReq = URLRequest(url: url)
            getReq.timeoutInterval = timeoutSeconds
            do {
                let (data, response) = try await URLSession.shared.data(for: getReq)
                if let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode), data.count > 0 {
                    return true
                }
            } catch {
                return false
            }
        }
        return false
    }

    private func fallbackFaviconURL(for url: URL) -> URL? {
        let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        return URL(string: "https://www.google.com/s2/favicons?sz=128&domain_url=\(encoded ?? url.absoluteString)")
    }
    
    private func generateAISummary(for content: String, title: String, url: URL) async -> String {
        let model = SystemLanguageModel.default
        guard model.availability == .available, !content.isEmpty else { return "" }
        do {
            let instructions = """
                You are a helpful assistant that creates concise summaries of web content.
                Create a brief, informative summary that captures the main points and key information.
                Focus on the most important and useful content for someone who wants to save this for later reference.
                Keep the summary under 200 words and make it engaging and informative.
                Do not include any markdown formatting in your response.
                """
            let session = LanguageModelSession(instructions: instructions)
            let clippedTitle = clippedForLanguageModel(title, limit: 256)
            let clippedContent = clippedForLanguageModel(content)
            let rawPrompt = "Summarize this web content from \(url.host ?? "website"):\n\nTitle: \(clippedTitle)\n\nContent: \(clippedContent)"
            let prompt = clippedForLanguageModel(rawPrompt)
            let response = try await session.respond(to: prompt)
            // Trim and return plain text
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            // Fallback to original content if AI fails
            return content
        }
    }

    private var foldersOverlayHeader: some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

        // Compute counts for smart folders
        let linksCount = visibleLinkNotes.count
        let regularNotesCount = visibleRegularNotes.count

        // Compute which user folders to show
        let userFolders = visibleFolders
        let displayedUserFolders: [Folder] = showAllFolders ? userFolders : []

        return VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, spacing: 10) {
                // Smart folder: Notes (all)
                Button(action: { selectedSmartFolder = .allNotes }) {
                    FolderSquircleView(
                        name: "Notes",
                        count: regularNotesCount,
                        symbolName: smartNotesSymbol,
                        color: colorFromHex(smartNotesColorHex.isEmpty ? nil : smartNotesColorHex)
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Choose Icon") {
                        tempSelectedSymbol = smartNotesSymbol
                        showingSmartIconPicker = .allNotes
                    }
                    Button("Choose Color") {
                        tempSelectedColor = colorFromHex(smartNotesColorHex.isEmpty ? nil : smartNotesColorHex) ?? .blue
                        showingSmartColorPicker = .allNotes
                    }
                }

                // Smart folder: Links
                Button(action: { selectedSmartFolder = .links }) {
                    FolderSquircleView(
                        name: "Links",
                        count: linksCount,
                        symbolName: smartLinksSymbol,
                        color: colorFromHex(smartLinksColorHex.isEmpty ? nil : smartLinksColorHex)
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Choose Icon") {
                        tempSelectedSymbol = smartLinksSymbol
                        showingSmartIconPicker = .links
                    }
                    Button("Choose Color") {
                        tempSelectedColor = colorFromHex(smartLinksColorHex.isEmpty ? nil : smartLinksColorHex) ?? .blue
                        showingSmartColorPicker = .links
                    }
                }

                // User folders (limited by See All)
                ForEach(displayedUserFolders) { folder in
                    Button(action: { selectedFolder = folder }) {
                        FolderSquircleView(
                            name: folder.name,
                            count: folder.notes.filter { !$0.isDeleted }.count,
                            symbolName: folder.symbolName ?? "folder.fill",
                            color: colorFromHex(folder.colorHex)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if !userFolders.isEmpty {
                Button(action: { withAnimation(.easeInOut) { showAllFolders.toggle() } }) {
                    HStack(spacing: 6) {
                        Text(showAllFolders ? "Show Fewer Folders" : "Show All Folders (\(userFolders.count))")
                            .font(.subheadline).bold()
                        Image(systemName: showAllFolders ? "chevron.up" : "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
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

    private func folderStorageDirectory(for folder: Folder) -> URL? {
        let fm = FileManager.default
        do {
            // Prefer iCloud Drive app container if available
            if let ubiq = fm.url(forUbiquityContainerIdentifier: nil) {
                let docs = ubiq.appendingPathComponent("Documents", isDirectory: true)
                let dir = docs.appendingPathComponent("Folder_\(folder.id.uuidString)", isDirectory: true)
                if !fm.fileExists(atPath: docs.path) {
                    try fm.createDirectory(at: docs, withIntermediateDirectories: true)
                }
                if !fm.fileExists(atPath: dir.path) {
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                }
                return dir
            }
            // Fallback to local Documents directory
            let localDocs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let localDir = localDocs.appendingPathComponent("Folder_\(folder.id.uuidString)", isDirectory: true)
            if !fm.fileExists(atPath: localDir.path) {
                try fm.createDirectory(at: localDir, withIntermediateDirectories: true)
            }
            return localDir
        } catch {
            return nil
        }
    }

    // Files are stored in iCloud Drive (ubiquitous container) when available, else locally.
    private func handleImportedFiles(_ urls: [URL], to folder: Folder) {
        guard let destDir = folderStorageDirectory(for: folder) else {
            importErrorMessage = "Unable to access folder storage."
            return
        }
        for src in urls {
            let accessed = src.startAccessingSecurityScopedResource()
            defer { if accessed { src.stopAccessingSecurityScopedResource() } }
            do {
                let dest = uniqueDestinationURL(for: src, in: destDir)
                if FileManager.default.fileExists(atPath: dest.path) == false {
                    try FileManager.default.copyItem(at: src, to: dest)
                }
                createNoteForImportedFile(at: dest, folder: folder)
            } catch {
                importErrorMessage = "Failed to import \(src.lastPathComponent): \(error.localizedDescription)"
            }
        }
        try? modelContext.save()
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

    private func createNoteForImportedFile(at fileURL: URL, folder: Folder) {
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
}

private struct NoteDetailCardView: View {
    let note: Note
    let previewURL: URL?
    let summary: String

    private var trimmedSummary: String {
        summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.gray.opacity(0.12))
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.gray.opacity(0.6))
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                if let url = previewURL {
                    if url.isFileURL {
                        LocalFileImageView(fileURL: url)
                            .aspectRatio(1, contentMode: .fill)
                            .clipped()
                    } else {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(1, contentMode: .fill)
                            case .failure:
                                placeholder
                            @unknown default:
                                placeholder
                            }
                        }
                        .clipped()
                    }
                } else {
                    placeholder
                }
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.gray.opacity(0.1))
            )

            Text(note.displayTitle)
                .font(.headline)
                .foregroundColor(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !trimmedSummary.isEmpty {
                Text(trimmedSummary)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private extension Optional where Wrapped == String {
    var trimmedNonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

// MARK: - Preview
#Preview {
    ContentView().modelContainer(for: [Note.self, Folder.self], inMemory: true)
}

extension SmartFolderKind: Identifiable {
    var id: String { self.title }
}
