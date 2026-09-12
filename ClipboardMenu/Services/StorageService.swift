import Foundation
import GRDB
import AppKit

@MainActor
class StorageService: ObservableObject {
    private var dbQueue: DatabaseQueue?
    private let fileManager = FileManager.default
    
    /// Custom base URL for testing (nil uses default app support directory)
    private let customBaseURL: URL?
    /// Use in-memory database for testing
    private let useInMemoryDatabase: Bool

    var appSupportURL: URL {
        if let custom = customBaseURL {
            try? fileManager.createDirectory(at: custom, withIntermediateDirectories: true)
            return custom
        }
        let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = urls[0].appendingPathComponent("ClipboardMenu", isDirectory: true)
        try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }
    
    /// Default initializer for production use
    init() {
        self.customBaseURL = nil
        self.useInMemoryDatabase = false
    }
    
    /// Initializer for testing with custom paths and optional in-memory database
    /// - Parameters:
    ///   - baseURL: Custom base URL for file storage (nil uses default)
    ///   - inMemory: If true, uses an in-memory database instead of file-based
    init(baseURL: URL?, inMemory: Bool = false) {
        self.customBaseURL = baseURL
        self.useInMemoryDatabase = inMemory
    }

    var mediaURL: URL {
        let url = appSupportURL.appendingPathComponent("Media", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    var thumbnailsURL: URL {
        let url = appSupportURL.appendingPathComponent("Thumbnails", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    
    /// Check if a path is within our app storage (safe to delete)
    /// External file references should NOT be deleted when removing clipboard items
    private func isInAppStorage(_ path: String) -> Bool {
        path.contains("ClipboardMenu")
    }
    
    /// Safely delete a file only if it's in our app storage
    /// External file references are preserved
    private func safeDeleteFile(atPath path: String) {
        guard isInAppStorage(path) else { return }
        try? fileManager.removeItem(atPath: path)
    }

    private var databaseURL: URL {
        appSupportURL.appendingPathComponent("clipboard.db")
    }

    func initialize() throws {
        if useInMemoryDatabase {
            dbQueue = try DatabaseQueue()
        } else {
            dbQueue = try DatabaseQueue(path: databaseURL.path)
        }
        try createTables()
    }

    private func createTables() throws {
        try dbQueue?.write { db in
            // Clipboard items table
            try db.create(table: "clipboard_items", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("contentType", .text).notNull()
                t.column("textContent", .text)
                t.column("richTextData", .blob)
                t.column("mediaPath", .text)
                t.column("mediaPaths", .text)  // JSON array for file stacks
                t.column("thumbnailPath", .text)
                t.column("sourceApp", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("isFavorite", .boolean).notNull().defaults(to: false)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }
            
            // Add mediaPaths column if it doesn't exist (migration for existing databases)
            if try db.columns(in: "clipboard_items").first(where: { $0.name == "mediaPaths" }) == nil {
                try db.alter(table: "clipboard_items") { t in
                    t.add(column: "mediaPaths", .text)
                }
            }
            
            // Add sortOrder column if it doesn't exist (migration for existing databases)
            if try db.columns(in: "clipboard_items").first(where: { $0.name == "sortOrder" }) == nil {
                try db.alter(table: "clipboard_items") { t in
                    t.add(column: "sortOrder", .integer).notNull().defaults(to: 0)
                }
                // Initialize sortOrder based on createdAt order (newest = 0)
                try db.execute(sql: """
                    UPDATE clipboard_items SET sortOrder = (
                        SELECT COUNT(*) FROM clipboard_items c2 
                        WHERE c2.createdAt > clipboard_items.createdAt
                    )
                """)
            }
            
            // Add bookmarkData column for security-scoped bookmarks (migration)
            if try db.columns(in: "clipboard_items").first(where: { $0.name == "bookmarkData" }) == nil {
                try db.alter(table: "clipboard_items") { t in
                    t.add(column: "bookmarkData", .blob)
                }
            }
            
            // Add bookmarkDatas column for file stack security-scoped bookmarks (migration)
            if try db.columns(in: "clipboard_items").first(where: { $0.name == "bookmarkDatas" }) == nil {
                try db.alter(table: "clipboard_items") { t in
                    t.add(column: "bookmarkDatas", .text)  // JSON array of base64-encoded bookmark data
                }
            }
            
            // Add isDownloading column for cloud file download tracking (migration)
            if try db.columns(in: "clipboard_items").first(where: { $0.name == "isDownloading" }) == nil {
                try db.alter(table: "clipboard_items") { t in
                    t.add(column: "isDownloading", .boolean).notNull().defaults(to: false)
                }
            }
            
            // Add originalCloudPath column for tracking original cloud file paths (migration)
            if try db.columns(in: "clipboard_items").first(where: { $0.name == "originalCloudPath" }) == nil {
                try db.alter(table: "clipboard_items") { t in
                    t.add(column: "originalCloudPath", .text)
                }
            }

            // Snippets table
            try db.create(table: "snippets", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("contentType", .text).notNull()
                t.column("textContent", .text)
                t.column("richTextData", .blob)
                t.column("mediaPath", .text)
                t.column("mediaPaths", .text)  // JSON array for file stacks
                t.column("thumbnailPath", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("modifiedAt", .datetime).notNull()
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }
            
            // Add mediaPaths column to snippets if it doesn't exist
            if try db.columns(in: "snippets").first(where: { $0.name == "mediaPaths" }) == nil {
                try db.alter(table: "snippets") { t in
                    t.add(column: "mediaPaths", .text)
                }
            }
            
            // Add bookmarkData column to snippets for security-scoped bookmarks (migration)
            if try db.columns(in: "snippets").first(where: { $0.name == "bookmarkData" }) == nil {
                try db.alter(table: "snippets") { t in
                    t.add(column: "bookmarkData", .blob)
                }
            }
            
            // Add bookmarkDatas column to snippets for file stack bookmarks (migration)
            if try db.columns(in: "snippets").first(where: { $0.name == "bookmarkDatas" }) == nil {
                try db.alter(table: "snippets") { t in
                    t.add(column: "bookmarkDatas", .text)  // JSON array of base64-encoded bookmark data
                }
            }
            
            // Add isDownloading column to snippets for cloud download tracking (migration)
            if try db.columns(in: "snippets").first(where: { $0.name == "isDownloading" }) == nil {
                try db.alter(table: "snippets") { t in
                    t.add(column: "isDownloading", .boolean).notNull().defaults(to: false)
                }
            }
            
            // Add downloadError column to snippets for failed download messages (migration)
            if try db.columns(in: "snippets").first(where: { $0.name == "downloadError" }) == nil {
                try db.alter(table: "snippets") { t in
                    t.add(column: "downloadError", .text)
                }
            }
            
            // Add downloadFileCount column to snippets for download progress display (migration)
            if try db.columns(in: "snippets").first(where: { $0.name == "downloadFileCount" }) == nil {
                try db.alter(table: "snippets") { t in
                    t.add(column: "downloadFileCount", .integer).notNull().defaults(to: 0)
                }
            }
            
            // Add cloudPath column to snippets for retry support (migration)
            if try db.columns(in: "snippets").first(where: { $0.name == "cloudPath" }) == nil {
                try db.alter(table: "snippets") { t in
                    t.add(column: "cloudPath", .text)
                }
            }
            
            // Add cloudPaths column to snippets for file stack retry support (migration)
            if try db.columns(in: "snippets").first(where: { $0.name == "cloudPaths" }) == nil {
                try db.alter(table: "snippets") { t in
                    t.add(column: "cloudPaths", .text)  // JSON array
                }
            }
            
            // Add currentDownloadIndex column to snippets for download progress tracking (migration)
            if try db.columns(in: "snippets").first(where: { $0.name == "currentDownloadIndex" }) == nil {
                try db.alter(table: "snippets") { t in
                    t.add(column: "currentDownloadIndex", .integer).notNull().defaults(to: 0)
                }
            }

            // Create indexes for faster queries
            try db.create(index: "idx_clipboard_items_createdAt",
                         on: "clipboard_items",
                         columns: ["createdAt"],
                         ifNotExists: true)
            
            try db.create(index: "idx_clipboard_items_sortOrder",
                         on: "clipboard_items",
                         columns: ["sortOrder"],
                         ifNotExists: true)

            try db.create(index: "idx_snippets_sortOrder",
                         on: "snippets",
                         columns: ["sortOrder"],
                         ifNotExists: true)
        }
    }

    // MARK: - Clipboard Items

    func saveClipboardItem(_ item: ClipboardItem) throws {
        try dbQueue?.write { db in
            // Shift all existing items down to make room at the top
            try db.execute(sql: "UPDATE clipboard_items SET sortOrder = sortOrder + 1")
            // Save new item at position 0
            var newItem = item
            newItem.sortOrder = 0
            try newItem.save(db)
        }
        objectWillChange.send()
    }

    func fetchClipboardItems(limit: Int = 200) throws -> [ClipboardItem] {
        try dbQueue?.read { db in
            try ClipboardItem
                .order(ClipboardItem.Columns.sortOrder.asc)
                .limit(limit)
                .fetchAll(db)
        } ?? []
    }

    func fetchClipboardItems(matching query: String, useRegex: Bool = false, contentType: ContentType? = nil) throws -> [ClipboardItem] {
        try dbQueue?.read { db in
            var request = ClipboardItem.all()

            if !query.isEmpty {
                if useRegex {
                    // SQLite REGEXP requires extension, use GLOB as fallback
                    request = request.filter(ClipboardItem.Columns.textContent.like("%\(query)%"))
                } else {
                    request = request.filter(ClipboardItem.Columns.textContent.like("%\(query)%"))
                }
            }

            if let type = contentType {
                request = request.filter(ClipboardItem.Columns.contentType == type.rawValue)
            }

            return try request
                .order(ClipboardItem.Columns.sortOrder.asc)
                .fetchAll(db)
        } ?? []
    }
    
    func updateClipboardItemOrder(_ items: [ClipboardItem]) throws {
        try dbQueue?.write { db in
            for (index, var item) in items.enumerated() {
                item.sortOrder = index
                try item.update(db)
            }
        }
        objectWillChange.send()
    }

    func deleteClipboardItem(_ item: ClipboardItem) throws {
        // Delete associated files (only if in app storage, not external references)
        if let mediaPath = item.mediaPath {
            safeDeleteFile(atPath: mediaPath)
        }
        if let mediaPaths = item.mediaPaths {
            for path in mediaPaths {
                safeDeleteFile(atPath: path)
            }
        }
        if let thumbnailPath = item.thumbnailPath {
            safeDeleteFile(atPath: thumbnailPath)
        }

        _ = try dbQueue?.write { db in
            try item.delete(db)
        }
        objectWillChange.send()
    }
    
    /// Delete a clipboard item by ID
    func deleteClipboardItem(id: UUID) throws {
        try dbQueue?.write { db in
            if let item = try ClipboardItem.fetchOne(db, key: id) {
                // Delete associated files (only if in app storage, not external references)
                if let mediaPath = item.mediaPath {
                    safeDeleteFile(atPath: mediaPath)
                }
                if let mediaPaths = item.mediaPaths {
                    for path in mediaPaths {
                        safeDeleteFile(atPath: path)
                    }
                }
                if let thumbnailPath = item.thumbnailPath {
                    safeDeleteFile(atPath: thumbnailPath)
                }
                try item.delete(db)
            }
        }
        objectWillChange.send()
    }

    func deleteOldItems(keepCount: Int) throws {
        try dbQueue?.write { db in
            let items = try ClipboardItem
                .filter(ClipboardItem.Columns.isFavorite == false)
                .order(ClipboardItem.Columns.createdAt.desc)
                .fetchAll(db)

            if items.count > keepCount {
                for item in items.dropFirst(keepCount) {
                    // Delete associated files (only if in app storage, not external references)
                    if let mediaPath = item.mediaPath {
                        safeDeleteFile(atPath: mediaPath)
                    }
                    if let mediaPaths = item.mediaPaths {
                        for path in mediaPaths {
                            safeDeleteFile(atPath: path)
                        }
                    }
                    if let thumbnailPath = item.thumbnailPath {
                        safeDeleteFile(atPath: thumbnailPath)
                    }
                    try item.delete(db)
                }
            }
        }
        objectWillChange.send()
    }
    
    /// Removes clipboard items that have invalid file references (deleted/moved external files)
    /// Only checks items that are file references (external paths, not copied to app storage)
    /// - Returns: The number of items removed
    @discardableResult
    func removeInvalidFileReferences() throws -> Int {
        var removedCount = 0
        
        try dbQueue?.write { db in
            // Fetch all clipboard items
            let items = try ClipboardItem.fetchAll(db)
            
            for item in items {
                // Only check file references (external paths)
                if item.isFileReference && !item.hasValidFileReference {
                    // Delete the thumbnail if it exists (it's in app storage)
                    if let thumbnailPath = item.thumbnailPath {
                        try? fileManager.removeItem(atPath: thumbnailPath)
                    }
                    // Don't delete mediaPath/mediaPaths - they're external files that no longer exist
                    try item.delete(db)
                    removedCount += 1
                }
            }
        }
        
        if removedCount > 0 {
            objectWillChange.send()
        }
        
        return removedCount
    }
    
    /// Async version of removeInvalidFileReferences that runs file system checks off the main thread
    /// Call this after the UI is displayed to avoid blocking menu responsiveness
    /// - Returns: The number of items removed
    @discardableResult
    nonisolated func removeInvalidFileReferencesAsync() async throws -> Int {
        // Run file system checks on a background thread
        let dbQueue = await MainActor.run { self.dbQueue }
        
        // First, fetch items and identify invalid ones off main thread
        let invalidItemIds: [UUID] = try await Task.detached(priority: .utility) {
            guard let dbQueue = dbQueue else { return [] }
            
            return try dbQueue.read { db in
                let items = try ClipboardItem.fetchAll(db)
                return items.compactMap { item -> UUID? in
                    // Only check file references (external paths)
                    if item.isFileReference && !item.hasValidFileReference {
                        return item.id
                    }
                    return nil
                }
            }
        }.value
        
        guard !invalidItemIds.isEmpty else { return 0 }
        
        // Delete invalid items and their thumbnails
        let removedCount: Int = try await Task.detached(priority: .utility) {
            guard let dbQueue = dbQueue else { return 0 }
            let fm = FileManager.default
            
            var count = 0
            try dbQueue.write { db in
                for itemId in invalidItemIds {
                    if let item = try ClipboardItem.fetchOne(db, key: itemId) {
                        // Delete the thumbnail if it exists
                        if let thumbnailPath = item.thumbnailPath {
                            try? fm.removeItem(atPath: thumbnailPath)
                        }
                        try item.delete(db)
                        count += 1
                    }
                }
            }
            return count
        }.value
        
        if removedCount > 0 {
            await MainActor.run {
                self.objectWillChange.send()
            }
        }
        
        return removedCount
    }

    func getMostRecentItem() throws -> ClipboardItem? {
        try dbQueue?.read { db in
            try ClipboardItem
                .order(ClipboardItem.Columns.createdAt.desc)
                .fetchOne(db)
        }
    }

    /// Finds an existing item matching the content and moves it to the top.
    /// Returns true if a duplicate was found and moved, false otherwise.
    func moveExistingItemToTop(textContent: String?, mediaPath: String?, contentType: ContentType) throws -> Bool {
        guard let dbQueue = dbQueue else { return false }

        let found = try dbQueue.write { db in
            var existingItem: ClipboardItem?

            // For text/richText, match by text content
            if let text = textContent, !text.isEmpty {
                existingItem = try ClipboardItem
                    .filter(ClipboardItem.Columns.textContent == text)
                    .filter(ClipboardItem.Columns.contentType == contentType.rawValue)
                    .fetchOne(db)
            }
            // For image/video, match by media path
            else if let path = mediaPath {
                existingItem = try ClipboardItem
                    .filter(ClipboardItem.Columns.mediaPath == path)
                    .fetchOne(db)
            }

            if var item = existingItem {
                let currentSortOrder = item.sortOrder
                // Shift items that are above this one (lower sortOrder) down by 1
                try db.execute(sql: "UPDATE clipboard_items SET sortOrder = sortOrder + 1 WHERE sortOrder < ?", arguments: [currentSortOrder])
                // Move this item to the top
                item.sortOrder = 0
                item.createdAt = Date()
                try item.update(db)
                return true
            }

            return false
        }
        if found {
            objectWillChange.send()
        }
        return found
    }

    /// Moves an existing item to the top by updating its sortOrder
    func moveItemToTop(_ item: ClipboardItem) throws {
        try dbQueue?.write { db in
            let currentSortOrder = item.sortOrder
            // Shift items that are above this one (lower sortOrder) down by 1
            try db.execute(sql: "UPDATE clipboard_items SET sortOrder = sortOrder + 1 WHERE sortOrder < ?", arguments: [currentSortOrder])
            // Move this item to the top
            var updatedItem = item
            updatedItem.sortOrder = 0
            updatedItem.createdAt = Date()  // Also update timestamp
            try updatedItem.update(db)
        }
        objectWillChange.send()
    }
    
    /// Moves an existing item to the top and updates its filename (textContent)
    /// Used when a file with the same content is copied but has been renamed
    func moveItemToTop(_ item: ClipboardItem, withFilename filename: String?) throws {
        try dbQueue?.write { db in
            let currentSortOrder = item.sortOrder
            // Shift items that are above this one (lower sortOrder) down by 1
            try db.execute(sql: "UPDATE clipboard_items SET sortOrder = sortOrder + 1 WHERE sortOrder < ?", arguments: [currentSortOrder])
            // Move this item to the top and update filename
            var updatedItem = item
            updatedItem.sortOrder = 0
            updatedItem.createdAt = Date()
            if let newFilename = filename {
                updatedItem.textContent = newFilename
            }
            try updatedItem.update(db)
        }
        objectWillChange.send()
    }
    
    // MARK: - Snippets

    func saveSnippet(_ snippet: Snippet) throws {
        try dbQueue?.write { db in
            try snippet.save(db)
        }
        objectWillChange.send()
    }

    func fetchSnippets() throws -> [Snippet] {
        try dbQueue?.read { db in
            try Snippet
                .order(Snippet.Columns.sortOrder.asc)
                .fetchAll(db)
        } ?? []
    }

    func deleteSnippet(_ snippet: Snippet) throws {
        // Delete associated files
        if let mediaPath = snippet.mediaPath {
            try? fileManager.removeItem(atPath: mediaPath)
        }
        if let mediaPaths = snippet.mediaPaths {
            for path in mediaPaths {
                try? fileManager.removeItem(atPath: path)
            }
        }
        if let thumbnailPath = snippet.thumbnailPath {
            try? fileManager.removeItem(atPath: thumbnailPath)
        }

        _ = try dbQueue?.write { db in
            try snippet.delete(db)
        }
        objectWillChange.send()
    }

    func updateSnippet(_ snippet: Snippet) throws {
        var updated = snippet
        updated.modifiedAt = Date()
        try dbQueue?.write { db in
            try updated.update(db)
        }
        objectWillChange.send()
    }
    
    func updateSnippetOrder(_ snippets: [Snippet]) throws {
        try dbQueue?.write { db in
            for (index, var snippet) in snippets.enumerated() {
                snippet.sortOrder = index
                try snippet.update(db)
            }
        }
        objectWillChange.send()
    }

    /// Extract the original filename from a storage path, stripping UUID prefixes
    /// Handles formats: {UUID}_{filename}, {UUID}_{index}_{filename}, snippet_{UUID}_{index}_{filename}
    private func extractOriginalFilename(from path: String) -> String {
        let filename = URL(fileURLWithPath: path).lastPathComponent
        
        // Check for snippet file stack format: snippet_{UUID}_{index}_{originalFilename}
        let snippetStackPattern = "^snippet_[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}_\\d+_"
        if let regex = try? NSRegularExpression(pattern: snippetStackPattern, options: []),
           let match = regex.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)),
           let matchRange = Range(match.range, in: filename) {
            return String(filename[matchRange.upperBound...])
        }
        
        // Check for clipboard file stack format: {UUID}_{index}_{originalFilename}
        let clipboardStackPattern = "^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}_\\d+_"
        if let regex = try? NSRegularExpression(pattern: clipboardStackPattern, options: []),
           let match = regex.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)),
           let matchRange = Range(match.range, in: filename) {
            return String(filename[matchRange.upperBound...])
        }
        
        // Check for single file format: {UUID}_{originalFilename}
        let singleFilePattern = "^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}_"
        if let regex = try? NSRegularExpression(pattern: singleFilePattern, options: []),
           let match = regex.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)),
           let matchRange = Range(match.range, in: filename) {
            let remainder = String(filename[matchRange.upperBound...])
            if !remainder.isEmpty {
                return remainder
            }
        }
        
        // Not a storage format, return as-is
        return filename
    }
    
