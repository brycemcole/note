//
//  MarkdownContentView.swift
//

import SwiftUI

struct MarkdownContentView: View {
    let content: String
    @State private var showingMediaViewer = false
    @State private var selectedImageURL: URL? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Process the markdown content to extract images and make them clickable
            ForEach(processedContentElements, id: \.id) { element in
                switch element.type {
                case .text:
                    Text(element.content.markdownAttributed)
                        .textSelection(.enabled)
                case .image:
                    imageView(for: element)
                }
            }
        }
        .fullScreenCover(isPresented: $showingMediaViewer) {
            if let url = selectedImageURL {
                MediaViewer(url: url)
            }
        }
    }
    
    @ViewBuilder
    private func imageView(for element: ContentElement) -> some View {
        if let url = element.url {
            Button {
                selectedImageURL = url
                showingMediaViewer = true
            } label: {
                if url.isFileURL {
                    // Local image
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 300)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        case .failure:
                            imageFailureView(filename: url.lastPathComponent)
                        case .empty:
                            imageLoadingView()
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    // Remote image
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 300)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        case .failure:
                            imageFailureView(filename: element.altText ?? "Image")
                        case .empty:
                            imageLoadingView()
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            // Fallback for malformed image markdown
            Text("![Invalid image URL: \(element.content)]")
                .foregroundColor(.secondary)
                .italic()
        }
    }
    
    private func imageLoadingView() -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.2))
            .frame(height: 200)
            .overlay {
                ProgressView()
                    .scaleEffect(0.8)
            }
    }
    
    private func imageFailureView(filename: String) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.1))
            .frame(height: 120)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Cannot load: \(filename)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
    }
    
    // Parse the markdown content to identify images and text blocks
    private var processedContentElements: [ContentElement] {
        var elements: [ContentElement] = []
        let lines = content.components(separatedBy: .newlines)
        var currentTextBlock = ""
        var currentIndex = 0
        
        for line in lines {
            if let imageMatch = extractImageFromLine(line) {
                // If we have accumulated text, add it as a text element
                if !currentTextBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    elements.append(ContentElement(
                        id: currentIndex,
                        type: .text,
                        content: currentTextBlock.trimmingCharacters(in: .whitespacesAndNewlines),
                        url: nil,
                        altText: nil
                    ))
                    currentIndex += 1
                    currentTextBlock = ""
                }
                
                // Add the image element
                elements.append(ContentElement(
                    id: currentIndex,
                    type: .image,
                    content: line,
                    url: imageMatch.url,
                    altText: imageMatch.altText
                ))
                currentIndex += 1
            } else {
                // Add to current text block
                currentTextBlock += line + "\n"
            }
        }
        
        // Add any remaining text
        if !currentTextBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            elements.append(ContentElement(
                id: currentIndex,
                type: .text,
                content: currentTextBlock.trimmingCharacters(in: .whitespacesAndNewlines),
                url: nil,
                altText: nil
            ))
        }
        
        return elements
    }
    
    private func extractImageFromLine(_ line: String) -> (url: URL, altText: String?)? {
        // Match markdown image syntax: ![alt text](url)
        let pattern = #"!\[([^\]]*)\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        
        let range = NSRange(location: 0, length: line.utf16.count)
        guard let match = regex.firstMatch(in: line, options: [], range: range) else { return nil }
        
        let altTextRange = Range(match.range(at: 1), in: line)
        let urlRange = Range(match.range(at: 2), in: line)
        
        guard let altTextRange = altTextRange,
              let urlRange = urlRange else { return nil }
        
        let altText = String(line[altTextRange])
        let urlString = String(line[urlRange])
        
        // Try to create URL
        if let url = URL(string: urlString) {
            return (url: url, altText: altText.isEmpty ? nil : altText)
        }
        
        return nil
    }
}

private struct ContentElement {
    let id: Int
    let type: ContentType
    let content: String
    let url: URL?
    let altText: String?
    
    enum ContentType {
        case text
        case image
    }
}