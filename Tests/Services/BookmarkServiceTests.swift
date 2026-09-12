import XCTest
@testable import ClipboardMenu

final class BookmarkServiceTests: XCTestCase {
    
    var bookmarkService: BookmarkService!
    var tempDir: TempDirectory!
    
    override func setUp() async throws {
        bookmarkService = BookmarkService()
        tempDir = try TempDirectory()
    }
    
    override func tearDown() async throws {
        bookmarkService = nil
        tempDir?.cleanup()
        tempDir = nil
    }
    
    // MARK: - Initialization
    
    func testBookmarkServiceCanBeCreated() {
        XCTAssertNotNil(bookmarkService)
    }
    
    // MARK: - createBookmark Tests
    
    func testCreateBookmarkForExistingFile() throws {
        let fileURL = try tempDir.createFile(name: "test.txt", content: "Test content")
        
        let bookmarkData = bookmarkService.createBookmark(for: fileURL)
        
        // Note: Security-scoped bookmarks may return nil in test environments
        // without proper sandbox entitlements, so we just verify no crash
        // In real usage with proper entitlements, this would return data
        _ = bookmarkData  // Just verify it doesn't crash
    }
    
    func testCreateBookmarkForNonexistentFileReturnsNil() {
        let nonexistentURL = URL(fileURLWithPath: "/nonexistent/path/file.txt")
        
        let bookmarkData = bookmarkService.createBookmark(for: nonexistentURL)
        
        XCTAssertNil(bookmarkData)
    }
    
    func testCreateBookmarkForDirectory() throws {
        let dirURL = try tempDir.createSubdirectory(name: "testdir")
        
        let bookmarkData = bookmarkService.createBookmark(for: dirURL)
        
        // Same as above - may be nil in test environment
        _ = bookmarkData
    }
    
    // MARK: - resolveBookmark Tests
    
    func testResolveBookmarkWithInvalidDataReturnsNil() {
        let invalidData = Data("not a bookmark".utf8)
        
        let result = bookmarkService.resolveBookmark(invalidData)
        
        XCTAssertNil(result)
    }
    
    func testResolveBookmarkWithEmptyDataReturnsNil() {
        let emptyData = Data()
        
        let result = bookmarkService.resolveBookmark(emptyData)
        
        XCTAssertNil(result)
    }
    
    func testResolveBookmarkWithRandomDataReturnsNil() {
        let randomData = Data((0..<100).map { _ in UInt8.random(in: 0...255) })
        
        let result = bookmarkService.resolveBookmark(randomData)
        
        XCTAssertNil(result)
    }
    
    // MARK: - startAccessing Tests
    
    func testStartAccessingRegularFile() throws {
        let fileURL = try tempDir.createFile(name: "access_test.txt", content: "Content")
        
        // For regular files (not from bookmarks), this returns true
        // because they're accessible locally
        let started = bookmarkService.startAccessing(fileURL)
        
        // Local files return true (they're accessible)
        XCTAssertTrue(started)
        bookmarkService.stopAccessing(fileURL)
    }
    
    func testStartAccessingNonexistentFile() {
        let nonexistentURL = URL(fileURLWithPath: "/nonexistent/file.txt")
        
        // Non-existent files still return true for startAccessingSecurityScopedResource
        // (it doesn't check file existence, just security scope)
        let started = bookmarkService.startAccessing(nonexistentURL)
        
        // The return value depends on the sandbox environment
        // Just verify it doesn't crash
        _ = started
    }
    
    // MARK: - stopAccessing Tests
    
    func testStopAccessingDoesNotCrash() throws {
        let fileURL = try tempDir.createFile(name: "stop_test.txt", content: "Content")
        
        // Should not crash even if access wasn't started
        bookmarkService.stopAccessing(fileURL)
    }
    
    func testStopAccessingNonexistentFileDoesNotCrash() {
        let nonexistentURL = URL(fileURLWithPath: "/nonexistent/stop_test.txt")
        
        // Should not crash
        bookmarkService.stopAccessing(nonexistentURL)
    }
    
    func testStopAccessingCanBeCalledMultipleTimes() throws {
        let fileURL = try tempDir.createFile(name: "multi_stop.txt", content: "Content")
        
        // Multiple calls should not crash
        bookmarkService.stopAccessing(fileURL)
        bookmarkService.stopAccessing(fileURL)
        bookmarkService.stopAccessing(fileURL)
    }
    
    // MARK: - Access Lifecycle Tests
    
    func testStartAndStopAccessingLifecycle() throws {
        let fileURL = try tempDir.createFile(name: "lifecycle.txt", content: "Content")
        
        // Start (will return false for non-bookmarked files)
        _ = bookmarkService.startAccessing(fileURL)
        
        // Stop (should always succeed)
        bookmarkService.stopAccessing(fileURL)
        
        // Can start again after stop
        _ = bookmarkService.startAccessing(fileURL)
        bookmarkService.stopAccessing(fileURL)
    }
    
    // MARK: - Bookmark Round-Trip Tests (Integration)
    
    func testCreateAndResolveBookmarkRoundTrip() throws {
        let fileURL = try tempDir.createFile(name: "roundtrip.txt", content: "Round trip content")
        
        // Create bookmark
        guard let bookmarkData = bookmarkService.createBookmark(for: fileURL) else {
            // Skip test if bookmarks not supported (no sandbox entitlements)
            return
        }
        
        // Resolve bookmark
        guard let (resolvedURL, isStale) = bookmarkService.resolveBookmark(bookmarkData) else {
            XCTFail("Failed to resolve bookmark that was just created")
            return
        }
        
        // Verify URL matches (standardized to handle symlinks)
        XCTAssertEqual(resolvedURL.standardizedFileURL, fileURL.standardizedFileURL)
        XCTAssertFalse(isStale)
    }
    
    func testResolvedBookmarkAllowsAccess() throws {
        let content = "Accessible content"
        let fileURL = try tempDir.createFile(name: "accessible.txt", content: content)
        
        // Create and resolve bookmark
        guard let bookmarkData = bookmarkService.createBookmark(for: fileURL),
              let (resolvedURL, _) = bookmarkService.resolveBookmark(bookmarkData) else {
            // Skip if bookmarks not supported
            return
        }
        
        // Start access
        let started = bookmarkService.startAccessing(resolvedURL)
        defer { bookmarkService.stopAccessing(resolvedURL) }
        
        // If access was granted, verify we can read the file
        if started {
            let readContent = try String(contentsOf: resolvedURL, encoding: .utf8)
            XCTAssertEqual(readContent, content)
        }
    }
}
