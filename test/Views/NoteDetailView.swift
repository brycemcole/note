//
//  NoteDetailView.swift
//

import SwiftUI
import SwiftData
import Foundation
import FoundationModels

struct NoteDetailView: View {
    var note: Note
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @State private var isEditing = false
    @State private var showingDeleteConfirmation = false
    @State private var isGeneratingTitle = false
    @State private var isGeneratingSummary = false
    @State private var showingSummary = false
    @State private var showingAskSection = false
    @State private var askQuestion = ""
    @State private var askResponses: [AskExchange] = []
    @State private var askErrorMessage: String? = nil
    @State private var isSubmittingQuestion = false
    @Environment(\.dismiss) private var dismiss

    @AppStorage("showPrivateFolders") private var showPrivateFolders: Bool = false
    
    @State private var didExtractForURL: URL? = nil
    @State private var isExtractingFromWeb = false
    @State private var draftTitle: String
    @State private var draftContent: String
    @State private var editHistory: [EditSnapshot] = []
    @State private var historyIndex: Int = 0
    @State private var isApplyingHistory = false
    @State private var editorSelection: NSRange = NSRange(location: 0, length: 0)
    @State private var isRecheckingLink = false
    @State private var recheckErrorMessage: String? = nil

    private var model = SystemLanguageModel.default

    init(note: Note) {
        self.note = note
        _draftTitle = State(initialValue: note.displayTitle)
        _draftContent = State(initialValue: note.content)
    }
    
    private var isInPrivateFolder: Bool {
        return note.folder?.isPrivate == true
    }
    
    private var canUseAskFeature: Bool {
        model.availability == .available && !isInPrivateFolder
    }
    
    private var canSubmitQuestion: Bool {
        canUseAskFeature && !askQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmittingQuestion
    }
    
    private var primaryLinkURL: URL? {
        if let raw = note.sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           let stored = URL(string: raw) {
            return upgradedToHTTPS(stored)
        }
        return firstLinkInContent
    }

