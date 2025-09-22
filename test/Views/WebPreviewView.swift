import SwiftUI
import WebKit
import Foundation

struct WebPreviewView: View {
    let url: URL
    var primaryTitle: String? = nil
    var primarySummary: String? = nil

    @State private var page = WebPage()

    private var previewTitle: String? {
        let rawTitle = page.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = rawTitle.isEmpty ? (url.host ?? url.absoluteString) : rawTitle
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let primaryTitle, titlesMatch(trimmed, primaryTitle) { return nil }
        if let primarySummary, titlesMatch(trimmed, primarySummary) { return nil }

        return trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let previewTitle {
                Text(previewTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            WebView(page)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
        .task {
            let request = URLRequest(url: url)
            page.load(request)
        }
    }
}

#Preview {
    WebPreviewView(url: URL(string: "https://www.swift.org")!, primaryTitle: "Swift.org")
        .frame(height: 480)
        .padding()
}