    func createSnippetFromItem(_ item: ClipboardItem, name: String = "") throws -> Snippet {
        var snippet = Snippet(from: item, name: name)
        
        // Add new snippet at the top by shifting all existing snippets down
        try dbQueue?.write { db in
            try db.execute(sql: "UPDATE snippets SET sortOrder = sortOrder + 1")
        }
        snippet.sortOrder = 0

        // For file stacks, copy all files to snippet storage
        if item.contentType == .fileStack, let paths = item.mediaPaths {
            var newPaths: [String] = []
            for (index, path) in paths.enumerated() {
                if fileManager.fileExists(atPath: path) {
                    let originalFilename = extractOriginalFilename(from: path)
                    let newPath = mediaURL.appendingPathComponent("snippet_\(snippet.id.uuidString)_\(index)_\(originalFilename)").path
                    try? fileManager.copyItem(atPath: path, toPath: newPath)
                    newPaths.append(newPath)
                }
            }
            snippet.mediaPaths = newPaths.isEmpty ? nil : newPaths
        }
        // For single file references (image, video, file), copy to snippet storage
        else if let mediaPath = item.mediaPath,
                fileManager.fileExists(atPath: mediaPath) {
            let originalFilename = extractOriginalFilename(from: mediaPath)
            let newMediaPath = mediaURL.appendingPathComponent("snippet_\(snippet.id.uuidString)_\(originalFilename)").path
            try? fileManager.copyItem(atPath: mediaPath, toPath: newMediaPath)
            snippet.mediaPath = newMediaPath
        }
        
        // Copy thumbnail if it exists (thumbnails are already in our storage)
        if let thumbnailPath = item.thumbnailPath,
           fileManager.fileExists(atPath: thumbnailPath) {
            let newThumbnailPath = thumbnailsURL.appendingPathComponent("snippet_\(snippet.id.uuidString).png").path
            try? fileManager.copyItem(atPath: thumbnailPath, toPath: newThumbnailPath)
            snippet.thumbnailPath = newThumbnailPath
        }

        try saveSnippet(snippet)
        return snippet
    }
    
