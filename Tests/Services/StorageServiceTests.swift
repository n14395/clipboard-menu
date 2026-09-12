import XCTest
import GRDB
@testable import ClipboardMenu

@MainActor
final class StorageServiceTests: XCTestCase {
    
    var storageService: StorageService!
    var tempDir: TempDirectory!
    
    override func setUp() async throws {
        // Use app storage temp dir so paths contain "ClipboardMenu"
        // This ensures media files are treated as internal (not external references)
        tempDir = try TempDirectory.appStorage()
        storageService = StorageService(baseURL: tempDir.url, inMemory: true)
        try storageService.initialize()
    }
    
    override func tearDown() async throws {
        storageService = nil
        tempDir?.cleanup()
        tempDir = nil
    }
    
    // MARK: - Initialization
    
    func testInitializeCreatesDatabase() throws {
        // The database should be initialized in setUp
        let items = try storageService.fetchClipboardItems()
        XCTAssertNotNil(items)
        XCTAssertEqual(items.count, 0)
    }
    
    func testCreateTablesIdempotent() throws {
        // Calling initialize twice should not throw
        try storageService.initialize()
        
        let items = try storageService.fetchClipboardItems()
        XCTAssertEqual(items.count, 0)
    }
    
    // MARK: - ClipboardItem CRUD
    
