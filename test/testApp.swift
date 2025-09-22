//
//  testApp.swift
//  test
//
//  Created by Bryce Cole on 9/16/25.
//

import SwiftUI
import SwiftData

@main
struct testApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isProcessingSharedContent = false
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Note.self,
            Folder.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema, 
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    SharedDataManager.shared.configure(with: sharedModelContainer)
                    Task { await processSharedContentIfNeeded() }
                }
                .onOpenURL { url in
                    print("🔗 Received URL: \(url)")
                    if url.scheme == "notesapp" && url.host == "process-shared-content" {
                        print("✅ Processing shared content...")
                        Task { await processSharedContentIfNeeded() }
                    } else {
                        print("❌ URL not recognized: scheme=\(url.scheme ?? "nil"), host=\(url.host ?? "nil")")
                    }
                }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await processSharedContentIfNeeded() }
            }
        }
    }
    
    @MainActor
    private func processSharedContentIfNeeded() async {
        guard !isProcessingSharedContent else { return }
        isProcessingSharedContent = true
        defer { isProcessingSharedContent = false }

        let appGroupID = "group.com.br3dev.test" 
        print("📂 Checking for shared content in app group: \(appGroupID)")
        
        guard let sharedDefaults = UserDefaults(suiteName: appGroupID) else {
            print("❌ Failed to access shared UserDefaults")
            return
        }
        
        guard let pendingShares = sharedDefaults.array(forKey: "pendingShares") as? [[String: Any]],
              !pendingShares.isEmpty else {
            print("📭 No pending shares found")
            return
        }
        
        print("📥 Found \(pendingShares.count) pending shares")
        
        // Process all pending shares
        for (index, shareData) in pendingShares.enumerated() {
            print("🔄 Processing share \(index + 1)/\(pendingShares.count)")
            
            guard let content = shareData["content"] as? String,
                  let isURL = shareData["isURL"] as? Bool else {
                print("❌ Invalid share data format")
                continue
            }
            
            print("📝 Content: \(content.prefix(100))\(content.count > 100 ? "..." : "")")
            print("🔗 Is URL: \(isURL)")
            
            let folderID = (shareData["folderID"] as? String).flatMap(UUID.init)
            let pageTitle = shareData["pageTitle"] as? String
            let sourceURL = shareData["sourceURL"] as? String

            let sharedContent = SharedContent(text: content,
                                              isURL: isURL,
                                              folderID: folderID,
                                              explicitTitle: pageTitle,
                                              sourceURL: sourceURL)
            
            do {
                try await SharedDataManager.shared.createNoteFromSharedContent(sharedContent)
                print("✅ Successfully created note from shared content")
            } catch {
                print("❌ Failed to create note from shared content: \(error)")
            }
        }
        
        // Clear processed shares
        sharedDefaults.removeObject(forKey: "pendingShares")
        sharedDefaults.synchronize()
        print("🗑️ Cleared processed shares")
    }
}
