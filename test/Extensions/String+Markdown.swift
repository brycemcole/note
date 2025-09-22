//
//  String+Markdown.swift
//  Extracted from ContentView.swift
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

extension String {
    /// Normalizes markdown bullet points to use consistent dash format
    var normalizedMarkdown: String {
        let lines = self.components(separatedBy: .newlines)

        // Helper to check if a trimmed line is a list marker (dash, asterisk, or numbered)
        func isListMarkerLine(_ trimmed: String) -> Bool {
            if trimmed.hasPrefix("- ") { return true }
            if trimmed.hasPrefix("* ") { return true }
            // Numbered list like "1. ", "23. \t"
            if let dotIndex = trimmed.firstIndex(of: ".") {
                let numberPart = trimmed[..<dotIndex]
                if numberPart.allSatisfy({ $0.isNumber }) {
                    let afterDot = trimmed[trimmed.index(after: dotIndex)...]
                    if afterDot.first?.isWhitespace == true { return true }
                }
            }
            return false
        }

        // Helper to find previous/next non-empty trimmed lines
        func previousNonEmptyIndex(from i: Int) -> Int? {
            var j = i - 1
            while j >= 0 {
                if !lines[j].trimmingCharacters(in: .whitespaces).isEmpty { return j }
                j -= 1
            }
            return nil
        }
        func nextNonEmptyIndex(from i: Int) -> Int? {
            var j = i + 1
            while j < lines.count {
                if !lines[j].trimmingCharacters(in: .whitespaces).isEmpty { return j }
                j += 1
            }
            return nil
        }

        let normalizedLines: [String] = lines.enumerated().map { (index, line) in
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Preserve code fences as-is
            if trimmed.hasPrefix("```") { return line }

            // Capture leading whitespace for indentation preservation
            let leadingWhitespace = String(line.prefix(while: { $0.isWhitespace }))
            let contentAfterIndent = String(line.dropFirst(leadingWhitespace.count))

            // Decide if this line should be treated as a list item
            let looksLikeAsteriskList = contentAfterIndent.hasPrefix("* ") || contentAfterIndent.hasPrefix("*\t") || contentAfterIndent.hasPrefix("*  ")

            if looksLikeAsteriskList {
                // Do not treat as list if it's clearly an intro/lead-in ending with ':' (e.g., "* Intro:")
                let afterStar = contentAfterIndent.dropFirst(2).trimmingCharacters(in: .whitespaces)
                if afterStar.hasSuffix(":") {
                    return line // keep as-is; likely a lead-in, not a list item
                }

                // Check neighboring lines to see if we are inside a list block
                let prevIdx = previousNonEmptyIndex(from: index)
                let nextIdx = nextNonEmptyIndex(from: index)
                let prevIsList = prevIdx.flatMap { idx in
                    Optional(isListMarkerLine(lines[idx].trimmingCharacters(in: .whitespaces)))
                } ?? false
                let nextIsList = nextIdx.flatMap { idx in
                    Optional(isListMarkerLine(lines[idx].trimmingCharacters(in: .whitespaces)))
                } ?? false

                // Only normalize '*' -> '-' if surrounded by, or followed/preceded by, other list items.
                if prevIsList || nextIsList {
                    return leadingWhitespace + "- " + afterStar
                } else {
                    // If not clearly part of a list block, leave it alone to avoid turning prose into a list
                    return line
                }
            }

            // Preserve lines that start with '*' but not as '* ' (might be emphasis like '*word*')
            if contentAfterIndent.hasPrefix("*") && !contentAfterIndent.hasPrefix("* ") {
                return line
            }

            // Fallback: if line starts with '*' and then whitespace somewhere later, and neighbors indicate list block, normalize
            if contentAfterIndent.first == "*" {
                // Find first whitespace after '*'
                var idx = contentAfterIndent.index(after: contentAfterIndent.startIndex)
                var foundSpace = false
                while idx < contentAfterIndent.endIndex {
                    if contentAfterIndent[idx].isWhitespace { foundSpace = true; break }
                    idx = contentAfterIndent.index(after: idx)
                }
                if foundSpace {
                    let prevIdx = previousNonEmptyIndex(from: index)
                    let nextIdx = nextNonEmptyIndex(from: index)
                    let prevIsList = prevIdx.flatMap { i in
                        Optional(isListMarkerLine(lines[i].trimmingCharacters(in: .whitespaces)))
                    } ?? false
                    let nextIsList = nextIdx.flatMap { i in
                        Optional(isListMarkerLine(lines[i].trimmingCharacters(in: .whitespaces)))
                    } ?? false
                    if prevIsList || nextIsList {
                        let rest = contentAfterIndent[contentAfterIndent.index(after: contentAfterIndent.startIndex)..<contentAfterIndent.endIndex]
                        let trimmedRest = rest.trimmingCharacters(in: .whitespaces)
                        return leadingWhitespace + "- " + trimmedRest
                    }
                }
            }

            return line
        }

        return normalizedLines.joined(separator: "\n")
    }

