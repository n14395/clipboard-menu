// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import ClipboardMenu

@MainActor
final class FilePermissionServiceTests: XCTestCase {
    var filePermissionService: FilePermissionService!
    var tempDirectory: URL!
    
    override func setUp() async throws {
        filePermissionService = FilePermissionService.shared
        
        // Create a temp directory for test files
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        // Clean up temp directory
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDirectory = nil
    }
    
    // MARK: - Singleton
    
    func testSharedInstanceExists() {
        XCTAssertNotNil(FilePermissionService.shared)
    }
    
    func testSharedInstanceIsSingleton() {
        let instance1 = FilePermissionService.shared
        let instance2 = FilePermissionService.shared
        
        XCTAssertTrue(instance1 === instance2)
    }
    
    // MARK: - canRead
    
    func testCanReadReturnsTrueForReadableFile() throws {
        // Create a test file in the temp directory
        let testFile = tempDirectory.appendingPathComponent("test.txt")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)
        
        let result = filePermissionService.canRead(path: testFile.path)
        
        XCTAssertTrue(result)
    }
    
    func testCanReadReturnsFalseForNonexistentFile() {
        let result = filePermissionService.canRead(path: "/nonexistent/path/file.txt")
        
        XCTAssertFalse(result)
    }
    
    func testCanReadReturnsFalseForEmptyPath() {
        let result = filePermissionService.canRead(path: "")
        
        XCTAssertFalse(result)
    }
    
    func testCanReadReturnsTrueForDirectory() throws {
        // Temp directory should be readable
        let result = filePermissionService.canRead(path: tempDirectory.path)
        
        XCTAssertTrue(result)
    }
    
    // MARK: - canReadAll
    
    func testCanReadAllReturnsTrueForAllReadableFiles() throws {
        let file1 = tempDirectory.appendingPathComponent("file1.txt")
        let file2 = tempDirectory.appendingPathComponent("file2.txt")
        
        try "content1".write(to: file1, atomically: true, encoding: .utf8)
        try "content2".write(to: file2, atomically: true, encoding: .utf8)
        
        let result = filePermissionService.canReadAll(paths: [file1.path, file2.path])
        
        XCTAssertTrue(result)
    }
    
    func testCanReadAllReturnsFalseIfAnyFileUnreadable() throws {
        let file1 = tempDirectory.appendingPathComponent("file1.txt")
        try "content1".write(to: file1, atomically: true, encoding: .utf8)
        
        let result = filePermissionService.canReadAll(paths: [file1.path, "/nonexistent/file.txt"])
        
        XCTAssertFalse(result)
    }
    
    func testCanReadAllReturnsTrueForEmptyArray() {
        let result = filePermissionService.canReadAll(paths: [])
        
        XCTAssertTrue(result)
    }
    
    func testCanReadAllReturnsFalseForAllUnreadableFiles() {
        let result = filePermissionService.canReadAll(paths: ["/nonexistent1.txt", "/nonexistent2.txt"])
        
        XCTAssertFalse(result)
    }
    
    // MARK: - hasFileSystemAccess
    
    func testHasFileSystemAccessInitialState() {
        // Without explicit access request, should reflect current state
        // This is a basic smoke test - actual value depends on system state
        _ = filePermissionService.hasFileSystemAccess
        // Just verify it doesn't crash
    }
    
    // MARK: - stopAccessingSecurityScopedResource
    
    func testStopAccessingSecurityScopedResourceDoesNotCrash() {
        // Should not crash even when no resource is being accessed
        filePermissionService.stopAccessingSecurityScopedResource()
    }
    
    // MARK: - requestAccess(to path:)
    
    func testRequestAccessToReadablePathReturnsTrue() throws {
        let testFile = tempDirectory.appendingPathComponent("readable.txt")
        try "content".write(to: testFile, atomically: true, encoding: .utf8)
        
        // If already readable, should return true without showing dialog
        let result = filePermissionService.requestAccess(to: testFile.path, message: nil)
        
        XCTAssertTrue(result)
    }
    
    // MARK: - requestAccess(to url:)
    
    func testRequestAccessToReadableURLReturnsTrue() throws {
        let testFile = tempDirectory.appendingPathComponent("readable.txt")
        try "content".write(to: testFile, atomically: true, encoding: .utf8)
        
        // If already readable, should return true without showing dialog
        let result = filePermissionService.requestAccess(to: testFile, message: nil)
        
        XCTAssertTrue(result)
    }
    
    // MARK: - requestFolderAccess
    
    func testRequestFolderAccessReturnsTrueForEmptyPaths() {
        let result = filePermissionService.requestFolderAccess(for: [], message: nil)
        
        XCTAssertTrue(result)
    }
    
    func testRequestFolderAccessReturnsTrueWhenAllPathsReadable() throws {
        let file1 = tempDirectory.appendingPathComponent("file1.txt")
        let file2 = tempDirectory.appendingPathComponent("file2.txt")
        
        try "content1".write(to: file1, atomically: true, encoding: .utf8)
        try "content2".write(to: file2, atomically: true, encoding: .utf8)
        
        let result = filePermissionService.requestFolderAccess(for: [file1.path, file2.path], message: nil)
        
        XCTAssertTrue(result)
    }
}

