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
    
    @State private var showingImportPicker = false
    @State private var importStatus = ""
    @State private var showingImportAlert = false
    @State private var importResults: ImportResults?
    
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
                }
                
                Section("About") {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("Notes")
                        Spacer()
                        Text("Manage your notes and bookmarks")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: [UTType.plainText, UTType(filenameExtension: "md") ?? UTType.plainText],
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
    }
    
    private func handleFileImport(result: Result<[URL], Error>) {
        importStatus = "Processing..."
        
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                importStatus = "No file selected"
                return
            }
            
            Task {
                await importBookmarks(from: url)
            }
            
        case .failure(let error):
            importStatus = "Import failed: \(error.localizedDescription)"
        }
    }
    
    private func importBookmarks(from url: URL) async {
        do {
            guard url.startAccessingSecurityScopedResource() else {
                await MainActor.run {
                    importStatus = "Cannot access file"
                }
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            let content = try String(contentsOf: url, encoding: .utf8)
            let parser = MarkdownBookmarkParser()
            let bookmarks = parser.parse(content)
            
            await MainActor.run {
                let results = createNotesFromBookmarks(bookmarks)
                try? modelContext.save()
                
                importResults = results
                showingImportAlert = true
                importStatus = "Import completed"
            }
            
        } catch {
            await MainActor.run {
                importStatus = "Import failed: \(error.localizedDescription)"
            }
        }
    }
    
    private func createNotesFromBookmarks(_ bookmarks: [BookmarkSection]) -> ImportResults {
        var notesCount = 0
        var foldersCount = 0
        
        for section in bookmarks {
            let folder: Folder?
            
            if section.name == "Ungrouped Bookmarks" {
                folder = nil
            } else {
                // Check if folder already exists
                folder = folders.first { $0.name == section.name } ?? {
                    let newFolder = Folder(name: section.name, symbolName: section.symbolName, colorHex: section.colorHex)
                    modelContext.insert(newFolder)
                    foldersCount += 1
                    return newFolder
                }()
            }
            
            for bookmark in section.bookmarks {
                let note = Note(
                    title: bookmark.title,
                    content: formatBookmarkContent(bookmark),
                    folder: folder
                )
                modelContext.insert(note)
                notesCount += 1
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
    func parse(_ content: String) -> [BookmarkSection] {
        let lines = content.components(separatedBy: .newlines)
        var sections: [BookmarkSection] = []
        var currentSection: String? = nil
        var currentSymbolName: String? = nil
        var currentColorHex: String? = nil
        var currentBookmarks: [Bookmark] = []
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmedLine.hasPrefix("## ") {
                // Save previous section if it exists
                if let sectionName = currentSection {
                    sections.append(BookmarkSection(
                        name: sectionName,
                        symbolName: currentSymbolName,
                        colorHex: currentColorHex,
                        bookmarks: currentBookmarks
                    ))
                }
                
                // Start new section
                let fullTitle = String(trimmedLine.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Check if the title has symbol and color info in parentheses
                if let parenRange = fullTitle.range(of: " (", options: .backwards),
                   fullTitle.hasSuffix(")") {
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
                
                currentBookmarks = []
                
            } else if !trimmedLine.isEmpty && trimmedLine.contains(" - [") && trimmedLine.contains("](") {
                // Parse bookmark line
                if let bookmark = parseBookmarkLine(trimmedLine) {
                    currentBookmarks.append(bookmark)
                }
            }
        }
        
        // Add the last section
        if let sectionName = currentSection {
            sections.append(BookmarkSection(
                name: sectionName,
                symbolName: currentSymbolName,
                colorHex: currentColorHex,
                bookmarks: currentBookmarks
            ))
        }
        
        return sections
    }
    
    private func parseBookmarkLine(_ line: String) -> Bookmark? {
        // Parse format: "4/23/2025, 1:43:16 PM - [Title](URL)"
        
        // Find the " - [" separator
        guard let separatorRange = line.range(of: " - [") else { return nil }
        
        let datePart = String(line[..<separatorRange.lowerBound])
        let linkPart = String(line[separatorRange.upperBound...])
        
        // Parse the link part [Title](URL)
        guard let titleEndIndex = linkPart.firstIndex(of: "]"),
              let urlStartIndex = linkPart.range(of: "](")?.upperBound,
              let urlEndIndex = linkPart.lastIndex(of: ")") else { return nil }
        
        let title = String(linkPart[..<titleEndIndex])
        let url = String(linkPart[urlStartIndex..<urlEndIndex])
        
        // Parse the date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "M/d/yyyy, h:mm:ss a"
        let date = dateFormatter.date(from: datePart)
        
        return Bookmark(title: title, url: url, date: date)
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
