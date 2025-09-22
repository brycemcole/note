//
//  SharedDataManager.swift
//

import Foundation
import SwiftData
import FoundationModels

@MainActor
class SharedDataManager {
    static let shared = SharedDataManager()
    static let appGroupIdentifier = "group.com.br3dev.test" 
    
    private var modelContainer: ModelContainer?
    
    private init() {}
    
    func configure(with container: ModelContainer) {
        self.modelContainer = container
        syncFolderSnapshot()
    }
    
    private var sharedModelContainer: ModelContainer {
        if let container = modelContainer {
            return container
        }

        let schema = Schema([Note.self, Folder.self])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        
        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            self.modelContainer = container
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
    
    func syncFolderSnapshot() {
        guard let sharedDefaults = UserDefaults(suiteName: Self.appGroupIdentifier) else { return }
        let context = ModelContext(sharedModelContainer)
        let descriptor = FetchDescriptor<Folder>(sortBy: [SortDescriptor(\.name)])
        let folders = (try? context.fetch(descriptor)) ?? []
        let payload: [[String: Any]] = folders.map { folder in
            [
                "id": folder.id.uuidString,
                "name": folder.name,
                "isPrivate": folder.isPrivate
            ]
        }
        sharedDefaults.set(payload, forKey: "availableFolders")
        sharedDefaults.synchronize()
    }
    
    func createNoteFromSharedContent(_ content: SharedContent) async throws {
        let context = ModelContext(sharedModelContainer)

        var noteContent = ""
        var noteTitle = content.explicitTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var targetFolder: Folder? = nil
        var linkMetadata: LinkMetadata? = nil

        if let folderID = content.folderID {
            let descriptor = FetchDescriptor<Folder>(predicate: #Predicate { $0.id == folderID })
            targetFolder = try? context.fetch(descriptor).first
        }

        switch content.type {
        case .text:
            noteContent = content.text
            if noteTitle.isEmpty {
                noteTitle = generateTitleFromText(content.text)
            }

        case .url:
            let urlString = content.sourceURL ?? content.text
            if let url = URL(string: urlString) {
                noteContent = "[\(url.host ?? "Link")](\(url.absoluteString))"
                if let extracted = await extractContentFromURL(url) {
                    noteContent += "\n\n" + extracted.content
                    linkMetadata = extracted.metadata
                    if noteTitle.isEmpty, let productName = extracted.metadata.productName, !productName.isEmpty {
                        noteTitle = productName
                    }
                }
                noteTitle = noteTitle.isEmpty ? (url.host ?? "Shared Link") : noteTitle
            } else {
                noteContent = content.text
                if noteTitle.isEmpty {
                    noteTitle = generateTitleFromText(content.text)
                }
            }
        }

        noteContent = noteContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if noteContent.isEmpty { noteContent = content.text }
        noteContent = noteContent.removingLeadingListMarkers

        let finalTitle = noteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = Note(title: finalTitle.isEmpty ? generateTitleFromText(noteContent) : finalTitle,
                        content: noteContent,
                        folder: targetFolder)
        if case .url = content.type {
            note.sourceURL = content.sourceURL ?? content.text
            note.applyLinkMetadata(linkMetadata)
            if let productName = linkMetadata?.productName?.trimmingCharacters(in: .whitespacesAndNewlines), !productName.isEmpty {
                note.title = productName
            }
        }
        context.insert(note)

        await generateSummaryForNote(note, context: context)

        try context.save()
        syncFolderSnapshot()
    }
    
    private func generateTitleFromText(_ text: String) -> String {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .prefix(8)
        
        let title = words.joined(separator: " ")
        return title.count > 50 ? String(title.prefix(47)) + "..." : title
    }
    
    private func extractContentFromURL(_ url: URL) async -> (content: String, metadata: LinkMetadata)? {
        do {
            let html = try await WebFetcher.fetchHTML(from: url)
            
            // Extract title and description
            let title = extractHTMLTitle(from: html)
            let description = extractHTMLMetaDescription(from: html)
            let metadata = extractLinkMetadata(from: html, baseURL: url)

            let decodedTitle = title?.htmlDecoded.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let decodedDescription = description?.htmlDecoded.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if decodedTitle.isEmpty && decodedDescription.isEmpty { return nil }

            let content = formatWebContent(
                title: decodedTitle.isEmpty ? (url.host ?? "Link") : decodedTitle,
                url: url,
                content: decodedDescription,
                imageURL: extractBestImageURL(from: html, baseURL: url)
            )
            return (content, metadata)
            
        } catch {
            return nil
        }
    }
    
    private func extractHTMLTitle(from html: String) -> String? {
        let pattern = #"<title[^>]*>(.*?)</title>"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        let range = NSRange(location: 0, length: html.utf16.count)
        guard let match = regex?.firstMatch(in: html, options: [], range: range),
              let r = Range(match.range(at: 1), in: html) else { return nil }
        let raw = String(html[r]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return raw.htmlDecoded.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func extractHTMLMetaDescription(from html: String) -> String? {
        let range = NSRange(location: 0, length: html.utf16.count)
        let metaPattern = #"<meta[^>]*name=[\"']description[\"'][^>]*content=[\"'](.*?)[\"'][^>]*>"#
        let metaRegex = try? NSRegularExpression(pattern: metaPattern, options: [.caseInsensitive])
        if let match = metaRegex?.firstMatch(in: html, options: [], range: range),
           let r = Range(match.range(at: 1), in: html) {
            let description = String(html[r])
                .htmlDecoded
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !description.isEmpty { return description }
        }

        let paragraphPattern = #"<p[^>]*>(.*?)</p>"#
        let paragraphRegex = try? NSRegularExpression(pattern: paragraphPattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        if let match = paragraphRegex?.firstMatch(in: html, options: [], range: range),
           let r = Range(match.range(at: 1), in: html) {
            let paragraph = String(html[r])
                .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                .htmlDecoded
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !paragraph.isEmpty && paragraph.count > 80 { return paragraph }
        }

        return nil
    }
    
    private func generateSummaryForNote(_ note: Note, context: ModelContext) async {
        let model = SystemLanguageModel.default
        guard model.availability == .available else { return }
        if let existing = note.summary, !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }

        do {
            let instructions = """
                You are a helpful assistant that creates descriptive overviews of document content.
                Your job is to describe WHAT the document is about and WHO it's for, NOT to summarize the specific details or steps.
                Keep it under 100 words and focus on describing the PURPOSE and AUDIENCE of the content.
                Only return the description text, nothing else.
                """
            let session = LanguageModelSession(instructions: instructions)
            let clippedContent = clippedForLanguageModel(note.content)
            let prompt = clippedForLanguageModel("Create a descriptive overview of what this document is about and who it's for: \(clippedContent)")
            let response = try await session.respond(to: prompt)
            let generatedSummary = response.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            note.summary = generatedSummary
            try context.save()
        } catch {
            // Ignore summary generation errors
        }
    }
}

struct SharedContent {
    enum ContentType {
        case text
        case url
    }
    
    let text: String
    let type: ContentType
    let folderID: UUID?
    let explicitTitle: String?
    let sourceURL: String?
    
    init(text: String,
         isURL: Bool? = nil,
         folderID: UUID? = nil,
         explicitTitle: String? = nil,
         sourceURL: String? = nil) {
        self.text = text
        self.folderID = folderID
        self.explicitTitle = explicitTitle
        self.sourceURL = sourceURL

        if let isURL = isURL {
            self.type = isURL ? .url : .text
        } else if text.hasPrefix("http://") || text.hasPrefix("https://") {
            self.type = .url
        } else {
            self.type = .text
        }
    }
}
