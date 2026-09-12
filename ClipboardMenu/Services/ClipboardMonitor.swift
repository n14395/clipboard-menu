import Foundation
import AppKit

/// Simple debug logging that writes to stderr immediately
private func debugLog(_ message: String) {
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    fputs("[\(timestamp)] \(message)\n", stderr)
    fflush(stderr)
}

@MainActor
class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int = 0
    private var timer: Timer?
    private let storageService: StorageService
    private let thumbnailService: ThumbnailService
    private let preferencesService: PreferencesService
    private let bookmarkService: BookmarkService
    private let pollingInterval: TimeInterval = 0.5
    
    /// Set to true temporarily when copying from our own history to prevent duplicate detection
    private var skipNextChange = false

    init(storageService: StorageService, thumbnailService: ThumbnailService, preferencesService: PreferencesService, bookmarkService: BookmarkService = BookmarkService()) {
        self.storageService = storageService
        self.thumbnailService = thumbnailService
        self.preferencesService = preferencesService
        self.bookmarkService = bookmarkService
        self.lastChangeCount = pasteboard.changeCount
    }
    
    /// Call this before copying an item from history to clipboard
    func willCopyFromHistory() {
        skipNextChange = true
    }
    
    /// Force a clipboard check - used when menu opens to ensure current clipboard is captured
    /// This bypasses the change count check to ensure current content is processed
    /// - Parameter completion: Called when processing is complete (on main thread)
    func checkClipboardNow(completion: (() -> Void)? = nil) {
        // Only process if there's actually content and it might be new
        // We check if the top item matches current clipboard content
        Task {
            await processClipboardIfNew()
            completion?()
        }
    }
    
    /// Process clipboard content only if it's not already at the top of history
    @MainActor
    private func processClipboardIfNew() async {
        // Get current clipboard content signature
        guard let currentSignature = getClipboardSignature() else {
            return // Empty clipboard
        }
        
        // Check if top item already matches
        do {
            let items = try storageService.fetchClipboardItems(limit: 1)
            if let topItem = items.first {
                let topSignature = getItemSignature(topItem)
                if topSignature == currentSignature {
                    debugLog("Clipboard content already at top of history")
                    return
                }
            }
        } catch {
            debugLog("Failed to fetch items for comparison: \(error)")
        }
        
        // Content is different - process it
        debugLog("Processing new clipboard content on menu open")
        lastChangeCount = pasteboard.changeCount  // Update to avoid double-processing
        await processClipboardContent()
    }
    
    /// Get a signature for the current clipboard content (for comparison)
    private func getClipboardSignature() -> String? {
        // Check for file URLs first
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !fileURLs.isEmpty {
            let paths = fileURLs.compactMap { $0.isFileURL ? $0.path : nil }.sorted()
            return "files:" + paths.joined(separator: "|")
        }
        
        // Check for rich text before image data - see processClipboardContent()
        if let data = pasteboard.data(forType: .rtf), containsReadableText(data) {
            return "rtf:\(data.count)"
        }

        // Check for image data
        if let data = pasteboard.data(forType: .png) {
            return "image:png:\(data.count)"
        }
        if let data = pasteboard.data(forType: .tiff) {
            return "image:tiff:\(data.count)"
        }

        // Check for rich text that couldn't be read as text (e.g. an embedded picture)
        if let data = pasteboard.data(forType: .rtf) {
            return "rtf:\(data.count)"
        }

        // Check for plain text
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return "text:" + text
        }
        
        return nil
    }
    
    /// Get a signature for a clipboard item (for comparison with clipboard)
    private func getItemSignature(_ item: ClipboardItem) -> String? {
        switch item.contentType {
        case .fileStack:
            if let paths = item.mediaPaths {
                // For file references, use the original paths
                // For copied files, extract original paths from storage paths
                let sortedPaths = paths.map { path -> String in
                    if path.contains("ClipboardMenu") {
                        // This is in our storage - we can't easily compare with clipboard
                        // Return a unique identifier that won't match
                        return "stored:\(path)"
                    }
                    return path
                }.sorted()
                return "files:" + sortedPaths.joined(separator: "|")
            }
            return nil
            
        case .file, .image, .video:
            if let path = item.mediaPath {
                if path.contains("ClipboardMenu") {
                    // Stored in our storage - compare by content if it's text
                    if let text = item.textContent {
                        return "text:" + text
                    }
                    return "stored:\(path)"
                }
                return "files:" + path
            }
            return nil
            
        case .text:
            if let text = item.textContent {
                return "text:" + text
            }
            return nil
            
        case .richText:
            if let data = item.richTextData {
                return "rtf:\(data.count)"
            }
            return nil
        }
    }
    
    /// Trigger async cleanup to enforce item count and storage limits
    private func triggerCleanup() {
        let maxItems = preferencesService.maxHistoryItems
        let maxStorageBytes = preferencesService.maxStorageBytes
        Task { @MainActor [storageService] in
            storageService.runCleanup(maxItems: maxItems, maxStorageBytes: maxStorageBytes)
        }
    }

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkClipboard()
            }
        }
        RunLoop.current.add(timer!, forMode: .common)
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func checkClipboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        // Skip if we just copied from our own history
        if skipNextChange {
            skipNextChange = false
            return
        }

        Task {
            await processClipboardContent()
        }
    }

    @MainActor
    private func processClipboardContent() async {
        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName

        debugLog("Processing clipboard content...")
        
        // Check for file URLs first (before image data, since file copies include preview images)
        debugLog("About to read file URLs from pasteboard...")
        let startTime = Date()
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !fileURLs.isEmpty {
            let elapsed = Date().timeIntervalSince(startTime)
            debugLog("readObjects took \(elapsed) seconds")
            let validFileURLs = fileURLs.filter { $0.isFileURL }
            
            debugLog("Found \(validFileURLs.count) file URL(s)")
            
            // Multiple files - save as file stack
            if validFileURLs.count > 1 {
                debugLog("Saving file stack...")
                await saveFileStackItem(urls: validFileURLs, sourceApp: sourceApp)
                debugLog("File stack save returned")
                triggerCleanup()
                return
            }
            
            // Single file - copy to storage
            if let url = validFileURLs.first {
                debugLog("Processing single file: \(url.lastPathComponent)")
                if isVideoFile(url) {
                    debugLog("Calling saveVideoItem...")
                    await saveVideoItem(url: url, sourceApp: sourceApp)
                    debugLog("saveVideoItem returned")
                    triggerCleanup()
                    return
                } else if isImageFile(url) {
                    debugLog("Calling saveImageItem...")
                    await saveImageItem(url: url, sourceApp: sourceApp)
                    debugLog("saveImageItem returned")
                    triggerCleanup()
                    return
                } else {
                    // Other file types (including text files like .md)
                    debugLog("Calling saveFileItem...")
                    await saveFileItem(url: url, sourceApp: sourceApp)
                    debugLog("saveFileItem returned")
                    triggerCleanup()
                    return
                }
            }
        }

        // Check for rich text before image data. Word processors put a rasterized
        // snapshot of the selection (TIFF, or PDF that NSImage will happily read) on
        // the pasteboard alongside the RTF, which would otherwise win and store the
        // copy as an image.
        if let rtfData = pasteboard.data(forType: .rtf), containsReadableText(rtfData) {
            await saveRichTextItem(data: rtfData, sourceApp: sourceApp)
            triggerCleanup()
            return
        }

        // Check for image data (actual image copies/screenshots, not file copies)
        if let imageData = getImageData() {
            await savePastedImageData(data: imageData, sourceApp: sourceApp)
            triggerCleanup()
            return
        }

        // Rich text that carries no readable text and no image data
        if let rtfData = pasteboard.data(forType: .rtf) {
            await saveRichTextItem(data: rtfData, sourceApp: sourceApp)
            triggerCleanup()
            return
        }

        // Check for plain text
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            await saveTextItem(text: text, sourceApp: sourceApp)
            triggerCleanup()
            return
        }
    }

    /// Whether RTF data carries actual text, as opposed to only an embedded picture.
    /// Copying a picture out of a word processor also produces RTF, but its only
    /// content is an attachment placeholder - those copies belong to the image path.
    private func containsReadableText(_ rtfData: Data) -> Bool {
        guard let attributedString = NSAttributedString(rtf: rtfData, documentAttributes: nil) else {
            return false
        }
        let stripped = attributedString.string
            .replacingOccurrences(of: "\u{FFFC}", with: "")  // attachment placeholders
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !stripped.isEmpty
    }

    private func getImageData() -> Data? {
        // Try PNG first
        if let data = pasteboard.data(forType: .png) {
            return data
        }
        // Try TIFF
        if let data = pasteboard.data(forType: .tiff) {
            return data
        }
        // Try to get NSImage and convert
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first {
            return image.pngData()
        }
        return nil
    }

    private func isVideoFile(_ url: URL) -> Bool {
        let videoExtensions = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]
        return videoExtensions.contains(url.pathExtension.lowercased())
    }

    private func isImageFile(_ url: URL) -> Bool {
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "webp"]
        return imageExtensions.contains(url.pathExtension.lowercased())
    }
    
    // MARK: - Cloud File Detection
    
    /// Check if a file is a ubiquitous (cloud-synced) item
    /// This includes iCloud Drive, iCloud Desktop & Documents sync, etc.
    private func isUbiquitousItem(_ url: URL) -> Bool {
        // First, check by path - common iCloud locations
        let path = url.path
        if path.contains("/Library/Mobile Documents/") ||
           path.contains("/iCloud Drive/") ||
           path.contains("~Library/CloudStorage/") ||
           path.contains("/CloudStorage/") {
            debugLog("isUbiquitousItem: path indicates cloud storage: \(url.lastPathComponent)")
            return true
        }
        
        // Then check via resource values
        do {
            let resourceValues = try url.resourceValues(forKeys: [.isUbiquitousItemKey])
            let isUbiquitous = resourceValues.isUbiquitousItem ?? false
            debugLog("isUbiquitousItem check for \(url.lastPathComponent): \(isUbiquitous)")
            return isUbiquitous
        } catch {
            debugLog("isUbiquitousItem error: \(error)")
            // If we can't determine, assume it might be cloud to be safe
            return false
        }
    }
    
    /// Check if a ubiquitous item is fully downloaded (without triggering a download)
    /// Returns true if the file is downloaded and can be read safely
    private func isCloudItemDownloaded(_ url: URL) -> Bool {
        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .ubiquitousItemDownloadingStatusKey,
                .isUbiquitousItemKey
            ])
            
            // Not a cloud item - treat as downloaded
            guard resourceValues.isUbiquitousItem == true else {
                return true
            }
            
            // Check download status
            if let status = resourceValues.ubiquitousItemDownloadingStatus {
                let isDownloaded = status == .current || status == .downloaded
                debugLog("Cloud item \(url.lastPathComponent) download status: \(status.rawValue), isDownloaded: \(isDownloaded)")
                return isDownloaded
            }
            
            // Can't determine status - assume not downloaded to be safe
            return false
        } catch {
            debugLog("isCloudItemDownloaded error: \(error)")
            return false
        }
    }
    
    /// Get the size of a file/folder using resource values (doesn't trigger cloud download)
    /// For folders, returns the total allocated size if available
    /// Returns nil if size cannot be determined without triggering download
    private func getFileSizeWithoutDownload(_ url: URL) -> Int64? {
        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .fileSizeKey,
                .totalFileAllocatedSizeKey,
                .isDirectoryKey
            ])
            
            if resourceValues.isDirectory == true {
                // For directories, we need to enumerate - but only if fully downloaded
                // Return nil to indicate we should treat as reference
                return nil
            }
            
            // For files, use fileSize
            if let size = resourceValues.fileSize {
                return Int64(size)
            }
            
            return nil
        } catch {
            return nil
        }
    }
    
    /// Save a cloud file item - copies to storage if downloaded and under size limit,
    /// otherwise saves as a reference
    @MainActor
    private func saveCloudFileItem(url: URL, sourceApp: String?, itemId: UUID) {
        let filename = url.lastPathComponent
        let isDir = isDirectory(url)
        
        // Check if the cloud item is downloaded
        let isDownloaded = isCloudItemDownloaded(url)
        debugLog("SaveCloudFile: \(filename) - isDownloaded: \(isDownloaded)")
        
        // If downloaded, try to copy to storage like a regular file
        if isDownloaded && !isDir {
            // Get size without triggering download
            if let fileSize = getFileSizeWithoutDownload(url),
               fileSize <= preferencesService.maxItemSizeBytes {
                // File is downloaded and under size limit - copy to storage
                debugLog("SaveCloudFile: Copying downloaded file to storage")
                do {
                    let data = try Data(contentsOf: url)
                    let contentType = getContentType(for: url)
                    
                    // Check for existing file with same data (already stored properly)
                    if let existingItem = try findExistingFileByData(data: data, contentType: contentType) {
                        try storageService.moveItemToTop(existingItem, withFilename: filename)
                        return
                    }
                    
                    // Check for existing reference to same path - if found, delete it
                    // so we can replace it with a proper stored copy
                    if let existingRef = try findExistingFileReference(path: url.path) {
                        debugLog("SaveCloudFile: Found existing reference, replacing with stored copy")
                        try storageService.deleteClipboardItem(existingRef)
                    }
                    
                    let mediaPath = try storageService.saveMedia(data: data, type: contentType, itemId: itemId, originalFilename: filename)
                    
                    // Generate thumbnail for images/videos
                    var thumbnailPath: String?
                    if contentType == .image {
                        if let thumbnail = thumbnailService.generateImageThumbnail(from: data, maxSize: 64) {
                            thumbnailPath = try storageService.saveThumbnail(data: thumbnail, itemId: itemId)
                        }
                    } else if contentType == .video {
                        let previewSize = CGFloat(preferencesService.previewSize)
                        if let previewImage = thumbnailService.generateVideoPreviewImage(from: mediaPath, maxSize: previewSize),
                           let pngData = previewImage.pngData() {
                            thumbnailPath = try storageService.saveThumbnail(data: pngData, itemId: itemId)
                        }
                    }
                    
                    let item = ClipboardItem(
                        id: itemId,
                        contentType: contentType,
                        textContent: filename,
                        mediaPath: mediaPath,
                        thumbnailPath: thumbnailPath,
                        sourceApp: sourceApp
                    )
                    
                    try storageService.saveClipboardItem(item)
                    debugLog("SaveCloudFile: Copied to storage successfully")
                    return
                } catch {
                    debugLog("SaveCloudFile: Failed to copy to storage: \(error), falling back to reference")
                    // Fall through to save as reference
                }
            }
        }
        
        // Save as reference (not downloaded, too large, is a folder, or copy failed)
        debugLog("SaveCloudFile: Saving as reference: \(filename)")
        
        let contentType = getContentType(for: url)
        
        do {
            // Check for existing reference to same path (move to top if found)
            if let existingItem = try findExistingFileReference(path: url.path) {
                try storageService.moveItemToTop(existingItem)
                return
            }
            
            // Only create bookmark if file is downloaded - bookmarkData() can trigger downloads
            // for cloud files that aren't locally available
            let bookmark: Data?
            if isDownloaded {
                bookmark = bookmarkService.createBookmark(for: url)
            } else {
                debugLog("SaveCloudFile: Skipping bookmark creation for undownloaded cloud file")
                bookmark = nil
            }
            
            let item = ClipboardItem(
                id: itemId,
                contentType: contentType,
                textContent: filename,
                mediaPath: url.path,  // Store original cloud path as reference
                sourceApp: sourceApp,
                bookmarkData: bookmark
            )
            
            try storageService.saveClipboardItem(item)
            debugLog("SaveCloudFile: Saved as reference")
        } catch {
            print("Failed to save cloud file reference: \(error)")
        }
    }
    
    /// Get the content type for a URL based on its extension
    private func getContentType(for url: URL) -> ContentType {
        if isDirectory(url) {
            return .file
        } else if isVideoFile(url) {
            return .video
        } else if isImageFile(url) {
            return .image
        } else {
            return .file
        }
    }
    
    /// Find an existing file item that matches the given data and content type
    private func findExistingFileByData(data: Data, contentType: ContentType) throws -> ClipboardItem? {
        let items = try storageService.fetchClipboardItems(limit: 100)
        let newDataHash = data.hashValue
        
        for item in items where item.contentType == contentType {
            if let path = item.mediaPath,
               let existingData = FileManager.default.contents(atPath: path),
               existingData.hashValue == newDataHash,
               existingData == data {
                return item
            }
        }
        return nil
    }
    
    @MainActor
    private func saveTextItem(text: String, sourceApp: String?) async {
        do {
            // Check for existing item with same content and move to top
            if try storageService.moveExistingItemToTop(textContent: text, mediaPath: nil, contentType: .text) {
                return
            }

            let item = ClipboardItem(
                contentType: .text,
                textContent: text,
                sourceApp: sourceApp
            )

            try storageService.saveClipboardItem(item)
        } catch {
            print("Failed to save text item: \(error)")
        }
    }

    @MainActor
    private func saveRichTextItem(data: Data, sourceApp: String?) async {
        // Extract plain text for display
        let plainText: String?
        if let attributedString = NSAttributedString(rtf: data, documentAttributes: nil) {
            plainText = attributedString.string
        } else {
            plainText = nil
        }

        do {
            // Check for existing item with same content and move to top
            if let text = plainText, try storageService.moveExistingItemToTop(textContent: text, mediaPath: nil, contentType: .richText) {
                return
            }

            let item = ClipboardItem(
                contentType: .richText,
                textContent: plainText,
                richTextData: data,
                sourceApp: sourceApp
            )

            try storageService.saveClipboardItem(item)
        } catch {
            print("Failed to save rich text item: \(error)")
        }
    }

    // MARK: - Image Items (copy to storage)
    
    @MainActor
    private func saveImageItem(url: URL, sourceApp: String?) async {
        // Check if this is a ubiquitous (cloud-synced) item - handle async to avoid blocking
        if isUbiquitousItem(url) {
            debugLog("SaveImage: File is ubiquitous, handling async")
            saveCloudFileItem(url: url, sourceApp: sourceApp, itemId: UUID())
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let filename = url.lastPathComponent
            
            // Skip if item exceeds max size
            if Int64(data.count) > preferencesService.maxItemSizeBytes {
                return
            }
            
            // Check for existing image with same data
            if let existingItem = try findExistingImageItem(matchingData: data) {
                try storageService.moveItemToTop(existingItem, withFilename: filename)
                return
            }

            let itemId = UUID()

            // Copy the image to storage (preserving original filename)
            let mediaPath = try storageService.saveMedia(data: data, type: .image, itemId: itemId, originalFilename: filename)

            // Generate thumbnail
            var thumbnailPath: String?
            if let thumbnail = thumbnailService.generateImageThumbnail(from: data, maxSize: 64) {
                thumbnailPath = try storageService.saveThumbnail(data: thumbnail, itemId: itemId)
            }

            let item = ClipboardItem(
                id: itemId,
                contentType: .image,
                textContent: filename,
                mediaPath: mediaPath,
                thumbnailPath: thumbnailPath,
                sourceApp: sourceApp
            )

            try storageService.saveClipboardItem(item)
        } catch {
            // Failed to read - save as file reference
            debugLog("SaveImage: Failed to read, saving as reference")
            saveCloudFileItem(url: url, sourceApp: sourceApp, itemId: UUID())
        }
    }
    
    @MainActor
    private func savePastedImageData(data: Data, sourceApp: String?) async {
        // Skip if item exceeds max size
        if Int64(data.count) > preferencesService.maxItemSizeBytes {
            return
        }
        
        do {
            // Check for existing image with same data
            if let existingItem = try findExistingImageItem(matchingData: data) {
                try storageService.moveItemToTop(existingItem)
                return
            }

            let itemId = UUID()

            // Save the image data
            let mediaPath = try storageService.saveMedia(data: data, type: .image, itemId: itemId)

            // Generate thumbnail
            var thumbnailPath: String?
            if let thumbnail = thumbnailService.generateImageThumbnail(from: data, maxSize: 64) {
                thumbnailPath = try storageService.saveThumbnail(data: thumbnail, itemId: itemId)
            }

            let item = ClipboardItem(
                id: itemId,
                contentType: .image,
                textContent: nil,
                mediaPath: mediaPath,
                thumbnailPath: thumbnailPath,
                sourceApp: sourceApp
            )

            try storageService.saveClipboardItem(item)
        } catch {
            print("Failed to save pasted image: \(error)")
        }
    }

    /// Find an existing image item that matches the given data
    private func findExistingImageItem(matchingData data: Data) throws -> ClipboardItem? {
        let items = try storageService.fetchClipboardItems(limit: 100)
        let newDataHash = data.hashValue
        
        for item in items where item.contentType == .image {
            if let path = item.mediaPath,
               let existingData = FileManager.default.contents(atPath: path),
               existingData.hashValue == newDataHash,
               existingData == data {
                return item
            }
        }
        return nil
    }
    
    // MARK: - Video Items (copy to storage)
    
    @MainActor
    private func saveVideoItem(url: URL, sourceApp: String?) async {
        // Check if this is a ubiquitous (cloud-synced) item - handle async to avoid blocking
        if isUbiquitousItem(url) {
            debugLog("SaveVideo: File is ubiquitous, handling async")
            saveCloudFileItem(url: url, sourceApp: sourceApp, itemId: UUID())
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let filename = url.lastPathComponent
            
            // Skip if item exceeds max size
            if Int64(data.count) > preferencesService.maxItemSizeBytes {
                return
            }
            
            // Check for existing video with same data
            if let existingItem = try findExistingVideoItem(matchingData: data) {
                try storageService.moveItemToTop(existingItem, withFilename: filename)
                return
            }

            let itemId = UUID()

            // Copy video file to storage (preserving original filename)
            let mediaPath = try storageService.saveMedia(data: data, type: .video, itemId: itemId, originalFilename: filename)

            // Generate preview screenshot at 20% through the video (size based on preferences)
            var thumbnailPath: String?
            let previewSize = CGFloat(preferencesService.previewSize)
            if let previewImage = thumbnailService.generateVideoPreviewImage(from: url.path, maxSize: previewSize),
               let pngData = previewImage.pngData() {
                thumbnailPath = try storageService.saveThumbnail(data: pngData, itemId: itemId)
            }

            let item = ClipboardItem(
                id: itemId,
                contentType: .video,
                textContent: filename,
                mediaPath: mediaPath,
                thumbnailPath: thumbnailPath,
                sourceApp: sourceApp
            )

            try storageService.saveClipboardItem(item)
        } catch {
            // Failed to read - save as file reference
            debugLog("SaveVideo: Failed to read, saving as reference")
            saveCloudFileItem(url: url, sourceApp: sourceApp, itemId: UUID())
        }
    }

    /// Find an existing video item that matches the given data
    private func findExistingVideoItem(matchingData data: Data) throws -> ClipboardItem? {
        let items = try storageService.fetchClipboardItems(limit: 100)
        let newDataHash = data.hashValue
        
        for item in items where item.contentType == .video {
            if let path = item.mediaPath,
               let existingData = FileManager.default.contents(atPath: path),
               existingData.hashValue == newDataHash,
               existingData == data {
                return item
            }
        }
        return nil
    }
    
    // MARK: - File Items (copy to storage or store reference)
    
    /// Calculate the total size of a file or folder (recursively for folders)
    private func calculateSize(of url: URL) -> Int64 {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return 0
        }
        
        if isDirectory.boolValue {
            // Folder - recursively sum all file sizes
            var total: Int64 = 0
            if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) {
                for case let fileURL as URL in enumerator {
                    if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                       resourceValues.isDirectory == false,
                       let fileSize = resourceValues.fileSize {
                        total += Int64(fileSize)
                    }
                }
            }
            return total
        } else {
            // Regular file
            if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int64 {
                return size
            }
            return 0
        }
    }
    
    /// Check if a URL points to a directory (without triggering cloud downloads)
    private func isDirectory(_ url: URL) -> Bool {
        // Use resource values to avoid triggering cloud downloads
        do {
            let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
            return resourceValues.isDirectory == true
        } catch {
            // Fallback: use path heuristics to avoid triggering downloads
            // Folders typically don't have extensions
            return url.pathExtension.isEmpty
        }
    }
    
    @MainActor
    private func saveFileItem(url: URL, sourceApp: String?) async {
        let filename = url.lastPathComponent
        let itemId = UUID()
        
        debugLog("SaveFile: Processing: \(url.path)")
        
        // Check if this is ANY kind of ubiquitous (cloud-synced) item
        // This includes iCloud Drive, iCloud Desktop & Documents, Dropbox, etc.
        // We must handle these async because reading them may trigger a download
        if isUbiquitousItem(url) {
            debugLog("SaveFile: File is ubiquitous (cloud-synced) - handling async to avoid blocking")
            saveCloudFileItem(url: url, sourceApp: sourceApp, itemId: itemId)
            debugLog("SaveFile: saveCloudFileItem returned immediately")
            return
        }
        
        debugLog("SaveFile: Regular local file, proceeding with normal save")
        
        // Check if this is a directory (folder)
        if isDirectory(url) {
            // Calculate folder size
            let folderSize = calculateSize(of: url)
            
            // If folder is under size limit, copy it to storage
            if folderSize <= preferencesService.maxItemSizeBytes {
                do {
                    // Check for existing reference to same path (move to top if found)
                    if let existingItem = try findExistingFileReference(path: url.path) {
                        try storageService.moveItemToTop(existingItem)
                        return
                    }
                    
                    // Copy folder to storage
                    let mediaPath = try storageService.saveFolder(sourceURL: url, itemId: itemId, originalFolderName: filename)
                    
                    let item = ClipboardItem(
                        id: itemId,
                        contentType: .file,
                        textContent: filename,
                        mediaPath: mediaPath,
                        sourceApp: sourceApp
                    )
                    
                    try storageService.saveClipboardItem(item)
                    return
                } catch {
                    print("Failed to copy folder to storage: \(error)")
                    // Fall through to store as reference
                }
            }
            
            // Folder is too large or copy failed - store as reference with security-scoped bookmark
            do {
                if let existingItem = try findExistingFileReference(path: url.path) {
                    try storageService.moveItemToTop(existingItem)
                    return
                }
                
                // Create security-scoped bookmark for persistent access
                let bookmark = bookmarkService.createBookmark(for: url)
                
                let item = ClipboardItem(
                    id: itemId,
                    contentType: .file,
                    textContent: filename,
                    mediaPath: url.path,  // Store original path as reference
                    sourceApp: sourceApp,
                    bookmarkData: bookmark
                )
                
                try storageService.saveClipboardItem(item)
            } catch {
                print("Failed to save folder reference: \(error)")
            }
            return
        }
        
        // Regular file - try to read file data (may fail for sandboxed/protected files or cloud files)
        print("[SaveFile] Attempting to read file data...")
        do {
            let data = try Data(contentsOf: url)
            print("[SaveFile] Successfully read \(data.count) bytes")
            
            // Skip if item exceeds max size
            if Int64(data.count) > preferencesService.maxItemSizeBytes {
                return
            }
            
            // Check for existing file with same data
            if let existingItem = try findExistingFileItem(matchingData: data) {
                try storageService.moveItemToTop(existingItem, withFilename: filename)
                return
            }

            // Copy file to storage
            let mediaPath = try storageService.saveMedia(data: data, type: .file, itemId: itemId, originalFilename: filename)

            let item = ClipboardItem(
                id: itemId,
                contentType: .file,
                textContent: filename,
                mediaPath: mediaPath,
                sourceApp: sourceApp
            )

            try storageService.saveClipboardItem(item)
        } catch {
            debugLog("SaveFile: Failed to read, saving as reference")
            
            // Can't read file - store as reference with security-scoped bookmark
            do {
                // Check for existing reference to same path
                if let existingItem = try findExistingFileReference(path: url.path) {
                    try storageService.moveItemToTop(existingItem)
                    return
                }
                
                // Create security-scoped bookmark for persistent access
                let bookmark = bookmarkService.createBookmark(for: url)
                
                let item = ClipboardItem(
                    id: itemId,
                    contentType: .file,
                    textContent: filename,
                    mediaPath: url.path,  // Store original path as reference
                    sourceApp: sourceApp,
                    bookmarkData: bookmark
                )
                
                try storageService.saveClipboardItem(item)
            } catch {
                print("Failed to save file reference: \(error)")
            }
        }
    }

    /// Find an existing file item that matches the given data
    private func findExistingFileItem(matchingData data: Data) throws -> ClipboardItem? {
        let items = try storageService.fetchClipboardItems(limit: 100)
        let newDataHash = data.hashValue
        
        for item in items where item.contentType == .file {
            if let path = item.mediaPath,
               let existingData = FileManager.default.contents(atPath: path),
               existingData.hashValue == newDataHash,
               existingData == data {
                return item
            }
        }
        return nil
    }
    
    /// Find an existing file reference that matches the given path
    /// Checks all file-based content types (file, image, video)
    private func findExistingFileReference(path: String) throws -> ClipboardItem? {
        let items = try storageService.fetchClipboardItems(limit: 100)
        let fileTypes: [ContentType] = [.file, .image, .video]
        
        for item in items where fileTypes.contains(item.contentType) {
            if item.mediaPath == path {
                return item
            }
        }
        return nil
    }
    
    // MARK: - File Stack Support (copy all files/folders to storage or store references)
    
    /// Information about a file or folder in a stack
    private enum StackItemInfo {
        case file(url: URL, data: Data)
        case folder(url: URL)
        case unreadable(url: URL)
        case cloudFile(url: URL)  // Cloud file that needs downloading
    }
    
    @MainActor
    private func saveFileStackItem(urls: [URL], sourceApp: String?) async {
        // Check cloud status for all files in one pass to minimize blocking
        // For any cloud item that's a folder or not downloaded, store entire stack as references
        var hasCloudFolderOrUndownloaded = false
        
        for url in urls {
            // Quick check using resource values (doesn't trigger downloads)
            do {
                let resourceValues = try url.resourceValues(forKeys: [
                    .isUbiquitousItemKey,
                    .isDirectoryKey,
                    .ubiquitousItemDownloadingStatusKey
                ])
                
                let isCloud = resourceValues.isUbiquitousItem == true
                if isCloud {
                    let isDir = resourceValues.isDirectory == true
                    let isDownloaded: Bool
                    if let status = resourceValues.ubiquitousItemDownloadingStatus {
                        isDownloaded = status == .current || status == .downloaded
                    } else {
                        isDownloaded = false
                    }
                    
                    if isDir || !isDownloaded {
                        hasCloudFolderOrUndownloaded = true
                        break
                    }
                }
            } catch {
                // If we can't check, treat as potentially problematic
                hasCloudFolderOrUndownloaded = true
                break
            }
        }
        
        if hasCloudFolderOrUndownloaded {
            // Has cloud folders or undownloaded files - store as references immediately
            debugLog("SaveFileStack: Stack contains cloud folders or undownloaded files, storing as references")
            await saveFileStackAsReferences(urls: urls, sourceApp: sourceApp)
            return
        }
        
        // All files are local or downloaded cloud files (no folders from cloud) - analyze normally
        var totalSize: Int64 = 0
        var stackItems: [StackItemInfo] = []
        var allAccessible = true
        
        for url in urls {
            if isDirectory(url) {
                // It's a folder - calculate its size (only local folders reach here)
                let folderSize = calculateSize(of: url)
                totalSize += folderSize
                stackItems.append(.folder(url: url))
            } else if let data = try? Data(contentsOf: url) {
                // It's a readable file
                totalSize += Int64(data.count)
                stackItems.append(.file(url: url, data: data))
            } else {
                // Can't read the file (sandboxed or inaccessible)
                allAccessible = false
                stackItems.append(.unreadable(url: url))
            }
        }
        
        if allAccessible && totalSize <= preferencesService.maxItemSizeBytes {
            // All items accessible and under size limit - copy to storage
            do {
                // Check for existing file stack with same paths
                let paths = urls.map { $0.path }
                if let existingItem = try findExistingFileStackReference(paths: paths) {
                    // If existing item is a reference (not stored), delete it so we can replace with stored copy
                    if existingItem.isFileReference {
                        debugLog("SaveFileStack: Found existing reference, replacing with stored copy")
                        try storageService.deleteClipboardItem(existingItem)
                    } else {
                        // Already stored properly, just move to top
                        try storageService.moveItemToTop(existingItem)
                        return
                    }
                }
                
                let itemId = UUID()
                
                // Copy all files and folders to storage
                var storedPaths: [String] = []
                for (index, stackItem) in stackItems.enumerated() {
                    switch stackItem {
                    case .file(let url, let data):
                        let filename = url.lastPathComponent
                        let storedPath = try storageService.saveMediaForStack(
                            data: data,
                            itemId: itemId,
                            index: index,
                            originalFilename: filename
                        )
                        storedPaths.append(storedPath)
                        
                    case .folder(let url):
                        let folderName = url.lastPathComponent
                        let storedPath = try storageService.saveFolderForStack(
                            sourceURL: url,
                            itemId: itemId,
                            index: index,
                            originalFolderName: folderName
                        )
                        storedPaths.append(storedPath)
                        
                    case .unreadable:
                        // This shouldn't happen if allAccessible is true
                        break
                    case .cloudFile:
                        // This shouldn't happen - cloud files are handled separately
                        break
                    }
                }
                
                // Create display text showing count
                let displayText = "\(urls.count) items"
                
                let item = ClipboardItem(
                    id: itemId,
                    contentType: .fileStack,
                    textContent: displayText,
                    mediaPaths: storedPaths,
                    sourceApp: sourceApp
                )
                
                try storageService.saveClipboardItem(item)
            } catch {
                print("Failed to save file stack item: \(error)")
                // Fall through to store as references
                await saveFileStackAsReferences(urls: urls, sourceApp: sourceApp)
            }
        } else {
            // Some items unreadable or total size too large - store references
            await saveFileStackAsReferences(urls: urls, sourceApp: sourceApp)
        }
    }
    
    /// Save a file stack as references (original paths) with security-scoped bookmarks
    @MainActor
    private func saveFileStackAsReferences(urls: [URL], sourceApp: String?) async {
        let paths = urls.map { $0.path }
        
        do {
            // Check for existing reference to same paths
            if let existingItem = try findExistingFileStackReference(paths: paths) {
                try storageService.moveItemToTop(existingItem)
                return
            }
        } catch {
            print("Failed to check existing file stack: \(error)")
        }
        
        let itemId = UUID()
        let displayText = "\(urls.count) items"
        
        // Only create bookmarks for downloaded files - bookmarkData() can trigger downloads
        // for cloud files that aren't locally available
        var bookmarks: [Data?] = []
        var allBookmarksCreated = true
        for url in urls {
            if isCloudItemDownloaded(url) {
                if let bookmark = bookmarkService.createBookmark(for: url) {
                    bookmarks.append(bookmark)
                } else {
                    allBookmarksCreated = false
                    bookmarks.append(nil)
                }
            } else {
                debugLog("SaveFileStackAsReferences: Skipping bookmark for undownloaded cloud file: \(url.lastPathComponent)")
                allBookmarksCreated = false
                bookmarks.append(nil)
            }
        }
        
        // Only store bookmark data if all bookmarks were successfully created
        let bookmarkDatas: [Data]? = allBookmarksCreated ? bookmarks.compactMap { $0 } : nil
        
        let item = ClipboardItem(
            id: itemId,
            contentType: .fileStack,
            textContent: displayText,
            mediaPaths: paths,  // Store original paths as references
            sourceApp: sourceApp,
            bookmarkDatas: bookmarkDatas
        )
        
        do {
            try storageService.saveClipboardItem(item)
        } catch {
            print("Failed to save file stack reference: \(error)")
        }
    }
    
    /// Find an existing file stack reference that matches the given paths
    private func findExistingFileStackReference(paths: [String]) throws -> ClipboardItem? {
        let items = try storageService.fetchClipboardItems(limit: 100)
        
        for item in items where item.contentType == .fileStack {
            if let existingPaths = item.mediaPaths, existingPaths == paths {
                return item
            }
        }
        return nil
    }
}

// MARK: - NSImage Extension
extension NSImage {
    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
