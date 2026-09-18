import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Drop Delegate for Clipboard Item Reordering

struct ClipboardItemDropDelegate: DropDelegate {
    let item: ClipboardItem
    let items: [ClipboardItem]
    @Binding var draggingItemId: UUID?
    let onReorder: (Int, Int) -> Void
    
    func performDrop(info: DropInfo) -> Bool {
        draggingItemId = nil
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let dragId = draggingItemId,
              dragId != item.id,
              let fromIndex = items.firstIndex(where: { $0.id == dragId }),
              let toIndex = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }
        
        if fromIndex != toIndex {
            withAnimation(.easeInOut(duration: 0.2)) {
                onReorder(fromIndex, toIndex > fromIndex ? toIndex + 1 : toIndex)
            }
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        return draggingItemId != nil
    }
}

// MARK: - Helper Functions

@MainActor
func openPreferences() {
    NSApp.activate(ignoringOtherApps: true)
    
    // Find and open the Settings window
    // On macOS 14+, we need to find the settings window directly
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        // Look for an existing Settings window and bring it forward
        for window in NSApp.windows {
            // Settings windows have a specific identifier or toolbar
            if window.title == "Settings" || window.title == "Preferences" ||
               window.identifier?.rawValue.contains("settings") == true ||
               window.identifier?.rawValue.contains("preferences") == true {
                window.makeKeyAndOrderFront(nil)
                return
            }
        }
        
        // If no settings window found, try to create one via the standard action
        // This works on macOS 13, may show console warning on macOS 14+ but still works
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

// MARK: - Text Preview View
struct TextPreviewView: View {
    let text: String
    let size: NSSize
    
    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - File Stack Preview View
struct FileStackPreviewView: View {
    let paths: [String]
    let size: NSSize
    var filenameOverride: String? = nil  // Used for single files when filename has been updated
    
    private var isSingleFile: Bool { paths.count == 1 }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(paths.enumerated()), id: \.offset) { index, path in
                    // Only use filename override for single file (first item when count is 1)
                    let override = isSingleFile ? filenameOverride : nil
                    FileStackPreviewRow(path: path, filenameOverride: override)
                }
            }
            .padding(12)
        }
        .frame(width: size.width, height: size.height)
    }
}

