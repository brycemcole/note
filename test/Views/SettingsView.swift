//
//  SettingsView.swift
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Folder.name) private var folders: [Folder]
    @Query(filter: #Predicate<Note> { !$0.isDeleted }) private var existingNotes: [Note]
    
    @AppStorage("showPrivateFolders") private var showPrivateFolders: Bool = false
    
    @State private var showingImportPicker = false
    @State private var importStatus = ""
    @State private var showingImportAlert = false
    @State private var importResults: ImportResults?
    @State private var debugLog: [String] = []
    @State private var showingDebugLog = false
    
    var body: some View {
        NavigationView {
            List {
                Section("Import") {
                    Button {
                        showingImportPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                                .foregroundColor(.blue)
                            Text("Import Bookmarks from Markdown")
                        }
                    }
                    
                    if !importStatus.isEmpty {
                        Text(importStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if !debugLog.isEmpty {
                        Button {
                            showingDebugLog = true
                        } label: {
                            HStack {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .foregroundColor(.orange)
                                Text("View Debug Log (\(debugLog.count) entries)")
                            }
                        }
                    }
                }
                
                Section("Privacy") {
                    Toggle(isOn: $showPrivateFolders) {
                        HStack {
                            Image(systemName: "eye.slash")
                                .foregroundColor(.purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Show Private Folders")
                                Text("Display folders marked as private")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Section("About") {
                    HStack {
                        Image(systemName: "gearshape")
                        Text("Settings")
                        Spacer()
                        Text("Manage notes and imports")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: [UTType.plainText, UTType(filenameExtension: "md") ?? .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result: result)
        }
        .alert("Import Results", isPresented: $showingImportAlert) {
            Button("OK") {
                importResults = nil
                importStatus = ""
            }
        } message: {
            if let results = importResults {
                Text("Successfully imported \(results.notesCount) bookmarks into \(results.foldersCount) folders.")
            }
        }
        .sheet(isPresented: $showingDebugLog) {
            NavigationView {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(debugLog.enumerated()), id: \.offset) { index, logEntry in
                            Text(logEntry)
                                .font(.caption)
                                .foregroundColor(logEntry.contains("❌") ? .red : 
                                               logEntry.contains("✅") ? .green : 
                                               logEntry.contains("🔍") ? .blue : .primary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding()
                }
                .navigationTitle("Debug Log")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { showingDebugLog = false }
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Clear") { 
                            debugLog.removeAll() 
                            showingDebugLog = false
                        }
                    }
                }
            }
        }
    }
    
    private func handleFileImport(result: Result<[URL], Error>) {
        importStatus = "Processing..."
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                importStatus = "No file selected"
                return
            }
            Task { await importBookmarks(from: url) }
        case .failure(let error):
            importStatus = "Import failed: \(error.localizedDescription)"
        }
    }
    
    private func importBookmarks(from url: URL) async {
        await MainActor.run { debugLog.removeAll() }
        
        do {
            guard url.startAccessingSecurityScopedResource() else {
                await MainActor.run { importStatus = "Cannot access file" }
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            let content = try String(contentsOf: url, encoding: .utf8)
            let parser = MarkdownBookmarkParser()
            let bookmarks = await parser.parse(content) { log in
                await MainActor.run { debugLog.append(log) }
            }
            
            await MainActor.run {
                let results = createNotesFromBookmarks(bookmarks)
                try? modelContext.save()
                importResults = results
                showingImportAlert = true
                importStatus = "Import completed"
            }
        } catch {
            await MainActor.run { importStatus = "Import failed: \(error.localizedDescription)" }
        }
    }
    
    private func createNotesFromBookmarks(_ bookmarks: [BookmarkSection]) -> ImportResults {
        var notesCount = 0
        var foldersCount = 0
        var seenURLs = Set<String>()

        for section in bookmarks {
            let folder: Folder?
            if section.name == "Ungrouped Bookmarks" {
                folder = nil
            } else {
                // Use existing folder if present, else create
                folder = folders.first { $0.name == section.name } ?? {
                    let newFolder = Folder(name: section.name, symbolName: section.symbolName, colorHex: section.colorHex)
                    modelContext.insert(newFolder)
                    foldersCount += 1
                    return newFolder
                }()
            }
            
            for bookmark in section.bookmarks {
                let canonical = canonicalizeURLString(bookmark.url)
                if let c = canonical, seenURLs.contains(c) { continue }
                if let c = canonical, isURLAlreadyImported(c) { continue }
                let note = Note(
                    title: bookmark.title,
                    content: formatBookmarkContent(bookmark),
                    folder: folder
                )
                modelContext.insert(note)
                notesCount += 1
                if let c = canonical { seenURLs.insert(c) }
            }
        }
        
        return ImportResults(notesCount: notesCount, foldersCount: foldersCount)
    }
    
    private func formatBookmarkContent(_ bookmark: Bookmark) -> String {
        var content = "# \(bookmark.title)\n\n"
        content += "**Link:** [\(bookmark.title)](\(bookmark.url))\n\n"
        if let date = bookmark.date {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            content += "**Saved:** \(formatter.string(from: date))\n\n"
        }
        content += "---\n\n"
        content += "*This bookmark was imported from a markdown file.*"
        return content
    }

    // MARK: - Duplicate detection helpers
    private func isURLAlreadyImported(_ canonicalURL: String) -> Bool {
        // Check if any existing note's content already contains the canonical URL
        existingNotes.contains { note in
            note.content.contains(canonicalURL)
        }
    }

    private func canonicalizeURLString(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var comps = URLComponents(string: trimmed) else { return trimmed }
        
        comps.scheme = comps.scheme?.lowercased()
        comps.host = comps.host?.lowercased()
        comps.fragment = nil
        
        // Remove common tracking parameters
        if let items = comps.queryItems, !items.isEmpty {
            let dropPrefixes = ["utm_", "fbclid", "gclid", "yclid", "mc_eid", "mc_cid", "igshid"]
            let dropNames: Set<String> = ["is_retargeting", "pid", "af_channel", "utm_id", "utm_content", "utm_term", "utm_source", "utm_medium", "utm_campaign"]
            let filtered = items.filter { item in
                let name = item.name.lowercased()
                if dropNames.contains(name) { return false }
                return !dropPrefixes.contains { name.hasPrefix($0) }
            }
            comps.queryItems = filtered.isEmpty ? nil : filtered
        }
        
        // Remove default ports
        if (comps.scheme == "http" && comps.port == 80) || (comps.scheme == "https" && comps.port == 443) {
            comps.port = nil
        }
        
        // Normalize path trailing slashes (except root)
        var path = comps.percentEncodedPath
        if path.count > 1 {
            while path.hasSuffix("/") { path.removeLast() }
            comps.percentEncodedPath = path
        }
        
        return comps.string
    }
}

struct ImportResults {
    let notesCount: Int
    let foldersCount: Int
}

struct BookmarkSection {
    let name: String
    let symbolName: String?
    let colorHex: String?
    let bookmarks: [Bookmark]
}

struct Bookmark {
    let title: String
    let url: String
    let date: Date?
}

class MarkdownBookmarkParser {
    func parse(_ content: String, logger: @escaping (String) async -> Void) async -> [BookmarkSection] {
        let lines = content.components(separatedBy: .newlines)
        var sections: [BookmarkSection] = []
        var currentSection: String? = nil
        var currentSymbolName: String? = nil
        var currentColorHex: String? = nil
        var currentBookmarks: [Bookmark] = []
        
        await logger("🔍 PARSER: Starting to parse \(lines.count) lines")
        
        for (lineIndex, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }
            
            if trimmedLine.hasPrefix("## ") {
                // Save previous section if it exists
                if let sectionName = currentSection {
                    await logger("🔍 PARSER: Saving section '\(sectionName)' with \(currentBookmarks.count) bookmarks")
                    sections.append(BookmarkSection(
                        name: sectionName,
                        symbolName: currentSymbolName,
                        colorHex: currentColorHex,
                        bookmarks: currentBookmarks
                    ))
                }
                
                // Start new section
                let fullTitle = String(trimmedLine.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Extract optional metadata: "Folder (symbol, color)"
                if let parenRange = fullTitle.range(of: " (", options: .backwards), fullTitle.hasSuffix(")") {
                    currentSection = String(fullTitle[..<parenRange.lowerBound])
                    let metaInfo = String(fullTitle[parenRange.upperBound..<fullTitle.index(fullTitle.endIndex, offsetBy: -1)])
                    let components = metaInfo.components(separatedBy: ", ")
                    currentSymbolName = components.first?.trimmingCharacters(in: .whitespacesAndNewlines)
                    if components.count > 1 {
                        let colorName = components[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        currentColorHex = colorNameToHex(colorName)
                    } else {
                        currentColorHex = nil
                    }
                } else {
                    currentSection = fullTitle
                    currentSymbolName = nil
                    currentColorHex = nil
                }
                await logger("🔍 PARSER: Started new section '\(currentSection ?? "nil")'")
                currentBookmarks = []
                continue
            }
            
            // Bookmark lines look like: "4/23/2025, 1:43:16 PM - [Title](URL)"
            // Relax detection to tolerate unicode dashes/spaces; defer to parser for exact matching
            if trimmedLine.contains("[") && trimmedLine.contains("](") {
                await logger("🔍 PARSER: Line \(lineIndex) looks like bookmark: \(trimmedLine.prefix(100))...")
                if let bookmark = await parseBookmarkLine(trimmedLine, logger: logger) { 
                    await logger("✅ PARSER: Successfully parsed bookmark: \(bookmark.title)")
                    currentBookmarks.append(bookmark) 
                } else {
                    await logger("❌ PARSER: Failed to parse bookmark line: \(trimmedLine.prefix(100))...")
                }
            } else if !trimmedLine.isEmpty && currentSection != nil {
                await logger("🔍 PARSER: Line \(lineIndex) in section '\(currentSection!)' doesn't look like bookmark: \(trimmedLine.prefix(50))...")
            }
        }
        
        // Add the last section
        if let sectionName = currentSection {
            await logger("🔍 PARSER: Saving final section '\(sectionName)' with \(currentBookmarks.count) bookmarks")
            sections.append(BookmarkSection(
                name: sectionName,
                symbolName: currentSymbolName,
                colorHex: currentColorHex,
                bookmarks: currentBookmarks
            ))
        }
        
        await logger("🔍 PARSER: Final result: \(sections.count) sections, total bookmarks: \(sections.reduce(0) { $0 + $1.bookmarks.count })")
        return sections
    }
    
    private func parseBookmarkLine(_ line: String, logger: @escaping (String) async -> Void) async -> Bookmark? {
        await logger("🔍 PARSE_LINE: Input: \(line.prefix(100))...")
        
        // Normalize non-breaking/narrow spaces used in some exports
        let normalized = line
            .replacingOccurrences(of: "\u{202F}", with: " ") // narrow no-break space (main issue!)
            .replacingOccurrences(of: "\u{00A0}", with: " ") // no-break space
            .replacingOccurrences(of: "\u{2009}", with: " ") // thin space
            .replacingOccurrences(of: "\u{200A}", with: " ") // hair space
            .replacingOccurrences(of: "\u{2007}", with: " ") // figure space
            .replacingOccurrences(of: "\u{2008}", with: " ") // punctuation space
            .replacingOccurrences(of: "\t", with: " ")
        
        // Normalize multiple spaces to single space  
        var result = normalized
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        result = result.trimmingCharacters(in: .whitespaces)
        
        await logger("🔍 PARSE_LINE: Normalized: \(result.prefix(100))...")
        
        // Find the date/link separator using regex to allow '-', '–', '—' and variable spaces
        let pattern = #"^\s*(.*?)\s*[\-–—]\s*\["#
        let ns = result as NSString
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            guard let m = regex.firstMatch(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count)) else {
                await logger("❌ PARSE_LINE: Regex failed to match pattern")
                return nil 
            }
            let datePart = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            // Keep the leading '[' for the remainder
            let remainderStart = m.range.location + m.range.length - 1
            let remainder = ns.substring(from: remainderStart)
            
            // Use robust extraction of [title](url) allowing nested brackets in title
            // Strategy: use the LAST occurrence of "](" for boundary, then find the matching opening '[' for the ']' before it with bracket balancing
            guard let lastTitleUrlSep = remainder.range(of: "](", options: .backwards) else { return nil }
            
            // Use the last closing paren to better handle ')' inside URLs
            guard let urlClose = remainder.lastIndex(of: ")") else { return nil }
            
            // Balanced search for matching '[' corresponding to the ']' right before "]("
            let closeBracketIndex = remainder.index(before: lastTitleUrlSep.lowerBound)
            var depth = 1
            var idx = closeBracketIndex
            var openBracketIndex: String.Index? = nil
            while idx > remainder.startIndex {
                idx = remainder.index(before: idx)
                let ch = remainder[idx]
                if ch == "]" { depth += 1 }
                if ch == "[" {
                    depth -= 1
                    if depth == 0 { openBracketIndex = idx; break }
                }
            }
            guard let titleOpen = openBracketIndex else { return nil }
            
            let titleRange = remainder.index(after: titleOpen)..<lastTitleUrlSep.lowerBound
            let urlRange = lastTitleUrlSep.upperBound..<urlClose
            let rawTitle = String(remainder[titleRange])
            let rawURL = String(remainder[urlRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Try multiple date formats for robustness
            let formats = [
                "M/d/yyyy, h:mm:ss a",
                "M/d/yyyy, h:mm a",
                "M/d/yyyy, H:mm:ss",
                "M/d/yyyy, H:mm"
            ]
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            var parsedDate: Date? = nil
            for f in formats {
                df.dateFormat = f
                if let d = df.date(from: datePart) { parsedDate = d; break }
            }
            
            await logger("✅ PARSE_LINE: Success - Title: '\(rawTitle)', URL: '\(rawURL.prefix(50))...', Date: \(parsedDate?.description ?? "nil")")
            return Bookmark(title: rawTitle, url: rawURL, date: parsedDate)
        } catch {
            await logger("❌ PARSE_LINE: Regex error: \(error)")
            return nil
        }
    }
    
    private func colorNameToHex(_ colorName: String) -> String? {
        let colorMap: [String: String] = [
            "red": "FF0000",
            "green": "00FF00",
            "blue": "0000FF",
            "yellow": "FFFF00",
            "orange": "FFA500",
            "purple": "800080",
            "pink": "FFC0CB",
            "brown": "A52A2A",
            "gray": "808080",
            "grey": "808080",
            "black": "000000",
            "white": "FFFFFF",
            "cyan": "00FFFF",
            "magenta": "FF00FF",
            "lime": "00FF00",
            "navy": "000080",
            "teal": "008080",
            "silver": "C0C0C0",
            "gold": "FFD700",
            "indigo": "4B0082"
        ]
        return colorMap[colorName]
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Note.self, Folder.self], inMemory: true)
}