    /// Creates a snippet in downloading state for cloud files
    /// The snippet is created immediately with isDownloading=true, and files will be copied
    /// after the cloud download completes via completeSnippetDownload()
    func createDownloadingSnippet(from item: ClipboardItem, name: String = "", fileCount: Int) throws -> Snippet {
        var snippet = Snippet(from: item, name: name)
        snippet.isDownloading = true
        snippet.downloadError = nil
        snippet.downloadFileCount = fileCount
        
        // Store original cloud paths for retry support and download
        // IMPORTANT: Clear mediaPath/mediaPaths so we don't delete the original cloud files
        // if the snippet is cancelled/deleted before download completes
        if item.contentType == .fileStack, let paths = item.mediaPaths {
            snippet.cloudPaths = paths
            snippet.mediaPaths = nil  // Don't store cloud paths here - will be set after download
        } else if let path = item.mediaPath {
            snippet.cloudPath = path
            snippet.mediaPath = nil  // Don't store cloud path here - will be set after download
        }
        
        // Add new snippet at the top by shifting all existing snippets down
        try dbQueue?.write { db in
            try db.execute(sql: "UPDATE snippets SET sortOrder = sortOrder + 1")
        }
        snippet.sortOrder = 0
        
        // Copy thumbnail if it exists (thumbnails are already in our storage and don't need download)
        if let thumbnailPath = item.thumbnailPath,
           fileManager.fileExists(atPath: thumbnailPath) {
            let newThumbnailPath = thumbnailsURL.appendingPathComponent("snippet_\(snippet.id.uuidString).png").path
            try? fileManager.copyItem(atPath: thumbnailPath, toPath: newThumbnailPath)
            snippet.thumbnailPath = newThumbnailPath
        }
        
        try saveSnippet(snippet)
        return snippet
    }
    