    func testSaveAndFetchClipboardItem() throws {
        let item = TestData.textItem(text: "Test content")
        try storageService.saveClipboardItem(item)
        
        let fetched = try storageService.fetchClipboardItems()
        
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, item.id)
        XCTAssertEqual(fetched.first?.textContent, "Test content")
    }
    
    func testSaveMultipleItems() throws {
        let items = TestData.textItems(count: 5)
        for item in items {
            try storageService.saveClipboardItem(item)
        }
        
        let fetched = try storageService.fetchClipboardItems()
        
        XCTAssertEqual(fetched.count, 5)
    }
    
    func testFetchWithLimit() throws {
        let items = TestData.textItems(count: 10)
        for item in items {
            try storageService.saveClipboardItem(item)
        }
        
        let fetched = try storageService.fetchClipboardItems(limit: 5)
        
        XCTAssertEqual(fetched.count, 5)
    }
    
    func testFetchOrdersByCreatedAtDesc() throws {
        let oldItem = TestData.textItem(text: "Old", createdAt: Date(timeIntervalSince1970: 1000))
        let newItem = TestData.textItem(text: "New", createdAt: Date(timeIntervalSince1970: 2000))
        
        try storageService.saveClipboardItem(oldItem)
        try storageService.saveClipboardItem(newItem)
        
        let fetched = try storageService.fetchClipboardItems()
        
        XCTAssertEqual(fetched.first?.textContent, "New")
        XCTAssertEqual(fetched.last?.textContent, "Old")
    }
    
    func testDeleteClipboardItem() throws {
        let item = TestData.textItem()
        try storageService.saveClipboardItem(item)
        
        XCTAssertEqual(try storageService.fetchClipboardItems().count, 1)
        
        try storageService.deleteClipboardItem(item)
        
        XCTAssertEqual(try storageService.fetchClipboardItems().count, 0)
    }
    
    func testDeleteClipboardItemPreservesExternalFileReferences() throws {
        // Create a temporary external file (simulating a large file stored as reference)
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("external_file_\(UUID().uuidString).txt")
        try "This file should NOT be deleted".write(to: tempFile, atomically: true, encoding: .utf8)
        
        // Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFile.path))
        
        // Create a clipboard item with external file reference (path doesn't contain "ClipboardMenu")
        let item = TestData.fileItem(mediaPath: tempFile.path)
        try storageService.saveClipboardItem(item)
        
        // Delete the clipboard item
        try storageService.deleteClipboardItem(item)
        
        // The external file should still exist (not deleted)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFile.path), "External file reference should NOT be deleted")
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempFile)
    }
    
    func testDeleteClipboardItemDeletesInternalFiles() throws {
        // This test verifies that files in app storage ARE deleted
        // The TestData creates items with paths like "/path/to/ClipboardMenu/Media/..."
        // which contain "ClipboardMenu" and should be deleted
        
        // Create a file item - in tests, internal paths would contain "ClipboardMenu"
        let item = TestData.fileItem(mediaPath: "/some/path/ClipboardMenu/Media/test.pdf")
        try storageService.saveClipboardItem(item)
        
        // Delete should not throw (file doesn't exist but that's OK)
        try storageService.deleteClipboardItem(item)
        
        XCTAssertEqual(try storageService.fetchClipboardItems().count, 0)
    }
    
    func testGetMostRecentItem() throws {
        let oldItem = TestData.textItem(text: "Old", createdAt: Date(timeIntervalSince1970: 1000))
        let newItem = TestData.textItem(text: "New", createdAt: Date(timeIntervalSince1970: 2000))
        
        try storageService.saveClipboardItem(oldItem)
        try storageService.saveClipboardItem(newItem)
        
        let recent = try storageService.getMostRecentItem()
        
        XCTAssertEqual(recent?.textContent, "New")
    }
    
    func testGetMostRecentItemWhenEmpty() throws {
        let recent = try storageService.getMostRecentItem()
        XCTAssertNil(recent)
    }
    
    // MARK: - Fetch with Filters
    
    func testFetchMatchingQuery() throws {
        let items = [
            TestData.textItem(text: "Hello World"),
            TestData.textItem(text: "Goodbye World"),
            TestData.textItem(text: "Hello There")
        ]
        for item in items {
            try storageService.saveClipboardItem(item)
        }
        
        let fetched = try storageService.fetchClipboardItems(matching: "Hello")
        
        XCTAssertEqual(fetched.count, 2)
    }
    
    func testFetchMatchingContentType() throws {
        try storageService.saveClipboardItem(TestData.textItem())
        try storageService.saveClipboardItem(TestData.imageItem())
        try storageService.saveClipboardItem(TestData.textItem())
        
        let fetched = try storageService.fetchClipboardItems(matching: "", contentType: .text)
        
        XCTAssertEqual(fetched.count, 2)
    }
    
    // MARK: - Deduplication
    
    func testMoveExistingTextToTop() throws {
        let item = TestData.textItem(text: "Duplicate me", createdAt: Date(timeIntervalSince1970: 1000))
        try storageService.saveClipboardItem(item)
        
        // Wait a bit to ensure different timestamp
        let moved = try storageService.moveExistingItemToTop(
            textContent: "Duplicate me",
            mediaPath: nil,
            contentType: .text
        )
        
        XCTAssertTrue(moved)
        
        let fetched = try storageService.fetchClipboardItems()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertGreaterThan(fetched.first!.createdAt, Date(timeIntervalSince1970: 1000))
    }
    
    func testMoveExistingTextNotFound() throws {
        let item = TestData.textItem(text: "Original")
        try storageService.saveClipboardItem(item)
        
        let moved = try storageService.moveExistingItemToTop(
            textContent: "Different text",
            mediaPath: nil,
            contentType: .text
        )
        
        XCTAssertFalse(moved)
    }
    
    func testMoveItemToTopUpdatesTimestamp() throws {
        let oldDate = Date(timeIntervalSince1970: 1000)
        var item = TestData.textItem(createdAt: oldDate)
        try storageService.saveClipboardItem(item)
        
        item.createdAt = oldDate // Reset to ensure we're testing the update
        try storageService.moveItemToTop(item)
        
        let fetched = try storageService.getMostRecentItem()
        XCTAssertGreaterThan(fetched!.createdAt, oldDate)
    }
    
    // MARK: - Cleanup
    
    func testDeleteOldItemsKeepsNewest() throws {
        for i in 0..<10 {
            let item = TestData.textItem(
                text: "Item \(i)",
                createdAt: Date(timeIntervalSinceNow: Double(-i * 60))
            )
            try storageService.saveClipboardItem(item)
        }
        
        try storageService.deleteOldItems(keepCount: 5)
        
        let remaining = try storageService.fetchClipboardItems()
        XCTAssertEqual(remaining.count, 5)
        
        // Verify newest items were kept
        for item in remaining {
            XCTAssertTrue(item.textContent?.hasPrefix("Item ") == true)
        }
    }
    
    func testDeleteOldItemsPreservesFavorites() throws {
        // Create old favorite
        let favorite = TestData.textItem(
            text: "Favorite",
            createdAt: Date(timeIntervalSince1970: 1000),
            isFavorite: true
        )
        try storageService.saveClipboardItem(favorite)
        
        // Create newer non-favorites
        for i in 0..<5 {
            let item = TestData.textItem(text: "Item \(i)")
            try storageService.saveClipboardItem(item)
        }
        
        try storageService.deleteOldItems(keepCount: 3)
        
        let remaining = try storageService.fetchClipboardItems()
        
        // Favorite should still exist even though it's old
        let hasFavorite = remaining.contains { $0.textContent == "Favorite" }
        XCTAssertTrue(hasFavorite)
    }
    
    func testEnforceItemCountLimit() throws {
        for i in 0..<10 {
            let item = TestData.textItem(
                text: "Item \(i)",
                createdAt: Date(timeIntervalSinceNow: Double(-i * 60))
            )
            try storageService.saveClipboardItem(item)
        }
        
        try storageService.enforceItemCountLimit(maxItems: 5)
        
        XCTAssertEqual(try storageService.getClipboardItemCount(), 5)
    }
    
    func testEnforceItemCountLimitNoOpUnderLimit() throws {
        for i in 0..<3 {
            try storageService.saveClipboardItem(TestData.textItem(text: "Item \(i)"))
        }
        
        try storageService.enforceItemCountLimit(maxItems: 10)
        
        XCTAssertEqual(try storageService.getClipboardItemCount(), 3)
    }
    
    // MARK: - Remove Invalid File References
    
    func testRemoveInvalidFileReferencesRemovesDeletedFiles() throws {
        // Add a file reference to a non-existent file
        let item = TestData.fileItem(mediaPath: "/nonexistent/deleted_file.pdf")
        try storageService.saveClipboardItem(item)
        
        // Verify item exists
        XCTAssertEqual(try storageService.getClipboardItemCount(), 1)
        
        // Remove invalid references
        let removedCount = try storageService.removeInvalidFileReferences()
        
        XCTAssertEqual(removedCount, 1)
        XCTAssertEqual(try storageService.getClipboardItemCount(), 0)
    }
    
    func testRemoveInvalidFileReferencesKeepsValidFiles() throws {
        // Create a temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test_valid_\(UUID().uuidString).txt")
        try "test content".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        // Add a file reference to an existing file
        let item = TestData.fileItem(mediaPath: tempFile.path)
        try storageService.saveClipboardItem(item)
        
        // Remove invalid references (should remove nothing)
        let removedCount = try storageService.removeInvalidFileReferences()
        
        XCTAssertEqual(removedCount, 0)
        XCTAssertEqual(try storageService.getClipboardItemCount(), 1)
    }
    
    func testRemoveInvalidFileReferencesKeepsInternalPaths() throws {
        // Internal paths (in ClipboardMenu storage) are not file references
        // They should not be checked/removed even if the file doesn't exist
        let item = TestData.fileItem(mediaPath: "/Users/test/Library/Application Support/ClipboardMenu/Media/file.pdf")
        try storageService.saveClipboardItem(item)
        
        // Remove invalid references (should not remove internal paths)
        let removedCount = try storageService.removeInvalidFileReferences()
        
        XCTAssertEqual(removedCount, 0)
        XCTAssertEqual(try storageService.getClipboardItemCount(), 1)
    }
    
    func testRemoveInvalidFileReferencesKeepsTextItems() throws {
        // Text items should never be removed
        let item = TestData.textItem(text: "Hello")
        try storageService.saveClipboardItem(item)
        
        let removedCount = try storageService.removeInvalidFileReferences()
        
        XCTAssertEqual(removedCount, 0)
        XCTAssertEqual(try storageService.getClipboardItemCount(), 1)
    }
    
    func testRemoveInvalidFileReferencesFileStackPartiallyMissing() throws {
        // Create one temp file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test_stack_\(UUID().uuidString).txt")
        try "content".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        // File stack with one existing and one missing file
        let item = TestData.fileStackItem(mediaPaths: [tempFile.path, "/nonexistent/missing.txt"])
        try storageService.saveClipboardItem(item)
        
        // Should be removed because ANY missing file makes it invalid
        let removedCount = try storageService.removeInvalidFileReferences()
        
        XCTAssertEqual(removedCount, 1)
        XCTAssertEqual(try storageService.getClipboardItemCount(), 0)
    }
    
    func testRemoveInvalidFileReferencesMixedItems() throws {
        // Create a temp file for valid reference
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test_mixed_\(UUID().uuidString).txt")
        try "content".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        // Add various items
        try storageService.saveClipboardItem(TestData.textItem(text: "Text 1"))                      // Should keep
        try storageService.saveClipboardItem(TestData.fileItem(mediaPath: tempFile.path))           // Should keep (valid)
        try storageService.saveClipboardItem(TestData.fileItem(mediaPath: "/missing/file.pdf"))     // Should remove
        try storageService.saveClipboardItem(TestData.textItem(text: "Text 2"))                      // Should keep
        
        XCTAssertEqual(try storageService.getClipboardItemCount(), 4)
        
        let removedCount = try storageService.removeInvalidFileReferences()
        
        XCTAssertEqual(removedCount, 1)
        XCTAssertEqual(try storageService.getClipboardItemCount(), 3)
    }
    
    // MARK: - Snippets
    
    func testSaveAndFetchSnippet() throws {
        let snippet = TestData.snippet(name: "My Snippet", textContent: "Content")
        try storageService.saveSnippet(snippet)
        
        let fetched = try storageService.fetchSnippets()
        
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "My Snippet")
        XCTAssertEqual(fetched.first?.textContent, "Content")
    }
    
    func testFetchSnippetsOrderBySortOrder() throws {
        let s1 = TestData.snippet(name: "Third", sortOrder: 2)
        let s2 = TestData.snippet(name: "First", sortOrder: 0)
        let s3 = TestData.snippet(name: "Second", sortOrder: 1)
        
        try storageService.saveSnippet(s1)
        try storageService.saveSnippet(s2)
        try storageService.saveSnippet(s3)
        
        let fetched = try storageService.fetchSnippets()
        
        XCTAssertEqual(fetched[0].name, "First")
        XCTAssertEqual(fetched[1].name, "Second")
        XCTAssertEqual(fetched[2].name, "Third")
    }
    
    func testUpdateSnippet() throws {
        var snippet = TestData.snippet(name: "Original")
        try storageService.saveSnippet(snippet)
        
        snippet.name = "Updated"
        try storageService.updateSnippet(snippet)
        
        let fetched = try storageService.fetchSnippets()
        XCTAssertEqual(fetched.first?.name, "Updated")
    }
    
    func testUpdateSnippetUpdatesModifiedAt() throws {
        let snippet = TestData.snippet(
            name: "Test",
            modifiedAt: Date(timeIntervalSince1970: 1000)
        )
        try storageService.saveSnippet(snippet)
        
        try storageService.updateSnippet(snippet)
        
        let fetched = try storageService.fetchSnippets()
        XCTAssertGreaterThan(fetched.first!.modifiedAt, Date(timeIntervalSince1970: 1000))
    }
    
    func testDeleteSnippet() throws {
        let snippet = TestData.snippet()
        try storageService.saveSnippet(snippet)
        
        XCTAssertEqual(try storageService.fetchSnippets().count, 1)
        
        try storageService.deleteSnippet(snippet)
        
        XCTAssertEqual(try storageService.fetchSnippets().count, 0)
    }
    
    func testCreateSnippetFromItem() throws {
        let item = TestData.textItem(text: "Source content")
        try storageService.saveClipboardItem(item)
        
        let snippet = try storageService.createSnippetFromItem(item, name: "New Snippet")
        
        XCTAssertEqual(snippet.name, "New Snippet")
        XCTAssertEqual(snippet.textContent, "Source content")
        XCTAssertEqual(snippet.contentType, .text)
        
        let fetched = try storageService.fetchSnippets()
        XCTAssertEqual(fetched.count, 1)
    }
    
    func testCreateSnippetFromItemShiftsOrder() throws {
        // Create existing snippets
        let existing = TestData.snippet(name: "Existing", sortOrder: 0)
        try storageService.saveSnippet(existing)
        
        let item = TestData.textItem()
        let newSnippet = try storageService.createSnippetFromItem(item, name: "New")
        
        XCTAssertEqual(newSnippet.sortOrder, 0)
        
        let fetched = try storageService.fetchSnippets()
        let existingFetched = fetched.first { $0.name == "Existing" }
        XCTAssertEqual(existingFetched?.sortOrder, 1)
    }
    
    func testUpdateSnippetOrder() throws {
        let s1 = TestData.snippet(name: "A", sortOrder: 0)
        let s2 = TestData.snippet(name: "B", sortOrder: 1)
        let s3 = TestData.snippet(name: "C", sortOrder: 2)
        
        try storageService.saveSnippet(s1)
        try storageService.saveSnippet(s2)
        try storageService.saveSnippet(s3)
        
        // Reverse the order
        let reordered = [s3, s2, s1]
        try storageService.updateSnippetOrder(reordered)
        
        let fetched = try storageService.fetchSnippets()
        XCTAssertEqual(fetched[0].name, "C")
        XCTAssertEqual(fetched[1].name, "B")
        XCTAssertEqual(fetched[2].name, "A")
    }
    
    // MARK: - File Storage
    
    func testSaveMediaCreatesFile() throws {
        let data = TestImageData.minimalPNG
        let itemId = UUID()
        
        let path = try storageService.saveMedia(data: data, type: .image, itemId: itemId)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        XCTAssertTrue(path.hasSuffix(".png"))
    }
    
    func testSaveMediaWithOriginalFilename() throws {
        let data = Data("test content".utf8)
        let itemId = UUID()
        
        let path = try storageService.saveMedia(
            data: data,
            type: .file,
            itemId: itemId,
            originalFilename: "document.txt"
        )
        
        XCTAssertTrue(path.hasSuffix(".txt"))
    }
    
    func testSaveThumbnail() throws {
        let data = TestImageData.minimalPNG
        let itemId = UUID()
        
        let path = try storageService.saveThumbnail(data: data, itemId: itemId)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        XCTAssertTrue(path.contains("Thumbnails"))
    }
    
    func testLoadMedia() throws {
        let originalData = Data("test content".utf8)
        let itemId = UUID()
        
        let path = try storageService.saveMedia(data: originalData, type: .file, itemId: itemId)
        let loadedData = storageService.loadMedia(from: path)
        
        XCTAssertEqual(loadedData, originalData)
    }
    
    func testLoadMediaNonExistent() {
        let data = storageService.loadMedia(from: "/nonexistent/path")
        XCTAssertNil(data)
    }
    
    func testSaveMediaForStack() throws {
        let data = Data("file content".utf8)
        let itemId = UUID()
        
        let path = try storageService.saveMediaForStack(
            data: data,
            itemId: itemId,
            index: 0,
            originalFilename: "file.txt"
        )
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        XCTAssertTrue(path.contains("_0_file.txt"))
    }
    
    // MARK: - Storage Stats
    
    func testGetClipboardItemCount() throws {
        XCTAssertEqual(storageService.getClipboardItemCount(), 0)
        
        for i in 0..<5 {
            try storageService.saveClipboardItem(TestData.textItem(text: "Item \(i)"))
        }
        
        XCTAssertEqual(storageService.getClipboardItemCount(), 5)
    }
    
    func testCalculateStorageSize() throws {
        // Save some data
        let data = TestImageData.data(ofSize: 1000)
        let itemId = UUID()
        _ = try storageService.saveMedia(data: data, type: .image, itemId: itemId)
        
        let size = storageService.calculateStorageSize()
        
        XCTAssertGreaterThanOrEqual(size, 1000)
    }
    
    // MARK: - Directory URLs
    
    func testAppSupportURLExists() {
        let url = storageService.appSupportURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
    
    func testMediaURLExists() {
        let url = storageService.mediaURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
    
    func testThumbnailsURLExists() {
        let url = storageService.thumbnailsURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
    
    // MARK: - runCleanup Tests
    
    func testRunCleanupEnforcesItemCountLimit() throws {
        // Create 10 items
        for i in 0..<10 {
            let item = TestData.textItem(
                text: "Item \(i)",
                createdAt: Date(timeIntervalSinceNow: Double(-i * 60))
            )
            try storageService.saveClipboardItem(item)
        }
        
        XCTAssertEqual(storageService.getClipboardItemCount(), 10)
        
        // Run cleanup with max 5 items
        storageService.runCleanup(maxItems: 5, maxStorageBytes: Int64.max)
        
        XCTAssertEqual(storageService.getClipboardItemCount(), 5)
    }
    
    func testRunCleanupEnforcesStorageLimit() throws {
        // Create items with media files
        for i in 0..<5 {
            let itemId = UUID()
            let data = TestImageData.data(ofSize: 1000) // 1KB each
            let mediaPath = try storageService.saveMedia(data: data, type: .image, itemId: itemId)
            
            let item = ClipboardItem(
                id: itemId,
                contentType: .image,
                mediaPath: mediaPath,
                createdAt: Date(timeIntervalSinceNow: Double(-i * 60))
            )
            try storageService.saveClipboardItem(item)
        }
        
        let initialSize = storageService.calculateClipboardItemsStorageSize()
        XCTAssertGreaterThanOrEqual(initialSize, 5000)
        
        // Run cleanup with very small storage limit (should delete some items)
        storageService.runCleanup(maxItems: Int.max, maxStorageBytes: 2000)
        
        let finalSize = storageService.calculateClipboardItemsStorageSize()
        XCTAssertLessThanOrEqual(finalSize, 2000)
    }
    
    func testRunCleanupEnforcesBothLimits() throws {
        // Create 10 items with media
        for i in 0..<10 {
            let itemId = UUID()
            let data = TestImageData.data(ofSize: 500)
            let mediaPath = try storageService.saveMedia(data: data, type: .image, itemId: itemId)
            
            let item = ClipboardItem(
                id: itemId,
                contentType: .image,
                mediaPath: mediaPath,
                createdAt: Date(timeIntervalSinceNow: Double(-i * 60))
            )
            try storageService.saveClipboardItem(item)
        }
        
        XCTAssertEqual(storageService.getClipboardItemCount(), 10)
        
        // Run cleanup with both limits
        storageService.runCleanup(maxItems: 3, maxStorageBytes: 2000)
        
        // Should be limited by item count (3 items)
        XCTAssertLessThanOrEqual(storageService.getClipboardItemCount(), 3)
    }
    
    func testRunCleanupNoOpWhenUnderLimits() throws {
        // Create 3 small items
        for i in 0..<3 {
            try storageService.saveClipboardItem(TestData.textItem(text: "Item \(i)"))
        }
        
        let initialCount = storageService.getClipboardItemCount()
        
        // Run cleanup with generous limits
        storageService.runCleanup(maxItems: 100, maxStorageBytes: 1024 * 1024 * 100)
        
        XCTAssertEqual(storageService.getClipboardItemCount(), initialCount)
    }
    
    func testRunCleanupDeletesOldestFirst() throws {
        // Create items with specific timestamps - newest first
        let newestItem = TestData.textItem(text: "Newest", createdAt: Date())
        let middleItem = TestData.textItem(text: "Middle", createdAt: Date(timeIntervalSinceNow: -120))
        let oldestItem = TestData.textItem(text: "Oldest", createdAt: Date(timeIntervalSinceNow: -240))
        
        // Save in random order
        try storageService.saveClipboardItem(middleItem)
        try storageService.saveClipboardItem(oldestItem)
        try storageService.saveClipboardItem(newestItem)
        
        XCTAssertEqual(storageService.getClipboardItemCount(), 3)
        
        // Keep only 1 item
        storageService.runCleanup(maxItems: 1, maxStorageBytes: Int64.max)
        
        let remaining = try storageService.fetchClipboardItems()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.textContent, "Newest")
    }
    
    func testRunCleanupPreservesSnippets() throws {
        // Create some clipboard items
        for i in 0..<5 {
            try storageService.saveClipboardItem(TestData.textItem(text: "Item \(i)"))
        }
        
        // Create some snippets
        for i in 0..<3 {
            try storageService.saveSnippet(TestData.snippet(name: "Snippet \(i)"))
        }
        
        XCTAssertEqual(storageService.getClipboardItemCount(), 5)
        XCTAssertEqual(storageService.getSnippetCount(), 3)
        
        // Run cleanup to delete all clipboard items
        storageService.runCleanup(maxItems: 0, maxStorageBytes: 0)
        
        // Snippets should be preserved
        XCTAssertEqual(storageService.getClipboardItemCount(), 0)
        XCTAssertEqual(storageService.getSnippetCount(), 3)
    }
    
    func testCalculateClipboardItemsStorageSizeIncludesMediaFiles() throws {
        // Create clipboard item with media
        let clipboardItemId = UUID()
        let clipboardData = TestImageData.data(ofSize: 1000)
        let clipboardMediaPath = try storageService.saveMedia(data: clipboardData, type: .image, itemId: clipboardItemId)
        try storageService.saveClipboardItem(ClipboardItem(
            id: clipboardItemId,
            contentType: .image,
            mediaPath: clipboardMediaPath
        ))
        
        let clipboardSize = storageService.calculateClipboardItemsStorageSize()
        
        // Clipboard size should include the media file
        XCTAssertGreaterThanOrEqual(clipboardSize, 1000)
    }
    
    func testRunCleanupWithZeroLimitsDeletesAll() throws {
        // Create some items
        for i in 0..<5 {
            try storageService.saveClipboardItem(TestData.textItem(text: "Item \(i)"))
        }
        
        XCTAssertEqual(storageService.getClipboardItemCount(), 5)
        
        // Run cleanup with zero limits
        storageService.runCleanup(maxItems: 0, maxStorageBytes: 0)
        
        XCTAssertEqual(storageService.getClipboardItemCount(), 0)
    }
    
    // MARK: - enforceStorageLimit Tests
    
    func testEnforceStorageLimitDeletesOldestFirst() throws {
        // Create items with media files - oldest first
        for i in 0..<5 {
            let itemId = UUID()
            let data = TestImageData.data(ofSize: 500)
            let mediaPath = try storageService.saveMedia(data: data, type: .image, itemId: itemId)
            
            let item = ClipboardItem(
                id: itemId,
                contentType: .image,
                mediaPath: mediaPath,
                createdAt: Date(timeIntervalSinceNow: Double(-i * 60)) // i=0 is newest, i=4 is oldest
            )
            try storageService.saveClipboardItem(item)
        }
        
        XCTAssertEqual(storageService.getClipboardItemCount(), 5)
        
        // Enforce a limit that should delete oldest items
        try storageService.enforceStorageLimit(maxBytes: 1500)
        
        // Should have deleted some items
        XCTAssertLessThan(storageService.getClipboardItemCount(), 5)
    }
    
    func testEnforceStorageLimitNoOpWhenUnderLimit() throws {
        // Create items with small media
        for i in 0..<3 {
            let itemId = UUID()
            let data = TestImageData.data(ofSize: 100)
            let mediaPath = try storageService.saveMedia(data: data, type: .image, itemId: itemId)
            
            let item = ClipboardItem(
                id: itemId,
                contentType: .image,
                mediaPath: mediaPath
            )
            try storageService.saveClipboardItem(item)
        }
        
        let countBefore = storageService.getClipboardItemCount()
        
        // Enforce generous limit
        try storageService.enforceStorageLimit(maxBytes: 1024 * 1024 * 100)
        
        XCTAssertEqual(storageService.getClipboardItemCount(), countBefore)
    }
    
    func testEnforceStorageLimitDeletesMediaFiles() throws {
        let itemId = UUID()
        let data = TestImageData.data(ofSize: 1000)
        let mediaPath = try storageService.saveMedia(data: data, type: .image, itemId: itemId)
        
        let item = ClipboardItem(
            id: itemId,
            contentType: .image,
            mediaPath: mediaPath
        )
        try storageService.saveClipboardItem(item)
        
        // Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: mediaPath))
        
        // Enforce zero limit to delete everything
        try storageService.enforceStorageLimit(maxBytes: 0)
        
        // File should be deleted
        XCTAssertFalse(FileManager.default.fileExists(atPath: mediaPath))
    }
    
    func testEnforceStorageLimitPreservesExternalReferences() throws {
        // Create a temporary external file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("external_storage_test_\(UUID().uuidString).txt")
        try "Test content for storage limit".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        // Create clipboard item with external reference
        let item = ClipboardItem(
            id: UUID(),
            contentType: .file,
            mediaPath: tempFile.path
        )
        try storageService.saveClipboardItem(item)
        
        // Enforce zero storage limit
        try storageService.enforceStorageLimit(maxBytes: 0)
        
        // External file should still exist (not deleted)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFile.path))
    }
    
    // MARK: - deleteAllSnippets Tests
    
    func testDeleteAllSnippetsRemovesAllRecords() throws {
        // Create multiple snippets
        for i in 0..<5 {
            try storageService.saveSnippet(TestData.snippet(name: "Snippet \(i)"))
        }
        
        XCTAssertEqual(storageService.getSnippetCount(), 5)
        
        try storageService.deleteAllSnippets()
        
        XCTAssertEqual(storageService.getSnippetCount(), 0)
    }
    
    func testDeleteAllSnippetsDeletesMediaFiles() throws {
        // Create snippet with media
        let itemId = UUID()
        let data = TestImageData.minimalPNG
        let mediaPath = try storageService.saveMedia(data: data, type: .image, itemId: itemId)
        
        var snippet = TestData.snippet(name: "Image Snippet")
        snippet.mediaPath = mediaPath
        try storageService.saveSnippet(snippet)
        
        // Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: mediaPath))
        
        try storageService.deleteAllSnippets()
        
        // File should be deleted
        XCTAssertFalse(FileManager.default.fileExists(atPath: mediaPath))
    }
    
    func testDeleteAllSnippetsPreservesClipboardItems() throws {
        // Create clipboard items
        for i in 0..<3 {
            try storageService.saveClipboardItem(TestData.textItem(text: "Item \(i)"))
        }
        
        // Create snippets
        for i in 0..<2 {
            try storageService.saveSnippet(TestData.snippet(name: "Snippet \(i)"))
        }
        
        XCTAssertEqual(storageService.getClipboardItemCount(), 3)
        XCTAssertEqual(storageService.getSnippetCount(), 2)
        
        try storageService.deleteAllSnippets()
        
        // Clipboard items should be preserved
        XCTAssertEqual(storageService.getClipboardItemCount(), 3)
        XCTAssertEqual(storageService.getSnippetCount(), 0)
    }
    
    func testDeleteAllSnippetsNoOpWhenEmpty() throws {
        XCTAssertEqual(storageService.getSnippetCount(), 0)
        
        // Should not throw
        try storageService.deleteAllSnippets()
        
        XCTAssertEqual(storageService.getSnippetCount(), 0)
    }
    
    // MARK: - updateClipboardItemOrder Tests
    
    func testUpdateClipboardItemOrderReorders() throws {
        let item1 = TestData.textItem(text: "First")
        let item2 = TestData.textItem(text: "Second")
        let item3 = TestData.textItem(text: "Third")
        
        try storageService.saveClipboardItem(item1)
        try storageService.saveClipboardItem(item2)
        try storageService.saveClipboardItem(item3)
        
        // Fetch current order (should be item3, item2, item1 due to saveClipboardItem shifting)
        var items = try storageService.fetchClipboardItems()
        XCTAssertEqual(items.count, 3)
        
        // Reverse the order
        let reversed = Array(items.reversed())
        try storageService.updateClipboardItemOrder(reversed)
        
        // Fetch again
        items = try storageService.fetchClipboardItems()
        
        // Verify order matches what we set
        XCTAssertEqual(items[0].textContent, reversed[0].textContent)
        XCTAssertEqual(items[1].textContent, reversed[1].textContent)
        XCTAssertEqual(items[2].textContent, reversed[2].textContent)
    }
    
    func testUpdateClipboardItemOrderAssignsSortOrders() throws {
        let items = TestData.textItems(count: 3)
        for item in items {
            try storageService.saveClipboardItem(item)
        }
        
        var fetched = try storageService.fetchClipboardItems()
        
        // Reorder
        try storageService.updateClipboardItemOrder(fetched)
        
        // Verify sortOrder values
        fetched = try storageService.fetchClipboardItems()
        XCTAssertEqual(fetched[0].sortOrder, 0)
        XCTAssertEqual(fetched[1].sortOrder, 1)
        XCTAssertEqual(fetched[2].sortOrder, 2)
    }
    
    // MARK: - Snippet File Stack Tests
    
    func testCreateSnippetFromFileStackItem() throws {
        // Create a file stack clipboard item with actual files
        let itemId = UUID()
        var paths: [String] = []
        
        for i in 0..<3 {
            let data = Data("File \(i) content".utf8)
            let path = try storageService.saveMediaForStack(data: data, itemId: itemId, index: i, originalFilename: "file\(i).txt")
            paths.append(path)
        }
        
        let item = ClipboardItem(
            id: itemId,
            contentType: .fileStack,
            mediaPaths: paths
        )
        try storageService.saveClipboardItem(item)
        
        // Create snippet from item
        let snippet = try storageService.createSnippetFromItem(item, name: "File Stack Snippet")
        
        XCTAssertEqual(snippet.name, "File Stack Snippet")
        XCTAssertEqual(snippet.contentType, .fileStack)
        XCTAssertNotNil(snippet.mediaPaths)
        XCTAssertEqual(snippet.mediaPaths?.count, 3)
        
        // Verify snippet files exist and are copies (different paths)
        for snippetPath in snippet.mediaPaths ?? [] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: snippetPath))
            XCTAssertTrue(snippetPath.contains("snippet_"))
        }
    }
    
    func testExtractOriginalFilename() throws {
        // Test via createSnippetFromItem which uses extractOriginalFilename internally
        let itemId = UUID()
        let originalFilename = "my_document.pdf"
        let data = Data("PDF content".utf8)
        let mediaPath = try storageService.saveMedia(data: data, type: .file, itemId: itemId, originalFilename: originalFilename)
        
        let item = ClipboardItem(
            id: itemId,
            contentType: .file,
            mediaPath: mediaPath
        )
        try storageService.saveClipboardItem(item)
        
        let snippet = try storageService.createSnippetFromItem(item, name: "Doc Snippet")
        
        // Snippet path should contain the original filename
        XCTAssertNotNil(snippet.mediaPath)
        XCTAssertTrue(snippet.mediaPath!.contains(originalFilename))
    }
    
    // MARK: - Storage Size Calculation Tests
    
    func testCalculateSnippetsStorageSize() throws {
        // Create snippets with media
        for i in 0..<3 {
            let itemId = UUID()
            let data = TestImageData.data(ofSize: 500)
            let mediaPath = try storageService.saveMedia(data: data, type: .image, itemId: itemId)
            
            var snippet = TestData.snippet(name: "Snippet \(i)")
            snippet.mediaPath = mediaPath
            try storageService.saveSnippet(snippet)
        }
        
        let size = storageService.calculateSnippetsStorageSize()
        
        // Should be at least 1500 bytes (3 x 500)
        XCTAssertGreaterThanOrEqual(size, 1500)
    }
    
    func testCalculateClipboardItemsStorageSizeExcludesSnippets() throws {
        // Create clipboard item with media
        let clipboardItemId = UUID()
        let clipboardData = TestImageData.data(ofSize: 1000)
        let clipboardMediaPath = try storageService.saveMedia(data: clipboardData, type: .image, itemId: clipboardItemId)
        try storageService.saveClipboardItem(ClipboardItem(
            id: clipboardItemId,
            contentType: .image,
            mediaPath: clipboardMediaPath
        ))
        
        // Create snippet with media
        let snippetId = UUID()
        let snippetData = TestImageData.data(ofSize: 2000)
        let snippetMediaPath = try storageService.saveMedia(data: snippetData, type: .image, itemId: snippetId)
        var snippet = TestData.snippet(name: "Test")
        snippet.mediaPath = snippetMediaPath
        try storageService.saveSnippet(snippet)
        
        let clipboardSize = storageService.calculateClipboardItemsStorageSize()
        let snippetSize = storageService.calculateSnippetsStorageSize()
        
        // Clipboard size should be around 1000 (not include snippet's 2000)
        XCTAssertGreaterThanOrEqual(clipboardSize, 1000)
        XCTAssertLessThan(clipboardSize, 1500) // Should not include snippet
        
        // Snippet size should be around 2000
        XCTAssertGreaterThanOrEqual(snippetSize, 2000)
    }
    
    // MARK: - regenerateVideoThumbnails Tests
    
    func testRegenerateVideoThumbnailsReturnsZeroWhenNoVideoItems() async throws {
        // Create non-video items only
        try storageService.saveClipboardItem(TestData.textItem(text: "Text"))
        try storageService.saveClipboardItem(TestData.imageItem())
        try storageService.saveSnippet(TestData.snippet(name: "Text Snippet"))
        
        let thumbnailService = ThumbnailService()
        let count = try await storageService.regenerateVideoThumbnails(
            thumbnailService: thumbnailService,
            maxSize: 500
        )
        
        XCTAssertEqual(count, 0)
    }
    
    func testRegenerateVideoThumbnailsSkipsItemsWithoutMediaPath() async throws {
        // Create video item without media path
        let item = ClipboardItem(
            id: UUID(),
            contentType: .video,
            mediaPath: nil,
            thumbnailPath: nil
        )
        try storageService.saveClipboardItem(item)
        
        let thumbnailService = ThumbnailService()
        let count = try await storageService.regenerateVideoThumbnails(
            thumbnailService: thumbnailService,
            maxSize: 500
        )
        
        XCTAssertEqual(count, 0)
    }
    
    func testRegenerateVideoThumbnailsClearsThumbnailPathOnFailure() async throws {
        // Create video item with invalid media path (thumbnail generation will fail)
        let item = ClipboardItem(
            id: UUID(),
            contentType: .video,
            mediaPath: "/nonexistent/video.mp4",
            thumbnailPath: "/old/thumbnail.png"
        )
        try storageService.saveClipboardItem(item)
        
        let thumbnailService = ThumbnailService()
        let count = try await storageService.regenerateVideoThumbnails(
            thumbnailService: thumbnailService,
            maxSize: 500
        )
        
        // Count is 0 because generation failed
        XCTAssertEqual(count, 0)
        
        // thumbnailPath should be cleared
        let fetched = try storageService.fetchClipboardItems()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertNil(fetched.first?.thumbnailPath)
    }
    
    func testRegenerateVideoThumbnailsDeletesOldThumbnail() async throws {
        // Create a temporary thumbnail file
        let thumbnailPath = tempDir.url.appendingPathComponent("old_thumb.png").path
        try TestImageData.minimalPNG.write(to: URL(fileURLWithPath: thumbnailPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbnailPath))
        
        // Create video item with the thumbnail
        let item = ClipboardItem(
            id: UUID(),
            contentType: .video,
            mediaPath: "/nonexistent/video.mp4",
            thumbnailPath: thumbnailPath
        )
        try storageService.saveClipboardItem(item)
        
        let thumbnailService = ThumbnailService()
        _ = try await storageService.regenerateVideoThumbnails(
            thumbnailService: thumbnailService,
            maxSize: 500
        )
        
        // Old thumbnail should be deleted
        XCTAssertFalse(FileManager.default.fileExists(atPath: thumbnailPath))
    }
    
    func testRegenerateVideoThumbnailsProcessesSnippets() async throws {
        // Create video snippet with invalid media path
        let snippet = Snippet(
            id: UUID(),
            name: "Video Snippet",
            contentType: .video,
            mediaPath: "/nonexistent/snippet_video.mp4",
            thumbnailPath: "/old/snippet_thumb.png",
            sortOrder: 0
        )
        try storageService.saveSnippet(snippet)
        
        let thumbnailService = ThumbnailService()
        _ = try await storageService.regenerateVideoThumbnails(
            thumbnailService: thumbnailService,
            maxSize: 500
        )
        
        // Snippet's thumbnailPath should be cleared (generation failed)
        let fetched = try storageService.fetchSnippets()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertNil(fetched.first?.thumbnailPath)
    }
    
    func testRegenerateVideoThumbnailsProcessesBothItemsAndSnippets() async throws {
        // Create video clipboard item
        let clipboardItem = ClipboardItem(
            id: UUID(),
            contentType: .video,
            mediaPath: "/nonexistent/video1.mp4",
            thumbnailPath: "/old/thumb1.png"
        )
        try storageService.saveClipboardItem(clipboardItem)
        
        // Create video snippet
        let snippet = Snippet(
            id: UUID(),
            name: "Video Snippet",
            contentType: .video,
            mediaPath: "/nonexistent/video2.mp4",
            thumbnailPath: "/old/thumb2.png",
            sortOrder: 0
        )
        try storageService.saveSnippet(snippet)
        
        // Also create non-video items that should be ignored
        try storageService.saveClipboardItem(TestData.textItem())
        try storageService.saveSnippet(TestData.snippet(name: "Text Snippet"))
        
        let thumbnailService = ThumbnailService()
        _ = try await storageService.regenerateVideoThumbnails(
            thumbnailService: thumbnailService,
            maxSize: 500
        )
        
        // Both video items should have thumbnailPath cleared
        let clipboardItems = try storageService.fetchClipboardItems()
        let videoClipboardItem = clipboardItems.first { $0.contentType == .video }
        XCTAssertNil(videoClipboardItem?.thumbnailPath)
        
        let snippets = try storageService.fetchSnippets()
        let videoSnippet = snippets.first { $0.contentType == .video }
        XCTAssertNil(videoSnippet?.thumbnailPath)
        
        // Non-video items should be unchanged (2 clipboard items total, 2 snippets total)
        XCTAssertEqual(clipboardItems.count, 2)
        XCTAssertEqual(snippets.count, 2)
    }
    
    func testRegenerateVideoThumbnailsFiltersOnlyVideoContentType() async throws {
        // Create items of various types
        try storageService.saveClipboardItem(TestData.textItem())
        try storageService.saveClipboardItem(TestData.imageItem())
        try storageService.saveClipboardItem(TestData.fileItem())
        try storageService.saveClipboardItem(TestData.videoItem(mediaPath: "/fake/video.mp4"))
        
        let thumbnailService = ThumbnailService()
        
        // This should only process the video item
        let count = try await storageService.regenerateVideoThumbnails(
            thumbnailService: thumbnailService,
            maxSize: 500
        )
        
        // Video item processed but failed (no valid video file), so count is 0
        XCTAssertEqual(count, 0)
        
        // Verify only the video item had its thumbnail cleared
        let items = try storageService.fetchClipboardItems()
        let videoItem = items.first { $0.contentType == .video }
        let imageItem = items.first { $0.contentType == .image }
        
        XCTAssertNil(videoItem?.thumbnailPath)
        // Image item should retain its thumbnail path (wasn't processed)
        XCTAssertNotNil(imageItem?.thumbnailPath)
    }
    
    // MARK: - Snippet Download State Tests
    
    func testCreateDownloadingSnippetSetsDownloadingState() throws {
        let item = TestData.textItem(text: "Cloud content")
        try storageService.saveClipboardItem(item)
        
        let snippet = try storageService.createDownloadingSnippet(from: item, name: "Downloading", fileCount: 3)
        
        XCTAssertTrue(snippet.isDownloading)
        XCTAssertNil(snippet.downloadError)
        XCTAssertEqual(snippet.downloadFileCount, 3)
    }
    
    func testCreateDownloadingSnippetSetsCloudPathForSingleFile() throws {
        let item = ClipboardItem(
            contentType: .file,
            textContent: "cloud_file.txt",
            mediaPath: "/Users/test/iCloud/cloud_file.txt"
        )
        try storageService.saveClipboardItem(item)
        
        let snippet = try storageService.createDownloadingSnippet(from: item, name: "Cloud File", fileCount: 1)
        
        XCTAssertEqual(snippet.cloudPath, "/Users/test/iCloud/cloud_file.txt")
        XCTAssertNil(snippet.mediaPath)  // Should be nil until download completes
    }
    
    func testCreateDownloadingSnippetSetsCloudPathsForFileStack() throws {
        let cloudPaths = ["/cloud/file1.txt", "/cloud/file2.txt"]
        let item = ClipboardItem(
            contentType: .fileStack,
            mediaPaths: cloudPaths
        )
        try storageService.saveClipboardItem(item)
        
        let snippet = try storageService.createDownloadingSnippet(from: item, name: "Cloud Stack", fileCount: 2)
        
        XCTAssertEqual(snippet.cloudPaths, cloudPaths)
        XCTAssertNil(snippet.mediaPaths)  // Should be nil until download completes
    }
    
    func testCompleteSnippetDownloadClearsDownloadingState() throws {
        let item = TestData.textItem(text: "Content")
        try storageService.saveClipboardItem(item)
        
        let snippet = try storageService.createDownloadingSnippet(from: item, name: "Test", fileCount: 1)
        XCTAssertTrue(snippet.isDownloading)
        
        try storageService.completeSnippetDownload(snippet.id)
        
        let updated = try storageService.fetchSnippet(id: snippet.id)
        XCTAssertFalse(updated!.isDownloading)
    }
    
    func testCompleteSnippetDownloadThrowsForNonexistentSnippet() {
        let fakeId = UUID()
        
        XCTAssertThrowsError(try storageService.completeSnippetDownload(fakeId))
    }
    
    func testCompleteSnippetDownloadAsyncClearsDownloadingState() async throws {
        let item = TestData.textItem(text: "Async content")
        try storageService.saveClipboardItem(item)
        
        let snippet = try storageService.createDownloadingSnippet(from: item, name: "Async Test", fileCount: 1)
        XCTAssertTrue(snippet.isDownloading)
        
        try await storageService.completeSnippetDownloadAsync(snippet.id)
        
        let updated = try storageService.fetchSnippet(id: snippet.id)
        XCTAssertFalse(updated!.isDownloading)
    }
    
    func testMarkSnippetDownloadFailedSetsError() throws {
        let item = TestData.textItem()
        try storageService.saveClipboardItem(item)
        
        let snippet = try storageService.createDownloadingSnippet(from: item, name: "Failing", fileCount: 1)
        
        try storageService.markSnippetDownloadFailed(snippet.id, error: "Network timeout")
        
        let updated = try storageService.fetchSnippet(id: snippet.id)
        XCTAssertFalse(updated!.isDownloading)
        XCTAssertEqual(updated!.downloadError, "Network timeout")
    }
    
    func testClearSnippetDownloadErrorResetsError() throws {
        let item = TestData.textItem()
        try storageService.saveClipboardItem(item)
        
        let snippet = try storageService.createDownloadingSnippet(from: item, name: "Error Clear", fileCount: 1)
        try storageService.markSnippetDownloadFailed(snippet.id, error: "Error")
        
        try storageService.clearSnippetDownloadError(snippet.id)
        
        let updated = try storageService.fetchSnippet(id: snippet.id)
        XCTAssertNil(updated!.downloadError)
    }
    
    func testUpdateSnippetDownloadProgressUpdatesIndices() throws {
        let item = TestData.textItem()
        try storageService.saveClipboardItem(item)
        
        let snippet = try storageService.createDownloadingSnippet(from: item, name: "Progress", fileCount: 5)
        
        try storageService.updateSnippetDownloadProgress(snippet.id, currentIndex: 3, totalFiles: 5)
        
        let updated = try storageService.fetchSnippet(id: snippet.id)
        XCTAssertEqual(updated!.currentDownloadIndex, 3)
        XCTAssertEqual(updated!.downloadFileCount, 5)
    }
    
    func testDeleteIncompleteDownloadsRemovesDownloadingSnippets() throws {
        let item1 = TestData.textItem(text: "Item 1")
        let item2 = TestData.textItem(text: "Item 2")
        try storageService.saveClipboardItem(item1)
        try storageService.saveClipboardItem(item2)
        
        // Create one downloading snippet
        _ = try storageService.createDownloadingSnippet(from: item1, name: "Incomplete", fileCount: 1)
        
        // Create one completed snippet
        let completeSnippet = try storageService.createSnippetFromItem(item2, name: "Complete")
        
        XCTAssertEqual(storageService.getSnippetCount(), 2)
        
        let deletedCount = try storageService.deleteIncompleteDownloads()
        
        XCTAssertEqual(deletedCount, 1)
        XCTAssertEqual(storageService.getSnippetCount(), 1)
        
        // The complete snippet should still exist
        let remaining = try storageService.fetchSnippets()
        XCTAssertEqual(remaining.first?.name, completeSnippet.name)
    }
    
    func testDeleteIncompleteDownloadsReturnsZeroWhenNoneIncomplete() throws {
        // Create only complete snippets
        try storageService.saveSnippet(TestData.snippet(name: "Complete 1"))
        try storageService.saveSnippet(TestData.snippet(name: "Complete 2"))
        
        let deletedCount = try storageService.deleteIncompleteDownloads()
        
        XCTAssertEqual(deletedCount, 0)
        XCTAssertEqual(storageService.getSnippetCount(), 2)
    }
    
    // MARK: - fetchSnippet by ID Tests
    
    func testFetchSnippetByIdReturnsSnippet() throws {
        let snippet = TestData.snippet(name: "Find Me")
        try storageService.saveSnippet(snippet)
        
        let found = try storageService.fetchSnippet(id: snippet.id)
        
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "Find Me")
    }
    
    func testFetchSnippetByIdReturnsNilForNonexistent() throws {
        let found = try storageService.fetchSnippet(id: UUID())
        
        XCTAssertNil(found)
    }
    
    // MARK: - deleteSnippet by ID Tests
    
    func testDeleteSnippetByIdRemovesSnippet() throws {
        let snippet = TestData.snippet(name: "Delete Me")
        try storageService.saveSnippet(snippet)
        
        XCTAssertEqual(storageService.getSnippetCount(), 1)
        
        try storageService.deleteSnippet(id: snippet.id)
        
        XCTAssertEqual(storageService.getSnippetCount(), 0)
    }
    
    func testDeleteSnippetByIdDoesNotThrowForNonexistent() throws {
        // Should not throw for non-existent ID
        try storageService.deleteSnippet(id: UUID())
    }
    
    // MARK: - wipeAllData Tests
    
    func testWipeAllDataClearsClipboardItems() throws {
        for i in 0..<5 {
            try storageService.saveClipboardItem(TestData.textItem(text: "Item \(i)"))
        }
        XCTAssertEqual(try storageService.getClipboardItemCount(), 5)
        
        try storageService.wipeAllData()
        
        XCTAssertEqual(try storageService.getClipboardItemCount(), 0)
    }
    
    func testWipeAllDataClearsSnippets() throws {
        for i in 0..<3 {
            try storageService.saveSnippet(TestData.snippet(name: "Snippet \(i)"))
        }
        XCTAssertEqual(storageService.getSnippetCount(), 3)
        
        try storageService.wipeAllData()
        
        XCTAssertEqual(storageService.getSnippetCount(), 0)
    }
    
    func testWipeAllDataClearsBothItemsAndSnippets() throws {
        try storageService.saveClipboardItem(TestData.textItem())
        try storageService.saveSnippet(TestData.snippet(name: "Test"))
        
        try storageService.wipeAllData()
        
        XCTAssertEqual(try storageService.getClipboardItemCount(), 0)
        XCTAssertEqual(storageService.getSnippetCount(), 0)
    }
}
