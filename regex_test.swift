#!/usr/bin/env swift

import Foundation

// Test the regex fixes for parsing markdown image syntax with special characters
func testRegexWithSpecialCharacters() {
    let imagePattern = #"!\[(.*?)\]\((.*?)\)"#
    
    // Test cases that might have caused issues
    let testCases = [
        "![Image](@\"Screenshot 2025-09-17 at 2.13.00 PM.heic\")",
        "![Test Image](screenshot_with_@_symbol.png)",
        "![Another](image@2x.png)",
        "Regular text with @\"Screenshot 2025-09-17 at 2.13.00 PM.heic\" reference",
        "![Valid](https://example.com/image.jpg)"
    ]
    
    for (index, testCase) in testCases.enumerated() {
        print("Test \(index + 1): \(testCase)")
        
        do {
            let regex = try NSRegularExpression(pattern: imagePattern, options: [])
            let range = NSRange(location: 0, length: testCase.utf16.count)
            
            if let match = regex.firstMatch(in: testCase, options: [], range: range) {
                let altTextRange = Range(match.range(at: 1), in: testCase)!
                let urlRange = Range(match.range(at: 2), in: testCase)!
                let altText = String(testCase[altTextRange])
                let imageURL = String(testCase[urlRange])
                
                print("  ✅ Match found - Alt: '\(altText)', URL: '\(imageURL)'")
            } else {
                print("  ⚪ No match (expected for test case 4)")
            }
        } catch {
            print("  ❌ Regex error: \(error)")
        }
        
        print("")
    }
}

print("Testing regex patterns with special characters...")
testRegexWithSpecialCharacters()