    /// Completes a snippet download by copying files from cloud paths to app storage
    /// Called after cloud files have been downloaded successfully
    func completeSnippetDownload(_ snippetId: UUID) throws {
        guard let dbQueue = dbQueue else { return }
        
        var copyErrors: [String] = []
        
        try dbQueue.write { db in
            guard var snippet = try Snippet.fetchOne(db, key: snippetId) else {
                throw NSError(domain: "StorageService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Snippet not found"])
            }
            
            // Copy files from cloud paths to snippet storage
            if snippet.contentType == .fileStack, let cloudPaths = snippet.cloudPaths {
                var newPaths: [String] = []
                for (index, path) in cloudPaths.enumerated() {
                    let sourceURL = URL(fileURLWithPath: path)
                    let originalFilename = extractOriginalFilename(from: path)
                    let newPath = mediaURL.appendingPathComponent("snippet_\(snippet.id.uuidString)_\(index)_\(originalFilename)").path
                    
                    // Check if source is a directory using resource values
                    var isDirectory = false
                    if let resourceValues = try? sourceURL.resourceValues(forKeys: [.isDirectoryKey]) {
                        isDirectory = resourceValues.isDirectory ?? false
                    }
                    
                    do {
                        if isDirectory {
                            try fileManager.copyItem(at: sourceURL, to: URL(fileURLWithPath: newPath))
                        } else {
                            try fileManager.copyItem(atPath: path, toPath: newPath)
                        }
                        newPaths.append(newPath)
                        print("[StorageService] Copied: \(originalFilename)")
                    } catch {
                        print("[StorageService] Failed to copy \(originalFilename): \(error)")
                        copyErrors.append("\(originalFilename): \(error.localizedDescription)")
                    }
                }
                snippet.mediaPaths = newPaths.isEmpty ? nil : newPaths
            } else if let cloudPath = snippet.cloudPath {
                let sourceURL = URL(fileURLWithPath: cloudPath)
                let originalFilename = extractOriginalFilename(from: cloudPath)
                let newMediaPath = mediaURL.appendingPathComponent("snippet_\(snippet.id.uuidString)_\(originalFilename)").path
                
                // Check if source is a directory using resource values
                var isDirectory = false
                if let resourceValues = try? sourceURL.resourceValues(forKeys: [.isDirectoryKey]) {
                    isDirectory = resourceValues.isDirectory ?? false
                }
                
                do {
                    if isDirectory {
                        try fileManager.copyItem(at: sourceURL, to: URL(fileURLWithPath: newMediaPath))
                    } else {
                        try fileManager.copyItem(atPath: cloudPath, toPath: newMediaPath)
                    }
                    snippet.mediaPath = newMediaPath
                    print("[StorageService] Copied: \(originalFilename)")
                } catch {
                    print("[StorageService] Failed to copy \(originalFilename): \(error)")
                    copyErrors.append("\(originalFilename): \(error.localizedDescription)")
                }
            }
            
            // Mark as completed
            snippet.isDownloading = false
            snippet.currentDownloadIndex = 0  // Reset progress
            snippet.downloadError = nil
            snippet.modifiedAt = Date()
            
            try snippet.update(db)
        }
        objectWillChange.send()
        