struct FileStackPreviewRow: View {
    let path: String
    var filenameOverride: String? = nil  // Override filename extraction from path
    
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "webp"
    ]
    
    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "json", "xml", "html", "htm", "css", "js", "ts",
        "swift", "py", "rb", "java", "c", "cpp", "h", "hpp", "m", "mm",
        "sh", "bash", "zsh", "fish", "yaml", "yml", "toml", "ini", "cfg", "conf",
        "log", "csv", "tsv", "sql", "rs", "go", "php", "pl", "r", "lua"
    ]
    
    private var url: URL { URL(fileURLWithPath: path) }
    
    /// Check if this is a cloud file that isn't downloaded (without triggering download)
    private var isCloudFileNotDownloaded: Bool {
        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey
            ])
            
            guard resourceValues.isUbiquitousItem == true else {
                return false
            }
            
            // Check download status - .current and .downloaded both mean available
            if let status = resourceValues.ubiquitousItemDownloadingStatus {
                if status == .current || status == .downloaded {
                    return false
                }
            }
            
            // Can't reliably check for local data without triggering download
            // Trust the iCloud status
            return true
        } catch {
            return false
        }
    }
    
    /// Extract the original filename from storage path or external path
    /// Storage formats:
    /// - Snippet file stack: snippet_{UUID}_{index}_{originalFilename}
    /// - Snippet single file: snippet_{UUID}_{originalFilename}
    /// - Clipboard file stack: {UUID}_{index}_{originalFilename}
    /// - Clipboard single file: {UUID}_{originalFilename}
    /// External format: just the regular path
    private var filename: String {
        // Use override if provided (for renamed files)
        if let override = filenameOverride, !override.isEmpty {
            return override
        }
        
        let lastComponent = url.lastPathComponent
        
        // Check for snippet file stack format: snippet_{UUID}_{index}_{originalFilename}
        let snippetStackPattern = "^snippet_[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}_\\d+_"
        if let regex = try? NSRegularExpression(pattern: snippetStackPattern, options: .caseInsensitive) {
            let range = NSRange(lastComponent.startIndex..., in: lastComponent)
            if let match = regex.firstMatch(in: lastComponent, range: range) {
                let matchEnd = Range(match.range, in: lastComponent)!.upperBound
                return String(lastComponent[matchEnd...])
            }
        }
        
        // Check for snippet single file format: snippet_{UUID}_{originalFilename}
        let snippetSinglePattern = "^snippet_[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}_"
        if let regex = try? NSRegularExpression(pattern: snippetSinglePattern, options: .caseInsensitive) {
            let range = NSRange(lastComponent.startIndex..., in: lastComponent)
            if let match = regex.firstMatch(in: lastComponent, range: range) {
                let matchEnd = Range(match.range, in: lastComponent)!.upperBound
                let remainder = String(lastComponent[matchEnd...])
                // Make sure it's not a file stack format (digit followed by underscore)
                if !remainder.isEmpty && !remainder.first!.isNumber {
                    return remainder
                }
            }
        }
        
        // Check for clipboard file stack format: {UUID}_{index}_{originalFilename}
        let clipboardStackPattern = "^[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}_\\d+_"
        if let regex = try? NSRegularExpression(pattern: clipboardStackPattern, options: .caseInsensitive) {
            let range = NSRange(lastComponent.startIndex..., in: lastComponent)
            if let match = regex.firstMatch(in: lastComponent, range: range) {
                let matchEnd = Range(match.range, in: lastComponent)!.upperBound
                return String(lastComponent[matchEnd...])
            }
        }
        
        // Check for clipboard single file format: {UUID}_{originalFilename}
        let clipboardSinglePattern = "^[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}_"
        if let regex = try? NSRegularExpression(pattern: clipboardSinglePattern, options: .caseInsensitive) {
            let range = NSRange(lastComponent.startIndex..., in: lastComponent)
            if let match = regex.firstMatch(in: lastComponent, range: range) {
                let matchEnd = Range(match.range, in: lastComponent)!.upperBound
                let remainder = String(lastComponent[matchEnd...])
                if !remainder.isEmpty {
                    return remainder
                }
            }
        }
        
        // Not an internal storage path, return as-is
        return lastComponent
    }
    
    private var ext: String { url.pathExtension.lowercased() }
    private var fileIcon: NSImage {
        // If file exists, get its icon directly
        if FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        
        // File doesn't exist - try to get icon based on file extension
        if !ext.isEmpty, let utType = UTType(filenameExtension: ext) {
            return NSWorkspace.shared.icon(for: utType)
        }
        
        // Fallback to generic document icon
        return NSWorkspace.shared.icon(for: .data)
    }
    private var isDirectory: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
    
    private var fileSize: String {
        // Don't access file system for cloud files that aren't downloaded
        if isCloudFileNotDownloaded {
            return cloudServiceName.map { "In \($0)" } ?? "In iCloud"
        }
        
        if isDirectory {
            // For cloud folders, show the cloud service name instead of item count
            // (item count is often wrong for cloud folders)
            if let cloudName = cloudServiceName {
                return "In \(cloudName)"
            }
            // Count items in the folder
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            let count = contents.count
            return count == 1 ? "Contains 1 item" : "Contains \(count) items"
        }
        
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else {
            return ""
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    /// Returns the cloud service name if this is a cloud path, nil otherwise
    private var cloudServiceName: String? {
        // Check path-based patterns first
        if path.contains("/Library/Mobile Documents/") || path.contains("/iCloud Drive/") {
            return "iCloud"
        }
        if path.contains("/CloudStorage/") {
            // Extract service name from path like /CloudStorage/OneDrive-Personal/
            // or /CloudStorage/Dropbox/
            if let range = path.range(of: "/CloudStorage/") {
                let afterCloudStorage = path[range.upperBound...]
                if let slashIndex = afterCloudStorage.firstIndex(of: "/") {
                    let servicePart = String(afterCloudStorage[..<slashIndex])
                    // Clean up common suffixes
                    if servicePart.lowercased().contains("onedrive") {
                        return "OneDrive"
                    } else if servicePart.lowercased().contains("dropbox") {
                        return "Dropbox"
                    } else if servicePart.lowercased().contains("google") {
                        return "Google Drive"
                    } else if servicePart.lowercased().contains("box") {
                        return "Box"
                    } else {
                        // Return the folder name as-is (might be custom)
                        return servicePart
                    }
                }
            }
            return "Cloud Storage"
        }
        
        // Check if file is ubiquitous (iCloud-synced) via resource values
        // This catches iCloud-synced Desktop/Documents folders which have regular paths
        do {
            let resourceValues = try url.resourceValues(forKeys: [.isUbiquitousItemKey])
            if resourceValues.isUbiquitousItem == true {
                return "iCloud"
            }
        } catch {
            // Ignore errors
        }
        
        return nil
    }
    
    private var isImage: Bool { Self.imageExtensions.contains(ext) }
    private var isText: Bool { Self.textExtensions.contains(ext) }
    
    private var textPreview: String? {
        // Don't try to read cloud files that aren't downloaded
        guard isText,
              !isCloudFileNotDownloaded,
              let data = FileManager.default.contents(atPath: path),
              data.count < 50000,
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return String(text.prefix(100)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var firstLinePreview: String? {
        // Don't try to read cloud files that aren't downloaded
        guard isText,
              !isCloudFileNotDownloaded,
              let data = FileManager.default.contents(atPath: path),
              data.count < 50000,
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        // Get first non-empty line
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                return String(trimmed.prefix(80))
            }
        }
        return nil
    }
    
    var body: some View {
        HStack(spacing: 10) {
            // Preview thumbnail
            previewThumbnail
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(filename)
                    .font(.system(.body))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                if isText, let preview = firstLinePreview, !fileSize.isEmpty {
                    Text("\(fileSize) - \(preview)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text(fileSize)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private var previewThumbnail: some View {
        if isCloudFileNotDownloaded {
            // Cloud file not downloaded - show blank file icon with cloud overlay
            ZStack {
                Image(systemName: "doc")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
                
                Image(systemName: "icloud")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .offset(y: 4)
            }
        } else if isImage, let image = NSImage(contentsOfFile: path) {
            // Image preview
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if isText, let preview = textPreview {
            // Text file preview - show miniature text
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.05))
                Text(preview)
                    .font(.system(size: 5, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.6))
                    .lineLimit(nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(3)
            }
        } else {
            // Default file icon
            Image(nsImage: fileIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

// MARK: - Preview Window Manager
@MainActor
class PreviewWindowManager {
    static let shared = PreviewWindowManager()
    
    private var previewWindow: NSWindow?
    private var currentItemId: UUID?
    private let gap: CGFloat = 4
    private let cornerRadius: CGFloat = 8
    
    // Preview size from preferences (default 500)
    var previewSize: CGFloat = 500
    
    // Computed preview constraints based on previewSize
    private var mediaPreviewSize: CGFloat { previewSize }
    private var textMinWidth: CGFloat { min(200, previewSize * 0.4) }
    private var textMaxWidth: CGFloat { previewSize }
    private var textMinHeight: CGFloat { textPadding }
    private var textMaxHeight: CGFloat { previewSize }
    private let textPadding: CGFloat = 24 // 12 on each side
    
    private init() {}
    
    /// Check if a path is a cloud file that isn't downloaded (without triggering download)
    private func isCloudFileNotDownloaded(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey
            ])
            
            guard resourceValues.isUbiquitousItem == true else {
                return false
            }
            
            // Check download status - .current and .downloaded both mean available
            if let status = resourceValues.ubiquitousItemDownloadingStatus {
                if status == .current || status == .downloaded {
                    return false
                }
            }
            
            // Can't reliably check for local data without triggering download
            // Trust the iCloud status
            return true
        } catch {
            return false
        }
    }
    
    /// Calculate the ideal size for image preview based on actual image dimensions
    private func calculateImagePreviewSize(for imagePath: String, hasFilename: Bool = true) -> NSSize {
        let padding: CGFloat = 16  // 8 on each side
        let minWidth: CGFloat = 150  // Minimum width for filename display
        let filenameHeight: CGFloat = hasFilename ? 40 : 0  // Space for filename (up to 3 lines + spacing)
        
        // Don't try to load cloud files that aren't downloaded
        if isCloudFileNotDownloaded(imagePath) {
            // Return default size for cloud file placeholder
            return NSSize(width: mediaPreviewSize + padding, height: mediaPreviewSize + padding + filenameHeight)
        }
        
        guard let image = NSImage(contentsOfFile: imagePath) else {
            // Fallback to square if we can't load the image
            return NSSize(width: mediaPreviewSize, height: mediaPreviewSize)
        }
        
        let imageSize = image.size
        guard imageSize.width > 0 && imageSize.height > 0 else {
            return NSSize(width: mediaPreviewSize, height: mediaPreviewSize)
        }
        
        let maxSize = mediaPreviewSize
        
        // Calculate scale to fit within maxSize while maintaining aspect ratio
        let widthRatio = maxSize / imageSize.width
        let heightRatio = maxSize / imageSize.height
        let scale = min(widthRatio, heightRatio, 1.0)  // Don't upscale small images beyond 1x
        
        var width = ceil(imageSize.width * scale)
        var height = ceil(imageSize.height * scale)
        
        // Ensure minimum size for very small images
        let minDimension: CGFloat = 100
        if width < minDimension && height < minDimension {
            let upscale = minDimension / max(width, height)
            width *= upscale
            height *= upscale
        }
        
        // Enforce minimum width for filename display
        width = max(width, minWidth)
        
        return NSSize(width: width + padding, height: height + padding + filenameHeight)
    }
    
    /// Calculate the ideal size for video preview based on stored thumbnail dimensions
    private func calculateVideoPreviewSize(for videoPath: String, thumbnailPath: String? = nil, hasFilename: Bool = true) -> NSSize {
        let padding: CGFloat = 16
        let minWidth: CGFloat = 150  // Minimum width for filename display
        let filenameHeight: CGFloat = hasFilename ? 40 : 0  // Space for filename (up to 3 lines + spacing)
        
        // If we have a stored thumbnail, use its dimensions
        if let thumbPath = thumbnailPath,
           let image = NSImage(contentsOfFile: thumbPath) {
            let imageSize = image.size
            if imageSize.width > 0 && imageSize.height > 0 {
                let width = max(imageSize.width, minWidth)
                return NSSize(width: width + padding, height: imageSize.height + padding + filenameHeight)
            }
        }
        
        // No thumbnail - return default 16:9 size for placeholder
        // Don't try to load video metadata as it may timeout for unsupported formats
        let width = max(mediaPreviewSize, minWidth)
        return NSSize(width: width + padding, height: mediaPreviewSize * 9 / 16 + padding + filenameHeight)
    }
    
    /// Calculate the ideal size for text preview based on content
    private func calculateTextPreviewSize(for text: String) -> NSSize {
        // Use a monospaced font matching the preview
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        
        // Calculate the size needed for the text
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        
        // Calculate bounding rect with a max width constraint
        let maxTextWidth = textMaxWidth - textPadding
        let boundingRect = attributedString.boundingRect(
            with: NSSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        
        // Add padding and constrain to min/max
        var width = ceil(boundingRect.width) + textPadding
        var height = ceil(boundingRect.height) + textPadding
        
        // Apply constraints
        width = min(max(width, textMinWidth), textMaxWidth)
        height = min(max(height, textMinHeight), textMaxHeight)
        
        return NSSize(width: width, height: height)
    }
    
    /// Calculate the ideal size for rich text preview based on its laid-out content
    private func calculateRichTextPreviewSize(for attributedString: NSAttributedString) -> NSSize {
        let maxTextWidth = textMaxWidth - textPadding
        let boundingRect = attributedString.boundingRect(
            with: NSSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        var width = ceil(boundingRect.width) + textPadding
        var height = ceil(boundingRect.height) + textPadding

        width = min(max(width, textMinWidth), textMaxWidth)
        height = min(max(height, textMinHeight), textMaxHeight)

        return NSSize(width: width, height: height)
    }

    /// Build the attributed string for a rich text preview, if the RTF can be read
    private func richTextPreviewContent(_ richTextData: Data?) -> NSAttributedString? {
        guard let data = richTextData,
              let attributedString = NSAttributedString(rtf: data, documentAttributes: nil),
              attributedString.length > 0 else {
            return nil
        }
        return attributedString
    }

    /// Calculate the ideal size for file stack preview based on file count and filename lengths
    private func calculateFileStackPreviewSize(for paths: [String], filenameOverride: String? = nil) -> NSSize {
        let rowHeight: CGFloat = 56  // Each file row height (including padding)
        let padding: CGFloat = 24
        let minWidth: CGFloat = 300
        let maxWidth: CGFloat = mediaPreviewSize  // Use max preview size from settings
        let minHeight: CGFloat = 80
        
        // Allow growing up to 2/3 of screen height to fit content
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        let maxHeight = screenHeight * 2 / 3
        
        let contentHeight = CGFloat(paths.count) * rowHeight + padding
        let height = min(max(contentHeight, minHeight), maxHeight)
        
        // Calculate width needed for filenames - find the longest filename
        var width: CGFloat = minWidth
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        
        // Layout components:
        // - Outer padding: 12 on each side = 24
        // - Icon: 40
        // - HStack spacing: 10
        // - Extra buffer for text rendering: 8
        let layoutOverhead: CGFloat = 24 + 40 + 10 + 8
        
        for (index, path) in paths.enumerated() {
            // Use filename override for single file (first item when count is 1)
            let filename: String
            if paths.count == 1 && index == 0, let override = filenameOverride, !override.isEmpty {
                filename = override
            } else {
                filename = extractFilename(from: path)
            }
            let textWidth = (filename as NSString).size(withAttributes: attributes).width
            let neededWidth = textWidth + layoutOverhead
            width = max(width, neededWidth)
        }
        
        // Clamp to max width
        width = min(width, maxWidth)
        
        return NSSize(width: width, height: height)
    }
    
    /// Extract original filename from storage path
    private func extractFilename(from path: String) -> String {
        let lastComponent = URL(fileURLWithPath: path).lastPathComponent
        
        // Check for snippet file stack format: snippet_{UUID}_{index}_{originalFilename}
        let snippetStackPattern = "^snippet_[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}_\\d+_"
        if let regex = try? NSRegularExpression(pattern: snippetStackPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: lastComponent, range: NSRange(lastComponent.startIndex..., in: lastComponent)),
           let matchRange = Range(match.range, in: lastComponent) {
            return String(lastComponent[matchRange.upperBound...])
        }
        
        // Check for snippet single file format: snippet_{UUID}_{originalFilename}
        let snippetSinglePattern = "^snippet_[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}_"
        if let regex = try? NSRegularExpression(pattern: snippetSinglePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: lastComponent, range: NSRange(lastComponent.startIndex..., in: lastComponent)),
           let matchRange = Range(match.range, in: lastComponent) {
            let remainder = String(lastComponent[matchRange.upperBound...])
            if !remainder.isEmpty && !remainder.first!.isNumber {
                return remainder
            }
        }
        
        // Check for clipboard file stack format: {UUID}_{index}_{originalFilename}
        let clipboardStackPattern = "^[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}_\\d+_"
        if let regex = try? NSRegularExpression(pattern: clipboardStackPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: lastComponent, range: NSRange(lastComponent.startIndex..., in: lastComponent)),
           let matchRange = Range(match.range, in: lastComponent) {
            return String(lastComponent[matchRange.upperBound...])
        }
        
        // Check for clipboard single file format: {UUID}_{originalFilename}
        let clipboardSinglePattern = "^[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}_"
        if let regex = try? NSRegularExpression(pattern: clipboardSinglePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: lastComponent, range: NSRange(lastComponent.startIndex..., in: lastComponent)),
           let matchRange = Range(match.range, in: lastComponent) {
            let remainder = String(lastComponent[matchRange.upperBound...])
            if !remainder.isEmpty {
                return remainder
            }
        }
        
        return lastComponent
    }
    
    /// Position the preview window next to the menu
    private func positionWindow(menuFrame: NSRect, itemY: CGFloat?, contentSize: NSSize) -> Bool {
        guard let screen = NSScreen.main else { return false }
        let visibleFrame = screen.visibleFrame
        
        let windowWidth = contentSize.width
        let windowHeight = contentSize.height
        
        // Determine if we should show on left or right of the menu
        let spaceOnLeft = menuFrame.minX - visibleFrame.minX
        let spaceOnRight = visibleFrame.maxX - menuFrame.maxX
        let showOnLeft = spaceOnLeft >= windowWidth || spaceOnLeft > spaceOnRight
        
        // Calculate the Y position (center on the hovered item)
        var centerY: CGFloat
        if let itemCenterY = itemY {
            centerY = itemCenterY
        } else {
            centerY = menuFrame.midY
        }
        
        // Calculate window position
        var windowX: CGFloat
        
        if showOnLeft {
            windowX = menuFrame.minX - windowWidth - gap
        } else {
            windowX = menuFrame.maxX + gap
        }
        
        // Center window vertically on the item, but clamp to screen
        var windowY = centerY - windowHeight / 2
        windowY = max(visibleFrame.minY, min(windowY, visibleFrame.maxY - windowHeight))
        
        // Position window
        let windowRect = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)
        previewWindow?.setFrame(windowRect, display: true)
        
        return true
    }
    
    private func createPreviewWindow(contentSize: NSSize, contentView: NSView) -> NSWindow {
        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        // Apply rounded corners to the content view
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = cornerRadius
        contentView.layer?.masksToBounds = true
        
        window.contentView = contentView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .popUpMenu
        window.hasShadow = true
        window.hidesOnDeactivate = false
        
        return window
    }
    
    func showPreview(for item: ClipboardItem, thumbnailService: ThumbnailService, menuFrame: NSRect?, itemY: CGFloat? = nil) {
        guard let menuFrame = menuFrame else { return }
        
        // Always hide and recreate to ensure correct positioning
        hidePreview()
        currentItemId = item.id
        
        let contentSize: NSSize
        let contentView: NSView
        
        // Determine preview type based on content
        if item.contentType == .image, let mediaPath = item.mediaPath {
            contentSize = calculateImagePreviewSize(for: mediaPath)
            let previewView = MediaPreviewPopover(
                mediaPath: mediaPath,
                contentType: item.contentType,
                thumbnailService: thumbnailService,
                maxPreviewSize: mediaPreviewSize,
                previewSize: contentSize,
                filename: item.textContent
            )
            let hostingView = NSHostingView(rootView: previewView)
            hostingView.frame = NSRect(origin: .zero, size: contentSize)
            contentView = wrapInVisualEffectView(hostingView, size: contentSize)
        } else if item.contentType == .video, let mediaPath = item.mediaPath {
            contentSize = calculateVideoPreviewSize(for: mediaPath, thumbnailPath: item.thumbnailPath)
            let previewView = MediaPreviewPopover(
                mediaPath: mediaPath,
                contentType: item.contentType,
                thumbnailService: thumbnailService,
                maxPreviewSize: mediaPreviewSize,
                previewSize: contentSize,
                thumbnailPath: item.thumbnailPath,
                filename: item.textContent
            )
            let hostingView = NSHostingView(rootView: previewView)
            hostingView.frame = NSRect(origin: .zero, size: contentSize)
            contentView = wrapInVisualEffectView(hostingView, size: contentSize)
        } else if item.contentType == .fileStack, let paths = item.mediaPaths, !paths.isEmpty {
            contentSize = calculateFileStackPreviewSize(for: paths)
            let previewView = FileStackPreviewView(paths: paths, size: contentSize)
            let hostingView = NSHostingView(rootView: previewView)
            hostingView.frame = NSRect(origin: .zero, size: contentSize)
            contentView = wrapInVisualEffectView(hostingView, size: contentSize)
        } else if item.contentType == .file, let path = item.mediaPath {
            // Single file - show as a one-item file stack
            contentSize = calculateFileStackPreviewSize(for: [path], filenameOverride: item.textContent)
            let previewView = FileStackPreviewView(paths: [path], size: contentSize, filenameOverride: item.textContent)
            let hostingView = NSHostingView(rootView: previewView)
            hostingView.frame = NSRect(origin: .zero, size: contentSize)
            contentView = wrapInVisualEffectView(hostingView, size: contentSize)
        } else if item.contentType == .richText,
                  let attributedString = richTextPreviewContent(item.richTextData) {
            contentSize = calculateRichTextPreviewSize(for: attributedString)
            let previewView = RichTextPreviewView(attributedString: attributedString, size: contentSize)
            let hostingView = NSHostingView(rootView: previewView)
            hostingView.frame = NSRect(origin: .zero, size: contentSize)
            contentView = wrapInVisualEffectView(hostingView, size: contentSize)
        } else if let text = item.previewText {
            contentSize = calculateTextPreviewSize(for: text)
            let previewView = TextPreviewView(text: text, size: contentSize)
            let hostingView = NSHostingView(rootView: previewView)
            hostingView.frame = NSRect(origin: .zero, size: contentSize)
            contentView = wrapInVisualEffectView(hostingView, size: contentSize)
        } else {
            return
        }
        
        // Create window
        previewWindow = createPreviewWindow(contentSize: contentSize, contentView: contentView)
        
        // Position and show
        if positionWindow(menuFrame: menuFrame, itemY: itemY, contentSize: contentSize) {
            previewWindow?.orderFront(nil)
        }
    }
    
    func showPreview(for snippet: Snippet, thumbnailService: ThumbnailService, menuFrame: NSRect?, itemY: CGFloat? = nil) {
        guard let menuFrame = menuFrame else { return }
        
        // Don't show preview for downloading snippets - they don't have local files yet
        if snippet.isDownloading {
            return
        }
        
        // Always hide and recreate to ensure correct positioning
        hidePreview()
        currentItemId = snippet.id
        
        let contentSize: NSSize
        let contentView: NSView
        
        // Determine preview type based on content
        if snippet.contentType == .image, let mediaPath = snippet.mediaPath {
            contentSize = calculateImagePreviewSize(for: mediaPath)
            let previewView = MediaPreviewPopover(
                mediaPath: mediaPath,
                contentType: snippet.contentType,
                thumbnailService: thumbnailService,
                maxPreviewSize: mediaPreviewSize,
                previewSize: contentSize,
                filename: snippet.textContent
            )
            let hostingView = NSHostingView(rootView: previewView)
            hostingView.frame = NSRect(origin: .zero, size: contentSize)
            contentView = wrapInVisualEffectView(hostingView, size: contentSize)
        } else if snippet.contentType == .video, let mediaPath = snippet.mediaPath {
            contentSize = calculateVideoPreviewSize(for: mediaPath, thumbnailPath: snippet.thumbnailPath)
            let previewView = MediaPreviewPopover(
                mediaPath: mediaPath,
                contentType: snippet.contentType,
                thumbnailService: thumbnailService,
                maxPreviewSize: mediaPreviewSize,
                previewSize: contentSize,
                thumbnailPath: snippet.thumbnailPath,
                filename: snippet.textContent
            )
            let hostingView = NSHostingView(rootView: previewView)
            hostingView.frame = NSRect(origin: .zero, size: contentSize)
            contentView = wrapInVisualEffectView(hostingView, size: contentSize)
        } else if snippet.contentType == .fileStack, let paths = snippet.mediaPaths, !paths.isEmpty {
            contentSize = calculateFileStackPreviewSize(for: paths)
            let previewView = FileStackPreviewView(paths: paths, size: contentSize)
            let hostingView = NSHostingView(rootView: previewView)
            hostingView.frame = NSRect(origin: .zero, size: contentSize)
            contentView = wrapInVisualEffectView(hostingView, size: contentSize)
        } else if snippet.contentType == .file, let path = snippet.mediaPath {
            // Single file - show as a one-item file stack
            contentSize = calculateFileStackPreviewSize(for: [path], filenameOverride: snippet.textContent)
            let previewView = FileStackPreviewView(paths: [path], size: contentSize, filenameOverride: snippet.textContent)
            let hostingView = NSHostingView(rootView: previewView)
            hostingView.frame = NSRect(origin: .zero, size: contentSize)
            contentView = wrapInVisualEffectView(hostingView, size: contentSize)
        } else if snippet.contentType == .richText,
                  let attributedString = richTextPreviewContent(snippet.richTextData) {
            contentSize = calculateRichTextPreviewSize(for: attributedString)
            let previewView = RichTextPreviewView(attributedString: attributedString, size: contentSize)
            let hostingView = NSHostingView(rootView: previewView)
            hostingView.frame = NSRect(origin: .zero, size: contentSize)
            contentView = wrapInVisualEffectView(hostingView, size: contentSize)
        } else if let text = snippet.previewText {
            contentSize = calculateTextPreviewSize(for: text)
            let previewView = TextPreviewView(text: text, size: contentSize)
            let hostingView = NSHostingView(rootView: previewView)
            hostingView.frame = NSRect(origin: .zero, size: contentSize)
            contentView = wrapInVisualEffectView(hostingView, size: contentSize)
        } else {
            return
        }
        
        // Create window
        previewWindow = createPreviewWindow(contentSize: contentSize, contentView: contentView)
        
        // Position and show
        if positionWindow(menuFrame: menuFrame, itemY: itemY, contentSize: contentSize) {
            previewWindow?.orderFront(nil)
        }
    }
    
    private func wrapInVisualEffectView(_ view: NSView, size: NSSize) -> NSVisualEffectView {
        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effectView.material = .popover
        effectView.state = .active
        effectView.wantsLayer = true
        view.frame = effectView.bounds
        view.autoresizingMask = [.width, .height]
        effectView.addSubview(view)
        return effectView
    }
    
    func hidePreview() {
        previewWindow?.orderOut(nil)
        previewWindow = nil
        currentItemId = nil
    }
    
    func hidePreview(for itemId: UUID) {
        guard currentItemId == itemId else { return }
        hidePreview()
    }
}

struct HistoryMenuView: View {
    @ObservedObject var controller: MenuBarController
    @State private var searchText = ""
    @State private var useRegex = false
    @State private var hoveredItemId: UUID?
    @State private var hoveredSnippetId: UUID?
    @State private var draggingItemId: UUID?
    @State private var draggingSnippetId: UUID?
    @State private var showClearConfirmation = false
    @State private var showLargeItemWarning = false
    @State private var pendingSnippetItem: ClipboardItem?
    @State private var snippetsExpanded = false
    @State private var calculatingItemId: UUID?  // Item currently being size-calculated for starring
    @StateObject private var sizeCalculator = SizeCalculator()
    @FocusState private var isSearchFocused: Bool

    var isIntegratedMode: Bool {
        controller.preferencesService.snippetsMenuMode == .integrated
    }

    var filteredItems: [ClipboardItem] {
        var items = controller.clipboardItems

        // Search
        if !searchText.isEmpty {
            items = controller.searchService.search(items: items, query: searchText, useRegex: useRegex)
        }

        return items
    }
    
    var filteredSnippets: [Snippet] {
        guard isIntegratedMode else { return [] }
        
        var snippets = controller.snippets
        
        // Search
        if !searchText.isEmpty {
            snippets = controller.searchService.search(snippets: snippets, query: searchText, useRegex: useRegex)
        }
        
        return snippets
    }
    

    
    /// The snippets to display in integrated mode (max 5 unless expanded)
    private var visibleIntegratedSnippets: [Snippet] {
        if snippetsExpanded {
            return filteredSnippets
        }
        return Array(filteredSnippets.prefix(5))
    }
    
    /// How many additional snippets exist beyond the visible 5
    private var hiddenSnippetCount: Int {
        max(0, filteredSnippets.count - 5)
    }
    
    /// Whether there are hidden snippets that can be shown
    private var canExpandSnippets: Bool {
        hiddenSnippetCount > 0
    }
    
    @ViewBuilder
    private var integratedSnippetsContent: some View {
        ForEach(visibleIntegratedSnippets) { snippet in
            IntegratedSnippetItemView(
                snippet: snippet,
                isHovered: hoveredSnippetId == snippet.id,
                isDragging: draggingSnippetId == snippet.id,
                isCompact: controller.preferencesService.compactSnippetsView,
                thumbnailService: controller.thumbnailService,
                onCopy: {
                    PreviewWindowManager.shared.hidePreview()
                    controller.copySnippetToClipboard(snippet)
                },
                onDelete: { controller.deleteSnippet(snippet) },
                onRetryDownload: { controller.retrySnippetDownload(snippet) },
                onCancelDownload: { controller.cancelSnippetDownload(snippet) },
                onHoverWithFrame: { snippet, isHovering, screenY in
                    hoveredSnippetId = isHovering ? snippet.id : nil
                    handleSnippetPreviewHover(snippet: snippet, isHovering: isHovering, itemScreenY: screenY)
                },
                isPendingDownload: controller.cloudDownloadService.pendingDownloadIds.contains(snippet.id)
            )
            // Force view update when download state changes
            .id("\(snippet.id)-\(snippet.currentDownloadIndex)-\(snippet.isDownloading)")
            .onDrag {
                draggingSnippetId = snippet.id
                return NSItemProvider(object: snippet.id.uuidString as NSString)
            } preview: {
                Color.clear.frame(width: 1, height: 1)
            }
            .onDrop(of: [.text], delegate: SnippetDropDelegate(
                snippet: snippet,
                snippets: controller.snippets,
                draggingSnippetId: $draggingSnippetId,
                onReorder: { from, to in
                    controller.moveSnippet(from: IndexSet(integer: from), to: to)
                }
            ))
        }
    }

    var body: some View {
        VisualEffectBackground {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Clipboard History")
                        .font(.headline)
                    Spacer()
                
                // Clear history button
                Button {
                    if !controller.clipboardItems.isEmpty {
                        showClearConfirmation = true
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear History")
                .disabled(controller.clipboardItems.isEmpty)
                
                // Settings button
                if #available(macOS 14.0, *) {
                    SettingsLink {
                        Image(systemName: "gearshape")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        openPreferences()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                // More options menu
                Menu {
                    Button("Rate ClipboardMenu…") {
                        // Deep-link to the Mac App Store write-review page. A menu-bar agent has no
                        // window to host the native review prompt, and Apple allows a manual "Rate"
                        // affordance only when it links out rather than calling requestReview().
                        // Replace with this app's App Store Connect numeric ID.
                        let appStoreID = "YOUR_APP_STORE_ID"
                        if let url = URL(string: "macappstore://apps.apple.com/app/id\(appStoreID)?action=write-review") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    #if SPARKLE
                    SparkleCheckForUpdatesButton()
                    #endif
                    Divider()
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .help("More Options")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onSubmit {
                        // Copy the first item when pressing Enter in search
                        if let firstItem = filteredItems.first {
                            PreviewWindowManager.shared.hidePreview()
                            controller.copyItemToClipboard(firstItem)
                        } else if let firstSnippet = filteredSnippets.first {
                            PreviewWindowManager.shared.hidePreview()
                            controller.copySnippetToClipboard(firstSnippet)
                        }
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Toggle(isOn: $useRegex) {
                    Text("RegEx")
                        .font(.caption)
                }
                .toggleStyle(.button)
                .help("Use Regular Expression")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Items list
            if filteredItems.isEmpty && filteredSnippets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? "No clipboard history" : "No matching items")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            // Anchor for scrolling to top
                            Color.clear
                                .frame(height: 0)
                                .id("historyTop")
                            
                            // Integrated snippets section (downloading snippets appear inline in the list)
                            if isIntegratedMode && !filteredSnippets.isEmpty {
                                HStack {
                                    Image(systemName: "star.fill")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("Saved Snippets")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                
                                // Show snippets (limited to 5 when there are more, downloading snippets appear inline)
                                integratedSnippetsContent
                                
                                // Show expand/collapse button if there are more than 5 snippets
                                if canExpandSnippets {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            snippetsExpanded.toggle()
                                        }
                                    } label: {
                                        HStack {
                                            Spacer()
                                            if snippetsExpanded {
                                                Text("Show less")
                                                    .font(.caption)
                                                Image(systemName: "chevron.up")
                                                    .font(.caption2)
                                            } else {
                                                Text("Show all \(filteredSnippets.count) snippets")
                                                    .font(.caption)
                                                Image(systemName: "chevron.down")
                                                    .font(.caption2)
                                            }
                                            Spacer()
                                        }
                                        .foregroundColor(.accentColor)
                                        .padding(.vertical, 6)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                // Divider between snippets and history
                                if !filteredItems.isEmpty {
                                    Divider()
                                        .padding(.vertical, 4)
                                }
                            }
                            
                            // History items section
                            if !filteredItems.isEmpty {
                                if isIntegratedMode && !filteredSnippets.isEmpty {
                                    HStack {
                                        Text("History")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Spacer()
                                    }
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                }
                                
                                ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                                    historyItemRow(item: item, index: index)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: controller.historyMenuOpenCount) {
                        proxy.scrollTo("historyTop", anchor: .top)
                        searchText = ""
                        snippetsExpanded = false
                        isSearchFocused = true
                    }
                }
            }
            }
        }
        .frame(width: 350, height: controller.historyMenuHeight)
        .onAppear {
            // Focus the search box when the popup opens
            isSearchFocused = true
        }
        .task {
            // Backup focus request in case immediate one doesn't work
            try? await Task.sleep(for: .milliseconds(50))
            isSearchFocused = true
        }
        .onDisappear {
            PreviewWindowManager.shared.hidePreview()
        }
        .onKeyPress(characters: .decimalDigits) { press in
            guard let number = Int(press.characters), number >= 1 && number <= 9 else {
                return .ignored
            }
            let index = number - 1
            if index < filteredItems.count {
                PreviewWindowManager.shared.hidePreview()
                controller.copyItemToClipboard(filteredItems[index])
                return .handled
            }
            return .ignored
        }
        .alert("Clear Clipboard History", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                controller.clearHistory()
            }
        } message: {
            Text("Are you sure you want to clear all \(controller.clipboardItems.count) items from your clipboard history? This cannot be undone.")
        }
        .sheet(isPresented: $showLargeItemWarning) {
            LargeItemWarningView(
                sizeCalculator: sizeCalculator,
                limitBytes: controller.preferencesService.maxItemSizeBytes,
                isCloudDownload: pendingSnippetItem?.isCloudFileNotDownloaded ?? false,
                onCancel: {
                    sizeCalculator.cancel()
                    pendingSnippetItem = nil
                    showLargeItemWarning = false
                },
                onSaveAnyway: {
                    if let item = pendingSnippetItem {
                        // Use appropriate method based on whether it's a file reference
                        if item.isFileReference {
                            controller.addCloudSnippet(from: item)
                        } else {
                            controller.addToSnippets(item)
                        }
                    }
                    sizeCalculator.reset()
                    pendingSnippetItem = nil
                    showLargeItemWarning = false
                }
            )
        }
        .onReceive(sizeCalculator.$exceedsLimit) { exceeds in
            if exceeds {
                calculatingItemId = nil
                showLargeItemWarning = true
            }
        }
        .onReceive(sizeCalculator.$isComplete) { complete in
            if complete && !sizeCalculator.exceedsLimit {
                // Under limit - add directly without showing warning
                if let item = pendingSnippetItem {
                    // Use appropriate method based on whether it's a file reference
                    if item.isFileReference {
                        controller.addCloudSnippet(from: item)
                    } else {
                        controller.addToSnippets(item)
                    }
                    pendingSnippetItem = nil
                }
                calculatingItemId = nil
                sizeCalculator.reset()
            }
        }
    }

    // MARK: - Size Calculation
    
    private func isCalculatingSizeFor(_ itemId: UUID) -> Bool {
        calculatingItemId == itemId && sizeCalculator.isCalculating
    }
    
    private func startSizeCalculation(for item: ClipboardItem) {
        pendingSnippetItem = item
        calculatingItemId = item.id
        sizeCalculator.startCalculation(
            for: item,
            limit: controller.preferencesService.maxItemSizeBytes,
            includeCloudFiles: item.isFileReference
        )
    }
    
    // MARK: - Item Row Builder
    
    @ViewBuilder
    private func historyItemRow(item: ClipboardItem, index: Int) -> some View {
        ClipboardItemView(
            item: item,
            isHovered: hoveredItemId == item.id,
            isDragging: draggingItemId == item.id,
            isCompact: controller.preferencesService.compactHistoryView,
            thumbnailService: controller.thumbnailService,
            downloadedPaths: controller.cloudDownloadService.downloadedPaths,
            onCopy: {
                PreviewWindowManager.shared.hidePreview()
                controller.copyItemToClipboard(item)
            },
            onFavorite: { startSizeCalculation(for: item) },
            onDelete: { controller.deleteItem(item) },
            onHoverWithFrame: { item, isHovering, screenY in
                hoveredItemId = isHovering ? item.id : nil
                handlePreviewHover(item: item, isHovering: isHovering, itemScreenY: screenY)
            },
            shortcutNumber: index < 9 ? index + 1 : nil,
            cachedCloudStatus: controller.cloudStatusCache[item.id],
            isComputingCloudStatus: controller.isComputingCloudStatus,
            isCalculatingSizeForStarring: isCalculatingSizeFor(item.id)
        )
        .onDrag {
            draggingItemId = item.id
            return NSItemProvider(object: item.id.uuidString as NSString)
        } preview: {
            Color.clear.frame(width: 1, height: 1)
        }
        .onDrop(of: [.text], delegate: ClipboardItemDropDelegate(
            item: item,
            items: controller.clipboardItems,
            draggingItemId: $draggingItemId,
            onReorder: { from, to in
                controller.moveClipboardItem(from: IndexSet(integer: from), to: to)
            }
        ))
    }
    
    // MARK: - Preview Management

    private func handlePreviewHover(item: ClipboardItem, isHovering: Bool, itemScreenY: CGFloat? = nil) {
        if isHovering {
            let popoverFrame = controller.historyPopoverFrame
            PreviewWindowManager.shared.previewSize = CGFloat(controller.preferencesService.previewSize)
            
            PreviewWindowManager.shared.showPreview(
                for: item,
                thumbnailService: controller.thumbnailService,
                menuFrame: popoverFrame,
                itemY: itemScreenY
            )
        } else {
            PreviewWindowManager.shared.hidePreview(for: item.id)
        }
    }
    
    private func handleSnippetPreviewHover(snippet: Snippet, isHovering: Bool, itemScreenY: CGFloat? = nil) {
        if isHovering {
            let popoverFrame = controller.historyPopoverFrame
            PreviewWindowManager.shared.previewSize = CGFloat(controller.preferencesService.previewSize)
            
            PreviewWindowManager.shared.showPreview(
                for: snippet,
                thumbnailService: controller.thumbnailService,
                menuFrame: popoverFrame,
                itemY: itemScreenY
            )
        } else {
            PreviewWindowManager.shared.hidePreview(for: snippet.id)
        }
    }
}

// MARK: - Integrated Snippet Item View

struct IntegratedSnippetItemView: View {
    let snippet: Snippet
    let isHovered: Bool
    var isDragging: Bool = false
    var isCompact: Bool = false
    let thumbnailService: ThumbnailService
    
    let onCopy: () -> Void
    let onDelete: () -> Void
    var onRetryDownload: (() -> Void)? = nil
    var onCancelDownload: (() -> Void)? = nil
    var onHoverWithFrame: ((Snippet, Bool, CGFloat?) -> Void)? = nil
    /// True if this snippet is queued waiting for another download to complete
    var isPendingDownload: Bool = false
    
    private var iconSize: CGFloat { isCompact ? 22 : 32 }
    private var verticalPadding: CGFloat { isCompact ? 4 : 8 }
    private var buttonSize: CGFloat { isCompact ? 22 : 28 }
    
    private var hoverBackground: Color {
        isDragging ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1)
    }
    
    /// Check if snippet has a download error
    private var hasError: Bool {
        snippet.downloadError != nil
    }
    
    /// Check if snippet is in a special state (downloading or error)
    private var isSpecialState: Bool {
        snippet.isDownloading || hasError
    }

    var body: some View {
        HStack(spacing: 8) {
            // Content type icon or thumbnail (show cloud icon when downloading/error)
            if snippet.isDownloading {
                downloadingIcon
                    .frame(width: iconSize, height: iconSize)
            } else if hasError {
                errorIcon
                    .frame(width: iconSize, height: iconSize)
            } else {
                contentPreview
                    .frame(width: iconSize, height: iconSize)
            }

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.displayText)
                    .font(.system(isCompact ? .callout : .body, weight: .medium))
                    .lineLimit(1)
                
                // Show status for downloading/error states
                if snippet.isDownloading {
                    HStack(spacing: 4) {
                        if isPendingDownload {
                            // Queued, waiting for another download to complete
                            Text("Waiting to download...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            // Actively downloading
                            ProgressView()
                                .controlSize(.mini)
                            if let cloudName = snippet.cloudServiceName {
                                Text("Downloading from \(cloudName)...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Copying Large \(snippet.downloadFileCount == 1 ? "File" : "Files")...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } else if let error = snippet.downloadError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(1)
                } else if !isCompact {
                    // Show text content preview for non-compact, non-special state
                    if let text = snippet.textContent, !text.isEmpty && text != snippet.name {
                        Text(text)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)
            
            // Action buttons
            if snippet.isDownloading {
                // Cancel button for downloading snippets
                Button(action: { onCancelDownload?() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(isCompact ? .caption : .body)
                        .frame(width: buttonSize, height: buttonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Cancel download")
            } else if hasError && isHovered {
                // Retry and delete buttons for error state
                HStack(spacing: 2) {
                    Button(action: { onRetryDownload?() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(isCompact ? .caption : .body)
                            .frame(width: buttonSize, height: buttonSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .help("Retry download")
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(isCompact ? .caption : .body)
                            .frame(width: buttonSize, height: buttonSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                    .help("Delete snippet")
                }
            } else if isHovered && !isDragging {
                // Normal delete button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(isCompact ? .caption : .body)
                        .frame(width: buttonSize, height: buttonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, verticalPadding)
        .frame(minHeight: iconSize + (verticalPadding * 2))
        .background(backgroundForState)
        .contentShape(Rectangle())
        .overlay(
            HoverTrackingView { hovering, screenFrame in
                // Don't show preview for downloading/error snippets
                if snippet.needsPreview && !isSpecialState {
                    let centerY = screenFrame.midY
                    onHoverWithFrame?(snippet, hovering, hovering ? centerY : nil)
                } else {
                    onHoverWithFrame?(snippet, hovering, nil)
                }
            }
        )
        .onTapGesture {
            // Only allow copy for completed snippets
            if !isSpecialState {
                onCopy()
            }
        }
    }
    
    private var backgroundForState: Color {
        if snippet.isDownloading {
            return Color.accentColor.opacity(0.1)
        } else if hasError {
            return Color.red.opacity(0.1)
        } else if isDragging || isHovered {
            return hoverBackground
        }
        return Color.clear
    }
    
    @ViewBuilder
    private var downloadingIcon: some View {
        let cornerRadius: CGFloat = isCompact ? 3 : 4
        
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.secondary.opacity(0.2))
            
            Image(systemName: "icloud.and.arrow.down")
                .font(isCompact ? .caption : .body)
                .foregroundColor(.accentColor)
        }
    }
    
    @ViewBuilder
    private var errorIcon: some View {
        let cornerRadius: CGFloat = isCompact ? 3 : 4
        
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.red.opacity(0.2))
            
            Image(systemName: "exclamationmark.icloud")
                .font(isCompact ? .caption : .body)
                .foregroundColor(.red)
        }
    }

    @ViewBuilder
    private var contentPreview: some View {
        let cornerRadius: CGFloat = isCompact ? 3 : 4
        let iconFont: Font = isCompact ? .caption : .body
        
        switch snippet.contentType {
        case .text, .richText:
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.secondary.opacity(0.2))
                .overlay(
                    Image(systemName: snippet.contentType.systemImageName)
                        .font(iconFont)
                        .foregroundColor(.secondary)
                )

        case .image, .video:
            if let thumbnailPath = snippet.thumbnailPath,
               let image = NSImage(contentsOfFile: thumbnailPath) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.secondary.opacity(0.2))
                    .overlay(
                        Image(systemName: snippet.contentType.systemImageName)
                            .font(iconFont)
                            .foregroundColor(.secondary)
                    )
            }

        case .file:
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.secondary.opacity(0.2))
                .overlay(
                    Image(systemName: snippet.fileSystemImageName)
                        .font(iconFont)
                        .foregroundColor(.secondary)
                )
        
        case .fileStack:
            if let paths = snippet.mediaPaths, !paths.isEmpty {
                FileStackIconsView(paths: paths, size: iconSize)
                    .id(paths.joined())  // Force refresh when paths change
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.secondary.opacity(0.2))
                    .overlay(
                        Image(systemName: "doc.on.doc")
                            .font(iconFont)
                            .foregroundColor(.secondary)
                    )
            }
        }
    }
}

// MARK: - Large Item Warning View

struct LargeItemWarningView: View {
    @ObservedObject var sizeCalculator: SizeCalculator
    let limitBytes: Int64
    var isCloudDownload: Bool = false
    let onCancel: () -> Void
    let onSaveAnyway: () -> Void
    
    private var title: String {
        isCloudDownload ? "Large Download" : "Large Item"
    }
    
    private var iconName: String {
        isCloudDownload ? "icloud.and.arrow.down" : "exclamationmark.triangle.fill"
    }
    
    private var actionText: String {
        isCloudDownload ? "Download Anyway" : "Save Anyway"
    }
    
    private var explanationText: String {
        if isCloudDownload {
            return "Downloading this file will exceed your storage limit and may take a while."
        } else {
            return "Saving it as a snippet will copy the data to your storage folder."
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundColor(.orange)
                Text(title)
                    .font(.headline)
            }
            
            // Message
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text(isCloudDownload ? "This file is" : "This item is")
                    Text(ByteCountFormatter.string(fromByteCount: sizeCalculator.currentSize, countStyle: .file))
                        .fontWeight(.semibold)
                    if sizeCalculator.isCalculating {
                        Text("(calculating...)")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
                
                Text("which exceeds your \(ByteCountFormatter.string(fromByteCount: limitBytes, countStyle: .file)) limit.")
                
                Text(explanationText)
                    .foregroundColor(.secondary)
                    .font(.callout)
            }
            .multilineTextAlignment(.center)
            
            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                
                Button(actionText) {
                    onSaveAnyway()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 340)
    }
}
