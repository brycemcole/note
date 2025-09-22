//
//  MarkdownContentView.swift
//

import SwiftUI
import Foundation

struct MarkdownContentView: View {
    let content: String
    
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(parseMarkdownElements(content), id: \.id) { element in
                renderElement(element)
            }
        }
    }
    
    private func renderElement(_ element: MarkdownElement) -> some View {
        Group {
            switch element.type {
            case .text:
                Text(element.content.markdownAttributed)
                    .textSelection(.enabled)
            case .image(let url, let altText):
                VStack(alignment: .leading, spacing: 8) {
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
                    .cornerRadius(8)
                    
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
        
        while i < lines.count {
            let line = lines[i]
            
            // Check for image syntax: ![alt text](url)
            let imagePattern = #"!\[(.*?)\]\((.*?)\)"#
            if let regex = try? NSRegularExpression(pattern: imagePattern, options: []),
               let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.count)) {
                
                // Save any accumulated text before the image
                if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    elements.append(MarkdownElement(type: .text, content: currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
                    currentText = ""
                }
                
                // Extract image info
                let altTextRange = Range(match.range(at: 1), in: line)!
                let urlRange = Range(match.range(at: 2), in: line)!
                let altText = String(line[altTextRange])
                let imageURL = String(line[urlRange])
                
                elements.append(MarkdownElement(type: .image(url: imageURL, altText: altText), content: ""))
                
                // Check if there's text after the image on the same line
                let imageEnd = match.range.upperBound
                if imageEnd < line.count {
                    let remainingText = String(line[line.index(line.startIndex, offsetBy: imageEnd)...])
                    if !remainingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        currentText += remainingText + "\n"
                    }
                }
            } else {
                // Regular text line
                currentText += line + "\n"
            }
            
            i += 1
        }
        
        // Add any remaining text
        if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            elements.append(MarkdownElement(type: .text, content: currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        
        return elements
    }
}

struct MarkdownElement {
    enum ElementType {
        case text
        case image(url: String, altText: String)
    }
    
    let id = UUID()
    let type: ElementType
    let content: String
}

#Preview {
    MarkdownContentView(content: """
    # Sample Content
    
    This is some sample text with **bold** and *italic* formatting.
    
    ![Sample Image](https://picsum.photos/400/200)
    
    Here's some text after the image.
    
    - Item 1
    - Item 2 
    - Item 3
    
    More content here.
    """)
    .padding()
}