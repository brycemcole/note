//
//  SymbolPickerView.swift
//

import SwiftUI

struct SymbolPickerView: View {
    @Binding var selectedSymbol: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    private let commonSymbols = [
        "folder.fill", "tray.full", "link", "bookmark", "star.fill", "heart.fill",
        "doc.text", "note.text", "book.fill", "archivebox.fill", "tag.fill",
        "paperclip", "globe", "safari", "network", "server.rack",
        "magazine", "newspaper", "books.vertical", "text.book.closed",
        "pencil", "pencil.circle", "square.and.pencil", "highlighter",
        "camera", "photo", "video", "music.note", "headphones",
        "gamecontroller", "tv", "display", "desktopcomputer", "laptopcomputer",
        "iphone", "ipad", "applewatch", "airpods", "homepod",
        "lightbulb", "gear", "wrench", "hammer", "screwdriver",
        "paintbrush", "eyedropper", "ruler", "level", "scope",
        "map", "location", "compass", "globe.americas", "globe.europe.africa"
    ]
    
    private var filteredSymbols: [String] {
        if searchText.isEmpty {
            return commonSymbols
        }
        return commonSymbols.filter { $0.contains(searchText.lowercased()) }
    }
    
    private let columns = Array(repeating: GridItem(.flexible()), count: 4)
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(filteredSymbols, id: \.self) { symbol in
                        Button {
                            selectedSymbol = symbol
                            dismiss()
                        } label: {
                            VStack {
                                Image(systemName: symbol)
                                    .font(.title2)
                                    .foregroundColor(selectedSymbol == symbol ? .white : .primary)
                                    .frame(width: 60, height: 60)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(selectedSymbol == symbol ? Color.blue : Color.gray.opacity(0.1))
                                    )
                                
                                Text(symbol)
                                    .font(.caption2)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Choose Icon")
            .searchable(text: $searchText, prompt: "Search symbols")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SymbolPickerView(selectedSymbol: .constant("folder.fill"))
}