    /// Removes lines by 1-based indices and returns the remaining content
    func applyingLineRemovals(lineNumbers: Set<Int>) -> String {
        let lines = self.components(separatedBy: .newlines)
        if lineNumbers.isEmpty { return self }
        var kept: [String] = []
        kept.reserveCapacity(lines.count)
        for (idx, line) in lines.enumerated() {
            let oneBased = idx + 1
            if !lineNumbers.contains(oneBased) {
                kept.append(line)
            }
        }
        return kept.joined(separator: "\n")
    }

    /// Strips leading "* " or "- " from lines that are not clearly part of a list block
    var removingLeadingListMarkers: String {
        let lines = self.components(separatedBy: .newlines)

        func isListMarkerLine(_ trimmed: String) -> Bool {
            if trimmed.hasPrefix("- ") { return true }
            if trimmed.hasPrefix("* ") { return true }
            if let dotIndex = trimmed.firstIndex(of: ".") {
                let numberPart = trimmed[..<dotIndex]
                if numberPart.allSatisfy({ $0.isNumber }) {
                    let afterDot = trimmed[trimmed.index(after: dotIndex)...]
                    if afterDot.first?.isWhitespace == true { return true }
                }
            }
            return false
        }

        func previousNonEmptyIndex(from i: Int) -> Int? {
            var j = i - 1
            while j >= 0 {
                if !lines[j].trimmingCharacters(in: .whitespaces).isEmpty { return j }
                j -= 1
            }
            return nil
        }
        func nextNonEmptyIndex(from i: Int) -> Int? {
            var j = i + 1
            while j < lines.count {
                if !lines[j].trimmingCharacters(in: .whitespaces).isEmpty { return j }
                j += 1
            }
            return nil
        }

        let processed: [String] = lines.enumerated().map { (index, line) in
            let leadingWhitespace = String(line.prefix(while: { $0.isWhitespace }))
            let contentAfterIndent = String(line.dropFirst(leadingWhitespace.count))
            let trimmed = contentAfterIndent.trimmingCharacters(in: .whitespaces)

            // Preserve code fences as-is
            if trimmed.hasPrefix("```") { return line }

            let startsWithDash = contentAfterIndent.hasPrefix("- ")
            let startsWithStar = contentAfterIndent.hasPrefix("* ")

            guard startsWithDash || startsWithStar else { return line }

            // Determine if neighbors indicate a list block
            let prevIdx = previousNonEmptyIndex(from: index)
            let nextIdx = nextNonEmptyIndex(from: index)
            let prevIsList = prevIdx.flatMap { i in Optional(isListMarkerLine(lines[i].trimmingCharacters(in: .whitespaces))) } ?? false
            let nextIsList = nextIdx.flatMap { i in Optional(isListMarkerLine(lines[i].trimmingCharacters(in: .whitespaces))) } ?? false

            if prevIsList || nextIsList {
                // Keep as list marker (will be normalized elsewhere)
                return line
            } else {
                // Not part of a list block — strip the leading marker
                let withoutMarker: String
                if startsWithDash {
                    withoutMarker = String(contentAfterIndent.dropFirst(2))
                } else {
                    withoutMarker = String(contentAfterIndent.dropFirst(2))
                }
                return leadingWhitespace + withoutMarker
            }
        }

        return processed.joined(separator: "\n")
    }
    