// MARK: - MockFilePermissionService Tests

@MainActor
final class MockFilePermissionServiceTests: XCTestCase {
    var mockService: MockFilePermissionService!
    
    override func setUp() async throws {
        mockService = MockFilePermissionService()
    }
    
    override func tearDown() async throws {
        mockService = nil
    }
    
    // MARK: - Protocol Conformance
    
    func testConformsToProtocol() {
        let service: FilePermissionServiceProtocol = mockService
        XCTAssertNotNil(service)
    }
    
    // MARK: - hasFileSystemAccess
    
    func testHasFileSystemAccessInitiallyFalse() {
        XCTAssertFalse(mockService.hasFileSystemAccess)
    }
    
    func testHasFileSystemAccessAfterGrant() {
        mockService._hasFileSystemAccess = true
        XCTAssertTrue(mockService.hasFileSystemAccess)
    }
    
    // MARK: - requestHomeDirectoryAccess
    
    func testRequestHomeDirectoryAccessGrantsAccess() {
        let prefs = PreferencesService(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        
        mockService.shouldGrantAccess = true
        let result = mockService.requestHomeDirectoryAccess(preferencesService: prefs)
        
        XCTAssertTrue(result)
        XCTAssertTrue(mockService.hasFileSystemAccess)
        XCTAssertEqual(mockService.requestHomeDirectoryAccessCallCount, 1)
    }
    
    func testRequestHomeDirectoryAccessDeniesAccess() {
        let prefs = PreferencesService(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        
        mockService.shouldGrantAccess = false
        let result = mockService.requestHomeDirectoryAccess(preferencesService: prefs)
        
        XCTAssertFalse(result)
        XCTAssertFalse(mockService.hasFileSystemAccess)
    }
    
    // MARK: - requestRootAccess
    
    func testRequestRootAccessGrantsAccess() {
        let prefs = PreferencesService(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        
        mockService.shouldGrantAccess = true
        let result = mockService.requestRootAccess(preferencesService: prefs)
        
        XCTAssertTrue(result)
        XCTAssertTrue(mockService.hasRootAccess)
        XCTAssertEqual(mockService.requestRootAccessCallCount, 1)
    }
    
    func testRequestRootAccessDeniesAccess() {
        let prefs = PreferencesService(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        
        mockService.shouldGrantAccess = false
        let result = mockService.requestRootAccess(preferencesService: prefs)
        
        XCTAssertFalse(result)
        XCTAssertFalse(mockService.hasRootAccess)
    }
    
    // MARK: - isPathOutsideHomeDirectory
    
    func testIsPathOutsideHomeDirectoryReturnsTrueForSystemPaths() {
        XCTAssertTrue(mockService.isPathOutsideHomeDirectory("/Applications/Safari.app"))
        XCTAssertTrue(mockService.isPathOutsideHomeDirectory("/tmp/test.txt"))
        XCTAssertTrue(mockService.isPathOutsideHomeDirectory("/var/log/system.log"))
    }
    
    func testIsPathOutsideHomeDirectoryReturnsFalseForHomePaths() {
        XCTAssertFalse(mockService.isPathOutsideHomeDirectory("/Users/testuser/Documents/file.txt"))
        XCTAssertFalse(mockService.isPathOutsideHomeDirectory("/Users/testuser/Desktop"))
    }
    
    // MARK: - needsRootAccess
    
    func testNeedsRootAccessReturnsTrueForSystemPathWithoutRootAccess() {
        mockService._hasRootAccess = false
        XCTAssertTrue(mockService.needsRootAccess(for: "/Applications/Safari.app"))
    }
    
    func testNeedsRootAccessReturnsFalseForSystemPathWithRootAccess() {
        mockService._hasRootAccess = true
        XCTAssertFalse(mockService.needsRootAccess(for: "/Applications/Safari.app"))
    }
    
    func testNeedsRootAccessReturnsFalseForHomePath() {
        mockService._hasRootAccess = false
        XCTAssertFalse(mockService.needsRootAccess(for: "/Users/testuser/Documents/file.txt"))
    }
    
    // MARK: - restoreFileSystemAccess
    
    func testRestoreFileSystemAccessWhenHasAccess() {
        let prefs = PreferencesService(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        mockService._hasFileSystemAccess = true
        
        let result = mockService.restoreFileSystemAccess(preferencesService: prefs)
        
        XCTAssertTrue(result)
        XCTAssertEqual(mockService.restoreFileSystemAccessCallCount, 1)
    }
    
    func testRestoreFileSystemAccessWhenNoAccess() {
        let prefs = PreferencesService(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        mockService._hasFileSystemAccess = false
        
        let result = mockService.restoreFileSystemAccess(preferencesService: prefs)
        
        XCTAssertFalse(result)
    }
    
    // MARK: - stopAccessingSecurityScopedResource
    
    func testStopAccessingRevokesAccess() {
        mockService._hasFileSystemAccess = true
        
        mockService.stopAccessingSecurityScopedResource()
        
        XCTAssertFalse(mockService.hasFileSystemAccess)
        XCTAssertEqual(mockService.stopAccessingCallCount, 1)
    }
    
    // MARK: - canRead
    
    func testCanReadReturnsFalseForUnknownPath() {
        let result = mockService.canRead(path: "/some/path")
        
        XCTAssertFalse(result)
    }
    
    func testCanReadReturnsTrueForGrantedPath() {
        mockService.readablePaths.insert("/some/path")
        
        let result = mockService.canRead(path: "/some/path")
        
        XCTAssertTrue(result)
    }
    
    // MARK: - canReadAll
    
    func testCanReadAllReturnsTrueForEmptyPaths() {
        let result = mockService.canReadAll(paths: [])
        
        XCTAssertTrue(result)
    }
    
    func testCanReadAllReturnsTrueWhenAllGranted() {
        mockService.grantAccess(to: ["/path1", "/path2"])
        
        let result = mockService.canReadAll(paths: ["/path1", "/path2"])
        
        XCTAssertTrue(result)
    }
    
    func testCanReadAllReturnsFalseWhenSomeNotGranted() {
        mockService.grantAccess(to: ["/path1"])
        
        let result = mockService.canReadAll(paths: ["/path1", "/path2"])
        
        XCTAssertFalse(result)
    }
    
    // MARK: - requestAccess(to path:)
    
    func testRequestAccessToPathRecordsRequest() {
        mockService.requestAccess(to: "/test/path", message: nil)
        
        XCTAssertEqual(mockService.requestedPaths, ["/test/path"])
    }
    
    func testRequestAccessToPathGrantsAccessWhenShouldGrant() {
        mockService.shouldGrantAccess = true
        mockService.requestAccess(to: "/test/path", message: nil)
        
        XCTAssertTrue(mockService.canRead(path: "/test/path"))
    }
    
    func testRequestAccessToPathDoesNotGrantWhenShouldNotGrant() {
        mockService.shouldGrantAccess = false
        mockService.requestAccess(to: "/test/path", message: nil)
        
        XCTAssertFalse(mockService.canRead(path: "/test/path"))
    }
    
    // MARK: - requestAccess(to url:)
    
    func testRequestAccessToURLRecordsRequest() {
        let url = URL(fileURLWithPath: "/test/url")
        mockService.requestAccess(to: url, message: nil)
        
        XCTAssertEqual(mockService.requestedURLs, [url])
    }
    
    func testRequestAccessToURLGrantsAccessWhenShouldGrant() {
        let url = URL(fileURLWithPath: "/test/url")
        mockService.shouldGrantAccess = true
        mockService.requestAccess(to: url, message: nil)
        
        XCTAssertTrue(mockService.canRead(path: url.path))
    }
    
    // MARK: - requestFolderAccess
    
    func testRequestFolderAccessRecordsPaths() {
        mockService.requestFolderAccess(for: ["/path1", "/path2"], message: nil)
        
        XCTAssertEqual(mockService.requestedPaths, ["/path1", "/path2"])
    }
    
    func testRequestFolderAccessGrantsAllPathsWhenShouldGrant() {
        mockService.shouldGrantAccess = true
        mockService.requestFolderAccess(for: ["/path1", "/path2"], message: nil)
        
        XCTAssertTrue(mockService.canReadAll(paths: ["/path1", "/path2"]))
    }
    
    // MARK: - reset
    
    func testResetClearsAllState() {
        mockService._hasFileSystemAccess = true
        mockService._hasRootAccess = true
        mockService.readablePaths = ["/path1", "/path2"]
        mockService.requestedPaths = ["/path3"]
        mockService.requestedURLs = [URL(fileURLWithPath: "/path4")]
        mockService.shouldGrantAccess = false
        mockService.requestHomeDirectoryAccessCallCount = 5
        mockService.requestRootAccessCallCount = 3
        mockService.restoreFileSystemAccessCallCount = 3
        mockService.stopAccessingCallCount = 2
        
        mockService.reset()
        
        XCTAssertFalse(mockService.hasFileSystemAccess)
        XCTAssertFalse(mockService.hasRootAccess)
        XCTAssertTrue(mockService.readablePaths.isEmpty)
        XCTAssertTrue(mockService.requestedPaths.isEmpty)
        XCTAssertTrue(mockService.requestedURLs.isEmpty)
        XCTAssertTrue(mockService.shouldGrantAccess)
        XCTAssertEqual(mockService.requestHomeDirectoryAccessCallCount, 0)
        XCTAssertEqual(mockService.requestRootAccessCallCount, 0)
        XCTAssertEqual(mockService.restoreFileSystemAccessCallCount, 0)
        XCTAssertEqual(mockService.stopAccessingCallCount, 0)
    }
    
    // MARK: - grantAccess helper
    
    func testGrantAccessAddsPaths() {
        mockService.grantAccess(to: ["/a", "/b", "/c"])
        
        XCTAssertTrue(mockService.canRead(path: "/a"))
        XCTAssertTrue(mockService.canRead(path: "/b"))
        XCTAssertTrue(mockService.canRead(path: "/c"))
    }
}