    private var firstLinkInContent: URL? {
        // Try to find a markdown link [text](url) first
        let markdownPattern = #"\[[^\]]*\]\((https?:\/\/[^)\s]+)\)"#
        if let urlString = firstMatch(in: note.content, pattern: markdownPattern) {
            if let raw = URL(string: urlString) { return upgradedToHTTPS(raw) }
            return nil
        }
        // Fallback: any plain http/https URL
        let plainPattern = #"https?:\/\/[^\s)]+"#
        if let urlString = firstMatch(in: note.content, pattern: plainPattern) {
            if let raw = URL(string: urlString) { return upgradedToHTTPS(raw) }
            return nil
        }
        return nil
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        if match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: text) {
            return String(text[r])
        }
        if let r0 = Range(match.range(at: 0), in: text) { return String(text[r0]) }
        return nil
    }
    
    private func extractSummaryFromWebPage(for url: URL) async {
        let shouldProceed: Bool = await MainActor.run {
            guard didExtractForURL != url, !isExtractingFromWeb else { return false }
            isExtractingFromWeb = true
            return true
        }
        guard shouldProceed else { return }

        defer {
            Task { await MainActor.run { isExtractingFromWeb = false } }
        }

        do {
            // Fetch the raw HTML of the page off the main actor
            let html = try await WebFetcher.fetchHTML(from: url)

            // Basic extraction from HTML
            let extractedTitle = extractHTMLTitle(from: html) ?? url.absoluteString
            let extractedDescription = extractHTMLMetaDescription(from: html)
            let (price, currency) = extractHTMLPrice(from: html)
            let (isbn, author) = extractHTMLBookInfo(from: html)

            let model = SystemLanguageModel.default

            var baseFacts: [String] = []
            if let p = price, !p.isEmpty {
                baseFacts.append("Price: \(currency ?? "") \(p)")
            }
            if let i = isbn, !i.isEmpty { baseFacts.append("ISBN: \(i)") }
            if let a = author, !a.isEmpty { baseFacts.append("Author: \(a)") }

            var contextSnippet = extractedDescription ?? ""
            if contextSnippet.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                let textOnly = html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
                contextSnippet = String(textOnly.prefix(1200))
            }

            var summaryText: String = ""
            if model.availability == .available {
                let instructions = """
                    You are a helpful assistant that creates a concise, useful summary of a web page for a note-taking app.
                    - If product-like info is present (price/currency), include it succinctly.
                    - If book/textbook signals are present (author/ISBN), include them.
                    - Otherwise, summarize the main topic clearly.
                    Keep it under 150 words. Return plain sentences, no markdown.
                    """
                let session = LanguageModelSession(instructions: instructions)
                let clippedFacts = clippedForLanguageModel(baseFacts.joined(separator: "; "), limit: 512)
                let clippedTitle = clippedForLanguageModel(extractedTitle, limit: 256)
                let clippedContext = clippedForLanguageModel(contextSnippet)
                let rawPrompt = """
                URL: \(url.absoluteString)
                Title: \(clippedTitle)
                Facts: \(clippedFacts)
                Context: \(clippedContext)
                """
                let prompt = clippedForLanguageModel(rawPrompt)
                do {
                    let response = try await session.respond(to: prompt)
                    summaryText = response.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                } catch {
                    summaryText = contextSnippet
                }
            } else {
                summaryText = contextSnippet
            }

            guard !summaryText.isEmpty else { return }

            await MainActor.run {
                note.summary = summaryText
                try? modelContext.save()
                didExtractForURL = url
            }
        } catch {
            // Ignore errors; keep UI responsive
        }
    }
    
    private func extractHTMLTitle(from html: String) -> String? {
        let pattern = #"<title[^>]*>(.*?)</title>"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        let range = NSRange(location: 0, length: html.utf16.count)
        guard let match = regex?.firstMatch(in: html, options: [], range: range),
              let r = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[r]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    private func extractHTMLMetaDescription(from html: String) -> String? {
        let range = NSRange(location: 0, length: html.utf16.count)
        let metaPattern = #"<meta[^>]*name=[\"']description[\"'][^>]*content=[\"'](.*?)[\"'][^>]*>"#
        let metaRegex = try? NSRegularExpression(pattern: metaPattern, options: [.caseInsensitive])
        if let match = metaRegex?.firstMatch(in: html, options: [], range: range),
           let r = Range(match.range(at: 1), in: html) {
            let description = String(html[r])
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            return description.isEmpty ? nil : description
        }
        return nil
    }

    private func extractHTMLPrice(from html: String) -> (String?, String?) {
        // Try common meta tags first
        let range = NSRange(location: 0, length: html.utf16.count)
        let priceMetaPattern = #"<meta[^>]*property=[\"'](?:product:price:amount|og:price:amount)[\"'][^>]*content=[\"'](.*?)[\"'][^>]*>"#
        let currencyMetaPattern = #"<meta[^>]*property=[\"'](?:product:price:currency|og:price:currency)[\"'][^>]*content=[\"'](.*?)[\"'][^>]*>"#
        let priceMetaRegex = try? NSRegularExpression(pattern: priceMetaPattern, options: [.caseInsensitive])
        let currencyMetaRegex = try? NSRegularExpression(pattern: currencyMetaPattern, options: [.caseInsensitive])
        var price: String? = nil
        var currency: String? = nil
        if let m = priceMetaRegex?.firstMatch(in: html, options: [], range: range), let r = Range(m.range(at: 1), in: html) {
            price = String(html[r])
        }
        if let m = currencyMetaRegex?.firstMatch(in: html, options: [], range: range), let r = Range(m.range(at: 1), in: html) {
            currency = String(html[r])
        }
        // Fallback: scan visible text for currency symbols and numbers
        if price == nil {
            let textOnly = html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            let pricePattern = #"([\$€£¥₹])\s*(\d+[\d.,]*)"#
            if let regex = try? NSRegularExpression(pattern: pricePattern, options: []),
               let match = regex.firstMatch(in: textOnly, options: [], range: NSRange(location: 0, length: textOnly.utf16.count)) {
                if let r1 = Range(match.range(at: 1), in: textOnly), let r2 = Range(match.range(at: 2), in: textOnly) {
                    currency = currency ?? String(textOnly[r1])
                    price = String(textOnly[r2])
                }
            }
        }
        return (price, currency)
    }

    private func extractHTMLBookInfo(from html: String) -> (String?, String?) {
        let range = NSRange(location: 0, length: html.utf16.count)
        // ISBN
        let isbnPattern = #"(?:itemprop=\"isbn\"[^>]*content=\"(.*?)\"|meta[^>]*name=\"isbn\"[^>]*content=\"(.*?)\")"#
        let isbnRegex = try? NSRegularExpression(pattern: isbnPattern, options: [.caseInsensitive])
        var isbn: String? = nil
        if let m = isbnRegex?.firstMatch(in: html, options: [], range: range) {
            for i in 1..<m.numberOfRanges {
                if let r = Range(m.range(at: i), in: html) { isbn = String(html[r]); break }
            }
        }
        // Author
        let authorPattern = #"(?:itemprop=\"author\"[^>]*content=\"(.*?)\"|meta[^>]*name=\"author\"[^>]*content=\"(.*?)\")"#
        let authorRegex = try? NSRegularExpression(pattern: authorPattern, options: [.caseInsensitive])
        var author: String? = nil
        if let m = authorRegex?.firstMatch(in: html, options: [], range: range) {
            for i in 1..<m.numberOfRanges {
                if let r = Range(m.range(at: i), in: html) { author = String(html[r]); break }
            }
        }
        return (isbn, author)
    }
    
    var body: some View {
        mainContent
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if isEditing {
                        undoButton
                        redoButton
                        saveButton
                    }
                    toolbarButton
                }
            }
            .alert("Delete Note", isPresented: $showingDeleteConfirmation) { deleteAlert } message: {
                Text("Are you sure you want to delete this note? It will be moved to trash.")
            }
            .alert("Recheck Failed", isPresented: Binding(
                get: { recheckErrorMessage != nil },
                set: { if !$0 { recheckErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { recheckErrorMessage = nil }
            } message: {
                Text(recheckErrorMessage ?? "Unknown error")
            }
            .onChange(of: isEditing) { editing in
                if editing {
                    beginEditingSession()
                } else {
                    endEditingSession()
                }
            }
            .onChange(of: draftTitle) { _ in recordSnapshotIfNeeded() }
            .onChange(of: draftContent) { _ in recordSnapshotIfNeeded() }
    }

    @ViewBuilder private var mainContent: some View {
        VStack {
            if isEditing {
                EditNoteView(title: $draftTitle,
                             content: $draftContent,
                             selectedRange: $editorSelection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .onDisappear {
                        if isEditing { saveEdits() }
                    }
            } else {
                noteDetailContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private var noteDetailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                noteTitle
                noteHeader
                productInfoSection
                webPreviewSection
                summarySection
                askSection
                noteContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
    
    private var noteTitle: some View {
        Text(note.displayTitle)
            .font(isLinkNote ? .title2 : .title)
            .fontWeight(.bold)
            .lineLimit(isLinkNote ? 3 : nil)
            .multilineTextAlignment(.leading)
    }

    private var isLinkNote: Bool {
        if let source = note.sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty {
            return true
        }
        return primaryLinkURL != nil
    }
    
    private var noteHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Created: \(note.dateCreated.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if isLinkNote {
                        Button { openLink() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "safari")
                                Text("Open Link")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .controlSize(.small)
                    }

                    Button {
                        if note.summary == nil || note.summary?.isEmpty == true {
                            Task { await generateSummary(); showingSummary = true }
                        } else {
                            showingSummary.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showingSummary ? "text.badge.minus" : "text.badge.plus")
                            Text("Summary")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                    .controlSize(.small)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingAskSection.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showingAskSection ? "questionmark.bubble.fill" : "questionmark.bubble")
                            Text("Ask")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                    .controlSize(.small)

                    if let name = note.folder?.name, !name.isEmpty {
                        Button {
                            // Placeholder for future folder navigation.
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "folder.fill")
                                Text(name)
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                        .controlSize(.small)
                    }

                    if isRecheckingLink {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.leading, 2)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
    
    @ViewBuilder private var productInfoSection: some View {
        if note.isProductLink {
            VStack(alignment: .leading, spacing: 10) {
                Text(note.productName?.isEmpty == false ? note.productName! : note.displayTitle)
                    .font(.headline)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 12) {
                    if let price = note.productPriceDisplay {
                        Text(price)
                            .font(.title3.weight(.semibold))
                    }
                    if let availability = note.productAvailabilityDisplay {
                        let inStock = note.productInStock
                        Text(availability)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(inStock == false ? .red : (inStock == true ? .green : .secondary))
                    }
                }

                if let checked = note.linkMetadataUpdatedAt {
                    Text("Last checked \(RelativeDateTimeFormatter.shared.localizedString(for: checked, relativeTo: Date()))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.gray.opacity(0.08))
            )
        }
    }

    @ViewBuilder private var summarySection: some View {
        if !isInPrivateFolder, showingSummary, let summary = note.summary, !summary.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Summary").font(.headline)
                Text(summary.markdownAttributed)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder private var askSection: some View {
        if showingAskSection {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ask This Note").font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Type your question", text: $askQuestion)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isSubmittingQuestion)
                        .submitLabel(.send)
                        .onSubmit { Task { await submitAskQuestion() } }
                    HStack(spacing: 12) {
                        if isSubmittingQuestion {
                            ProgressView()
                                .progressViewStyle(.circular)
                        }
                        Spacer()
                        Button {
                            Task { await submitAskQuestion() }
                        } label: {
                            Label("Send", systemImage: "paperplane.fill")
                                .labelStyle(.titleAndIcon)
                        }
                        .disabled(!canSubmitQuestion)
                    }
                }
                if !canUseAskFeature {
                    Text("Asking questions is unavailable when the note is private or the on-device language model is offline.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let message = askErrorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                ForEach(askResponses) { exchange in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(exchange.question)
                            .font(.subheadline)
                            .bold()
                        Text(exchange.answer)
                            .font(.body)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.gray.opacity(0.1))
                    )
                }
            }
        }
    }
    
    @ViewBuilder private var webPreviewSection: some View {
        if let url = primaryLinkURL {
            WebPreviewView(
                url: upgradedToHTTPS(url),
                primaryTitle: note.displayTitle,
                primarySummary: note.summary
            )
                .frame(height: 480)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
        }
    }
    
    private var noteContent: some View {
        MarkdownContentView(content: sanitizedNoteContent)
    }

    private var sanitizedNoteContent: String {
        guard isLinkNote else { return note.content }

        var lines = note.content.components(separatedBy: .newlines)
        guard let firstIndex = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return note.content
        }

        let firstLine = lines[firstIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutHeading = firstLine.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)

        guard titlesMatch(withoutHeading, note.displayTitle) else { return note.content }

        lines.remove(at: firstIndex)
        if firstIndex < lines.count && lines[firstIndex].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.remove(at: firstIndex)
        }

        while let sourceIndex = lines.firstIndex(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            let lower = trimmed.lowercased()
            return lower.hasPrefix("**source:**") || lower.hasPrefix("source:")
        }) {
            lines.remove(at: sourceIndex)
            if sourceIndex < lines.count && lines[sourceIndex].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.remove(at: sourceIndex)
            }
        }

        while let imageIndex = lines.firstIndex(where: { line in
            line.range(of: "![Preview Image]", options: [.caseInsensitive]) != nil
        }) {
            lines.remove(at: imageIndex)
            if imageIndex < lines.count && lines[imageIndex].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.remove(at: imageIndex)
            }
        }

        return lines.joined(separator: "\n")
    }

    private func openLink() {
        guard let url = primaryLinkURL else { return }
        openURL(url)
    }

