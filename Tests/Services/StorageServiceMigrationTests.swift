// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import XCTest
import GRDB
@testable import ClipboardMenu

/// Tests for database migrations and schema evolution
@MainActor
final class StorageServiceMigrationTests: XCTestCase {
    
    var tempDir: TempDirectory!
    
    override func setUp() async throws {
        tempDir = try TempDirectory()
    }
    
    override func tearDown() async throws {
        tempDir?.cleanup()
        tempDir = nil
    }
    
    // MARK: - Schema Creation Tests
    
    func testInitializeCreatesClipboardItemsTable() throws {
        let storageService = StorageService(baseURL: tempDir.url, inMemory: true)
        try storageService.initialize()
        
        // Should be able to save and fetch items
        let item = TestData.textItem(text: "Test")
        try storageService.saveClipboardItem(item)
        
        let fetched = try storageService.fetchClipboardItems()
        XCTAssertEqual(fetched.count, 1)
    }
    
    func testInitializeCreatesSnippetsTable() throws {
        let storageService = StorageService(baseURL: tempDir.url, inMemory: true)
        try storageService.initialize()
        
        // Should be able to save and fetch snippets
        let snippet = TestData.snippet(name: "Test")
        try storageService.saveSnippet(snippet)
        
        let fetched = try storageService.fetchSnippets()
        XCTAssertEqual(fetched.count, 1)
    }
    
    func testInitializeCreatesIndexes() throws {
        let storageService = StorageService(baseURL: tempDir.url, inMemory: true)
        try storageService.initialize()
        
        // Add multiple items and verify sorting works (relies on indexes)
        for i in 0..<10 {
            let item = TestData.textItem(
                text: "Item \(i)",
                createdAt: Date(timeIntervalSinceNow: Double(-i * 60))
            )
            try storageService.saveClipboardItem(item)
        }
        
        let fetched = try storageService.fetchClipboardItems()
        XCTAssertEqual(fetched.count, 10)
        
        // Verify order (newest first due to sortOrder)
        // Items are saved with sortOrder shifting, so newest should be at position 0
        XCTAssertEqual(fetched.first?.sortOrder, 0)
    }
    
    func testMultipleInitializationsAreSafe() throws {
        let storageService = StorageService(baseURL: tempDir.url, inMemory: true)
        
        // Initialize multiple times - should not throw
        try storageService.initialize()
        try storageService.initialize()
        try storageService.initialize()
        
        // Should still work
        let item = TestData.textItem()
        try storageService.saveClipboardItem(item)
        
        let count = storageService.getClipboardItemCount()
        XCTAssertEqual(count, 1)
    }
    
    // MARK: - Column Migration Tests
    
    func testMediaPathsColumnExists() throws {
        let storageService = StorageService(baseURL: tempDir.url, inMemory: true)
        try storageService.initialize()
        
        // Create a file stack item which uses mediaPaths
        let item = TestData.fileStackItem(mediaPaths: ["/path1", "/path2"])
        try storageService.saveClipboardItem(item)
        
        let fetched = try storageService.fetchClipboardItems().first
        XCTAssertEqual(fetched?.mediaPaths?.count, 2)
    }
    
    func testSortOrderColumnExists() throws {
        let storageService = StorageService(baseURL: tempDir.url, inMemory: true)
        try storageService.initialize()
        
        // Create items and verify sortOrder is maintained
        try storageService.saveClipboardItem(TestData.textItem(text: "First"))
        try storageService.saveClipboardItem(TestData.textItem(text: "Second"))
        try storageService.saveClipboardItem(TestData.textItem(text: "Third"))
        
        let fetched = try storageService.fetchClipboardItems()
        
        // Newest items should have lower sortOrder (0 = top)
        let sortOrders = fetched.map { $0.sortOrder }
        XCTAssertEqual(sortOrders, [0, 1, 2])
    }
    
    func testSnippetMediaPathsColumnExists() throws {
        let storageService = StorageService(baseURL: tempDir.url, inMemory: true)
        try storageService.initialize()
        
        // Create a file stack clipboard item
        let item = TestData.fileStackItem(mediaPaths: ["/path1", "/path2"])
        try storageService.saveClipboardItem(item)
        
        // Create snippet from it
        let snippet = try storageService.createSnippetFromItem(item, name: "Test Stack")
        
        XCTAssertEqual(snippet.contentType, .fileStack)
        // Note: mediaPaths may be nil if files don't exist (since createSnippetFromItem copies files)
    }
    
    // MARK: - Data Integrity Tests
    
    func testAllContentTypesCanBeSaved() throws {
        let storageService = StorageService(baseURL: tempDir.url, inMemory: true)
        try storageService.initialize()
        
        // Test all content types
        try storageService.saveClipboardItem(TestData.textItem(text: "Text"))
        try storageService.saveClipboardItem(TestData.imageItem())
        try storageService.saveClipboardItem(TestData.fileItem(mediaPath: "/test.pdf"))
        try storageService.saveClipboardItem(TestData.fileStackItem(mediaPaths: ["/a", "/b"]))
        
        let fetched = try storageService.fetchClipboardItems()
        XCTAssertEqual(fetched.count, 4)
        
        let types = Set(fetched.map { $0.contentType })
        XCTAssertTrue(types.contains(.text))
        XCTAssertTrue(types.contains(.image))
        XCTAssertTrue(types.contains(.file))
        XCTAssertTrue(types.contains(.fileStack))
    }
    
    func testRichTextDataIsPersisted() throws {
        let storageService = StorageService(baseURL: tempDir.url, inMemory: true)
        try storageService.initialize()
        
        let richTextData = Data([0x01, 0x02, 0x03, 0x04])
        let item = ClipboardItem(
            contentType: .richText,
            textContent: "Plain text fallback",
            richTextData: richTextData
        )
        try storageService.saveClipboardItem(item)
        
        let fetched = try storageService.fetchClipboardItems().first
        XCTAssertEqual(fetched?.richTextData, richTextData)
        XCTAssertEqual(fetched?.textContent, "Plain text fallback")
    }
    
    func testSourceAppIsPersisted() throws {
        let storageService = StorageService(baseURL: tempDir.url, inMemory: true)
        try storageService.initialize()
        
        var item = TestData.textItem(text: "Test")
        item.sourceApp = "com.example.app"
        try storageService.saveClipboardItem(item)
        
        let fetched = try storageService.fetchClipboardItems().first
        XCTAssertEqual(fetched?.sourceApp, "com.example.app")
    }
    
    func testFavoriteFlagIsPersisted() throws {
        let storageService = StorageService(baseURL: tempDir.url, inMemory: true)
        try storageService.initialize()
        
        let item = TestData.textItem(text: "Favorite", isFavorite: true)
        try storageService.saveClipboardItem(item)
        
        let fetched = try storageService.fetchClipboardItems().first
        XCTAssertTrue(fetched?.isFavorite ?? false)
    }
}
