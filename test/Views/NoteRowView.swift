//
//  NoteRowView.swift
//

import SwiftUI

struct NoteRowView: View {
    let note: Note
    var isSelected: Bool = false
    var isSelectionMode: Bool = false
    
    @ViewBuilder
    private var folderIndicator: some View {
        if let name = note.folder?.name, !name.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "folder.fill")
                Text(name)
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.gray.opacity(0.12))
            )
        }
    }
    
    private var firstImageURL: String? {
        let imagePattern = #"!\[.*?\]\((.*?)\)"#
        guard let regex = try? NSRegularExpression(pattern: imagePattern, options: []) else { return nil }
        let range = NSRange(location: 0, length: note.content.utf16.count)
        
        if let match = regex.firstMatch(in: note.content, options: [], range: range),
           let urlRange = Range(match.range(at: 1), in: note.content) {
            let url = String(note.content[urlRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            return url.isEmpty ? nil : url
        }
        return nil
    }

    private func productAvailabilityText(for note: Note) -> String? {
        if let explicit = note.productAvailabilityDisplay, !explicit.isEmpty {
            return explicit
        }
        if let inStock = note.productInStock {
            return inStock ? "In stock" : "Out of stock"
        }
        return nil
    }

    private func availabilityColor(for note: Note) -> Color {
        if note.productInStock == false { return .red }
        if note.productInStock == true { return .green }
        return .secondary
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Selection indicator
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(note.displayTitle)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)

                if note.isProductLink {
                    let availabilityText = productAvailabilityText(for: note)
                    HStack(spacing: 6) {
                        if let availabilityText {
                            Text(availabilityText)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(availabilityColor(for: note))
                        }
                        if let price = note.productPriceDisplay {
                            if availabilityText != nil {
                                Text("•")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text(price)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    if let summary = note.summary {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    } else if !note.previewText.isEmpty {
                        Text(note.previewText.markdownAttributed)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }

                HStack(spacing: 6) {
                    Text(note.dateCreated, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let name = note.folder?.name, !name.isEmpty {
                        Text("|")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            if let imageURL = firstImageURL {
                ThumbnailWithFallback(url: imageURL)
            }
        }
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

struct ThumbnailWithFallback: View {
    let url: String
    @State private var currentURLIndex = 0
    
    private func upgradedToHTTPS(_ url: URL) -> URL {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if comps?.scheme == "http" {
            comps?.scheme = "https"
        }
        return comps?.url ?? url
    }
    
    private var possibleURLs: [String] {
        var urls: [String] = []
        
        // Only try HTTPS URLs to avoid ATS issues
        if let raw = URL(string: url) {
            let https = upgradedToHTTPS(raw).absoluteString
            urls.append(https)
            
            // Add variant without query parameters
            if https.contains("?") {
                urls.append(String(https.split(separator: "?")[0]))
            }
        }
        
        return Array(Set(urls)) // Remove duplicates
    }
    
    var body: some View {
        let current = URL(string: possibleURLs[safe: currentURLIndex] ?? url)
        Group {
            if let current, current.isFileURL {
                // For local files, show a file icon instead of trying to load the image
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 60, height: 60)
                    .overlay {
                        Image(systemName: "doc.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
            } else {
                AsyncImage(url: current ?? URL(string: url)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    case .failure(_):
                        if currentURLIndex < possibleURLs.count - 1 {
                            // Try next fallback URL with delay
                            Color.clear
                                .frame(width: 60, height: 60)
                                .onAppear {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        currentURLIndex += 1
                                    }
                                }
                        } else {
                            // All URLs failed, show placeholder
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.1))
                                .frame(width: 60, height: 60)
                                .overlay {
                                    Image(systemName: "photo")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                        }
                    case .empty:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.1))
                            .frame(width: 60, height: 60)
                            .overlay { ProgressView().scaleEffect(0.8) }
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
    }
}

#if canImport(UIKit)
import UIKit
#endif