private func recheckLinkMetadata() async {
        guard !isRecheckingLink, let url = primaryLinkURL else { return }
        await MainActor.run {
            isRecheckingLink = true
            recheckErrorMessage = nil
        }

        defer {
            Task { await MainActor.run { isRecheckingLink = false } }
        }

        do {
            let html = try await WebFetcher.fetchHTML(from: url)
            let newTitle = extractHTMLTitle(from: html)?.htmlDecoded.trimmingCharacters(in: .whitespacesAndNewlines) ?? note.displayTitle
            let description = extractHTMLMetaDescription(from: html)
            let imageURL = extractBestImageURL(from: html, baseURL: url)
            let metadata = extractLinkMetadata(from: html, baseURL: url)
            let body = description ?? ""
            let trimmedProductName = metadata.productName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalTitle = (trimmedProductName?.isEmpty == false ? trimmedProductName : nil) ?? newTitle
            let formatted = formatWebContent(title: finalTitle, url: url, content: body, imageURL: imageURL)

            await MainActor.run {
                note.title = finalTitle
                note.content = formatted
                note.sourceURL = url.absoluteString
                note.applyLinkMetadata(metadata)
                if let productName = metadata.productName?.trimmingCharacters(in: .whitespacesAndNewlines), !productName.isEmpty {
                    note.title = productName
                }
                if (note.summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true), let description = description, !description.isEmpty {
                    note.summary = description
                }
                try? modelContext.save()
            }
        } catch {
            await MainActor.run {
                recheckErrorMessage = error.localizedDescription
            }
        }
    }
    
    private var toolbarButton: some View {
        Menu {
            if isLinkNote {
                if isRecheckingLink {
                    Label("Rechecking…", systemImage: "clock")
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        Task { await recheckLinkMetadata() }
                    } label: {
                        Label("Recheck Link", systemImage: "arrow.clockwise")
                    }
                }
                Divider()
            }
            editButton
            shareButton
            summarizeButton
            generateTitleButton
            Divider()
            deleteButton
        } label: { Image(systemName: "ellipsis.circle") }
    }

    private var editButton: some View {
        Button {
            draftTitle = note.displayTitle
            draftContent = note.content
            isEditing = true
        } label: { Label("Edit", systemImage: "pencil") }
    }

    private var saveButton: some View {
        Button(action: { saveEdits() }) {
            Image(systemName: "externaldrive.fill")
        }
        .accessibilityLabel("Save")
    }

    private var shareButton: some View { ShareLink(item: note.content, subject: Text(note.displayTitle)) { Label("Share", systemImage: "square.and.arrow.up") } }
    
    private var summarizeButton: some View {
        Button { Task { await generateSummary() } } label: { Label("Summarize", systemImage: "sparkles") }
            .disabled(isGeneratingSummary || model.availability != .available || isInPrivateFolder)
    }
    
    private var generateTitleButton: some View {
        Button { Task { await generateTitle() } } label: { Label("Generate Title", systemImage: "text.badge.plus") }
            .disabled(isGeneratingTitle || model.availability != .available)
    }

    private var deleteButton: some View {
        Button(role: .destructive) { showingDeleteConfirmation = true } label: { Label("Delete", systemImage: "trash") }
    }
    
    @ViewBuilder private var deleteAlert: some View {
        Button("Cancel", role: .cancel) { }
        Button("Delete", role: .destructive) {
            note.moveToTrash()
            try? modelContext.save()
            dismiss()
        }
    }

    private var hasPendingChanges: Bool {
        draftTitle != note.displayTitle || draftContent != note.content
    }

    private func saveEdits() {
        if hasPendingChanges {
            note.title = draftTitle
            note.content = draftContent
            try? modelContext.save()
        }
        isEditing = false
    }

    private var canUndo: Bool { historyIndex > 0 }
    private var canRedo: Bool { historyIndex < editHistory.count - 1 }

    private var undoButton: some View {
        Button {
            undoEdits()
        } label: {
            Image(systemName: "arrow.uturn.backward")
        }
        .disabled(!canUndo)
        .accessibilityLabel("Undo")
    }

    private var redoButton: some View {
        Button {
            redoEdits()
        } label: {
            Image(systemName: "arrow.uturn.forward")
        }
        .disabled(!canRedo)
        .accessibilityLabel("Redo")
    }

    private func beginEditingSession() {
        let initialSelection = editorSelection.clamped(for: draftContent)
        editorSelection = initialSelection
        let initial = EditSnapshot(title: draftTitle,
                                   content: draftContent,
                                   selection: initialSelection)
        editHistory = [initial]
        historyIndex = 0
    }

    private func endEditingSession() {
        editHistory.removeAll()
        historyIndex = 0
        isApplyingHistory = false
        editorSelection = NSRange(location: 0, length: 0)
    }

    private func recordSnapshotIfNeeded() {
        guard isEditing, !isApplyingHistory else { return }
        let clampedSelection = editorSelection.clamped(for: draftContent)
        editorSelection = clampedSelection
        let current = EditSnapshot(title: draftTitle, content: draftContent, selection: clampedSelection)

        if editHistory.isEmpty {
            editHistory = [current]
            historyIndex = 0
            return
        }

        if historyIndex < editHistory.count - 1 {
            editHistory = Array(editHistory.prefix(historyIndex + 1))
        }

        if current == editHistory.last { return }

        editHistory.append(current)
        historyIndex = editHistory.count - 1

        if editHistory.count > maxHistoryEntries {
            let overflow = editHistory.count - maxHistoryEntries
            editHistory.removeFirst(overflow)
            historyIndex = max(0, historyIndex - overflow)
        }
    }

    private func undoEdits() {
        guard canUndo else { return }
        historyIndex -= 1
        applySnapshot(editHistory[historyIndex])
    }

    private func redoEdits() {
        guard canRedo else { return }
        historyIndex += 1
        applySnapshot(editHistory[historyIndex])
    }

    private func applySnapshot(_ snapshot: EditSnapshot) {
        isApplyingHistory = true
        draftTitle = snapshot.title
        draftContent = snapshot.content
        editorSelection = snapshot.selection.clamped(for: snapshot.content)
        DispatchQueue.main.async {
            isApplyingHistory = false
        }
    }

    private let maxHistoryEntries = 100

    private struct EditSnapshot: Equatable {
        let title: String
        let content: String
        let selection: NSRange

        static func == (lhs: EditSnapshot, rhs: EditSnapshot) -> Bool {
            lhs.title == rhs.title &&
            lhs.content == rhs.content &&
            lhs.selection.location == rhs.selection.location &&
            lhs.selection.length == rhs.selection.length
        }
    }

    private struct AskExchange: Identifiable {
        let id = UUID()
        let question: String
        let answer: String
    }

    @MainActor private func submitAskQuestion() async {
        let trimmedQuestion = askQuestion.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else { return }
        guard canUseAskFeature else {
            askErrorMessage = "Can't reach the language model right now."
            return
        }

        askErrorMessage = nil
        isSubmittingQuestion = true
        defer { isSubmittingQuestion = false }

        do {
            let instructions = """
                You answer questions about the provided note content.
                Respond using only what is contained in the note.
                If the note does not include the answer, reply that the information is not available in the note.
                Keep responses concise and conversational.
                """
            let session = LanguageModelSession(instructions: instructions)
            let clippedContent = clippedForLanguageModel(note.content)
            let promptBody = """
            Note content:
            \(clippedContent)

            Question: \(trimmedQuestion)

            Provide the best answer you can using the note.
            """
            let prompt = clippedForLanguageModel(promptBody)
            let response = try await session.respond(to: prompt)
            let cleanedAnswer = response.content
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                .removingLeadingListMarkers
            let exchange = AskExchange(question: trimmedQuestion, answer: cleanedAnswer)
            askResponses.insert(exchange, at: 0)
            askQuestion = ""
        } catch {
            askErrorMessage = "Something went wrong while asking the question. Please try again."
            print("Failed to ask question: \(error)")
        }
    }

    @MainActor private func generateSummary() async {
        guard !isInPrivateFolder else { return }
        guard model.availability == .available else { return }
        isGeneratingSummary = true
        defer { isGeneratingSummary = false }
        guard note.summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true else { return }
        do {
            let instructions = """
                You are a helpful assistant that creates descriptive overviews of document content.
                
                Your job is to describe WHAT the document is about and WHO it's for, NOT to summarize the specific details or steps.
                
                Think of this as writing a brief description that would appear in a library catalog or app store description.
                
                Examples:
                - For a Venus Fly Trap care guide → "A comprehensive care guide for Venus Fly Trap owners covering feeding, watering, and maintenance"
                - For a recipe → "A step-by-step recipe for making homemade bread with tips for beginners"
                - For meeting notes → "Meeting notes covering project updates, budget discussions, and next steps"
                - For a tutorial → "A beginner-friendly tutorial explaining how to set up and use SwiftUI"
                
                Keep it under 100 words and focus on describing the PURPOSE and AUDIENCE of the content.
                Do NOT include specific details, steps, or facts from the content.
                Only return the description text, nothing else.
                Do not introduce list bullets; return plain sentences.
                """
            let session = LanguageModelSession(instructions: instructions)
            let clippedContent = clippedForLanguageModel(note.content)
            let prompt = clippedForLanguageModel("Create a descriptive overview of what this document is about and who it's for: \(clippedContent)")
            let response = try await session.respond(to: prompt)
            let generatedSummary = response.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let sanitized = generatedSummary.removingLeadingListMarkers
            note.summary = sanitized
            try? modelContext.save()
        } catch {
            print("Failed to generate summary: \(error)")
        }
    }
    
    @MainActor private func generateTitle() async {
        guard !isInPrivateFolder else { return }
        guard model.availability == .available else { return }
        isGeneratingTitle = true
        defer { isGeneratingTitle = false }
        do {
            let instructions = """
                You are a helpful assistant that creates concise, descriptive titles for notes.
                Analyze the content and generate a clear, specific title that captures the main topic.
                Keep the title under 50 characters and make it engaging.
                
                IMPORTANT: Return ONLY plain text for the title. 
                Do NOT include any markdown formatting like:
                - Headers (# ## ###)
                - Bold (**text**)
                - Italic (*text*)
                - Code (`text`)
                - Any other markdown syntax
                
                Just return clean, readable title text with no formatting symbols.
                """
            let session = LanguageModelSession(instructions: instructions)
            let clippedContent = clippedForLanguageModel(note.content)
            let prompt = clippedForLanguageModel("Create a plain text title (no markdown) for this note content: \(clippedContent)")
            let response = try await session.respond(to: prompt)
            let cleanedTitle = cleanMarkdownFromTitle(response.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))
            if !cleanedTitle.isEmpty {
                note.title = cleanedTitle
                try? modelContext.save()
            }
        } catch {
            print("Failed to generate title: \(error)")
        }
    }
    
    private func cleanMarkdownFromTitle(_ title: String) -> String {
        var cleanedTitle = title
        cleanedTitle = cleanedTitle.replacingOccurrences(of: "**", with: "") // Bold
        cleanedTitle = cleanedTitle.replacingOccurrences(of: "*", with: "")  // Italic/Bold
        cleanedTitle = cleanedTitle.replacingOccurrences(of: "`", with: "")  // Code
        cleanedTitle = cleanedTitle.replacingOccurrences(of: "# ", with: "") // Headers
        cleanedTitle = cleanedTitle.replacingOccurrences(of: "## ", with: "")
        cleanedTitle = cleanedTitle.replacingOccurrences(of: "### ", with: "")
        cleanedTitle = cleanedTitle.replacingOccurrences(of: "#### ", with: "")
        cleanedTitle = cleanedTitle.replacingOccurrences(of: "##### ", with: "")
        cleanedTitle = cleanedTitle.replacingOccurrences(of: "###### ", with: "")
        return cleanedTitle.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}

private extension RelativeDateTimeFormatter {
    static let shared: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

private extension NSRange {
    func clamped(for text: String) -> NSRange {
        let nsString = text as NSString
        let safeLocation = max(0, min(location, nsString.length))
        let safeLength = max(0, min(length, nsString.length - safeLocation))
        return NSRange(location: safeLocation, length: safeLength)
    }
}
