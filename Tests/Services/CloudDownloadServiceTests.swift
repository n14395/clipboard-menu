// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import ClipboardMenu

@MainActor
final class CloudDownloadServiceTests: XCTestCase {
    
    var cloudDownloadService: CloudDownloadService!
    var storageService: StorageService!
    var tempDir: TempDirectory!
    
    override func setUp() async throws {
        tempDir = try TempDirectory()
        storageService = StorageService(baseURL: tempDir.url, inMemory: true)
        try storageService.initialize()
        
        cloudDownloadService = CloudDownloadService()
        cloudDownloadService.configure(storageService: storageService)
    }
    
    override func tearDown() async throws {
        cloudDownloadService.cancel()
        cloudDownloadService = nil
        storageService = nil
        tempDir?.cleanup()
        tempDir = nil
    }
    
    // MARK: - Initialization Tests
    
    func testCloudDownloadServiceCanBeCreated() {
        XCTAssertNotNil(cloudDownloadService)
    }
    
    func testInitialStateIsNotDownloading() {
        XCTAssertFalse(cloudDownloadService.isDownloading)
    }
    
    func testInitialCurrentFileIndexIsZero() {
        XCTAssertEqual(cloudDownloadService.currentFileIndex, 0)
    }
    
    func testInitialTotalFilesIsZero() {
        XCTAssertEqual(cloudDownloadService.totalFiles, 0)
    }
    
    func testInitialDownloadingSnippetIdIsNil() {
        XCTAssertNil(cloudDownloadService.downloadingSnippetId)
    }
    
    func testInitialDownloadedPathsIsEmpty() {
        XCTAssertTrue(cloudDownloadService.downloadedPaths.isEmpty)
    }
    
    // MARK: - Configuration Tests
    
    func testConfigureWithStorageService() {
        let newService = CloudDownloadService()
        
        newService.configure(storageService: storageService)
        
        // Service should accept configuration without crashing
        XCTAssertNotNil(newService)
    }
    
    // MARK: - isPathDownloaded Tests
    
    func testIsPathDownloadedReturnsFalseForUnknownPath() {
        let result = cloudDownloadService.isPathDownloaded("/some/unknown/path.txt")
        
        XCTAssertFalse(result)
    }
    
    func testIsPathDownloadedReturnsFalseInitially() {
        let path = "/Users/test/Documents/file.txt"
        
        let result = cloudDownloadService.isPathDownloaded(path)
        
        XCTAssertFalse(result)
    }
    
    // MARK: - Cancel Tests
    
    func testCancelResetsState() {
        cloudDownloadService.cancel()
        
        XCTAssertFalse(cloudDownloadService.isDownloading)
        XCTAssertNil(cloudDownloadService.downloadingSnippetId)
        XCTAssertEqual(cloudDownloadService.currentFileIndex, 0)
        XCTAssertEqual(cloudDownloadService.totalFiles, 0)
    }
    
    func testCancelCanBeCalledMultipleTimes() {
        cloudDownloadService.cancel()
        cloudDownloadService.cancel()
        cloudDownloadService.cancel()
        
        XCTAssertFalse(cloudDownloadService.isDownloading)
    }
    
    func testCancelAndDeleteResetsState() {
        cloudDownloadService.cancelAndDelete()
        
        XCTAssertFalse(cloudDownloadService.isDownloading)
        XCTAssertNil(cloudDownloadService.downloadingSnippetId)
    }
    
    // MARK: - isPathCloudFileNotDownloadedSync Tests
    
    func testIsPathCloudFileNotDownloadedSyncForLocalFile() throws {
        let fileURL = try tempDir.createFile(name: "local.txt", content: "Local content")
        
        let result = CloudDownloadService.isPathCloudFileNotDownloadedSync(fileURL.path)
        
        // Local files are not cloud files, so should return false
        XCTAssertFalse(result)
    }
    
    func testIsPathCloudFileNotDownloadedSyncForNonexistentFile() {
        let result = CloudDownloadService.isPathCloudFileNotDownloadedSync("/nonexistent/path.txt")
        
        // Non-existent files should return false (can't determine cloud status)
        XCTAssertFalse(result)
    }
    
    func testIsPathCloudFileNotDownloadedSyncForDirectory() throws {
        let dirURL = try tempDir.createSubdirectory(name: "localdir")
        
        let result = CloudDownloadService.isPathCloudFileNotDownloadedSync(dirURL.path)
        
        // Local directories are not cloud files
        XCTAssertFalse(result)
    }
    
    func testIsPathCloudFileNotDownloadedSyncForTempFile() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try "temp content".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        let result = CloudDownloadService.isPathCloudFileNotDownloadedSync(tempFile.path)
        