        // If we had copy errors but no files copied, throw
        if !copyErrors.isEmpty {
            print("[StorageService] Completed with errors: \(copyErrors)")
        }
    }
    
    /// Async version that does file copying on background thread
    nonisolated     func completeSnippetDownloadAsync(_ snippetId: UUID) async throws {
        // Capture values from main actor first, including bookmarks for security-scoped access
        let (dbQueue, mediaURLPath, contentType, cloudPaths, cloudPath, snippetUUID, bookmarkData, bookmarkDatas): (DatabaseQueue?, String, ContentType, [String]?, String?, UUID, Data?, [Data]?) = await MainActor.run {
            guard let dbQueue = self.dbQueue else { 
                return (nil, "", ContentType.text, nil, nil, UUID(), nil, nil)
            }
            
            let snippet: Snippet? = try? dbQueue.read { db in
                try Snippet.fetchOne(db, key: snippetId)
            }
            
            guard let snippet = snippet else {
                return (nil, "", ContentType.text, nil, nil, UUID(), nil, nil)
            }
            
            return (dbQueue, self.mediaURL.path, snippet.contentType, snippet.cloudPaths, snippet.cloudPath, snippet.id, snippet.bookmarkData, snippet.bookmarkDatas)
        }
        
        guard let dbQueue = dbQueue else {
            throw NSError(domain: "StorageService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Snippet not found or database unavailable"])
        }
        
        // Copy files on background queue using continuation
        let (newPaths, newPath, copyErrors): ([String]?, String?, [String]) = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fm = FileManager.default
                var resultPaths: [String]? = nil
                var resultPath: String? = nil
                var errors: [String] = []
                var accessedURLs: [URL] = []  // Track URLs we've started accessing
                
                // Ensure we stop accessing all security-scoped resources when done
                defer {
                    for url in accessedURLs {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                
                /// Helper to resolve bookmark and start accessing security-scoped resource
                func resolveAndAccess(_ bookmark: Data) -> URL? {
                    var isStale = false
                    do {
                        let url = try URL(
                            resolvingBookmarkData: bookmark,
                            options: .withSecurityScope,
                            relativeTo: nil,
                            bookmarkDataIsStale: &isStale
                        )
                        if url.startAccessingSecurityScopedResource() {
                            accessedURLs.append(url)
                            return url
                        }
                    } catch {
                        print("[StorageService] Failed to resolve bookmark: \(error)")
                    }
                    return nil
                }
                
                /// Helper to verify a file is actually readable (not a cloud stub)
                func verifyFileAccessible(_ url: URL, isDirectory: Bool) -> Bool {
                    if isDirectory {
                        // For directories, check we can enumerate
                        return fm.enumerator(at: url, includingPropertiesForKeys: nil) != nil
                    } else {
                        // For files, try to open and read a byte
                        guard let handle = try? FileHandle(forReadingFrom: url) else {
                            return false
                        }
                        defer { try? handle.close() }
                        // Just verify we can read - don't need to actually read data
                        do {
                            _ = try handle.read(upToCount: 1)
                            return true
                        } catch {
                            return false
                        }
                    }
                }
                
                if contentType == .fileStack, let sourcePaths = cloudPaths {
                    var paths: [String] = []
                    for (index, path) in sourcePaths.enumerated() {
                        // Try to use bookmark for security-scoped access if available
                        var sourceURL: URL
                        if let bookmarks = bookmarkDatas, index < bookmarks.count,
                           let resolvedURL = resolveAndAccess(bookmarks[index]) {
                            sourceURL = resolvedURL
                            print("[StorageService] Using security-scoped URL for: \(sourceURL.lastPathComponent)")
                        } else {
                            sourceURL = URL(fileURLWithPath: path)
                        }
                        
                        let originalFilename = sourceURL.lastPathComponent
                        let destPath = URL(fileURLWithPath: mediaURLPath).appendingPathComponent("snippet_\(snippetUUID.uuidString)_\(index)_\(originalFilename)").path
                        
                        // Check if source is a directory using resource values
                        var isDirectory = false
                        if let resourceValues = try? sourceURL.resourceValues(forKeys: [.isDirectoryKey]) {
                            isDirectory = resourceValues.isDirectory ?? false
                        }
                        
                        // Verify file is accessible before copying
                        if !verifyFileAccessible(sourceURL, isDirectory: isDirectory) {
                            print("[StorageService] File not accessible (may be cloud stub): \(originalFilename)")
                            errors.append("\(originalFilename): File not accessible - may still be downloading from iCloud")
                            continue
                        }
                        
                        do {
                            // Remove existing destination if present (from failed previous attempt)
                            let destURL = URL(fileURLWithPath: destPath)
                            if fm.fileExists(atPath: destPath) {
                                try fm.removeItem(at: destURL)
                            }
                            
                            if isDirectory {
                                // For directories, copy recursively
                                try fm.copyItem(at: sourceURL, to: destURL)
                            } else {
                                // For files, copy directly
                                try fm.copyItem(at: sourceURL, to: destURL)
                            }
                            paths.append(destPath)
                            print("[StorageService] Copied: \(originalFilename) -> \(destPath)")
                        } catch {
                            print("[StorageService] Failed to copy \(originalFilename): \(error)")
                            errors.append("\(originalFilename): \(error.localizedDescription)")
                        }
                    }
                    resultPaths = paths.isEmpty ? nil : paths
                } else if let sourcePath = cloudPath {
                    // Try to use bookmark for security-scoped access if available
                    var sourceURL: URL
                    if let bookmark = bookmarkData,
                       let resolvedURL = resolveAndAccess(bookmark) {
                        sourceURL = resolvedURL
                        print("[StorageService] Using security-scoped URL for: \(sourceURL.lastPathComponent)")
                    } else {
                        sourceURL = URL(fileURLWithPath: sourcePath)
                    }
                    
                    let originalFilename = sourceURL.lastPathComponent
                    let destPath = URL(fileURLWithPath: mediaURLPath).appendingPathComponent("snippet_\(snippetUUID.uuidString)_\(originalFilename)").path
                    
                    // Check if source is a directory using resource values
                    var isDirectory = false
                    if let resourceValues = try? sourceURL.resourceValues(forKeys: [.isDirectoryKey]) {
                        isDirectory = resourceValues.isDirectory ?? false
                    }
                    
                    // Verify file is accessible before copying
                    if !verifyFileAccessible(sourceURL, isDirectory: isDirectory) {
                        print("[StorageService] File not accessible (may be cloud stub): \(originalFilename)")
                        errors.append("\(originalFilename): File not accessible - may still be downloading from iCloud")
                    } else {
                        do {
                            // Remove existing destination if present (from failed previous attempt)
                            let destURL = URL(fileURLWithPath: destPath)
                            if fm.fileExists(atPath: destPath) {
                                try fm.removeItem(at: destURL)
                            }
                            
                            if isDirectory {
                                try fm.copyItem(at: sourceURL, to: destURL)
                            } else {
                                try fm.copyItem(at: sourceURL, to: destURL)
                            }
                            resultPath = destPath
                            print("[StorageService] Copied: \(originalFilename) -> \(destPath)")
                        } catch {
                            print("[StorageService] Failed to copy \(originalFilename): \(error)")
                            errors.append("\(originalFilename): \(error.localizedDescription)")
                        }
                    }
                }
                
                continuation.resume(returning: (resultPaths, resultPath, errors))
            }
        }
        
        // If we failed to copy any files, throw an error
        if !copyErrors.isEmpty && newPaths == nil && newPath == nil {
            throw NSError(domain: "StorageService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to copy files: \(copyErrors.joined(separator: ", "))"])
        }
        
        // Update database on main actor
        await MainActor.run {
            do {
                try dbQueue.write { db in
                    guard var updatedSnippet = try Snippet.fetchOne(db, key: snippetId) else {
                        return
                    }
                    
                    if let paths = newPaths {
                        updatedSnippet.mediaPaths = paths
                    } else if let path = newPath {
                        updatedSnippet.mediaPath = path
                    }
                    
                    // Always mark as not downloading, even if file copy failed
                    updatedSnippet.isDownloading = false
                    updatedSnippet.currentDownloadIndex = 0  // Reset progress
                    updatedSnippet.downloadError = nil
                    updatedSnippet.modifiedAt = Date()
                    
                    try updatedSnippet.update(db)
                }
                self.objectWillChange.send()
            } catch {
                print("completeSnippetDownloadAsync: Failed to update snippet: \(error)")
                // Even if database update fails, try to at least mark as not downloading
                try? dbQueue.write { db in
                    guard var updatedSnippet = try Snippet.fetchOne(db, key: snippetId) else { return }
                    updatedSnippet.isDownloading = false
                    updatedSnippet.currentDownloadIndex = 0
                    updatedSnippet.downloadError = "Failed to save: \(error.localizedDescription)"
                    try updatedSnippet.update(db)
                }
                self.objectWillChange.send()
            }
        }
    }
    
    /// Marks a snippet download as failed with an error message
    func markSnippetDownloadFailed(_ snippetId: UUID, error: String) throws {
        guard let dbQueue = dbQueue else { return }
        
        try dbQueue.write { db in
            guard var snippet = try Snippet.fetchOne(db, key: snippetId) else { return }
            snippet.isDownloading = false
            snippet.currentDownloadIndex = 0  // Reset progress
            snippet.downloadError = error
            snippet.modifiedAt = Date()
            try snippet.update(db)
        }
        objectWillChange.send()
    }
    
    /// Clears the download error on a snippet (for retry)
    func clearSnippetDownloadError(_ snippetId: UUID) throws {
        guard let dbQueue = dbQueue else { return }
        
        try dbQueue.write { db in
            guard var snippet = try Snippet.fetchOne(db, key: snippetId) else { return }
            snippet.downloadError = nil
            snippet.isDownloading = true
            snippet.currentDownloadIndex = 0
            snippet.modifiedAt = Date()
            try snippet.update(db)
        }
        objectWillChange.send()
    }
    
    /// Updates the download progress for a snippet (current file index)
    func updateSnippetDownloadProgress(_ snippetId: UUID, currentIndex: Int, totalFiles: Int) throws {
        guard let dbQueue = dbQueue else { return }
        
        try dbQueue.write { db in
            guard var snippet = try Snippet.fetchOne(db, key: snippetId) else { return }
            snippet.currentDownloadIndex = currentIndex
            snippet.downloadFileCount = totalFiles
            try snippet.update(db)
        }
        objectWillChange.send()
    }
    
    /// Deletes any snippets that are still in downloading state (cleanup on app launch)
    /// Returns the number of snippets deleted
    @discardableResult
    func deleteIncompleteDownloads() throws -> Int {
        guard let dbQueue = dbQueue else { return 0 }
        
        var deletedCount = 0
        
        try dbQueue.write { db in
            let downloadingSnippets = try Snippet
                .filter(Snippet.Columns.isDownloading == true)
                .fetchAll(db)
            
            for snippet in downloadingSnippets {
                // Delete any partially copied files
                if let mediaPath = snippet.mediaPath {
                    try? fileManager.removeItem(atPath: mediaPath)
                }
                if let mediaPaths = snippet.mediaPaths {
                    for path in mediaPaths {
                        try? fileManager.removeItem(atPath: path)
                    }
                }
                if let thumbnailPath = snippet.thumbnailPath {
                    try? fileManager.removeItem(atPath: thumbnailPath)
                }
                
                try snippet.delete(db)
                deletedCount += 1
            }
        }
        
        if deletedCount > 0 {
            objectWillChange.send()
        }
        
        return deletedCount
    }
    
    /// Delete a snippet by ID
    func deleteSnippet(id: UUID) throws {
        guard let dbQueue = dbQueue else { return }
        
        try dbQueue.write { db in
            if let snippet = try Snippet.fetchOne(db, key: id) {
                // Delete associated files
                if let mediaPath = snippet.mediaPath {
                    try? fileManager.removeItem(atPath: mediaPath)
                }
                if let mediaPaths = snippet.mediaPaths {
                    for path in mediaPaths {
                        try? fileManager.removeItem(atPath: path)
                    }
                }
                if let thumbnailPath = snippet.thumbnailPath {
                    try? fileManager.removeItem(atPath: thumbnailPath)
                }
                
                try snippet.delete(db)
            }
        }
        objectWillChange.send()
    }
    
    /// Fetch a snippet by ID
    func fetchSnippet(id: UUID) throws -> Snippet? {
        try dbQueue?.read { db in
            try Snippet.fetchOne(db, key: id)
        }
    }

    // MARK: - File Storage

    func saveMedia(data: Data, type: ContentType, itemId: UUID, originalFilename: String? = nil) throws -> String {
        let filename: String
        if let original = originalFilename, !original.isEmpty {
            // Preserve original filename in storage path: {UUID}_{originalFilename}
            filename = "\(itemId.uuidString)_\(original)"
        } else {
            // No original filename, use UUID with default extension
            let ext: String
            switch type {
            case .image: ext = "png"
            case .video: ext = "mp4"
            default: ext = "dat"
            }
            filename = "\(itemId.uuidString).\(ext)"
        }

        let path = mediaURL.appendingPathComponent(filename)
        try data.write(to: path)
        return path.path
    }

    func saveThumbnail(data: Data, itemId: UUID) throws -> String {
        let path = thumbnailsURL.appendingPathComponent("\(itemId.uuidString).png")
        try data.write(to: path)
        return path.path
    }
    
    /// Save a file as part of a file stack
    func saveMediaForStack(data: Data, itemId: UUID, index: Int, originalFilename: String) throws -> String {
        let path = mediaURL.appendingPathComponent("\(itemId.uuidString)_\(index)_\(originalFilename)")
        try data.write(to: path)
        return path.path
    }
    
    /// Save a folder to storage by copying it recursively
    /// - Parameters:
    ///   - sourceURL: The source folder URL to copy
    ///   - itemId: The clipboard item UUID
    ///   - originalFolderName: The original folder name to preserve
    /// - Returns: The path to the copied folder in storage
    func saveFolder(sourceURL: URL, itemId: UUID, originalFolderName: String) throws -> String {
        let destPath = mediaURL.appendingPathComponent("\(itemId.uuidString)_\(originalFolderName)")
        // copyItem preserves symlinks as-is by default
        try fileManager.copyItem(at: sourceURL, to: destPath)
        return destPath.path
    }
    
    /// Save a folder as part of a file stack
    /// - Parameters:
    ///   - sourceURL: The source folder URL to copy
    ///   - itemId: The clipboard item UUID
    ///   - index: The index in the file stack
    ///   - originalFolderName: The original folder name to preserve
    /// - Returns: The path to the copied folder in storage
    func saveFolderForStack(sourceURL: URL, itemId: UUID, index: Int, originalFolderName: String) throws -> String {
        let destPath = mediaURL.appendingPathComponent("\(itemId.uuidString)_\(index)_\(originalFolderName)")
        // copyItem preserves symlinks as-is by default
        try fileManager.copyItem(at: sourceURL, to: destPath)
        return destPath.path
    }

    func loadMedia(from path: String) -> Data? {
        fileManager.contents(atPath: path)
    }

    // MARK: - Storage Stats

    func calculateStorageSize() -> Int64 {
        var totalSize: Int64 = 0

        let enumerator = fileManager.enumerator(at: appSupportURL, includingPropertiesForKeys: [.fileSizeKey])
        while let url = enumerator?.nextObject() as? URL {
            if let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(fileSize)
            }
        }

        return totalSize
    }
    
    /// Calculate storage size for clipboard items only (excludes snippets)
    func calculateClipboardItemsStorageSize() -> Int64 {
        var totalSize: Int64 = 0
        
        // Calculate size of media files for clipboard items only
        do {
            let items = try fetchClipboardItems(limit: Int.max)
            for item in items {
                if let mediaPath = item.mediaPath,
                   let attrs = try? fileManager.attributesOfItem(atPath: mediaPath) {
                    totalSize += (attrs[.size] as? Int64) ?? 0
                }
                if let mediaPaths = item.mediaPaths {
                    for path in mediaPaths {
                        if let attrs = try? fileManager.attributesOfItem(atPath: path) {
                            totalSize += (attrs[.size] as? Int64) ?? 0
                        }
                    }
                }
                if let thumbnailPath = item.thumbnailPath,
                   let attrs = try? fileManager.attributesOfItem(atPath: thumbnailPath) {
                    totalSize += (attrs[.size] as? Int64) ?? 0
                }
            }
        } catch {
            print("Failed to calculate clipboard items storage: \(error)")
        }
        
        return totalSize
    }
    
    /// Get the count of clipboard history items (excludes snippets)
    func getClipboardItemCount() -> Int {
        do {
            return try dbQueue?.read { db in
                try ClipboardItem.fetchCount(db)
            } ?? 0
        } catch {
            print("Failed to get clipboard item count: \(error)")
            return 0
        }
    }
    
    /// Calculate storage size for snippets only
    func calculateSnippetsStorageSize() -> Int64 {
        var totalSize: Int64 = 0
        
        do {
            let snippets = try fetchSnippets()
            for snippet in snippets {
                if let mediaPath = snippet.mediaPath,
                   let attrs = try? fileManager.attributesOfItem(atPath: mediaPath) {
                    totalSize += (attrs[.size] as? Int64) ?? 0
                }
                if let mediaPaths = snippet.mediaPaths {
                    for path in mediaPaths {
                        if let attrs = try? fileManager.attributesOfItem(atPath: path) {
                            totalSize += (attrs[.size] as? Int64) ?? 0
                        }
                    }
                }
                if let thumbnailPath = snippet.thumbnailPath,
                   let attrs = try? fileManager.attributesOfItem(atPath: thumbnailPath) {
                    totalSize += (attrs[.size] as? Int64) ?? 0
                }
            }
        } catch {
            print("Failed to calculate snippets storage: \(error)")
        }
        
        return totalSize
    }
    
    /// Get the count of snippets
    func getSnippetCount() -> Int {
        do {
            return try dbQueue?.read { db in
                try Snippet.fetchCount(db)
            } ?? 0
        } catch {
            print("Failed to get snippet count: \(error)")
            return 0
        }
    }
    
    /// Delete all snippets and their associated files
    func deleteAllSnippets() throws {
        let snippets = try fetchSnippets()
        
        for snippet in snippets {
            // Delete associated files
            if let mediaPath = snippet.mediaPath {
                try? fileManager.removeItem(atPath: mediaPath)
            }
            if let mediaPaths = snippet.mediaPaths {
                for path in mediaPaths {
                    try? fileManager.removeItem(atPath: path)
                }
            }
            if let thumbnailPath = snippet.thumbnailPath {
                try? fileManager.removeItem(atPath: thumbnailPath)
            }
        }
        
        // Delete all snippet records from database
        _ = try dbQueue?.write { db in
            try Snippet.deleteAll(db)
        }
        
        objectWillChange.send()
    }
    
    /// Wipe all data: deletes the entire storage folder including database, media, and thumbnails
    /// This is a destructive operation that cannot be undone
    func wipeAllData() throws {
        // Close database connection first
        dbQueue = nil
        
        // Delete the entire app support directory
        if fileManager.fileExists(atPath: appSupportURL.path) {
            try fileManager.removeItem(at: appSupportURL)
        }
        
        // Recreate the directory structure
        try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        
        // Reinitialize the database
        try initialize()
        
        objectWillChange.send()
    }

    /// Enforce storage limit by deleting oldest clipboard items (excludes snippets)
    func enforceStorageLimit(maxBytes: Int64) throws {
        var currentSize = calculateClipboardItemsStorageSize()

        if currentSize <= maxBytes { return }

        // Delete oldest clipboard items until under limit (never delete snippets)
        try dbQueue?.write { db in
            let items = try ClipboardItem
                .order(ClipboardItem.Columns.createdAt.asc)
                .fetchAll(db)

            for item in items {
                guard currentSize > maxBytes else { break }

                var freedBytes: Int64 = 0

                // Only delete and count files in app storage, not external references
                if let mediaPath = item.mediaPath, isInAppStorage(mediaPath),
                   let attrs = try? fileManager.attributesOfItem(atPath: mediaPath) {
                    freedBytes += (attrs[.size] as? Int64) ?? 0
                    try? fileManager.removeItem(atPath: mediaPath)
                }
                if let mediaPaths = item.mediaPaths {
                    for path in mediaPaths where isInAppStorage(path) {
                        if let attrs = try? fileManager.attributesOfItem(atPath: path) {
                            freedBytes += (attrs[.size] as? Int64) ?? 0
                            try? fileManager.removeItem(atPath: path)
                        }
                    }
                }
                if let thumbnailPath = item.thumbnailPath, isInAppStorage(thumbnailPath),
                   let attrs = try? fileManager.attributesOfItem(atPath: thumbnailPath) {
                    freedBytes += (attrs[.size] as? Int64) ?? 0
                    try? fileManager.removeItem(atPath: thumbnailPath)
                }

                try item.delete(db)
                currentSize -= freedBytes
            }
        }
        objectWillChange.send()
    }
    
    /// Enforce item count limit by deleting oldest clipboard items (excludes snippets)
    func enforceItemCountLimit(maxItems: Int) throws {
        let currentCount = getClipboardItemCount()
        
        if currentCount <= maxItems { return }
        
        let itemsToDelete = currentCount - maxItems
        
        // Delete oldest clipboard items (never delete snippets)
        try dbQueue?.write { db in
            let items = try ClipboardItem
                .order(ClipboardItem.Columns.createdAt.asc)
                .limit(itemsToDelete)
                .fetchAll(db)
            
            for item in items {
                // Delete associated files (only if in app storage, not external references)
                if let mediaPath = item.mediaPath {
                    safeDeleteFile(atPath: mediaPath)
                }
                if let mediaPaths = item.mediaPaths {
                    for path in mediaPaths {
                        safeDeleteFile(atPath: path)
                    }
                }
                if let thumbnailPath = item.thumbnailPath {
                    safeDeleteFile(atPath: thumbnailPath)
                }
                
                try item.delete(db)
            }
        }
        objectWillChange.send()
    }
    
    /// Run cleanup to enforce both item count and storage limits
    func runCleanup(maxItems: Int, maxStorageBytes: Int64) {
        do {
            try enforceItemCountLimit(maxItems: maxItems)
            try enforceStorageLimit(maxBytes: maxStorageBytes)
        } catch {
            print("Cleanup failed: \(error)")
        }
    }
    
    // MARK: - Thumbnail Regeneration
    
    /// Regenerate all video thumbnails with a new size
    /// - Parameters:
    ///   - thumbnailService: The thumbnail service to use for generation
    ///   - maxSize: The new maximum size for thumbnails
    /// - Returns: The number of thumbnails regenerated
    @discardableResult
    func regenerateVideoThumbnails(thumbnailService: ThumbnailService, maxSize: CGFloat) async throws -> Int {
        var count = 0
        
        // Get all video clipboard items
        let clipboardItems = try fetchClipboardItems(limit: Int.max).filter { $0.contentType == .video }
        
        for var item in clipboardItems {
            guard let mediaPath = item.mediaPath else { continue }
            
            // Delete old thumbnail if it exists
            if let oldThumbnailPath = item.thumbnailPath {
                try? fileManager.removeItem(atPath: oldThumbnailPath)
            }
            
            // Generate new thumbnail (runs on background thread)
            if let previewImage = await thumbnailService.generateVideoPreviewImageAsync(from: mediaPath, maxSize: maxSize),
               let pngData = previewImage.pngData() {
                let newThumbnailPath = try saveThumbnail(data: pngData, itemId: item.id)
                item.thumbnailPath = newThumbnailPath
                try updateClipboardItem(item)
                count += 1
            } else {
                // Clear thumbnail path if generation failed
                item.thumbnailPath = nil
                try updateClipboardItem(item)
            }
        }
        
        // Get all video snippets
        let snippets = try fetchSnippets().filter { $0.contentType == .video }
        
        for var snippet in snippets {
            guard let mediaPath = snippet.mediaPath else { continue }
            
            // Delete old thumbnail if it exists
            if let oldThumbnailPath = snippet.thumbnailPath {
                try? fileManager.removeItem(atPath: oldThumbnailPath)
            }
            
            // Generate new thumbnail (runs on background thread)
            if let previewImage = await thumbnailService.generateVideoPreviewImageAsync(from: mediaPath, maxSize: maxSize),
               let pngData = previewImage.pngData() {
                let newThumbnailPath = thumbnailsURL.appendingPathComponent("snippet_\(snippet.id.uuidString).png").path
                try pngData.write(to: URL(fileURLWithPath: newThumbnailPath))
                snippet.thumbnailPath = newThumbnailPath
                try updateSnippet(snippet)
                count += 1
            } else {
                // Clear thumbnail path if generation failed
                snippet.thumbnailPath = nil
                try updateSnippet(snippet)
            }
        }
        
        objectWillChange.send()
        return count
    }
    
    /// Update a clipboard item in the database
    private func updateClipboardItem(_ item: ClipboardItem) throws {
        try dbQueue?.write { db in
            try item.update(db)
        }
    }
}
