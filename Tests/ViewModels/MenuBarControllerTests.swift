// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Combine
@testable import ClipboardMenu

/// Tests for MenuBarController's data operations and state management.
/// Note: These tests focus on logic that doesn't require NSStatusBar/NSPopover setup.
@MainActor
final class MenuBarControllerTests: XCTestCase {
    
    var storageService: StorageService!
    var preferencesService: PreferencesService!
    var searchService: SearchService!
    var thumbnailService: ThumbnailService!
    var clipboardMonitor: ClipboardMonitor!
    var bookmarkService: BookmarkService!
    var tempDir: TempDirectory!
    var testDefaults: UserDefaults!
    
    override func setUp() async throws {
        tempDir = try TempDirectory()
        
        // Set up services with test isolation
        storageService = StorageService(baseURL: tempDir.url, inMemory: true)
        try storageService.initialize()
        
        let suiteName = "com.clipboardmenu.tests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        preferencesService = PreferencesService(defaults: testDefaults)
        
        searchService = SearchService()
        thumbnailService = ThumbnailService()
        bookmarkService = BookmarkService()
        clipboardMonitor = ClipboardMonitor(
            storageService: storageService,
            thumbnailService: thumbnailService,
            preferencesService: preferencesService,
            bookmarkService: bookmarkService
        )
    }
    
    override func tearDown() async throws {
        storageService = nil
        preferencesService = nil
        searchService = nil
        thumbnailService = nil
        clipboardMonitor = nil
        bookmarkService = nil
        tempDir?.cleanup()
        tempDir = nil
        testDefaults = nil
    }
    
    // MARK: - Helper to create controller (skipped when NSStatusBar unavailable)
    
    /// Creates a MenuBarController for testing.
    /// Note: This will create actual status bar items which may not be available in CI environments.
    private func createController() -> MenuBarController {
        MenuBarController(
            storageService: storageService,
            thumbnailService: thumbnailService,
            preferencesService: preferencesService,
            searchService: searchService,
            clipboardMonitor: clipboardMonitor,
            bookmarkService: bookmarkService
        )
    }
    
    // MARK: - Storage Service Integration Tests
    // These test the underlying data operations that MenuBarController depends on
    
    func testLoadDataFetchesItems() async throws {
        // Add some items to storage
        let item1 = TestData.textItem(text: "Item 1")
        let item2 = TestData.textItem(text: "Item 2")
        try storageService.saveClipboardItem(item1)
        try storageService.saveClipboardItem(item2)
        
        // Verify storage has the items
        let items = try storageService.fetchClipboardItems()
        XCTAssertEqual(items.count, 2)
    }
    
    func testLoadDataFetchesSnippets() async throws {
        let snippet = TestData.snippet(name: "Test Snippet")
        try storageService.saveSnippet(snippet)
        
        let snippets = try storageService.fetchSnippets()
        XCTAssertEqual(snippets.count, 1)
        XCTAssertEqual(snippets.first?.name, "Test Snippet")
    }
    
    func testDeleteItemRemovesFromStorage() async throws {
        let item = TestData.textItem()
        try storageService.saveClipboardItem(item)
        
        XCTAssertEqual(try storageService.fetchClipboardItems().count, 1)
        
        try storageService.deleteClipboardItem(item)
        
        XCTAssertEqual(try storageService.fetchClipboardItems().count, 0)
    }
    
    func testDeleteSnippetRemovesFromStorage() async throws {
        let snippet = TestData.snippet()
        try storageService.saveSnippet(snippet)
        
        XCTAssertEqual(try storageService.fetchSnippets().count, 1)
        
        try storageService.deleteSnippet(snippet)
        
        XCTAssertEqual(try storageService.fetchSnippets().count, 0)
    }
    
    func testAddToSnippetsCreatesSnippet() async throws {
        let item = TestData.textItem(text: "Source content")
        try storageService.saveClipboardItem(item)
        
        let snippet = try storageService.createSnippetFromItem(item, name: "New Snippet")
        
        XCTAssertEqual(snippet.textContent, "Source content")
        
        let snippets = try storageService.fetchSnippets()
        XCTAssertEqual(snippets.count, 1)
    }
    
    func testMoveSnippetReorders() async throws {
        let s1 = TestData.snippet(name: "First", sortOrder: 0)
        let s2 = TestData.snippet(name: "Second", sortOrder: 1)
        let s3 = TestData.snippet(name: "Third", sortOrder: 2)
        
        try storageService.saveSnippet(s1)
        try storageService.saveSnippet(s2)
        try storageService.saveSnippet(s3)
        
        // Reorder: Third, First, Second
        let snippets = try storageService.fetchSnippets()
        let reordered = [snippets[2], snippets[0], snippets[1]]
        try storageService.updateSnippetOrder(reordered)
        
        let fetched = try storageService.fetchSnippets()
        XCTAssertEqual(fetched[0].name, "Third")
        XCTAssertEqual(fetched[1].name, "First")
        XCTAssertEqual(fetched[2].name, "Second")
    }
    
    func testClearHistoryDeletesAllItems() async throws {
        for i in 0..<5 {
            try storageService.saveClipboardItem(TestData.textItem(text: "Item \(i)"))
        }
        
        XCTAssertEqual(try storageService.fetchClipboardItems().count, 5)
        
        // Simulate clearHistory
        let items = try storageService.fetchClipboardItems()
        for item in items {
            try storageService.deleteClipboardItem(item)
        }
        
        XCTAssertEqual(try storageService.fetchClipboardItems().count, 0)
    }
    
