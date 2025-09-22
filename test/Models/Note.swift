//
//  Note.swift
//  Extracted from ContentView.swift
//

import Foundation
import SwiftData

@Model
final class Note {
    @Attribute(.unique) var id: UUID
    var title: String
    var content: String
    var summary: String?
    var dateCreated: Date
    var isDeleted: Bool
    var dateDeleted: Date?
    var isAICleaned: Bool
    var isContentFetched: Bool
    var lastContentFetch: Date?
    var sourceURL: String?
    @Relationship var folder: Folder?
    var linkKindRaw: String?
    var productName: String?
    var productPrice: String?
    var productCurrency: String?
    var productAvailability: String?
    var productInStock: Bool?
    var linkMetadataUpdatedAt: Date?
    
    init(title: String, content: String, folder: Folder? = nil) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.summary = nil
        self.dateCreated = Date()
        self.isDeleted = false
        self.dateDeleted = nil
        self.isAICleaned = false
        self.isContentFetched = false
        self.lastContentFetch = nil
        self.sourceURL = nil
        self.folder = folder
        self.linkKindRaw = nil
        self.productName = nil
        self.productPrice = nil
        self.productCurrency = nil
        self.productAvailability = nil
        self.productInStock = nil
        self.linkMetadataUpdatedAt = nil
    }
    
    func moveToTrash() {
        isDeleted = true
        dateDeleted = Date()
        moveAttachmentsToTrash()
    }
    
    func restore() {
        isDeleted = false
        dateDeleted = nil
        restoreAttachmentsFromTrash()
    }
    
    // MARK: - Attachment file management
    private func documentsDirectory() -> URL? {
        return try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }

    private func folderStorageDirectory() -> URL? {
        guard let docs = documentsDirectory(), let folder = folder else { return nil }
        let dir = docs.appendingPathComponent("Folder_\(folder.id.uuidString)", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func trashDirectory() -> URL? {
        guard let docs = documentsDirectory() else { return nil }
        let dir = docs.appendingPathComponent("Trash/\(id.uuidString)", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func localFileURLs() -> [URL] {
        // Match both images ![...](...) and links [...](...)
        let patterns = [#"!\[[^\]]*\]\((file:[^)\s]+)\)"#, #"\[[^\]]*\]\((file:[^)\s]+)\)"#]
        var results: [URL] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(location: 0, length: content.utf16.count)
            let matches = regex.matches(in: content, options: [], range: range)
            for m in matches {
                if m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: content) {
                    let s = String(content[r])
                    if let u = URL(string: s), u.isFileURL { results.append(u) }
                }
            }
        }
        return results
    }

    private func replaceURLInContent(old: URL, new: URL) {
        let oldStr = old.absoluteString
        let newStr = new.absoluteString
        content = content.replacingOccurrences(of: oldStr, with: newStr)
    }

    private func moveAttachmentsToTrash() {
        let urls = localFileURLs()
        guard !urls.isEmpty, let trashDir = trashDirectory() else { return }
        for src in urls {
            // Only move files that are inside our folder storage
            if let folderDir = folderStorageDirectory(), src.path.hasPrefix(folderDir.path) {
                let dest = trashDir.appendingPathComponent(src.lastPathComponent)
                // If a file with same name exists in trash, uniquify
                let uniqueDest = uniqueDestinationURL(for: dest)
                do {
                    try FileManager.default.moveItem(at: src, to: uniqueDest)
                    replaceURLInContent(old: src, new: uniqueDest)
                } catch {
                    // If move fails, ignore to avoid blocking deletion
                }
            }
        }
    }

    private func restoreAttachmentsFromTrash() {
        let urls = localFileURLs()
        guard !urls.isEmpty, let destDir = folderStorageDirectory() else { return }
        for src in urls {
            // Only move files that are inside our note's trash directory
            if let trashDir = trashDirectory(), src.path.hasPrefix(trashDir.path) {
                var dest = destDir.appendingPathComponent(src.lastPathComponent)
                // Uniquify if needed
                dest = uniqueDestinationURL(for: dest)
                do {
                    try FileManager.default.moveItem(at: src, to: dest)
                    replaceURLInContent(old: src, new: dest)
                } catch {
                    // Ignore failures silently
                }
            }
        }
        // Optionally clean up empty trash dir for this note
        if let trashDir = trashDirectory() {
            _ = try? FileManager.default.removeItem(at: trashDir)
        }
    }

    func deleteAttachmentsInTrash() {
        // Permanently delete any files in this note's trash directory
        if let trashDir = trashDirectory() {
            _ = try? FileManager.default.removeItem(at: trashDir)
        }
    }

    private func uniqueDestinationURL(for proposed: URL) -> URL {
        var candidate = proposed
        let baseName = proposed.deletingPathExtension().lastPathComponent
        let ext = proposed.pathExtension
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = "\(baseName)-\(index)"
            candidate = proposed.deletingLastPathComponent().appendingPathComponent(name).appendingPathExtension(ext)
            index += 1
        }
        return candidate
    }
    
    /// Returns clean preview text, skipping blank lines and non-content-only markdown lines.
    /// Keeps headers (e.g., "#", "##", ... "######") so previews can show them.
    var previewText: String {
        let lines = content.components(separatedBy: .newlines)
        let meaningfulLines = lines.compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty lines
            guard !trimmed.isEmpty else { return nil }
            
            // Skip lines that are just markdown formatting (dividers, fences, pure rule lines, quotes-only)
            // Note: Do NOT skip header lines; we want them in previews.
            if trimmed.hasPrefix("---") ||
               trimmed.hasPrefix("***") ||
               trimmed.hasPrefix("```") ||
               trimmed == ">" ||
               trimmed.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" || $0 == "=" }) {
                return nil
            }
            
            return trimmed
        }
        
        // Return the first two meaningful lines, joined
        return meaningfulLines.prefix(2).joined(separator: " ")
    }

    enum LinkKind: String {
        case general
        case product
    }

    var linkKind: LinkKind {
        get { LinkKind(rawValue: linkKindRaw ?? LinkKind.general.rawValue) ?? .general }
        set { linkKindRaw = newValue == .general ? nil : newValue.rawValue }
    }

    var isProductLink: Bool { linkKind == .product }

    var productPriceDisplay: String? {
        guard let rawPrice = productPrice?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPrice.isEmpty else { return nil }
        guard let currency = productCurrency?.trimmingCharacters(in: .whitespacesAndNewlines), !currency.isEmpty else {
            return rawPrice
        }
        if rawPrice.localizedCaseInsensitiveContains(currency) { return rawPrice }
        return "\(currency) \(rawPrice)"
    }

    var productAvailabilityDisplay: String? {
        productAvailability?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var displayTitle: String {
        title.htmlDecoded
    }

    func applyLinkMetadata(_ metadata: LinkMetadata?) {
        guard let metadata else {
            linkKind = .general
            productName = nil
            productPrice = nil
            productCurrency = nil
            productAvailability = nil
            productInStock = nil
            linkMetadataUpdatedAt = Date()
            return
        }

        linkKind = LinkKind(rawValue: metadata.kind.rawValue) ?? .general
        productName = metadata.productName?.trimmingCharacters(in: .whitespacesAndNewlines)
        productPrice = metadata.price?.trimmingCharacters(in: .whitespacesAndNewlines)
        productCurrency = metadata.currency?.trimmingCharacters(in: .whitespacesAndNewlines)
        productAvailability = metadata.availability?.trimmingCharacters(in: .whitespacesAndNewlines)
        productInStock = metadata.isInStock
        linkMetadataUpdatedAt = Date()
    }
}
