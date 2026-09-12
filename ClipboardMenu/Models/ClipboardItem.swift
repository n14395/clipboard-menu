import Foundation
import GRDB

struct ClipboardItem: Identifiable, Codable, Equatable {
    var id: UUID
    var contentType: ContentType
    var textContent: String?
    var richTextData: Data?
    var mediaPath: String?
    var mediaPaths: [String]?  // For file stacks
    var thumbnailPath: String?
    var sourceApp: String?
    var createdAt: Date
    var isFavorite: Bool
    var sortOrder: Int
    var bookmarkData: Data?  // Security-scoped bookmark for file references
    var bookmarkDatas: [Data]?  // Security-scoped bookmarks for file stack references

    init(
        id: UUID = UUID(),
        contentType: ContentType,
        textContent: String? = nil,
        richTextData: Data? = nil,
        mediaPath: String? = nil,
        mediaPaths: [String]? = nil,
        thumbnailPath: String? = nil,
        sourceApp: String? = nil,
        createdAt: Date = Date(),
        isFavorite: Bool = false,
        sortOrder: Int = 0,
        bookmarkData: Data? = nil,
        bookmarkDatas: [Data]? = nil
    ) {
        self.id = id
        self.contentType = contentType
        self.textContent = textContent
        self.richTextData = richTextData
        self.mediaPath = mediaPath
        self.mediaPaths = mediaPaths
        self.thumbnailPath = thumbnailPath
        self.sourceApp = sourceApp
        self.createdAt = createdAt
        self.isFavorite = isFavorite
        self.sortOrder = sortOrder
        self.bookmarkData = bookmarkData
        self.bookmarkDatas = bookmarkDatas
    }
    
    /// Returns the number of files in a file stack, or 1 for single file items
    var fileCount: Int {
        if contentType == .fileStack, let paths = mediaPaths {
            return paths.count
        }
        return mediaPath != nil ? 1 : 0
    }
    
    /// Returns filenames for file stack items
    /// Extracts original filenames from internal storage paths (format: {UUID}_{index}_{originalFilename})
    var fileNames: [String] {
        if contentType == .fileStack, let paths = mediaPaths {
            return paths.map { Self.extractOriginalFilename(from: $0) }
        }
        if let path = mediaPath {
            return [Self.extractOriginalFilename(from: path)]
        }
        return []
    }
    
    // MARK: - Cached Regex Patterns
    
