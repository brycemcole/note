//
//  AddFolderView.swift
//

import SwiftUI
import SwiftData

struct AddFolderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name: String = ""
    @State private var selectedSymbol: String = "folder.fill"
    @State private var selectedColor: Color = .blue
    @State private var isPrivate: Bool = false
    
    var body: some View {
        NavigationView {
            Form {
                TextField("Folder Name", text: $name)
                
                Section("Appearance") {
                    HStack(spacing: 12) {
                        Image(systemName: selectedSymbol)
                            .font(.system(size: 24))
                            .foregroundStyle(selectedColor)
                        Text("Preview")
                        Spacer()
                    }
                    ColorPicker("Color", selection: $selectedColor, supportsOpacity: false)
                    NavigationLink("Choose Icon") { SymbolPickerInline(selectedSymbol: $selectedSymbol) }
                }
                
                Section("Privacy") {
                    Toggle(isOn: $isPrivate) {
                        HStack {
                            Image(systemName: "eye.slash")
                                .foregroundColor(.purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Private Folder")
                                Text("Hide from main view unless enabled in settings")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Folder")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        addFolder()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
    
    private func addFolder() {
        let nameClean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = selectedColor.toHexString() ?? "0000FF"
        let folder = Folder(name: nameClean, symbolName: selectedSymbol, colorHex: hex, isPrivate: isPrivate)
        modelContext.insert(folder)
        try? modelContext.save()
        SharedDataManager.shared.syncFolderSnapshot()
        dismiss()
    }
}

extension Color {
    func toHexString() -> String? {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        let ri = Int(round(r * 255)), gi = Int(round(g * 255)), bi = Int(round(b * 255)), ai = Int(round(a * 255))
        if ai < 255 { return String(format: "%02X%02X%02X%02X", ai, ri, gi, bi) }
        return String(format: "%02X%02X%02X", ri, gi, bi)
        #else
        return nil
        #endif
    }
}

struct SymbolPickerInline: View {
    @Binding var selectedSymbol: String
    @State private var query: String = ""
    private let symbols = defaultSymbols
    private var filtered: [String] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? symbols : symbols.filter { $0.contains(q) }
    }
    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 12)]
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(filtered, id: \.self) { name in
                    Button {
                        selectedSymbol = name
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: name)
                                .font(.system(size: 20))
                                .frame(width: 44, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedSymbol == name ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.08))
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
        .searchable(text: $query)
    }
}

private let defaultSymbols: [String] = [
    "folder", "folder.fill", "folder.badge.plus", "folder.badge.gearshape",
    "book", "text.book.closed", "bookmark", "tag", "star",
    "doc.text", "square.and.pencil", "tray", "archivebox", "paperclip", "link"
]
