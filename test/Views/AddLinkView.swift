//
//  AddLinkView.swift
//

import SwiftUI
import SwiftData
import Foundation
import FoundationModels

struct AddLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var urlText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    private var model = SystemLanguageModel.default
    
    var body: some View {
        NavigationView {
            contentView
                .navigationTitle("Add Link")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) { cancelButton }
                    ToolbarItem(placement: .navigationBarTrailing) { addButton }
                }
        }
    }
    
    private var contentView: some View {
        VStack(spacing: 20) {
            urlInputSection
            loadingView
            errorView
            Spacer()
        }
    }
    
    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enter a URL").font(.headline)
            TextField("https://example.com", text: $urlText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.URL)
                .autocapitalization(.none)
                .autocorrectionDisabled()
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder private var loadingView: some View {
        if isLoading {
            VStack(spacing: 12) {
                ProgressView().scaleEffect(1.2)
                Text("Extracting content...").font(.subheadline).foregroundColor(.secondary)
            }
            .padding()
        }
    }
    
    @ViewBuilder private var errorView: some View {
        if let error = errorMessage {
            Text(error).foregroundColor(.red).font(.subheadline).multilineTextAlignment(.center).padding()
        }
    }
    
    private var cancelButton: some View { Button("Cancel") { dismiss() } }
    
    private var addButton: some View {
        Button("Add") { Task { await addLink() } }
            .disabled(urlText.isEmpty || isLoading)
    }
    
    private func addLink() async {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "Please enter a valid URL"
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        
        do {
            let html = try await WebFetcher.fetchHTML(from: url)

            let title = extractTitle(from: html) ?? url.absoluteString
            let description = extractMetaDescription(from: html)
            let imageURL = extractBestImageURL(from: html, baseURL: url)
            let metadata = extractLinkMetadata(from: html, baseURL: url)
            let body = description ?? ""

            let trimmedProductName = metadata.productName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalTitle = (trimmedProductName?.isEmpty == false ? trimmedProductName : nil) ?? title

            let formatted = formatWebContent(title: finalTitle, url: url, content: body, imageURL: imageURL)
            let aiSummary = await generateAISummary(for: body, title: title, url: url)

            let note = Note(title: finalTitle, content: formatted)
            note.sourceURL = url.absoluteString
            note.applyLinkMetadata(metadata)
            if let productName = metadata.productName?.trimmingCharacters(in: .whitespacesAndNewlines), !productName.isEmpty {
                note.title = productName
            }
            if !aiSummary.isEmpty { note.summary = aiSummary }

            modelContext.insert(note)
            try? modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Failed to fetch URL: \(error.localizedDescription)"
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
        // Look for meta description
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

        // Fallback to first paragraph
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
    
    private func extractFirstImageURL(from html: String, baseURL: URL) -> String? {
        let imgPattern = #"<img[^>]*src=[\"'](.*?)[\"']"#
        let regex = try? NSRegularExpression(pattern: imgPattern, options: [.caseInsensitive])
        let range = NSRange(location: 0, length: html.utf16.count)
        if let match = regex?.firstMatch(in: html, options: [], range: range) {
            let imgRange = Range(match.range(at: 1), in: html)
            if let imgRange = imgRange {
                let imageURLString = String(html[imgRange])
                if imageURLString.hasPrefix("//") {
                    return baseURL.scheme! + ":" + imageURLString
                } else if imageURLString.hasPrefix("/") {
                    return baseURL.scheme! + "://" + baseURL.host! + imageURLString
                } else if !imageURLString.hasPrefix("http") {
                    return baseURL.scheme! + "://" + baseURL.host! + "/" + imageURLString
                }
                return imageURLString
            }
        }
        return nil
    }
    
    private func generateAISummary(for content: String, title: String, url: URL) async -> String {
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
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return content // Fallback to original content if AI fails
        }
    }
    
}