    /// Cached regex for extracting filename from UUID_index_filename format
    private static let uuidIndexFilenameRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: "^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}_\\d+_",
            options: []
        )
    }()
    
    /// Extract original filename from a storage path
    /// Storage format: {UUID}_{index}_{originalFilename}
    /// External format: regular path (returned as-is)
    private static func extractOriginalFilename(from path: String) -> String {
        let lastComponent = URL(fileURLWithPath: path).lastPathComponent
        
        // Check if this is an internal storage path with UUID prefix
        // Pattern: 8-4-4-4-12 hex chars followed by underscore, digit(s), underscore
        // Example: A19D867C-B777-4550-8209-02DF77F01D6C_0_filename.txt
        if let regex = uuidIndexFilenameRegex {
            let range = NSRange(lastComponent.startIndex..., in: lastComponent)
            if let match = regex.firstMatch(in: lastComponent, range: range) {
                // Found UUID prefix, extract the original filename after it
                if let matchRange = Range(match.range, in: lastComponent) {
                    return String(lastComponent[matchRange.upperBound...])
                }
            }
        }
        
        // Not an internal storage path, return as-is
        return lastComponent
    }

    var displayText: String {
        // For file stacks, show count
        if contentType == .fileStack, let paths = mediaPaths {
            return "\(paths.count) items"
        }
        if let text = textContent {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 50 {
                return String(trimmed.prefix(50)) + "..."
            }
            return trimmed
        }
        return contentType.displayName
    }

    var fullText: String {
        textContent ?? ""
    }

    /// Returns true if the text content is long enough to warrant a preview popup
    var needsTextPreview: Bool {
        guard let text = textContent else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 50 || trimmed.contains("\n")
    }
    
    /// Returns true if this is a file that can be previewed as text
    var isTextFile: Bool {
        guard contentType == .file, let path = mediaPath else { return false }
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        let textExtensions: Set<String> = [
            "txt", "md", "markdown", "json", "xml", "html", "htm", "css", "js", "ts",
            "swift", "py", "rb", "java", "c", "cpp", "h", "hpp", "m", "mm",
            "sh", "bash", "zsh", "fish", "yaml", "yml", "toml", "ini", "cfg", "conf",
            "log", "csv", "tsv", "sql", "rs", "go", "php", "pl", "r", "lua",
            "vim", "gitignore", "dockerfile", "makefile", "cmake", "gradle"
        ]
        // Also check files without extension but common names
        let textFilenames: Set<String> = [
            "readme", "license", "changelog", "authors", "contributors",
            "makefile", "dockerfile", "gemfile", "podfile", "cartfile"
        ]
        let filename = url.lastPathComponent.lowercased()
        return textExtensions.contains(ext) || textFilenames.contains(filename)
    }
    
    /// Returns the text content for preview - file contents for text files, otherwise textContent
    var previewText: String? {
        // For text files, load the file contents
        if isTextFile, let path = mediaPath {
            // Limit file size to prevent loading huge files
            let url = URL(fileURLWithPath: path)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  let fileSize = attributes[.size] as? Int64,
                  fileSize < 1_000_000 else { // 1MB limit
                return nil
            }
            return try? String(contentsOf: url, encoding: .utf8)
        }
        // For regular text items, return textContent
        if let text = textContent {
            return text
        }
        return nil
    }
    
    /// Returns true if this item needs a preview popup
    var needsPreview: Bool {
        // All items with content get a preview
        if contentType == .image || contentType == .video {
            return true
        }
        if contentType == .fileStack {
            return true
        }
        if contentType == .file {
            return true
        }
        // Text and rich text always get preview
        if contentType == .text || contentType == .richText {
            return textContent != nil
        }
        return false
    }

    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
    
    /// Returns true if this item contains file references (not copied to app storage)
    /// This happens when files are too large or couldn't be read
    var isFileReference: Bool {
        // Check for file stacks with external paths (not in app support)
        if contentType == .fileStack, let paths = mediaPaths {
            // If any path doesn't contain our app's identifier, it's a reference
            return paths.contains { !$0.contains("ClipboardMenu") }
        }
        // Check for single files with external paths
        if (contentType == .file || contentType == .image || contentType == .video),
           let path = mediaPath {
            return !path.contains("ClipboardMenu")
        }
        return false
    }
    
    /// Returns true if this item's file references are valid (files still exist)
    /// For non-file-references, always returns true
    /// For file stacks, returns false if ANY referenced file is missing
    /// Note: For cloud files, this checks metadata without triggering downloads
    var hasValidFileReference: Bool {
        // Only validate file references (external paths)
        guard isFileReference else { return true }
        
        // Check file stacks - all paths must exist
        if contentType == .fileStack, let paths = mediaPaths {
            return paths.allSatisfy { Self.pathExistsWithoutTriggeringDownload($0) }
        }
        
        // Check single files
        if let path = mediaPath {
            return Self.pathExistsWithoutTriggeringDownload(path)
        }
        
        return true
    }
    
    /// Check if a path exists without triggering iCloud downloads
    /// For cloud files, checks if the file is known to iCloud (even if not downloaded)
    /// For local files, uses standard file existence check
    private static func pathExistsWithoutTriggeringDownload(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        
        // First, check if this is an iCloud file using resource values (doesn't trigger download)
        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey
            ])
            
            // If it's a cloud item, it exists in iCloud (even if not downloaded locally)
            if resourceValues.isUbiquitousItem == true {
                return true
            }
        } catch {
            // If we can't read resource values, fall through to regular check
        }
        
        // For non-cloud files, use standard existence check
        return FileManager.default.fileExists(atPath: path)
    }
    
    /// Returns true if this item represents a folder (directory)
    /// Note: Uses path heuristics to avoid file system I/O during view rendering
    var isFolder: Bool {
        guard contentType == .file, let path = mediaPath else {
            return false
        }
        // Heuristic: folders typically don't have extensions
        // This avoids FileManager calls during view rendering
        let url = URL(fileURLWithPath: path)
        return url.pathExtension.isEmpty
    }
    
    /// Returns the appropriate system image name for this item's file type
    /// Note: Uses path heuristics to avoid file system I/O during view rendering
    var fileSystemImageName: String {
        guard contentType == .file, let path = mediaPath else {
            return "doc"
        }
        let url = URL(fileURLWithPath: path)
        // Heuristic: folders typically don't have extensions
        if url.pathExtension.isEmpty {
            return "folder.fill"
        }
        return "doc"
    }
    
    /// Returns true if this is a cloud file reference (file stored in iCloud)
    /// Used to show cloud icon indicator in the UI
    var isCloudFile: Bool {
        // Only check file references (not items stored in app storage)
        guard isFileReference else { return false }
        
        // Check all paths for file stacks
        if contentType == .fileStack, let paths = mediaPaths {
            return paths.contains { Self.isPathCloudFile($0) }
        }
        
        // Check the primary path
        if let path = mediaPath {
            return Self.isPathCloudFile(path)
        }
        
        return false
    }
    
    /// Returns true if this is a cloud file reference that isn't downloaded locally
    /// These items cannot be pasted until the cloud files are downloaded
    /// For folders, checks if any contents are not downloaded (without triggering download)
    var isCloudFileNotDownloaded: Bool {
        // Only check file references (not items stored in app storage)
        guard isFileReference else { return false }
        
        // Check all paths for file stacks
        if contentType == .fileStack, let paths = mediaPaths {
            return paths.contains { Self.isPathCloudFileNotDownloaded($0) }
        }
        
        // Check the primary path
        if let path = mediaPath {
            return Self.isPathCloudFileNotDownloaded(path)
        }
        
        return false
    }
    
    /// Check if a single path is a cloud file (ubiquitous item)
    /// Does NOT trigger downloads - only reads resource values
    /// Uses both path-based detection and resource values for comprehensive detection
    private static func isPathCloudFile(_ path: String) -> Bool {
        // Check by path - common iCloud/cloud storage locations
        if path.contains("/Library/Mobile Documents/") ||
           path.contains("/iCloud Drive/") ||
           path.contains("~Library/CloudStorage/") ||
           path.contains("/CloudStorage/") {
            return true
        }
        
        let url = URL(fileURLWithPath: path)
        
        do {
            let resourceValues = try url.resourceValues(forKeys: [.isUbiquitousItemKey])
            return resourceValues.isUbiquitousItem == true
        } catch {
            return false
        }
    }
    
    /// Check if a single path (file or folder) has undownloaded cloud content
    /// Does NOT trigger downloads - only reads resource values
    /// For folders, checks contents to see if any files inside are not downloaded
    private static func isPathCloudFileNotDownloaded(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        
        // First check by path - common iCloud/cloud storage locations
        let isCloudPath = path.contains("/Library/Mobile Documents/") ||
                          path.contains("/iCloud Drive/") ||
                          path.contains("~Library/CloudStorage/") ||
                          path.contains("/CloudStorage/")
        
        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemIsDownloadingKey,
                .isDirectoryKey
            ])
            
            // Check if it's a cloud item (either by resource value or path)
            let isUbiquitous = resourceValues.isUbiquitousItem == true || isCloudPath
            
            // Not a cloud item - it's available locally
            guard isUbiquitous else {
                return false
            }
            
            // If actively downloading, show cloud icon
            if resourceValues.ubiquitousItemIsDownloading == true {
                return true
            }
            
            // Check download status - .current and .downloaded both mean fully available locally
            if let status = resourceValues.ubiquitousItemDownloadingStatus {
                if status == .current || status == .downloaded {
                    // File/folder itself is marked as downloaded
                    // But for folders, we need to check contents too
                    if resourceValues.isDirectory == true {
                        return isFolderContentsNotDownloaded(url)
                    }
                    return false  // Single file is downloaded
                }
                return true  // Not downloaded, show cloud icon
            }
            
            // Status is nil - for folders check contents, otherwise treat as not downloaded
            if resourceValues.isDirectory == true {
                return isFolderContentsNotDownloaded(url)
            }
            
            // For cloud paths with no status, assume not downloaded
            return isCloudPath
        } catch {
            // If we can't check but it's a cloud path, assume not downloaded
            return isCloudPath
        }
    }
    
    /// Check folder contents for undownloaded cloud files
    /// Scans up to 100 files for performance
    private static func isFolderContentsNotDownloaded(_ folderURL: URL) -> Bool {
        let fileManager = FileManager.default
        
        // Check if folder is in a cloud path
        let folderPath = folderURL.path
        let isCloudPath = folderPath.contains("/Library/Mobile Documents/") ||
                          folderPath.contains("/iCloud Drive/") ||
                          folderPath.contains("~Library/CloudStorage/") ||
                          folderPath.contains("/CloudStorage/")
        
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemIsDownloadingKey,
                .isDirectoryKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            // Can't enumerate - if cloud path, assume not downloaded
            return isCloudPath
        }
        
        var checkedCount = 0
        let maxCheck = 100  // Limit scan for performance
        
        for case let fileURL as URL in enumerator {
            checkedCount += 1
            if checkedCount > maxCheck { break }
            
            do {
                let values = try fileURL.resourceValues(forKeys: [
                    .isUbiquitousItemKey,
                    .ubiquitousItemDownloadingStatusKey,
                    .ubiquitousItemIsDownloadingKey,
                    .isDirectoryKey
                ])
                
                // Skip directories - we only care about actual file contents
                if values.isDirectory == true {
                    continue
                }
                
                // Check if this is a cloud file (by resource value or path)
                let isUbiquitous = values.isUbiquitousItem == true || isCloudPath
                
                if isUbiquitous {
                    let status = values.ubiquitousItemDownloadingStatus
                    let isDownloading = values.ubiquitousItemIsDownloading ?? false
                    
                    // If actively downloading, not complete
                    if isDownloading {
                        return true
                    }
                    
                    // If status is .current or .downloaded, it's available
                    if let status = status {
                        if status != .current && status != .downloaded {
                            return true  // Found an undownloaded file
                        }
                    } else {
                        // No status = not downloaded
                        return true
                    }
                }
            } catch {
                continue
            }
        }
        
        return false  // All checked files are downloaded
    }
    
    /// Returns the total size of this item on disk in bytes
    /// For folders, recursively calculates the size of all contents
    var sizeOnDisk: Int64 {
        var total: Int64 = 0
        
        // Single media file or folder
        if let mediaPath = mediaPath {
            total += Self.calculatePathSize(mediaPath)
        }
        
        // File stack (may include folders)
        if let paths = mediaPaths {
            for path in paths {
                total += Self.calculatePathSize(path)
            }
        }
        
        // Text/rich text data (in-memory size)
        if let text = textContent {
            total += Int64(text.utf8.count)
        }
        if let richData = richTextData {
            total += Int64(richData.count)
        }
        
        return total
    }
    
    /// Calculate the size of a file or folder (recursively for folders)
    private static func calculatePathSize(_ path: String) -> Int64 {
        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: path)
        
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return 0
        }
        
        if isDirectory.boolValue {
            // Folder - recursively sum all contents
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
            if let attrs = try? fileManager.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64 {
                return size
            }
            return 0
        }
    }
}

// MARK: - GRDB Support
extension ClipboardItem: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "clipboard_items" }

    enum Columns: String, ColumnExpression {
        case id, contentType, textContent, richTextData, mediaPath, mediaPaths
        case thumbnailPath, sourceApp, createdAt, isFavorite, sortOrder
        case bookmarkData, bookmarkDatas
    }
}
