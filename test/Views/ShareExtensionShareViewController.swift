//
//  ShareViewController.swift
//  ShareExtension
//

import UIKit
import Social
import UniformTypeIdentifiers
import MobileCoreServices

class ShareViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Add a small delay to show the UI briefly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.handleSharedContent()
        }
    }
    
    private func handleSharedContent() {
        guard let extensionContext = extensionContext,
              let inputItem = extensionContext.inputItems.first as? NSExtensionItem,
              let attachments = inputItem.attachments else {
            completeRequest()
            return
        }
        
        // Process the first attachment
        if let attachment = attachments.first {
            processAttachment(attachment)
        } else {
            completeRequest()
        }
    }
    
    private func processAttachment(_ attachment: NSItemProvider) {
        // Try URL first (for web links)
        if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, error in
                DispatchQueue.main.async {
                    if let url = item as? URL {
                        self?.saveSharedContent(url.absoluteString, isURL: true)
                    } else if let urlString = item as? String, let url = URL(string: urlString) {
                        self?.saveSharedContent(url.absoluteString, isURL: true)
                    } else {
                        self?.completeRequest()
                    }
                }
            }
        }
        // Then try plain text
        else if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, error in
                DispatchQueue.main.async {
                    if let text = item as? String {
                        // Check if the text is actually a URL
                        if text.hasPrefix("http://") || text.hasPrefix("https://") {
                            self?.saveSharedContent(text, isURL: true)
                        } else {
                            self?.saveSharedContent(text, isURL: false)
                        }
                    } else {
                        self?.completeRequest()
                    }
                }
            }
        }
        // Try property list (for Safari and other web browsers)
        else if attachment.hasItemConformingToTypeIdentifier(kUTTypePropertyList as String) {
            attachment.loadItem(forTypeIdentifier: kUTTypePropertyList as String, options: nil) { [weak self] item, error in
                DispatchQueue.main.async {
                    if let dict = item as? [String: Any] {
                        // Handle Safari share extension data
                        if let results = dict[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any] {
                            if let url = results["URL"] as? String ?? results["url"] as? String {
                                self?.saveSharedContent(url, isURL: true)
                                return
                            }
                            if let title = results["title"] as? String {
                                self?.saveSharedContent(title, isURL: false)
                                return
                            }
                        }
                        
                        // Try other common keys
                        if let url = dict["URL"] as? String ?? dict["url"] as? String {
                            self?.saveSharedContent(url, isURL: true)
                            return
                        }
                    }
                    self?.completeRequest()
                }
            }
        }
        else {
            completeRequest()
        }
    }
    
    private func saveSharedContent(_ content: String, isURL: Bool) {
        // Save to UserDefaults for the main app to pick up
        let appGroupID = "group.com.br3dev.test" // Must match your app group ID
        guard let sharedDefaults = UserDefaults(suiteName: appGroupID) else {
            completeRequest()
            return
        }
        
        let sharedData: [String: Any] = [
            "content": content,
            "isURL": isURL,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        // Get existing pending shares and add this one
        var pendingShares = sharedDefaults.array(forKey: "pendingShares") as? [[String: Any]] ?? []
        pendingShares.append(sharedData)
        sharedDefaults.set(pendingShares, forKey: "pendingShares")
        sharedDefaults.synchronize()
        
        // Try to open the main app with a custom URL scheme
        openMainApp()
        
        completeRequest()
    }
    
    private func openMainApp() {
        // Try multiple approaches to open the main app
        if let url = URL(string: "notesapp://process-shared-content") {
            // Method 1: Try to open via extension context
            if let context = extensionContext {
                context.open(url, completionHandler: nil)
                return
            }
            
            // Method 2: Try via UIApplication if available
            var responder = self as UIResponder?
            while responder != nil {
                if let application = responder as? UIApplication {
                    application.open(url, options: [:], completionHandler: nil)
                    return
                }
                responder = responder?.next
            }
            
            // Method 3: Try NSExtensionContext open method
            let selector = NSSelectorFromString("openURL:completionHandler:")
            if let context = extensionContext, context.responds(to: selector) {
                context.perform(selector, with: url, with: nil)
            }
        }
    }
    
    private func completeRequest() {
        DispatchQueue.main.async {
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
}