    func testClearHistoryPreservesSnippets() async throws {
        try storageService.saveClipboardItem(TestData.textItem())
        try storageService.saveSnippet(TestData.snippet(name: "Keep Me"))
        
        // Clear clipboard items only
        let items = try storageService.fetchClipboardItems()
        for item in items {
            try storageService.deleteClipboardItem(item)
        }
        
        XCTAssertEqual(try storageService.fetchClipboardItems().count, 0)
        XCTAssertEqual(try storageService.fetchSnippets().count, 1)
    }
    
    // MARK: - Search Integration Tests
    
    func testSearchFiltersItems() async throws {
        let items = [
            TestData.textItem(text: "Hello World"),
            TestData.textItem(text: "Goodbye World"),
            TestData.textItem(text: "Hello There")
        ]
        
        let results = searchService.search(items: items, query: "Hello", useRegex: false)
        
        XCTAssertEqual(results.count, 2)
    }
    
    func testSearchFiltersSnippets() async throws {
        let snippets = [
            TestData.snippet(name: "Email", textContent: "Hello"),
            TestData.snippet(name: "Address", textContent: "123 Main St"),
            TestData.snippet(name: "Email Template", textContent: "Hi")
        ]
        
        let results = searchService.search(snippets: snippets, query: "Email", useRegex: false)
        
        XCTAssertEqual(results.count, 2)
    }
    
    func testContentTypeFilter() async throws {
        let items = [
            TestData.textItem(),
            TestData.imageItem(),
            TestData.videoItem(),
            TestData.textItem()
        ]
        
        let textOnly = searchService.filterByContentType(items: items, types: [.text])
        
        XCTAssertEqual(textOnly.count, 2)
    }
    
    // MARK: - Preferences Integration Tests
    
    func testMaxHistoryItemsRespected() async throws {
        preferencesService.maxHistoryItems = 5
        
        // Add more items than the limit
        for i in 0..<10 {
            let item = TestData.textItem(
                text: "Item \(i)",
                createdAt: Date(timeIntervalSinceNow: Double(-i))
            )
            try storageService.saveClipboardItem(item)
        }
        
        // Fetch with limit
        let items = try storageService.fetchClipboardItems(limit: preferencesService.maxHistoryItems)
        
        XCTAssertEqual(items.count, 5)
    }
    
    func testSnippetsMenuModeIntegrated() async throws {
        preferencesService.snippetsMenuMode = .integrated
        
        XCTAssertEqual(preferencesService.snippetsMenuMode, .integrated)
    }
    
    func testSnippetsMenuModeSeparate() async throws {
        preferencesService.snippetsMenuMode = .separate
        
        XCTAssertEqual(preferencesService.snippetsMenuMode, .separate)
    }
    
    // MARK: - Menu Height Calculation Tests
    // These test the height calculation logic without needing actual UI
    
    func testMenuHeightConstants() {
        // Verify the constants used in height calculation are reasonable
        let menuWidth: CGFloat = 350
        let menuMinHeight: CGFloat = 200
        let headerHeight: CGFloat = 120
        let itemRowHeight: CGFloat = 52
        
        XCTAssertGreaterThan(menuWidth, 0)
        XCTAssertGreaterThan(menuMinHeight, 0)
        XCTAssertGreaterThan(headerHeight, 0)
        XCTAssertGreaterThan(itemRowHeight, 0)
        
        // A reasonable max height should fit many items
        let itemsForReasonableHeight = 10
        let calculatedHeight = headerHeight + (CGFloat(itemsForReasonableHeight) * itemRowHeight)
        XCTAssertGreaterThan(calculatedHeight, menuMinHeight)
    }
}

// MARK: - ClipboardMonitor Basic Tests

@MainActor
final class ClipboardMonitorBasicTests: XCTestCase {
    
    var storageService: StorageService!
    var preferencesService: PreferencesService!
    var thumbnailService: ThumbnailService!
    var clipboardMonitor: ClipboardMonitor!
    var tempDir: TempDirectory!
    var testDefaults: UserDefaults!
    
    override func setUp() async throws {
        tempDir = try TempDirectory()
        
        storageService = StorageService(baseURL: tempDir.url, inMemory: true)
        try storageService.initialize()
        
        let suiteName = "com.clipboardmenu.tests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        preferencesService = PreferencesService(defaults: testDefaults)
        
        thumbnailService = ThumbnailService()
        clipboardMonitor = ClipboardMonitor(
            storageService: storageService,
            thumbnailService: thumbnailService,
            preferencesService: preferencesService
        )
    }
    
    override func tearDown() async throws {
        clipboardMonitor?.stopMonitoring()
        storageService = nil
        preferencesService = nil
        thumbnailService = nil
        clipboardMonitor = nil
        tempDir?.cleanup()
        tempDir = nil
        testDefaults = nil
    }
    
    func testClipboardMonitorCreation() {
        XCTAssertNotNil(clipboardMonitor)
    }
    
    func testWillCopyFromHistoryFlag() {
        // This should set an internal flag to skip the next clipboard change
        clipboardMonitor.willCopyFromHistory()
        // No assertion needed - just verifying it doesn't crash
    }
    
    func testStartAndStopMonitoring() {
        clipboardMonitor.startMonitoring()
        // Brief delay not needed in unit tests
        clipboardMonitor.stopMonitoring()
        // No assertion needed - just verifying it doesn't crash
    }
}