    /// Collapses extra blank lines between a lead-in line (ending with ':', even if wrapped in markdown like **bold**) and the following list
    var collapsedLeadInListSpacing: String {
        let lines = self.components(separatedBy: .newlines)

        func isListMarkerLine(_ trimmed: String) -> Bool {
            if trimmed.hasPrefix("- ") { return true }
            if trimmed.hasPrefix("* ") { return true }
            if let dotIndex = trimmed.firstIndex(of: ".") {
                let numberPart = trimmed[..<dotIndex]
                if numberPart.allSatisfy({ $0.isNumber }) {
                    let afterDot = trimmed[trimmed.index(after: dotIndex)...]
                    if afterDot.first?.isWhitespace == true { return true }
                }
            }
            return false
        }

        // Detects a line that semantically ends with a ':' even if it's followed by
        // closing markdown markers like **, __, `, or ~ (e.g., "**Strengths:**").
        func endsWithColonIgnoringMarkdownClosers(_ raw: String) -> Bool {
            var view = raw[...]
            // Trim trailing whitespace first
            while let last = view.last, last.isWhitespace { view = view.dropLast() }
            // Then trim trailing markdown closers
            while let last = view.last, last == "*" || last == "_" || last == "`" || last == "~" { view = view.dropLast() }
            return view.last == ":"
        }

        var result: [String] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            result.append(line)

            // If this is a lead-in ending with ':' and next non-empty is a list marker, drop intervening empty lines
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if endsWithColonIgnoringMarkdownClosers(trimmed) {
                // Peek ahead to find the next non-empty
                var j = i + 1
                var sawEmpty = false
                while j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).isEmpty {
                    sawEmpty = true
                    j += 1
                }
                if sawEmpty, j < lines.count {
                    let nextTrimmed = lines[j].trimmingCharacters(in: .whitespaces)
                    if isListMarkerLine(nextTrimmed) {
                        // Remove the previously appended empty lines from result
                        while result.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
                            _ = result.popLast()
                        }
                        // Ensure only a single newline before the list (by doing nothing extra here)
                        // Advance i to just before the next non-empty so the loop appends it next
                        i = j - 1
                    }
                }
            }

            i += 1
        }

        return result.joined(separator: "\n")
    }
    
    /// Removes invisible/zero-width characters and normalizes non-breaking spaces
    var sanitizedForMarkdown: String {
        // Characters to remove entirely
        let removals: [Character] = [
            "\u{200B}", // ZERO WIDTH SPACE
            "\u{200C}", // ZERO WIDTH NON-JOINER
            "\u{200D}", // ZERO WIDTH JOINER
            "\u{FEFF}", // ZERO WIDTH NO-BREAK SPACE (BOM)
            "\u{200E}", // LEFT-TO-RIGHT MARK
            "\u{200F}"  // RIGHT-TO-LEFT MARK
        ]
        // Replace non-breaking space with a normal space so trimming works
        let replaced = self.replacingOccurrences(of: "\u{00A0}", with: " ")
        let filtered = replaced.filter { ch in !removals.contains(ch) }
        return String(filtered)
    }

    /// Replaces a subset of common LaTeX inline commands with their unicode equivalents so that
    /// mathematical symbols render even when Markdown doesn't understand TeX syntax.
    var replacingCommonLaTeXSymbols: String {
        let replacements: [String: String] = [
            "\\alpha": "α", "\\beta": "β", "\\gamma": "γ", "\\delta": "δ",
            "\\epsilon": "ε", "\\zeta": "ζ", "\\eta": "η", "\\theta": "θ",
            "\\vartheta": "ϑ", "\\iota": "ι", "\\kappa": "κ", "\\lambda": "λ",
            "\\mu": "μ", "\\nu": "ν", "\\xi": "ξ", "\\pi": "π",
            "\\varpi": "ϖ", "\\rho": "ρ", "\\varrho": "ϱ", "\\sigma": "σ",
            "\\varsigma": "ς", "\\tau": "τ", "\\upsilon": "υ", "\\phi": "φ",
            "\\varphi": "ϕ", "\\chi": "χ", "\\psi": "ψ", "\\omega": "ω",
            "\\Gamma": "Γ", "\\Delta": "Δ", "\\Theta": "Θ", "\\Lambda": "Λ",
            "\\Xi": "Ξ", "\\Pi": "Π", "\\Sigma": "Σ", "\\Upsilon": "Υ",
            "\\Phi": "Φ", "\\Psi": "Ψ", "\\Omega": "Ω",
            "\\times": "×", "\\cdot": "·", "\\pm": "±", "\\mp": "∓",
            "\\leq": "≤", "\\geq": "≥", "\\neq": "≠", "\\approx": "≈",
            "\\infty": "∞", "\\partial": "∂", "\\nabla": "∇", "\\degree": "°",
            "\\rightarrow": "→", "\\leftarrow": "←", "\\leftrightarrow": "↔",
            "\\Rightarrow": "⇒", "\\Leftarrow": "⇐", "\\Leftrightarrow": "⇔",
            "\\sum": "∑", "\\prod": "∏", "\\int": "∫", "\\oint": "∮",
            "\\forall": "∀", "\\exists": "∃", "\\neg": "¬", "\\lor": "∨",
            "\\land": "∧", "\\oplus": "⊕", "\\otimes": "⊗",
            "\\subset": "⊂", "\\subseteq": "⊆", "\\supset": "⊃", "\\supseteq": "⊇",
            "\\cup": "∪", "\\cap": "∩", "\\emptyset": "∅", "\\in": "∈",
            "\\notin": "∉", "\\propto": "∝", "\\sim": "∼"
        ]

        var output = self
        let sortedKeys = replacements.keys.sorted { $0.count > $1.count }
        for key in sortedKeys {
            if let value = replacements[key] {
                output = output.replacingOccurrences(of: key, with: value)
            }
        }

        // Strip common inline math delimiters so "\(x\)" renders as "(x)"
        output = output.replacingOccurrences(of: "\\(", with: "")
            .replacingOccurrences(of: "\\)", with: "")
            .replacingOccurrences(of: "\\[", with: "")
            .replacingOccurrences(of: "\\]", with: "")
            .replacingOccurrences(of: "$$", with: "")

        return output
    }
    
    /// Renumbers ordered list items for display so repeated "1." items become 1,2,3,...
    /// This operates purely on text and preserves indentation/nesting levels.
    var renumberOrderedListsForDisplay: String {
        let lines = self.components(separatedBy: .newlines)
        var result: [String] = []
        // Track counters per indent width to support simple nesting
        var counters: [Int: Int] = [:]

        func leadingIndentWidth(of s: Substring) -> Int {
            var w = 0
            for ch in s { if ch == " " { w += 1 } else if ch == "\t" { w += 4 } else { break } }
            return w
        }

        func isOrderedListLine(_ s: Substring) -> (indent: Int, restIndex: Substring.Index)? {
            let indent = leadingIndentWidth(of: s)
            let start = s.index(s.startIndex, offsetBy: indent)
            var i = start
            var sawDigit = false
            while i < s.endIndex, s[i].isNumber { sawDigit = true; i = s.index(after: i) }
            guard sawDigit, i < s.endIndex, s[i] == "." else { return nil }
            let next = s.index(after: i)
            guard next < s.endIndex, s[next].isWhitespace else { return nil }
            return (indent, s.index(after: i))
        }

        var prevWasOrderedAtIndent: Int? = nil
        for line in lines {
            let s = Substring(line)
            if let (indent, restIdx) = isOrderedListLine(s) {
                // Start or continue a list at this indent
                if prevWasOrderedAtIndent != indent {
                    counters[indent] = 1
                } else {
                    counters[indent, default: 1] += 1
                }
                // Reset deeper indents
                for key in counters.keys where key > indent { counters[key] = nil }

                let count = counters[indent] ?? 1
                let indentStr = String(s.prefix(while: { $0 == " " || $0 == "\t" }))
                let rest = s[restIdx...]
                let newLine = indentStr + String(count) + "." + String(rest)
                result.append(newLine)
                prevWasOrderedAtIndent = indent
            } else {
                // Non-ordered line: reset state
                prevWasOrderedAtIndent = nil
                // Also clear all counters when encountering a blank line
                if s.trimmingCharacters(in: .whitespaces).isEmpty { counters.removeAll() }
                result.append(line)
            }
        }
        return result.joined(separator: "\n")
    }
    
    var markdownAttributed: AttributedString {
        do {
            // Normalize bullets and remove stray markers first. Do not collapse lead-in spacing here;
            // we handle the visual break during assembly to preserve list semantics.
            let normalizedContent = self.sanitizedForMarkdown
                .replacingCommonLaTeXSymbols
                .removingLeadingListMarkers
                .normalizedMarkdown
                .renumberOrderedListsForDisplay

            // Split content by double line breaks to preserve paragraph spacing
            let paragraphs = normalizedContent.components(separatedBy: "\n\n")
            var result = AttributedString()

            for (index, paragraph) in paragraphs.enumerated() {
                let trimmedParagraph = paragraph.trimmingCharacters(in: .whitespaces)

                if !trimmedParagraph.isEmpty {
                    // Use full parsing for headers and code blocks only. For lists and normal text,
                    // use inline parsing so that visible markers ("- ", "1.") are preserved in Text.
                    let useFull = trimmedParagraph.hasPrefix("#") ||
                                  trimmedParagraph.hasPrefix("```") ||
                                  paragraph.contains("```")

                    let options: AttributedString.MarkdownParsingOptions = .init(
                        interpretedSyntax: useFull ? .full : .inlineOnlyPreservingWhitespace
                    )
                    let parsed = try AttributedString(markdown: trimmedParagraph, options: options)
                    result.append(parsed)
                }

                // Add paragraph break (except for the last paragraph)
                if index < paragraphs.count - 1 {
                    // Detect lead-in lines like "**Strengths:**" where ':' is before closing markdown markers
                    let currentEndsWithColon = trimmedParagraph.endsWithColonIgnoringMarkdownClosers()
                    let nextParagraph = paragraphs[index + 1]
                    let nextStartsList = nextParagraph.startsWithListMarker()
                    // If a lead-in ends with ':' and the next starts with a list, insert only a single newline
                    let breakString = (currentEndsWithColon && nextStartsList) ? "\n" : "\n\n"
                    let breakAttr = AttributedString(breakString)
                    result.append(breakAttr)
                }
            }

            return result.applyingCustomMarkdownFormatting()
        } catch {
            // If markdown parsing fails, return plain text
            return AttributedString(self)
        }
    }

    // MARK: - Helper predicates to ease type checking

    fileprivate func startsWithListMarker() -> Bool {
        let trimmed = self.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- ") { return true }
        if trimmed.hasPrefix("* ") { return true }
        if let dotIndex = trimmed.firstIndex(of: ".") {
            let numberPart = trimmed[..<dotIndex]
            if numberPart.allSatisfy({ $0.isNumber }) {
                let afterDot = trimmed[trimmed.index(after: dotIndex)...]
                if afterDot.first?.isWhitespace == true { return true }
            }
        }
        return false
    }

    fileprivate func endsWithColonIgnoringMarkdownClosers() -> Bool {
        var view = self[...]
        while let last = view.last, last.isWhitespace { view = view.dropLast() }
        while let last = view.last, last == "*" || last == "_" || last == "`" || last == "~" { view = view.dropLast() }
        return view.last == ":"
    }
}

private extension AttributedString {
    func applyingCustomMarkdownFormatting() -> AttributedString {
        guard characters.contains("+") else { return self }

        let mutable = NSMutableAttributedString(self)
        let pattern = "\\+\\+(.+?)\\+\\+"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return self
        }

        while true {
            let nsRange = NSRange(location: 0, length: mutable.length)
            guard let match = regex.firstMatch(in: mutable.string, options: [], range: nsRange) else { break }

            let underlineRange = match.range(at: 1)
            if underlineRange.length > 0 {
                mutable.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: underlineRange)
            }

            let closingRange = NSRange(location: match.range.location + match.range.length - 2, length: 2)
            mutable.replaceCharacters(in: closingRange, with: "")

            let openingRange = NSRange(location: match.range.location, length: 2)
            mutable.replaceCharacters(in: openingRange, with: "")
        }

        return AttributedString(mutable)
    }
}
