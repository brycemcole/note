# Share Extension Setup Instructions

This setup allows users to share content from Safari, other apps, and text selections directly to your Notes app. The app will automatically create new notes and generate summaries for the shared content.

## Setup Steps in Xcode

### 1. Enable App Groups

1. In your main app target, go to "Signing & Capabilities"
2. Click "+ Capability" and add "App Groups"
3. Create a new app group with identifier: `group.com.yourapp.notesapp`
   (Replace `com.yourapp.notesapp` with your actual app's bundle identifier)

### 2. Create Share Extension Target

1. In Xcode, go to File → New → Target
2. Choose "Share Extension" under iOS
3. Name it "ShareExtension"
4. Make sure to use the same bundle identifier prefix as your main app

### 3. Configure Share Extension

1. In the ShareExtension target, go to "Signing & Capabilities"
2. Add "App Groups" capability
3. Enable the same app group: `group.com.yourapp.notesapp`

### 4. Update App Group Identifier

In both `SharedDataManager.swift` and `ShareViewController.swift`, update this line:
```swift
static let appGroupIdentifier = "group.com.yourapp.notesapp"
```
Replace with your actual app group identifier.

### 5. Add Files to Share Extension Target

Make sure these files are added to the ShareExtension target:
- `ShareViewController.swift`
- `MainInterface.storyboard`
- `Info.plist` (the ShareExtension one)
- `NotesAppShareExtension.js`

### 6. Add Shared Files to Both Targets

These files need to be included in both the main app and ShareExtension targets:
- `SharedDataManager.swift`
- `Note.swift`
- `Folder.swift` (if you have one)
- Any other model files

### 7. Update Main App Info.plist

Add the URL scheme to your main app's Info.plist (if you haven't already):
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>com.yourapp.notesapp</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>notesapp</string>
        </array>
    </dict>
</array>
```

## How It Works

### For Users:
1. **From Safari**: Users can tap the Share button on any webpage, then select "Save to Notes"
2. **From Text Selection**: Users can select text in any app, tap Share, then "Save to Notes"
3. **From Links**: Users can long-press on links and share them directly

### Behind the Scenes:
1. The Share Extension captures the shared content (URL or text)
2. It saves the content to shared UserDefaults using App Groups
3. It attempts to open the main app using a custom URL scheme
4. The main app processes the shared content and creates a new note
5. If it's a URL, the app fetches the webpage content and extracts title/description
6. The app automatically generates a summary using Foundation Models (if available)

## Features:
- ✅ Automatic title generation from content
- ✅ Web page content extraction (title, description, meta info)
- ✅ AI-powered summary generation
- ✅ Works offline (content is queued and processed when app opens)
- ✅ Supports both URLs and plain text
- ✅ Integrates with your existing SwiftData model

## Testing:
1. Build and run both the main app and ShareExtension
2. Open Safari and navigate to any webpage
3. Tap the Share button
4. Look for "Save to Notes" in the share sheet
5. Tap it - you should see a brief "Saving to Notes..." screen
6. The main app should open and create a new note with the webpage content

## Troubleshooting:
- Make sure App Groups are enabled and use the same identifier in both targets
- Ensure the URL scheme in Info.plist matches what's used in the code
- Check that all model files are included in both targets
- Verify that the ShareExtension target has access to the necessary frameworks (SwiftData, Foundation, etc.)