import XCTest
import GRDB
@testable import ClipboardMenu

/// Integration tests that verify multiple services working together correctly
@MainActor
final class IntegrationTests: XCTestCase {
    
    var tempDir: TempDirectory!
    var storageService: StorageService!
    var preferencesService: PreferencesService!
    var testDefaults: UserDefaults!
    
    override func setUp() async throws {
        tempDir = try TempDirectory()
        storageService = StorageService(baseURL: tempDir.url, inMemory: true)
        try storageService.initialize()
        
        let suiteName = "com.clipboardmenu.integration.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        preferencesService = PreferencesService(defaults: testDefaults)
    }
    
    override func tearDown() async throws {
        storageService = nil
        preferencesService = nil
        testDefaults = nil
        tempDir?.cleanup()
        tempDir = nil
    }
    
    // MARK: - Storage + Preferences Integration
    
    func testCleanupRespectsPreferencesItemLimit() throws {
        // Set a low item limit
        preferencesService.maxHistoryItems = 5
        
        // Add more items than the limit
        for i in 0..<10 {
            let item = TestData.textItem(
                text: "Item \(i)",
                createdAt: Date(timeIntervalSinceNow: Double(-i * 60))
            )
            try storageService.saveClipboardItem(item)
        }
        
        XCTAssertEqual(storageService.getClipboardItemCount(), 10)
        
        // Run cleanup with preferences limit
        storageService.runCleanup(
            maxItems: preferencesService.maxHistoryItems,
            maxStorageBytes: preferencesService.maxStorageBytes
        )
        
        XCTAssertEqual(storageService.getClipboardItemCount(), 5)
    }
    
