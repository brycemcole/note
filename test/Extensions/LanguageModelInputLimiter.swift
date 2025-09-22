import Foundation

/// Maximum number of characters we allow when sending prompts to the on-device language model.
/// Roughly maps to ~3k tokens assuming ~3 characters per token, which keeps us well inside
/// the system model's default 4k context window and avoids "text too long" errors.
let languageModelInputCharacterLimit = 8000

/// Trims text to the configured character limit while preserving line boundaries.
func clippedForLanguageModel(_ text: String, limit: Int = languageModelInputCharacterLimit) -> String {
    guard text.count > limit else { return text }
    let endIndex = text.index(text.startIndex, offsetBy: limit)
    return String(text[..<endIndex])
}

/// Helper that trims the content portion of prompts while preserving the static instructions.
func clippedPrompt(_ instructions: String, content: String, limit: Int = languageModelInputCharacterLimit) -> String {
    let trimmedContent = clippedForLanguageModel(content, limit: max(0, limit - instructions.count))
    return instructions + trimmedContent
}
