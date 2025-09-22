# Xcode Setup Instructions to Fix Info.plist Conflict

I've created all the necessary files for you. Now you need to configure these in Xcode:

## Files Created:
1. `Note.entitlements` - Main app entitlements
2. `ShareExtension.entitlements` - Share extension entitlements  
3. `ShareExtension-Info.plist` - Proper Info.plist for share extension
4. Updated `ShareViewController.swift` - Improved share handling

## Manual Steps in Xcode:

### Step 1: Configure Main App Target ("Note")
1. Select your project in Project Navigator
2. Select the **"Note"** target
3. Go to **"Build Settings"** tab
4. Search for "Code Signing Entitlements"
5. Set it to: `Note.entitlements`
6. Go to **"Build Phases"** tab
7. Open **"Copy Bundle Resources"**
8. **Remove any Info.plist file** from this list (click the `-` button)
9. Go to **"General"** tab
10. Set **Bundle Identifier** to: `br3dev.test`

### Step 2: Create/Configure Share Extension Target
If you don't have a ShareExtension target yet:
1. Go to **File > New > Target**
2. Choose **"Share Extension"** under iOS
3. Set **Product Name** to: `ShareExtension`
4. Set **Bundle Identifier** to: `br3dev.test.ShareExtension`

For the ShareExtension target:
1. Select the **"ShareExtension"** target
2. Go to **"Build Settings"** tab
3. Search for "Info.plist File"
4. Set it to: `ShareExtension-Info.plist`
5. Search for "Code Signing Entitlements"
6. Set it to: `ShareExtension.entitlements`
7. Go to **"General"** tab
8. Set **Bundle Identifier** to: `br3dev.test.ShareExtension`

### Step 3: Add Files to Targets
1. In Project Navigator, select `Note.entitlements`
2. In File Inspector (right panel), check **"Note"** target
3. Select `ShareExtension.entitlements`
4. In File Inspector, check **"ShareExtension"** target
5. Select `ShareExtension-Info.plist`
6. In File Inspector, check **"ShareExtension"** target

### Step 4: Configure App Groups (if not done)
**Main App Target:**
1. Select "Note" target
2. Go to "Signing & Capabilities"
3. Click "+ Capability" 
4. Add "App Groups"
5. Set group ID: `group.com.br3dev.test`

**Share Extension Target:**
1. Select "ShareExtension" target
2. Go to "Signing & Capabilities"
3. Click "+ Capability"
4. Add "App Groups" 
5. Set group ID: `group.com.br3dev.test`

### Step 5: Configure URL Scheme
1. Select "Note" target
2. Go to "Info" tab
3. Expand "URL Types"
4. Add new URL Type:
   - **URL Schemes**: `notesapp`
   - **Identifier**: `br3dev.test.urlscheme`
   - **Role**: Editor

### Step 6: Clean and Build
1. Press `Cmd+Shift+K` to clean
2. Press `Cmd+B` to build

## What This Fixes:
- Removes Info.plist conflict (main app uses auto-generated one)
- Share extension uses its own specific Info.plist
- Both targets share the same app group for data sharing
- URL scheme allows share extension to open main app
- Proper entitlements for both targets

After following these steps, your share extension should work properly and the Info.plist conflict should be resolved!