    func testCleanupRespectsPreferencesStorageLimit() throws {
        // Set a low storage limit (5KB)
        preferencesService.maxStorageMB = 1 // We'll use maxStorageBytes directly
        
        // Create items with media files
        for i in 0..<5 {
            let itemId = UUID()
            let data = TestImageData.data(ofSize: 2000) // 2KB each = 10KB total
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
        XCTAssertGreaterThanOrEqual(initialSize, 10000)
        
        // Run cleanup with 5KB limit
        storageService.runCleanup(maxItems: Int.max, maxStorageBytes: 5000)
        
        let finalSize = storageService.calculateClipboardItemsStorageSize()
        XCTAssertLessThanOrEqual(finalSize, 5000)
    }
    
    // MARK: - Clipboard Item to Snippet Workflow
    
    func testCompleteSnippetCreationWorkflow() throws {
        // 1. Create a clipboard item with text
        let textItem = TestData.textItem(text: "Important code snippet")
        try storageService.saveClipboardItem(textItem)
        
        // 2. Fetch the item
        let items = try storageService.fetchClipboardItems()
        XCTAssertEqual(items.count, 1)
        
        // 3. Create snippet from item
        let snippet = try storageService.createSnippetFromItem(items.first!, name: "My Snippet")
        
        // 4. Verify snippet was created correctly
        XCTAssertEqual(snippet.name, "My Snippet")
        XCTAssertEqual(snippet.textContent, "Important code snippet")
        XCTAssertEqual(snippet.contentType, .text)
        
        // 5. Fetch snippets to verify persistence
        let snippets = try storageService.fetchSnippets()
        XCTAssertEqual(snippets.count, 1)
        XCTAssertEqual(snippets.first?.name, "My Snippet")
    }
    
    func testSnippetCreationWithImageCopiesFile() throws {
        // 1. Create and save an image to storage
        let itemId = UUID()
        let imageData = TestImageData.minimalPNG
        let mediaPath = try storageService.saveMedia(data: imageData, type: .image, itemId: itemId)
        
        // 2. Create clipboard item with image
        let imageItem = ClipboardItem(
            id: itemId,
            contentType: .image,
            mediaPath: mediaPath
        )
        try storageService.saveClipboardItem(imageItem)
        
        // 3. Create snippet from image item
        let snippet = try storageService.createSnippetFromItem(imageItem, name: "Image Snippet")
        
        // 4. Verify snippet has its own copy of the media file
        XCTAssertNotNil(snippet.mediaPath)
        XCTAssertNotEqual(snippet.mediaPath, imageItem.mediaPath)
        XCTAssertTrue(snippet.mediaPath?.contains("snippet_") ?? false)
        
        // 5. Verify both files exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: mediaPath))
        if let snippetPath = snippet.mediaPath {
            XCTAssertTrue(FileManager.default.fileExists(atPath: snippetPath))
        }
    }
    
    // MARK: - Deduplication Workflow
    
    func testTextDeduplicationUpdatesTimestamp() throws {
        // 1. Create initial item with very old timestamp
        let oldTimestamp = Date(timeIntervalSince1970: 1000)
        let item1 = TestData.textItem(text: "Duplicate text", createdAt: oldTimestamp)
        try storageService.saveClipboardItem(item1)
        
        // 2. Create more items with explicit timestamps to ensure ordering
        let item2 = TestData.textItem(text: "Other text 1", createdAt: Date(timeIntervalSince1970: 2000))
        let item3 = TestData.textItem(text: "Other text 2", createdAt: Date(timeIntervalSince1970: 3000))
        try storageService.saveClipboardItem(item2)
        try storageService.saveClipboardItem(item3)
        
        // 3. Verify the duplicate item has the old timestamp before moving
        let beforeMove = try storageService.fetchClipboardItems().first { $0.textContent == "Duplicate text" }
        XCTAssertEqual(beforeMove?.createdAt.timeIntervalSince1970 ?? 0, 1000, accuracy: 1)
        
        // 4. Simulate copying the same text again - this updates createdAt to now
        let moved = try storageService.moveExistingItemToTop(
            textContent: "Duplicate text",
            mediaPath: nil,
            contentType: .text
        )
        
        XCTAssertTrue(moved)
        
        // 5. Verify only 3 items exist (no duplicate created)
        let items = try storageService.fetchClipboardItems()
        XCTAssertEqual(items.count, 3)
        
        // 6. Verify the duplicate's timestamp was updated (is now much more recent)
        let afterMove = items.first { $0.textContent == "Duplicate text" }
        XCTAssertNotNil(afterMove)
        XCTAssertGreaterThan(afterMove?.createdAt ?? Date.distantPast, Date(timeIntervalSince1970: 3000))
        
        // 7. Verify it's now the most recent by createdAt
        let mostRecent = try storageService.getMostRecentItem()
        XCTAssertEqual(mostRecent?.textContent, "Duplicate text")
    }
    
    func testMoveItemToTopUpdatesSortOrder() throws {
        // 1. Create initial items
        try storageService.saveClipboardItem(TestData.textItem(text: "First"))
        try storageService.saveClipboardItem(TestData.textItem(text: "Second"))
        try storageService.saveClipboardItem(TestData.textItem(text: "Third"))
        
        // Order should be: Third (0), Second (1), First (2)
        var items = try storageService.fetchClipboardItems()
        XCTAssertEqual(items[0].textContent, "Third")
        XCTAssertEqual(items[2].textContent, "First")
        
        // 2. Move "First" to top using moveItemToTop
        let firstItem = items.first { $0.textContent == "First" }!
        try storageService.moveItemToTop(firstItem)
        
        // 3. Verify new order: First (0), Third (1), Second (2)
        items = try storageService.fetchClipboardItems()
        XCTAssertEqual(items[0].textContent, "First")
        XCTAssertEqual(items[0].sortOrder, 0)
    }
    
    // MARK: - File Reference Cleanup Workflow
    
    func testInvalidFileReferenceCleanupOnLoad() throws {
        // 1. Create a temp file in system temp dir (not in ClipboardMenu folder)
        // to simulate an external file reference
        let systemTempDir = FileManager.default.temporaryDirectory
        let tempFile = systemTempDir.appendingPathComponent("external_file_\(UUID().uuidString).txt")
        try "Content".write(to: tempFile, atomically: true, encoding: .utf8)
        
        // 2. Create clipboard item referencing external file
        // Path must NOT contain "ClipboardMenu" to be considered a file reference
        let item = ClipboardItem(
            id: UUID(),
            contentType: .file,
            mediaPath: tempFile.path
        )
        try storageService.saveClipboardItem(item)
        
        XCTAssertEqual(storageService.getClipboardItemCount(), 1)
        
        // Verify it's treated as a file reference
        let fetchedItem = try storageService.fetchClipboardItems().first
        XCTAssertTrue(fetchedItem?.isFileReference ?? false)
        
        // 3. Delete the external file (simulating user deleting it)
        try FileManager.default.removeItem(at: tempFile)
        
        // 4. Run invalid reference cleanup (like app does on load)
        let removed = try storageService.removeInvalidFileReferences()
        
        // 5. Verify item was removed
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(storageService.getClipboardItemCount(), 0)
    }
    
    // MARK: - Snippet Ordering Workflow
    
    func testSnippetReorderingPersists() throws {
        // 1. Create multiple snippets
        let s1 = TestData.snippet(name: "First", sortOrder: 0)
        let s2 = TestData.snippet(name: "Second", sortOrder: 1)
        let s3 = TestData.snippet(name: "Third", sortOrder: 2)
        
        try storageService.saveSnippet(s1)
        try storageService.saveSnippet(s2)
        try storageService.saveSnippet(s3)
        
        // 2. Fetch and verify initial order
        var snippets = try storageService.fetchSnippets()
        XCTAssertEqual(snippets.map { $0.name }, ["First", "Second", "Third"])
        
        // 3. Reorder (move Third to top)
        let reordered = [snippets[2], snippets[0], snippets[1]] // Third, First, Second
        try storageService.updateSnippetOrder(reordered)
        
        // 4. Fetch again and verify new order
        snippets = try storageService.fetchSnippets()
        XCTAssertEqual(snippets.map { $0.name }, ["Third", "First", "Second"])
    }
    
    // MARK: - Full Workflow Tests
    
    func testClearHistoryPreservesSnippets() throws {
        // 1. Create clipboard items
        for i in 0..<5 {
            try storageService.saveClipboardItem(TestData.textItem(text: "Item \(i)"))
        }
        
        // 2. Create snippets
        let snippet1 = TestData.snippet(name: "Preserved 1")
        let snippet2 = TestData.snippet(name: "Preserved 2")
        try storageService.saveSnippet(snippet1)
        try storageService.saveSnippet(snippet2)
        
        XCTAssertEqual(storageService.getClipboardItemCount(), 5)
        XCTAssertEqual(storageService.getSnippetCount(), 2)
        
        // 3. Clear history by setting item limit to 0
        storageService.runCleanup(maxItems: 0, maxStorageBytes: 0)
        
        // 4. Verify history cleared but snippets preserved
        XCTAssertEqual(storageService.getClipboardItemCount(), 0)
        XCTAssertEqual(storageService.getSnippetCount(), 2)
        
        let snippets = try storageService.fetchSnippets()
        XCTAssertTrue(snippets.contains { $0.name == "Preserved 1" })
        XCTAssertTrue(snippets.contains { $0.name == "Preserved 2" })
    }
}
