// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import Foundation
import GRDB

struct Snippet: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var contentType: ContentType
    var textContent: String?
    var richTextData: Data?
    var mediaPath: String?
    var mediaPaths: [String]?  // For file stacks
    var thumbnailPath: String?
    var createdAt: Date
    var modifiedAt: Date
    var sortOrder: Int
    var bookmarkData: Data?  // Security-scoped bookmark for file references
    var bookmarkDatas: [Data]?  // Security-scoped bookmarks for file stack references
    
    // Cloud download state
    var isDownloading: Bool  // True while cloud files are being downloaded
    var downloadError: String?  // Error message if download failed, nil otherwise
    var downloadFileCount: Int  // Total number of files to download (for progress display)
    var currentDownloadIndex: Int  // Current file being downloaded (1-based, for progress display)
    
    // Original cloud file paths for retry (stored separately from mediaPath/mediaPaths
    // which will be updated to point to local copies after download completes)
    var cloudPath: String?  // Original cloud path for single files
    var cloudPaths: [String]?  // Original cloud paths for file stacks

    init(
        id: UUID = UUID(),
        name: String = "",
        contentType: ContentType,
        textContent: String? = nil,
        richTextData: Data? = nil,
        mediaPath: String? = nil,
        mediaPaths: [String]? = nil,
        thumbnailPath: String? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        sortOrder: Int = 0,
        bookmarkData: Data? = nil,
        bookmarkDatas: [Data]? = nil,
        isDownloading: Bool = false,
        downloadError: String? = nil,
        downloadFileCount: Int = 0,
        currentDownloadIndex: Int = 0,
        cloudPath: String? = nil,
        cloudPaths: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.contentType = contentType
        self.textContent = textContent
        self.richTextData = richTextData
        self.mediaPath = mediaPath
        self.mediaPaths = mediaPaths
        self.thumbnailPath = thumbnailPath
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.sortOrder = sortOrder
        self.bookmarkData = bookmarkData
        self.bookmarkDatas = bookmarkDatas
        self.isDownloading = isDownloading
        self.downloadError = downloadError
        self.downloadFileCount = downloadFileCount
        self.currentDownloadIndex = currentDownloadIndex
        self.cloudPath = cloudPath
        self.cloudPaths = cloudPaths
    }

    init(from clipboardItem: ClipboardItem, name: String = "") {
        self.id = UUID()
        self.name = name.isEmpty ? clipboardItem.displayText : name
        self.contentType = clipboardItem.contentType
        self.textContent = clipboardItem.textContent
        self.richTextData = clipboardItem.richTextData
        self.mediaPath = clipboardItem.mediaPath
        self.mediaPaths = clipboardItem.mediaPaths
        self.thumbnailPath = clipboardItem.thumbnailPath
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.sortOrder = 0
        self.bookmarkData = clipboardItem.bookmarkData
        self.bookmarkDatas = clipboardItem.bookmarkDatas
        self.isDownloading = false
        self.downloadError = nil
        self.downloadFileCount = 0
        self.currentDownloadIndex = 0
        self.cloudPath = nil
        self.cloudPaths = nil
    }

    var displayText: String {
        if !name.isEmpty {
            return name
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
        let textFilenames: Set<String> = [
            "readme", "license", "changelog", "authors", "contributors",
            "makefile", "dockerfile", "gemfile", "podfile", "cartfile"
        ]
        let filename = url.lastPathComponent.lowercased()
        return textExtensions.contains(ext) || textFilenames.contains(filename)
    }
    
    /// Returns the text content for preview - file contents for text files, otherwise textContent
    var previewText: String? {
        if isTextFile, let path = mediaPath {
            let url = URL(fileURLWithPath: path)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  let fileSize = attributes[.size] as? Int64,
                  fileSize < 1_000_000 else {
                return nil
            }
            return try? String(contentsOf: url, encoding: .utf8)
        }
        if let text = textContent {
            return text
        }
        return nil
    }
    
    /// Returns true if this snippet needs a preview popup
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
    
    /// Returns true if this snippet represents a folder (directory)
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
    
    /// Returns the appropriate system image name for this snippet's file type
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
    
    /// Returns true if this snippet contains file references (not copied to app storage)
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
    /// These snippets cannot be pasted until the cloud files are downloaded
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
    private static func isPathCloudFile(_ path: String) -> Bool {
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
    private static func isPathCloudFileNotDownloaded(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        
        // Check by path - common iCloud/cloud storage locations
        let isCloudPath = path.contains("/Library/Mobile Documents/") ||
                          path.contains("/iCloud Drive/") ||
                          path.contains("~Library/CloudStorage/") ||
                          path.contains("/CloudStorage/")
        
        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemIsDownloadingKey
            ])
            
            // Check if it's a cloud item (either by resource value or path)
            let isUbiquitous = resourceValues.isUbiquitousItem == true || isCloudPath
            
            // Not a cloud item - it's available locally
            guard isUbiquitous else {
                return false
            }
            
            // If actively downloading, it's not yet available
            if resourceValues.ubiquitousItemIsDownloading == true {
                return true
            }
            
            // Check download status - .current and .downloaded both mean available
            if let status = resourceValues.ubiquitousItemDownloadingStatus {
                if status == .current || status == .downloaded {
                    return false
                }
                return true  // Not downloaded
            }
            
            // Status is nil - for cloud paths, assume not downloaded
            return isCloudPath
        } catch {
            // If we can't check but it's a cloud path, assume not downloaded
            return isCloudPath
        }
    }
    
    /// Returns true if this downloading snippet is downloading from cloud storage
    /// (vs copying a large local file). Uses cloudPath/cloudPaths which store the source paths.
    var isDownloadingFromCloud: Bool {
        // Only relevant for downloading snippets
        guard isDownloading else { return false }
        
        // Check cloud paths (source paths for the download/copy operation)
        if let paths = cloudPaths {
            return paths.contains { Self.isPathCloudFileNotDownloaded($0) }
        }
        
        if let path = cloudPath {
            return Self.isPathCloudFileNotDownloaded(path)
        }
        
        return false
    }
    
    /// Returns the cloud service name for this snippet's source files (e.g., "iCloud", "OneDrive")
    /// Returns nil if not a cloud file
    var cloudServiceName: String? {
        // Check cloudPath first (used during download), then mediaPath
        let pathToCheck = cloudPath ?? cloudPaths?.first ?? mediaPath ?? mediaPaths?.first
        guard let path = pathToCheck else { return nil }
        
        return Self.extractCloudServiceName(from: path)
    }
    
    /// Extract cloud service name from a file path
    private static func extractCloudServiceName(from path: String) -> String? {
        // Check iCloud paths
        if path.contains("/Library/Mobile Documents/") || path.contains("/iCloud Drive/") {
            return "iCloud"
        }
        
        // Check CloudStorage paths (OneDrive, Dropbox, Google Drive, etc.)
        if path.contains("/CloudStorage/") {
            if let range = path.range(of: "/CloudStorage/") {
                let afterCloudStorage = path[range.upperBound...]
                if let slashIndex = afterCloudStorage.firstIndex(of: "/") {
                    let servicePart = String(afterCloudStorage[..<slashIndex])
                    if servicePart.lowercased().contains("onedrive") {
                        return "OneDrive"
                    } else if servicePart.lowercased().contains("dropbox") {
                        return "Dropbox"
                    } else if servicePart.lowercased().contains("google") {
                        return "Google Drive"
                    } else if servicePart.lowercased().contains("box") {
                        return "Box"
                    } else {
                        return servicePart
                    }
                }
            }
            return "Cloud Storage"
        }
        
        // Check if file is ubiquitous (iCloud-synced Desktop/Documents)
        let url = URL(fileURLWithPath: path)
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
}

// MARK: - GRDB Support
extension Snippet: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "snippets" }

    enum Columns: String, ColumnExpression {
        case id, name, contentType, textContent, richTextData
        case mediaPath, mediaPaths, thumbnailPath, createdAt, modifiedAt
        case sortOrder, bookmarkData, bookmarkDatas
        case isDownloading, downloadError, downloadFileCount, currentDownloadIndex
        case cloudPath, cloudPaths
    }
}
