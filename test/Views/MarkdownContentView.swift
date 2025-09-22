//
//  MarkdownContentView.swift
//

import SwiftUI
import Foundation
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct MarkdownContentView: View {
    let content: String
    
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(parseMarkdownElements(content), id: \.id) { (element: MarkdownElement) in
                renderElement(element)
            }
        }
    }

    private func renderCodeBlock(language: String?, code: String) -> some View {
        CodeBlockView(language: language, code: code)
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            return .title
        case 2:
            return .title2
        case 3:
            return .title3
        default:
            return .headline
        }
    }

    private func headingTopPadding(for level: Int) -> CGFloat {
        switch level {
        case 1:
            return 20
        case 2:
            return 16
        default:
            return 12
        }
    }

    private func renderElement(_ element: MarkdownElement) -> some View {
        Group {
            switch element.type {
            case .paragraph(let text):
                Text(text.markdownAttributed)
                    .textSelection(.enabled)
            case .heading(let level, let text):
                Text(text.markdownAttributed)
                    .font(headingFont(for: level))
                    .fontWeight(level <= 2 ? .semibold : .medium)
                    .foregroundColor(level <= 2 ? .primary : .secondary)
                    .padding(.top, headingTopPadding(for: level))
            case .codeBlock(let language, let code):
                renderCodeBlock(language: language, code: code)
            case .image(let url, let altText):
                VStack(alignment: .leading, spacing: 8) {
                    Group {
                        if let fileURL = URL(string: url), fileURL.isFileURL {
                            LocalFileImageView(fileURL: fileURL)
                        } else {
                            AsyncImage(url: URL(string: url)) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 200)
                                    .overlay {
                                        VStack(spacing: 8) {
                                            Image(systemName: "photo")
                                                .font(.title2)
                                                .foregroundColor(.secondary)
                                            Text("Loading image...")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                            }
                            .frame(maxHeight: 400)
                        }
                    }
                    .cornerRadius(8)

                    if !altText.isEmpty {
                        Text(altText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
            case .video(let url, let altText):
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 200)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.title)
                                    .foregroundColor(.secondary)
                                Text("Video")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if let fileURL = URL(string: url) {
                                    Text(fileURL.lastPathComponent)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                    if !altText.isEmpty {
                        Text(altText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
            }
        }
    }
    
    private func parseMarkdownElements(_ markdown: String) -> [MarkdownElement] {
        var elements: [MarkdownElement] = []
        var currentText = ""

        let lines = markdown.components(separatedBy: .newlines)
        var i = 0
        let mediaPattern = #"!\[(.*?)\]\((.*?)\)"#
        let mediaRegex = try? NSRegularExpression(pattern: mediaPattern, options: [])

        func flushCurrentText() {
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                elements.append(MarkdownElement(type: .paragraph(trimmed)))
            }
            currentText = ""
        }

        while i < lines.count {
            let line = lines[i]
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.hasPrefix("```") {
                flushCurrentText()

                let language = trimmedLine.dropFirst(3).trimmingCharacters(in: .whitespaces)
                i += 1

                var codeLines: [String] = []
                while i < lines.count {
                    let potentialClosing = lines[i].trimmingCharacters(in: .whitespaces)
                    if potentialClosing.hasPrefix("```") { break }
                    codeLines.append(lines[i])
                    i += 1
                }

                if i < lines.count { i += 1 }

                let codeBlock = codeLines.joined(separator: "\n")
                let languageValue = language.isEmpty ? nil : String(language)
                elements.append(MarkdownElement(type: .codeBlock(language: languageValue, code: codeBlock)))
                continue
            }

            if let heading = parseHeading(from: trimmedLine) {
                flushCurrentText()
                elements.append(MarkdownElement(type: .heading(level: heading.level, text: heading.text)))
                i += 1
                continue
            }

            if let regex = mediaRegex,
               let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)) {
                flushCurrentText()

                let nsLine = line as NSString
                let altText = nsLine.substring(with: match.range(at: 1))
                let mediaURL = nsLine.substring(with: match.range(at: 2))
                let isVideo = isVideoFile(mediaURL)
                let elementType: MarkdownElement.ElementType = isVideo
                    ? .video(url: mediaURL, altText: altText)
                    : .image(url: mediaURL, altText: altText)

                elements.append(MarkdownElement(type: elementType))

                let mediaEnd = match.range.location + match.range.length
                if mediaEnd < nsLine.length {
                    let remainingText = nsLine.substring(from: mediaEnd)
                    if !remainingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        currentText += remainingText + "\n"
                    }
                }

                i += 1
                continue
            }

            currentText += line
            if i < lines.count - 1 { currentText += "\n" }
            i += 1
        }

        flushCurrentText()

        return elements
    }

    private func parseHeading(from line: String) -> (level: Int, text: String)? {
        guard line.hasPrefix("#") else { return nil }

        var level = 0
        var currentIndex = line.startIndex
        while currentIndex < line.endIndex, line[currentIndex] == "#", level < 6 {
            level += 1
            currentIndex = line.index(after: currentIndex)
        }

        guard level > 0 else { return nil }
        guard currentIndex < line.endIndex else { return nil }
        guard line[currentIndex].isWhitespace else { return nil }

        while currentIndex < line.endIndex, line[currentIndex].isWhitespace {
            currentIndex = line.index(after: currentIndex)
        }

        guard currentIndex <= line.endIndex else { return nil }

        let rawText = line[currentIndex...]
        let cleaned = rawText
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespaces))

        return (level, cleaned)
    }

    private func isVideoFile(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        
        // Check UTType if possible for local files
        if url.isFileURL {
            if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
                return contentType.conforms(to: .movie) || contentType.conforms(to: .audiovisualContent)
            }
        }
        
        // Fallback to extension checking
        let ext = url.pathExtension.lowercased()
        let videoExtensions = ["mp4", "mov", "m4v", "avi", "mkv", "webm", "hevc"]
        
        return videoExtensions.contains(ext)
    }
}

private struct CodeBlockView: View {
    let language: String?
    let code: String

    private var displayCode: String {
        code.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
    }

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                if let language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: copyToPasteboard) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy code")
                .overlay(alignment: .top) {
                    if copied {
                        CopiedBadge()
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(displayCode)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.gray.opacity(0.1))
        )
    }

    private func copyToPasteboard() {
#if canImport(UIKit)
        UIPasteboard.general.string = displayCode
#endif
#if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(displayCode, forType: NSPasteboard.PasteboardType.string)
#endif

        withAnimation(.easeOut(duration: 0.2)) {
            copied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                copied = false
            }
        }
    }
}

private struct CopiedBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
            Text("Copied")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .offset(y: -36)
    }
}

struct MarkdownElement {
    enum ElementType {
        case paragraph(String)
        case heading(level: Int, text: String)
        case codeBlock(language: String?, code: String)
        case image(url: String, altText: String)
        case video(url: String, altText: String)
    }

    let id = UUID()
    let type: ElementType
}

#Preview {
    MarkdownContentView(content: """
    # Sample Content
    
    This is some sample text with **bold** and *italic* formatting.
    
    ![Sample Image](https://picsum.photos/400/200)
    
    Here's some text after the image.
    
    ![Sample Video](file:///path/to/video.mp4)
    
    - Item 1
    - Item 2 
    - Item 3
    
    More content here.
    """)
    .padding()
}
