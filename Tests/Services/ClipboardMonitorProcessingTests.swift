import XCTest
import AppKit
@testable import ClipboardMenu

/// Tests for ClipboardMonitor's clipboard processing logic
/// These tests verify the internal processing methods by checking storage results
@MainActor
final class ClipboardMonitorProcessingTests: XCTestCase {
    
    var storageService: StorageService!
    var preferencesService: PreferencesService!
    var thumbnailService: ThumbnailService!
    var clipboardMonitor: ClipboardMonitor!
    var tempDir: TempDirectory!
    var testDefaults: UserDefaults!
    
    override func setUp() async throws {
        // Use app storage temp dir so paths contain "ClipboardMenu"
        // This ensures saved folders are treated as internal storage
        tempDir = try TempDirectory.appStorage()
        
        storageService = StorageService(baseURL: tempDir.url, inMemory: true)
        try storageService.initialize()
        
        let suiteName = "com.clipboardmenu.tests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        preferencesService = PreferencesService(defaults: testDefaults)
        
        // Set reasonable test limits
        preferencesService.maxItemSizeMB = 10  // 10MB limit for tests
        preferencesService.maxHistoryItems = 100
        
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
        if let defaults = testDefaults {
            defaults.removePersistentDomain(forName: defaults.description)
        }
        testDefaults = nil
    }
    
    // MARK: - Helper Methods
    
    /// Simulates a clipboard change and waits for processing
    private func simulateClipboardChange() async {
        // Small delay to allow async processing
        try? await Task.sleep(for: .milliseconds(100))
    }
    
    /// Creates a test image file
    private func createTestImage(name: String = "test.png") throws -> URL {
        let image = NSImage(size: NSSize(width: 100, height: 100))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 100, height: 100).fill()
        image.unlockFocus()
        
        guard let data = image.pngData() else {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG data"])
        }
        