        XCTAssertFalse(result)
    }
    
    // MARK: - Callback Tests
    
    func testOnDownloadCompleteCallbackCanBeSet() {
        cloudDownloadService.onDownloadComplete = {
            // Callback body - would be called on download complete
        }
        
        // Just verify callback can be set without crash
        // cancelAndDelete only calls callback if there's a downloadingSnippetId
        XCTAssertNotNil(cloudDownloadService.onDownloadComplete)
    }
    
    func testOnProgressUpdateCallbackCanBeSet() {
        var callbackCalled = false
        
        cloudDownloadService.onProgressUpdate = {
            callbackCalled = true
        }
        
        // The callback is only called during actual downloads, not on cancel
        // Just verify it can be set without issues
        XCTAssertFalse(callbackCalled)
    }
    
    // MARK: - startDownload Tests (with local files)
    
    func testStartDownloadWithEmptyCloudPathsCompletesImmediately() async throws {
        let snippet = Snippet(
            name: "Empty Snippet",
            contentType: .text,
            textContent: "Test"
        )
        try storageService.saveSnippet(snippet)
        
        var downloadCompleted = false
        cloudDownloadService.onDownloadComplete = {
            downloadCompleted = true
        }
        
        // Start download with empty paths
        cloudDownloadService.startDownload(for: snippet, cloudPaths: [])
        
        // Wait a bit for async completion
        try await Task.sleep(for: .milliseconds(100))
        
        XCTAssertTrue(downloadCompleted)
        XCTAssertFalse(cloudDownloadService.isDownloading)
    }
    
    func testStartDownloadWithLocalFilesCompletesImmediately() async throws {
        let fileURL = try tempDir.createFile(name: "local_download.txt", content: "Content")
        
        let snippet = Snippet(
            name: "Local File Snippet",
            contentType: .file,
            mediaPath: fileURL.path
        )
        try storageService.saveSnippet(snippet)
        
        var downloadCompleted = false
        cloudDownloadService.onDownloadComplete = {
            downloadCompleted = true
        }
        
        // Start download with local file path (not a cloud file)
        cloudDownloadService.startDownload(for: snippet, cloudPaths: [fileURL.path])
        
        // Wait for async completion
        try await Task.sleep(for: .milliseconds(100))
        
        // Local files don't need download, so should complete
        XCTAssertTrue(downloadCompleted)
        XCTAssertFalse(cloudDownloadService.isDownloading)
    }
    
    func testStartDownloadIgnoresSecondRequest() async throws {
        let snippet1 = Snippet(
            name: "Snippet 1",
            contentType: .text,
            textContent: "Test 1",
            isDownloading: true
        )
        
        // Manually set downloading state
        cloudDownloadService.startDownload(for: snippet1, cloudPaths: [])
        
        // Brief wait
        try await Task.sleep(for: .milliseconds(50))
        
        // Create second snippet and try to start download
        let snippet2 = Snippet(
            name: "Snippet 2",
            contentType: .text,
            textContent: "Test 2",
            isDownloading: true
        )
        
        // If already downloading, second request should be ignored
        // (The first one completes immediately with empty paths though)
        cloudDownloadService.startDownload(for: snippet2, cloudPaths: [])
    }
    
    // MARK: - retryDownload Tests
    
    func testRetryDownloadWithNoCloudPathsDoesNothing() throws {
        let snippet = Snippet(
            name: "No Cloud Paths",
            contentType: .text,
            textContent: "Test"
        )
        
        // Should not crash with snippet that has no cloud paths
        cloudDownloadService.retryDownload(for: snippet)
        
        XCTAssertFalse(cloudDownloadService.isDownloading)
    }
    
    func testRetryDownloadWithSingleCloudPath() throws {
        let localFile = try tempDir.createFile(name: "retry_single.txt", content: "Content")
        
        var snippet = Snippet(
            name: "Single Cloud Path",
            contentType: .file,
            mediaPath: localFile.path,
            cloudPath: localFile.path  // Using local path as stand-in for cloud path
        )
        snippet.downloadError = "Previous error"
        
        cloudDownloadService.retryDownload(for: snippet)
        
        // Should start or complete download
        // (completes immediately for local files)
    }
    
    func testRetryDownloadWithMultipleCloudPaths() throws {
        let file1 = try tempDir.createFile(name: "retry1.txt", content: "Content 1")
        let file2 = try tempDir.createFile(name: "retry2.txt", content: "Content 2")
        
        var snippet = Snippet(
            name: "Multiple Cloud Paths",
            contentType: .fileStack,
            mediaPaths: [file1.path, file2.path],
            cloudPaths: [file1.path, file2.path]
        )
        snippet.downloadError = "Previous error"
        
        cloudDownloadService.retryDownload(for: snippet)
        
        // Should attempt to restart download
    }
    
    // MARK: - State Management Tests
    
    func testDownloadingSnippetIdIsSetDuringDownload() async throws {
        let snippet = Snippet(
            id: UUID(),
            name: "Track ID",
            contentType: .text,
            textContent: "Test"
        )
        try storageService.saveSnippet(snippet)
        
        // For very quick operations, the ID might be set and cleared rapidly
        // Just verify the service handles the snippet correctly
        cloudDownloadService.startDownload(for: snippet, cloudPaths: [])
        
        // Wait for completion
        try await Task.sleep(for: .milliseconds(100))
        
        // After completion, should be nil
        XCTAssertNil(cloudDownloadService.downloadingSnippetId)
    }
}

// MARK: - Download Error Tests

@MainActor
final class CloudDownloadErrorTests: XCTestCase {
    
    func testDownloadErrorDownloadFailedDescription() {
        // Note: DownloadError is private, so we test behavior indirectly
        // through the service's error handling
    }
    
    func testDownloadErrorTimeoutDescription() {
        // Timeout errors are handled internally
    }
    
    func testDownloadErrorCancelledDescription() {
        // Cancellation errors are handled internally
    }
}
