//
//  AddNoteView.swift
//

import SwiftUI
import SwiftData
import Foundation
import FoundationModels

struct AddNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var content = ""
    
    private var model = SystemLanguageModel.default
    
    var body: some View {
        NavigationView {
            noteEditor
                .navigationTitle("New Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) { cancelButton }
                    ToolbarItem(placement: .navigationBarTrailing) { saveButton }
                }
        }
    }
    
    private var noteEditor: some View {
        VStack {
            TextEditor(text: $content)
                .padding()
            Spacer()
        }
    }
    
    private var cancelButton: some View { Button("Cancel") { dismiss() } }
    
    private var saveButton: some View {
        Button("Save") { saveNote() }
            .disabled(content.isEmpty)
    }
    
    private func saveNote() {
        // Insert immediately for instant UX; generate title in background
        Task { await saveNoteImmediately() }
        dismiss()
    }
    
    private func saveNoteImmediately() async {
        // Create note immediately with local normalization only
        let newNote = Note(title: "Untitled", content: content.removingLeadingListMarkers.normalizedMarkdown)
        await MainActor.run {
            modelContext.insert(newNote)
            try? modelContext.save()
            // Generate title in the background
            Task { await generateTitleInBackground(for: newNote) }
        }
    }
    
    private func generateTitleInBackground(for note: Note) async {
        guard model.availability == .available else { return }
        do {
            let instructions = """
                You are a helpful assistant that creates concise, descriptive titles for notes.
                Analyze the content and generate a clear, specific title that captures the main topic.
                Keep the title under 50 characters and make it engaging.
                
                IMPORTANT: Return ONLY plain text for the title. 
                Do NOT include any markdown formatting like:
                - Headers (# ## ###)
                - Bold (**text**)
                - Italic (*text*)
                - Code (`text`)
                - Any other markdown syntax
                
                Just return clean, readable title text with no formatting symbols.
                """
            let session = LanguageModelSession(instructions: instructions)
            let clippedContent = clippedForLanguageModel(note.content)
            let prompt = clippedForLanguageModel("Create a plain text title (no markdown) for this note content: \(clippedContent)")
            let response = try await session.respond(to: prompt)
            let generatedTitle = cleanMarkdownFromTitle(response.content.trimmingCharacters(in: .whitespacesAndNewlines))
            if !generatedTitle.isEmpty {
                await MainActor.run {
                    note.title = generatedTitle
                    try? modelContext.save()
                }
            }
        } catch {
            print("Failed to generate title: \(error)")
        }
    }
    
    private func cleanMarkdownFromTitle(_ title: String) -> String {
        var cleanedTitle = title
        cleanedTitle = cleanedTitle.replacingOccurrences(of: "**", with: "") // Bold
        cleanedTitle = cleanedTitle.replacingOccurrences(of: "*", with: "")  // Italic/Bold
        cleanedTitle = cleanedTitle.replacingOccurrences(of: "`", with: "")  // Code
        cleanedTitle = cleanedTitle.replacingOccurrences(of: "# ", with: "") // Headers
        cleanedTitle = cleanedTitle.replacingOccurrences(of: "## ", with: "")
        cleanedTitle = cleanedTitle.replacingOccurrences(of: "### ", with: "")
        cleanedTitle = cleanedTitle.replacingOccurrences(of: "#### ", with: "")
        cleanedTitle = cleanedTitle.replacingOccurrences(of: "##### ", with: "")
        cleanedTitle = cleanedTitle.replacingOccurrences(of: "###### ", with: "")
        return cleanedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