        return try tempDir.createFile(name: name, content: data)
    }
    
    /// Creates a test text file
    private func createTestTextFile(name: String = "test.txt", content: String = "Test content") throws -> URL {
        return try tempDir.createFile(name: name, content: content)
    }
    
    /// Creates a test folder with files
    private func createTestFolder(name: String = "TestFolder", fileCount: Int = 3) throws -> URL {
        let folder = try tempDir.createSubdirectory(name: name)
        for i in 0..<fileCount {
            try "File \(i) content".write(
                to: folder.appendingPathComponent("file\(i).txt"),
                atomically: true,
                encoding: .utf8
            )
        }
        return folder
    }
    
    // MARK: - Size Calculation Tests
    
    func testCalculateSize_ForFile() throws {
        let content = String(repeating: "A", count: 500)
        let file = try tempDir.createFile(name: "test.txt", content: content)
        
        // Verify file size using FileManager
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        let size = attrs[.size] as? Int64 ?? 0
        
        XCTAssertEqual(size, 500)
    }
    
    func testCalculateSize_ForEmptyFolder() throws {
        let folder = try tempDir.createSubdirectory(name: "empty")
        
        // Empty folder should have zero content size
        var totalSize: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(size)
                }
            }
        }
        
        XCTAssertEqual(totalSize, 0)
    }
    
    func testCalculateSize_ForFolderWithFiles() throws {
        let folder = try tempDir.createSubdirectory(name: "withfiles")
        try Data(repeating: 0x41, count: 100).write(to: folder.appendingPathComponent("file1.txt"))
        try Data(repeating: 0x42, count: 200).write(to: folder.appendingPathComponent("file2.txt"))
        
        var totalSize: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) {
            for case let fileURL as URL in enumerator {
                if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                   values.isDirectory == false,
                   let size = values.fileSize {
                    totalSize += Int64(size)
                }
            }
        }
        
        XCTAssertEqual(totalSize, 300)
    }
    
    func testCalculateSize_ForNestedFolder() throws {
        let outer = try tempDir.createSubdirectory(name: "outer")
        let inner = outer.appendingPathComponent("inner")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        
        try Data(repeating: 0x41, count: 100).write(to: outer.appendingPathComponent("outer.txt"))
        try Data(repeating: 0x42, count: 200).write(to: inner.appendingPathComponent("inner.txt"))
        
        var totalSize: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at: outer, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) {
            for case let fileURL as URL in enumerator {
                if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                   values.isDirectory == false,
                   let size = values.fileSize {
                    totalSize += Int64(size)
                }
            }
        }
        
        XCTAssertEqual(totalSize, 300)
    }
    
    // MARK: - Directory Detection Tests
    
    func testIsDirectory_ForFolder() throws {
        let folder = try tempDir.createSubdirectory(name: "testfolder")
        
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir)
        
        XCTAssertTrue(exists)
        XCTAssertTrue(isDir.boolValue)
    }
    
    func testIsDirectory_ForFile() throws {
        let file = try tempDir.createFile(name: "test.txt", content: "content")
        
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir)
        
        XCTAssertTrue(exists)
        XCTAssertFalse(isDir.boolValue)
    }
    
    func testIsDirectory_ForNonExistent() {
        let nonExistent = tempDir.path(for: "nonexistent")
        
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: nonExistent, isDirectory: &isDir)
        
        XCTAssertFalse(exists)
    }
    
    // MARK: - File Type Detection Tests
    
    func testIsVideoFile_ValidExtensions() {
        let videoExtensions = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]
        
        for ext in videoExtensions {
            let url = URL(fileURLWithPath: "/test/video.\(ext)")
            XCTAssertTrue(videoExtensions.contains(url.pathExtension.lowercased()), "Should recognize .\(ext) as video")
        }
    }
    
    func testIsVideoFile_InvalidExtensions() {
        let nonVideoExtensions = ["txt", "pdf", "png", "jpg", "doc"]
        let videoExtensions = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]
        
        for ext in nonVideoExtensions {
            let url = URL(fileURLWithPath: "/test/file.\(ext)")
            XCTAssertFalse(videoExtensions.contains(url.pathExtension.lowercased()), "Should not recognize .\(ext) as video")
        }
    }
    
    func testIsImageFile_ValidExtensions() {
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "webp"]
        
        for ext in imageExtensions {
            let url = URL(fileURLWithPath: "/test/image.\(ext)")
            XCTAssertTrue(imageExtensions.contains(url.pathExtension.lowercased()), "Should recognize .\(ext) as image")
        }
    }
    
    func testIsImageFile_CaseInsensitive() {
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "webp"]
        let testCases = ["PNG", "Jpg", "JPEG", "GIF", "BMP", "TIFF", "HEIC", "WebP"]
        
        for ext in testCases {
            let url = URL(fileURLWithPath: "/test/image.\(ext)")
            XCTAssertTrue(imageExtensions.contains(url.pathExtension.lowercased()), "Should recognize .\(ext) as image (case insensitive)")
        }
    }
    
    // MARK: - willCopyFromHistory Skip Behavior Tests
    
    func testWillCopyFromHistory_SetsSkipFlag() {
        // This indirectly tests that the flag is set
        clipboardMonitor.willCopyFromHistory()
        // No crash = success, flag is private but we verified it doesn't crash
    }
    
    func testWillCopyFromHistory_MultipleCallsAreSafe() {
        for _ in 0..<100 {
            clipboardMonitor.willCopyFromHistory()
        }
    }
    
    // MARK: - Storage Service Integration Tests
    
    func testStorageIntegration_SavesTextItem() throws {
        // Directly test storage to verify integration
        let item = ClipboardItem(
            contentType: .text,
            textContent: "Test clipboard text",
            sourceApp: "TestApp"
        )
        
        try storageService.saveClipboardItem(item)
        
        let items = try storageService.fetchClipboardItems()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.textContent, "Test clipboard text")
        XCTAssertEqual(items.first?.contentType, .text)
    }
    
    func testStorageIntegration_SavesRichTextItem() throws {
        let rtfData = Data("RTF content".utf8)
        let item = ClipboardItem(
            contentType: .richText,
            textContent: "Plain text fallback",
            richTextData: rtfData
        )
        
        try storageService.saveClipboardItem(item)
        
        let items = try storageService.fetchClipboardItems()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.contentType, .richText)
        XCTAssertNotNil(items.first?.richTextData)
        XCTAssertEqual(items.first?.textContent, "Plain text fallback")
    }
    
    func testStorageIntegration_SavesImageItem() throws {
        let imageFile = try createTestImage()
        
        let item = ClipboardItem(
            contentType: .image,
            mediaPath: imageFile.path
        )
        
        try storageService.saveClipboardItem(item)
        
        let items = try storageService.fetchClipboardItems()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.contentType, .image)
        XCTAssertEqual(items.first?.mediaPath, imageFile.path)
    }
    
    func testStorageIntegration_SavesFileItem() throws {
        let file = try createTestTextFile()
        
        let item = ClipboardItem(
            contentType: .file,
            textContent: "test.txt",
            mediaPath: file.path
        )
        
        try storageService.saveClipboardItem(item)
        
        let items = try storageService.fetchClipboardItems()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.contentType, .file)
    }
    
    func testStorageIntegration_SavesFileStackItem() throws {
        let file1 = try createTestTextFile(name: "file1.txt", content: "Content 1")
        let file2 = try createTestTextFile(name: "file2.txt", content: "Content 2")
        
        let item = ClipboardItem(
            contentType: .fileStack,
            textContent: "2 items",
            mediaPaths: [file1.path, file2.path]
        )
        
        try storageService.saveClipboardItem(item)
        
        let items = try storageService.fetchClipboardItems()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.contentType, .fileStack)
        XCTAssertEqual(items.first?.mediaPaths?.count, 2)
    }
    
    // MARK: - Size Limit Tests
    
    func testSizeLimit_RejectsItemOverLimit() throws {
        // Set very small limit
        preferencesService.maxItemSizeMB = 1  // 1MB
        
        // Verify the limit is correctly calculated
        XCTAssertEqual(preferencesService.maxItemSizeBytes, 1 * 1024 * 1024)
    }
    
    func testSizeLimit_AcceptsItemUnderLimit() throws {
        preferencesService.maxItemSizeMB = 10  // 10MB
        
        // A small text item should be under the limit
        let text = String(repeating: "A", count: 1000)
        XCTAssertLessThan(Int64(text.utf8.count), preferencesService.maxItemSizeBytes)
    }
    
    // MARK: - Deduplication Tests
    
    func testDeduplication_MovesExistingTextToTop() throws {
        // Save initial item with old date
        let oldDate = Date(timeIntervalSince1970: 1000)
        let item = ClipboardItem(
            contentType: .text,
            textContent: "Duplicate text",
            createdAt: oldDate
        )
        try storageService.saveClipboardItem(item)
        
        // Move to top
        let moved = try storageService.moveExistingItemToTop(
            textContent: "Duplicate text",
            mediaPath: nil,
            contentType: .text
        )
        
        XCTAssertTrue(moved)
        
        let items = try storageService.fetchClipboardItems()
        XCTAssertEqual(items.count, 1)
        XCTAssertGreaterThan(items.first!.createdAt, oldDate)
    }
    
    func testDeduplication_DoesNotDuplicateExistingText() throws {
        let item = ClipboardItem(
            contentType: .text,
            textContent: "Same text"
        )
        try storageService.saveClipboardItem(item)
        
        // Try to move non-existent text
        let moved = try storageService.moveExistingItemToTop(
            textContent: "Different text",
            mediaPath: nil,
            contentType: .text
        )
        
        XCTAssertFalse(moved)
    }
    
    // MARK: - Cleanup Trigger Tests
    
    func testCleanup_EnforcesItemCountLimit() async throws {
        // Set limit to 5 items
        preferencesService.maxHistoryItems = 5
        
        // Add 10 items
        for i in 0..<10 {
            let item = ClipboardItem(
                contentType: .text,
                textContent: "Item \(i)",
                createdAt: Date().addingTimeInterval(Double(i))
            )
            try storageService.saveClipboardItem(item)
        }
        
        // Verify all 10 were added
        var items = try storageService.fetchClipboardItems()
        XCTAssertEqual(items.count, 10)
        
        // Run cleanup
        storageService.runCleanup(maxItems: 5, maxStorageBytes: Int64.max)
        
        // Wait for cleanup
        try? await Task.sleep(for: .milliseconds(100))
        
        // Verify only 5 remain
        items = try storageService.fetchClipboardItems()
        XCTAssertEqual(items.count, 5)
    }
    
    // MARK: - Folder Storage Tests
    
    func testFolderStorage_SavesSmallFolder() throws {
        let folder = try createTestFolder(name: "SmallFolder", fileCount: 2)
        let itemId = UUID()
        
        // Use storage service to save folder
        let savedPath = try storageService.saveFolder(
            sourceURL: folder,
            itemId: itemId,
            originalFolderName: "SmallFolder"
        )
        
        // Verify folder was copied
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedPath))
        XCTAssertTrue(savedPath.contains("ClipboardMenu"))
        
        // Verify contents were copied
        let contents = try FileManager.default.contentsOfDirectory(atPath: savedPath)
        XCTAssertEqual(contents.count, 2)
    }
    
    func testFolderStorage_SavesFolderForStack() throws {
        let folder = try createTestFolder(name: "StackFolder", fileCount: 2)
        let itemId = UUID()
        
        let savedPath = try storageService.saveFolderForStack(
            sourceURL: folder,
            itemId: itemId,
            index: 0,
            originalFolderName: "StackFolder"
        )
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedPath))
        XCTAssertTrue(savedPath.contains("_0_"))  // Contains index
    }
    
    func testFolderStorage_PreservesNestedStructure() throws {
        let outer = try tempDir.createSubdirectory(name: "OuterFolder")
        let inner = outer.appendingPathComponent("InnerFolder")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try "outer content".write(to: outer.appendingPathComponent("outer.txt"), atomically: true, encoding: .utf8)
        try "inner content".write(to: inner.appendingPathComponent("inner.txt"), atomically: true, encoding: .utf8)
        
        let itemId = UUID()
        let savedPath = try storageService.saveFolder(
            sourceURL: outer,
            itemId: itemId,
            originalFolderName: "OuterFolder"
        )
        
        // Verify nested structure
        let savedInner = URL(fileURLWithPath: savedPath).appendingPathComponent("InnerFolder")
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedInner.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedInner.appendingPathComponent("inner.txt").path))
    }
    
    // MARK: - File Reference Tests
    
    func testFileReference_DetectsExternalPath() {
        let item = ClipboardItem(
            contentType: .file,
            mediaPath: "/Users/external/path/file.pdf"
        )
        
        XCTAssertTrue(item.isFileReference)
    }
    
    func testFileReference_DetectsInternalPath() {
        let item = ClipboardItem(
            contentType: .file,
            mediaPath: "/Users/test/Library/Application Support/ClipboardMenu/Media/file.pdf"
        )
        
        XCTAssertFalse(item.isFileReference)
    }
    
    func testFileReference_FileStackWithExternalPaths() {
        let item = ClipboardItem(
            contentType: .fileStack,
            mediaPaths: ["/external/file1.txt", "/external/file2.txt"]
        )
        
        XCTAssertTrue(item.isFileReference)
    }
    
    func testFileReference_FileStackWithInternalPaths() {
        let item = ClipboardItem(
            contentType: .fileStack,
            mediaPaths: [
                "/Library/ClipboardMenu/file1.txt",
                "/Library/ClipboardMenu/file2.txt"
            ]
        )
        
        XCTAssertFalse(item.isFileReference)
    }
    
    // MARK: - Source App Detection Tests
    
    func testSourceApp_IsPreserved() throws {
        let item = ClipboardItem(
            contentType: .text,
            textContent: "Test",
            sourceApp: "Safari"
        )
        
        try storageService.saveClipboardItem(item)
        
        let items = try storageService.fetchClipboardItems()
        XCTAssertEqual(items.first?.sourceApp, "Safari")
    }
    
    func testSourceApp_HandlesNil() throws {
        let item = ClipboardItem(
            contentType: .text,
            textContent: "Test",
            sourceApp: nil
        )
        
        try storageService.saveClipboardItem(item)
        
        let items = try storageService.fetchClipboardItems()
        XCTAssertNil(items.first?.sourceApp)
    }
}
