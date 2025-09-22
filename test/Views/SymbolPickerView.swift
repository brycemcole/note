import SwiftUI

struct SymbolPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var selection: String

    let onSelect: (String) -> Void

    private var allSymbols: [String] = defaultSymbols

    init(selectedSymbol: Binding<String>) {
        _selection = State(initialValue: selectedSymbol.wrappedValue)
        self.onSelect = { newValue in selectedSymbol.wrappedValue = newValue }
    }

    private var filteredSymbols: [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return allSymbols }
        return allSymbols.filter { $0.contains(q) }
    }

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 12)]

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filteredSymbols, id: \.self) { name in
                        Button {
                            selection = name
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: name)
                                    .font(.system(size: 20))
                                    .frame(width: 44, height: 44)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(selection == name ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.08))
                                    )
                                Text(name)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: 72)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
            .navigationTitle("Choose Icon")
            .searchable(text: $query, prompt: "Search symbols")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) { Button("Use") { onSelect(selection); dismiss() } }
            }
        }
    }
}

private let defaultSymbols: [String] = [
    // Folders
    "folder", "folder.fill", "folder.circle", "folder.circle.fill", "folder.badge.plus", "folder.badge.minus", "folder.badge.gearshape", "folder.badge.person", "folder.badge.questionmark",
    // Documents & notes
    "doc", "doc.fill", "doc.text", "doc.text.fill", "doc.richtext", "doc.on.doc", "doc.on.clipboard", "clipboard", "note.text", "square.and.pencil", "pencil", "pencil.and.outline", "highlighter",
    // Books & reading
    "book", "book.fill", "text.book.closed", "books.vertical", "magazine", "newspaper",
    // Links & attachments
    "link", "link.circle", "link.circle.fill", "paperclip", "paperclip.circle", "paperclip.circle.fill",
    // Organization & tags
    "tag", "tag.fill", "bookmark", "bookmark.fill", "bookmark.circle", "bookmark.circle.fill",
    // Containers
    "tray", "tray.full", "archivebox", "archivebox.fill", "shippingbox", "shippingbox.fill",
    // Time
    "clock", "alarm", "timer", "hourglass",
    // Communication
    "envelope", "paperplane", "paperplane.fill",
    // Media
    "camera", "photo", "photo.on.rectangle", "video", "music.note", "mic", "waveform",
    // Creativity & tools
    "paintbrush", "hammer", "wrench", "gear", "cpu", "terminal", "keyboard",
    // Commerce
    "cart", "creditcard", "gift",
    // Travel & location
    "map", "mappin", "mappin.circle", "location", "airplane", "car", "tram", "bicycle",
    // Health & fitness
    "heart", "heart.fill", "stethoscope", "pill", "cross", "brain.head.profile", "lungs", "dumbbell",
    // Sports & activities
    "sportscourt", "soccerball", "basketball", "tennis.racket", "figure.run", "figure.walk",
    // Work & business
    "briefcase", "building.2", "house",
    // Finance & data
    "banknote", "chart.bar", "chart.line.uptrend.xyaxis", "chart.pie",
    // Lists & status
    "list.bullet", "list.number", "checkmark.seal", "checkmark.circle", "xmark.circle", "exclamationmark.triangle", "questionmark.circle", "info.circle",
    // Ideas & stars
    "lightbulb", "sparkles", "star", "star.fill", "star.circle",
    // Weather & nature
    "cloud", "cloud.fill", "cloud.sun", "cloud.rain", "cloud.bolt", "cloud.moon", "sun.max", "moon", "snowflake", "thermometer", "drop", "leaf", "tree", "mountain.2",
    // Animals
    "pawprint", "ant", "ladybug", "tortoise", "hare", "fish",
    // Energy & devices
    "bolt", "bolt.heart", "battery.100", "battery.25", "plug", "powerplug",
    // Security & privacy
    "shield", "lock", "lock.open", "key", "fingerprint", "faceid",
    // Layout & grids
    "rectangle.stack", "square.grid.2x2", "square.grid.3x2", "square.grid.3x3", "square.grid.4x3.fill",
    // Sharing
    "square.and.arrow.up", "square.and.arrow.down"
]
