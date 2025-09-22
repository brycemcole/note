# Notes App with Bookmark Import

This notes app now includes the ability to import bookmarks from markdown files.

## New Features

### Settings View
- Added a settings icon (gear) in the top-left corner of the home screen
- Access settings to import bookmark files

### Bookmark Import
- Import bookmarks from markdown files
- Supports the format:
  ```markdown
  ## Folder Name
  Date - [Title](URL)
  
  ## Folder Name (icon_name, color)
  Date - [Title](URL)
  ```

### Folder Creation from Import
- Folders are automatically created based on markdown headers
- "Ungrouped Bookmarks" section creates notes without folders
- Folder metadata can be specified in parentheses after the folder name
- Example: `## Tech News (newspaper, blue)` creates a folder with newspaper icon and blue color

## Usage

1. Tap the settings icon (gear) in the top-left corner
2. Select "Import Bookmarks from Markdown"
3. Choose your markdown file
4. Bookmarks will be imported as notes with proper folder organization

## Sample Format

See `sample_bookmarks.md` for an example of the supported format.

The app will:
- Parse bookmark sections and create corresponding folders
- Extract titles, URLs, and dates from bookmark entries  
- Create individual notes for each bookmark
- Maintain folder organization and styling