# Setup Guide: Adding Settings and Import Features

## Issue: Cannot find 'SettingsView' in scope

The error occurs because the Swift files I created need to be properly added to your Xcode project. Here's how to fix it:

## Step 1: Add Missing Swift Files to Xcode Project

You need to add these Swift files to your Xcode project:

1. **SettingsView.swift** - Main settings interface with import functionality
2. **SmartFolderKind.swift** - Enum for smart folder types
3. **NoteRowView.swift** - Displays individual notes in lists
4. **FolderSquircleView.swift** - Displays folder cards with icons and counts
5. **SmartFolderDetailView.swift** - Shows notes filtered by smart folders
6. **FoldersView.swift** - Manages all user folders
7. **TrashView.swift** - Shows deleted notes with restore functionality
8. **SymbolPickerView.swift** - Icon selection interface

### How to add files to Xcode:

1. **Right-click** on your project folder in the Navigator
2. Select **"Add Files to [ProjectName]"**
3. Navigate to where these `.swift` files are located
4. Select all the files listed above
5. Make sure **"Add to target"** is checked for your app target
6. Click **"Add"**

## Step 2: Replace Temporary Settings Code

Once the files are added, replace this line in ContentView.swift:

**Find this code (around line 82):**
```swift
.sheet(isPresented: $showingSettings) {
    // Temporary placeholder - replace with SettingsView() once file is added to project
    NavigationView {
        // ... temporary content
    }
}
```

**Replace it with:**
```swift
.sheet(isPresented: $showingSettings) { SettingsView() }
```

## Step 3: Fix ShareExtensionShareViewController.swift Deprecations

In `ShareExtensionShareViewController.swift`, replace:

**Line 71:** 
```swift
kUTTypePropertyList  →  UTType.propertyList.identifier
```

**Line 72:**
```swift
kUTTypePropertyList  →  UTType.propertyList.identifier
```

And add this import at the top:
```swift
import UniformTypeIdentifiers
```

## Step 4: Verify All Files Are Added

After adding the files, your project should include:

- ✅ SettingsView.swift
- ✅ SmartFolderKind.swift  
- ✅ NoteRowView.swift
- ✅ FolderSquircleView.swift
- ✅ SmartFolderDetailView.swift
- ✅ FoldersView.swift
- ✅ TrashView.swift
- ✅ SymbolPickerView.swift

## Step 5: Build and Test

1. **Build** the project (Cmd+B)
2. **Run** the app (Cmd+R)
3. **Test** the new settings icon in the top-left corner
4. **Test** the bookmark import functionality

## Features You'll Get:

- ⚙️ **Settings icon** in top-left corner
- 📁 **Import bookmarks** from markdown files
- 🗂️ **Automatic folder creation** from markdown headers
- 🎨 **Folder customization** with icons and colors
- 📝 **Smart bookmark parsing** with dates, titles, and URLs

## Troubleshooting:

If you still get build errors:
1. **Clean Build Folder** (Product → Clean Build Folder)
2. **Restart Xcode**
3. **Check Target Membership** for all new files
4. **Verify imports** are correct in each file

## Sample Import File:

Use `sample_bookmarks.md` as a test file for the import functionality.