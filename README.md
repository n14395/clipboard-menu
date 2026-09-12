# ClipboardMenu

A powerful macOS menu bar clipboard manager with snippets, search, and iCloud sync.

## Features

- **Clipboard History**: Automatically captures text, rich text, images, and videos
- **Two Menu Bar Items**: Separate menus for history and saved snippets
- **Thumbnails & Previews**: Images/videos shown as thumbnails, expand on hover
- **Snippets with Variables**: Save frequently used text with dynamic variables:
  - `{{date}}`, `{{time}}`, `{{datetime}}`
  - `{{clipboard}}` - current clipboard content
  - `{{cursor}}` - cursor position after paste
  - `{{uuid}}`, `{{random}}`, `{{username}}`, `{{hostname}}`
- **Regex Search**: Power-user friendly search with regex support
- **iCloud Sync**: Snippets sync across your devices via iCloud
- **User Configurable**: Set your own limits for history items and storage

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later
- Apple Developer account (for CloudKit/iCloud features)

## Building

### Using Swift Package Manager

```bash
cd clipboard-menu
swift build
```

### Using Xcode

1. Open the project in Xcode:
   ```bash
   open Package.swift
   ```

2. Select the "ClipboardMenu" scheme

3. Build and run (⌘R)

### Creating a Release Build

```bash
swift build -c release
```

The built executable will be at `.build/release/ClipboardMenu`

## Project Structure

```
ClipboardMenu/
├── ClipboardMenuApp.swift          # App entry point
├── Models/
│   ├── ClipboardItem.swift         # Clipboard history item model
│   ├── Snippet.swift               # Saved snippet model
│   └── ContentType.swift           # Content type enum
├── Services/
│   ├── ClipboardMonitor.swift      # Monitors clipboard for changes
│   ├── StorageService.swift        # SQLite + file storage
│   ├── ThumbnailService.swift      # Image/video thumbnail generation
│   ├── SearchService.swift         # Text and regex search
│   ├── VariableService.swift       # Snippet variable expansion
│   ├── CloudKitService.swift       # iCloud sync for snippets
│   └── PreferencesService.swift    # User preferences
├── Views/
│   ├── MenuBarController.swift     # Menu bar item management
│   ├── HistoryMenuView.swift       # Clipboard history menu
│   ├── SnippetsMenuView.swift      # Snippets menu
│   ├── ClipboardItemView.swift     # Individual item row
│   ├── MediaPreviewPopover.swift   # Hover preview for media
│   └── PreferencesView.swift       # Settings window
└── Resources/
    └── Assets.xcassets             # App icons (add your own)
```

## Configuration

### iCloud Setup

To enable iCloud sync:

1. Sign in to your Apple Developer account
2. Create a CloudKit container with identifier `iCloud.com.clipboardmenu.app`
3. Enable CloudKit capability in Xcode
4. Update the entitlements file if using a different container ID

### Keyboard Shortcuts

Default shortcuts (customizable in preferences):
- `⌘⇧V` - Open clipboard history
- `⌘⇧S` - Open snippets

## Storage

Data is stored in:
- `~/Library/Application Support/ClipboardMenu/clipboard.db` - SQLite database
- `~/Library/Application Support/ClipboardMenu/Media/` - Original media files
- `~/Library/Application Support/ClipboardMenu/Thumbnails/` - Generated thumbnails

## Dependencies

- [GRDB.swift](https://github.com/groue/GRDB.swift) - SQLite database wrapper

## License

MIT License
