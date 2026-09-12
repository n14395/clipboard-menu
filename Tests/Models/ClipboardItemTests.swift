import XCTest
@testable import ClipboardMenu

final class ClipboardItemTests: XCTestCase {
    
    // MARK: - Initialization
    
    func testInitWithDefaults() {
        let item = ClipboardItem(contentType: .text)
        
        XCTAssertNotNil(item.id)
        XCTAssertEqual(item.contentType, .text)
        XCTAssertNil(item.textContent)
        XCTAssertNil(item.richTextData)
        XCTAssertNil(item.mediaPath)
        XCTAssertNil(item.mediaPaths)
        XCTAssertNil(item.thumbnailPath)
        XCTAssertNil(item.sourceApp)
        XCTAssertFalse(item.isFavorite)
    }
    
    func testInitWithCustomValues() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1000)
        let item = ClipboardItem(
            id: id,
            contentType: .richText,
            textContent: "Test",
            richTextData: Data([0x01]),
            mediaPath: "/path/to/media",
            mediaPaths: ["/path1", "/path2"],
            thumbnailPath: "/path/to/thumb",
            sourceApp: "TestApp",
            createdAt: date,
            isFavorite: true
        )
        
        XCTAssertEqual(item.id, id)
        XCTAssertEqual(item.contentType, .richText)
        XCTAssertEqual(item.textContent, "Test")
        XCTAssertEqual(item.richTextData, Data([0x01]))
        XCTAssertEqual(item.mediaPath, "/path/to/media")
        XCTAssertEqual(item.mediaPaths, ["/path1", "/path2"])
        XCTAssertEqual(item.thumbnailPath, "/path/to/thumb")
        XCTAssertEqual(item.sourceApp, "TestApp")
        XCTAssertEqual(item.createdAt, date)
        XCTAssertTrue(item.isFavorite)
    }
    
    // MARK: - displayText
    
    func testDisplayTextReturnsTextContent() {
        let item = TestData.textItem(text: "Hello World")
        XCTAssertEqual(item.displayText, "Hello World")
    }
    
    func testDisplayTextTruncatesAt50Chars() {
        let longText = String(repeating: "A", count: 60)
        let item = TestData.textItem(text: longText)
        
        XCTAssertEqual(item.displayText.count, 53) // 50 + "..."
        XCTAssertTrue(item.displayText.hasSuffix("..."))
    }
    
    func testDisplayTextExactly50CharsNoTruncation() {
        let text = TestData.exactly50Chars
        let item = TestData.textItem(text: text)
        
        XCTAssertEqual(item.displayText, text)
        XCTAssertFalse(item.displayText.hasSuffix("..."))
    }
    
    func testDisplayTextTrimsWhitespace() {
        let item = TestData.textItem(text: "  Hello World  \n")
        XCTAssertEqual(item.displayText, "Hello World")
    }
    
    func testDisplayTextForFileStackShowsCount() {
        let item = TestData.fileStackItem(mediaPaths: ["/a", "/b", "/c"])
        XCTAssertEqual(item.displayText, "3 items")
    }
    
    func testDisplayTextForEmptyFileStack() {
        let item = ClipboardItem(contentType: .fileStack, mediaPaths: [])
        XCTAssertEqual(item.displayText, "0 items")
    }
    
    func testDisplayTextFallsBackToContentType() {
        let item = TestData.imageItem()
        XCTAssertEqual(item.displayText, "Image")
    }
    
    // MARK: - fullText
    
    func testFullTextReturnsTextContent() {
        let item = TestData.textItem(text: "Full text here")
        XCTAssertEqual(item.fullText, "Full text here")
    }
    
    func testFullTextReturnsEmptyForNil() {
        let item = TestData.imageItem()
        XCTAssertEqual(item.fullText, "")
    }
    
    // MARK: - needsTextPreview
    
    func testNeedsTextPreviewForLongText() {
        let item = TestData.textItem(text: TestData.exactly51Chars)
        XCTAssertTrue(item.needsTextPreview)
    }
    
    func testNeedsTextPreviewForMultiline() {
        let item = TestData.textItem(text: TestData.multilineText)
        XCTAssertTrue(item.needsTextPreview)
    }
    
    func testNeedsTextPreviewFalseForShort() {
        let item = TestData.textItem(text: TestData.shortText)
        XCTAssertFalse(item.needsTextPreview)
    }
    
    func testNeedsTextPreviewFalseForExactly50() {
        let item = TestData.textItem(text: TestData.exactly50Chars)
        XCTAssertFalse(item.needsTextPreview)
    }
    
    func testNeedsTextPreviewFalseForNil() {
        let item = TestData.imageItem()
        XCTAssertFalse(item.needsTextPreview)
    }
    
    func testNeedsTextPreviewIgnoresLeadingWhitespace() {
        // 30 spaces + 30 chars = 60 total, but trimmed is only 30
        let item = TestData.textItem(text: String(repeating: " ", count: 30) + String(repeating: "A", count: 30))
        XCTAssertFalse(item.needsTextPreview)
    }
    
    // MARK: - isTextFile
    
    func testIsTextFileRecognizesSwiftExtension() {
        let item = TestData.textFileItem(mediaPath: "/path/to/file.swift")
        XCTAssertTrue(item.isTextFile)
    }
    
    func testIsTextFileRecognizesPythonExtension() {
        let item = TestData.textFileItem(mediaPath: "/path/to/script.py")
        XCTAssertTrue(item.isTextFile)
    }
    
    func testIsTextFileRecognizesJsonExtension() {
        let item = TestData.textFileItem(mediaPath: "/path/to/data.json")
        XCTAssertTrue(item.isTextFile)
    }
    
    func testIsTextFileRecognizesMakefile() {
        let item = TestData.textFileItem(mediaPath: "/path/to/Makefile")
        XCTAssertTrue(item.isTextFile)
    }
    
    func testIsTextFileRecognizesDockerfile() {
        let item = TestData.textFileItem(mediaPath: "/path/to/Dockerfile")
        XCTAssertTrue(item.isTextFile)
    }
    
    func testIsTextFileFalseForNonFile() {
        let item = TestData.textItem(text: "Not a file")
        XCTAssertFalse(item.isTextFile)
    }
    
    func testIsTextFileFalseForUnknownExtension() {
        let item = TestData.fileItem(mediaPath: "/path/to/file.xyz")
        XCTAssertFalse(item.isTextFile)
    }
    
    func testIsTextFileFalseForImage() {
        let item = TestData.imageItem(mediaPath: "/path/to/image.png")
        XCTAssertFalse(item.isTextFile)
    }
    
    func testIsTextFileCaseInsensitive() {
        let item = TestData.textFileItem(mediaPath: "/path/to/FILE.SWIFT")
        XCTAssertTrue(item.isTextFile)
    }
    
    // MARK: - needsPreview
    
    func testNeedsPreviewForImage() {
        let item = TestData.imageItem()
        XCTAssertTrue(item.needsPreview)
    }
    
    func testNeedsPreviewForVideo() {
        let item = TestData.videoItem()
        XCTAssertTrue(item.needsPreview)
    }
    
    func testNeedsPreviewForFileStack() {
        let item = TestData.fileStackItem()
        XCTAssertTrue(item.needsPreview)
    }
    
    func testNeedsPreviewForLongText() {
        let item = TestData.textItem(text: TestData.longText)
        XCTAssertTrue(item.needsPreview)
    }
    
    func testNeedsPreviewForTextFile() {
        let item = TestData.textFileItem(mediaPath: "/path/code.swift")
        XCTAssertTrue(item.needsPreview)
    }
    
    func testNeedsPreviewTrueForShortText() {
        // All text items now show preview
        let item = TestData.textItem(text: TestData.shortText)
        XCTAssertTrue(item.needsPreview)
    }
    
    // MARK: - fileCount
    
    func testFileCountForSingleFile() {
        let item = TestData.fileItem(mediaPath: "/path/file.pdf")
        XCTAssertEqual(item.fileCount, 1)
    }
    
    func testFileCountForImage() {
        let item = TestData.imageItem(mediaPath: "/path/image.png")
        XCTAssertEqual(item.fileCount, 1)
    }
    
    func testFileCountForFileStack() {
        let item = TestData.fileStackItem(mediaPaths: ["/a", "/b", "/c", "/d"])
        XCTAssertEqual(item.fileCount, 4)
    }
    
    func testFileCountZeroWhenNoMedia() {
        let item = TestData.textItem()
        XCTAssertEqual(item.fileCount, 0)
    }
    
    // MARK: - fileNames
    
    func testFileNamesForSingleFile() {
        let item = TestData.fileItem(mediaPath: "/path/to/document.pdf")
        XCTAssertEqual(item.fileNames, ["document.pdf"])
    }
    
    func testFileNamesForFileStack() {
        let item = TestData.fileStackItem(mediaPaths: ["/path/a.txt", "/path/b.pdf", "/path/c.png"])
        XCTAssertEqual(item.fileNames, ["a.txt", "b.pdf", "c.png"])
    }
    
    func testFileNamesExtractsOriginalFromStoragePath() {
        // Test that UUID-prefixed storage paths return just the original filename
        let storagePath = "/Library/ClipboardMenu/Media/A19D867C-B777-4550-8209-02DF77F01D6C_0_document.pdf"
        let item = TestData.fileItem(mediaPath: storagePath)
        XCTAssertEqual(item.fileNames, ["document.pdf"])
    }
    
    func testFileNamesExtractsOriginalFromStoragePathsInStack() {
        // Test that UUID-prefixed storage paths return just the original filenames for stacks
        let storagePaths = [
            "/Library/ClipboardMenu/Media/A19D867C-B777-4550-8209-02DF77F01D6C_0_file1.txt",
            "/Library/ClipboardMenu/Media/A19D867C-B777-4550-8209-02DF77F01D6C_1_file2.pdf",
            "/Library/ClipboardMenu/Media/A19D867C-B777-4550-8209-02DF77F01D6C_2_file3.png"
        ]
        let item = TestData.fileStackItem(mediaPaths: storagePaths)
        XCTAssertEqual(item.fileNames, ["file1.txt", "file2.pdf", "file3.png"])
    }
    
    func testFileNamesExternalPathsUnchanged() {
        // Test that external paths (not in app storage) remain unchanged
        let externalPaths = [
            "/Users/test/Documents/report.pdf",
            "/Users/test/Downloads/image.png"
        ]
        let item = TestData.fileStackItem(mediaPaths: externalPaths)
        XCTAssertEqual(item.fileNames, ["report.pdf", "image.png"])
    }
    
    func testFileNamesEmptyWhenNoMedia() {
        let item = TestData.textItem()
        XCTAssertEqual(item.fileNames, [])
    }
    
    // MARK: - isFileReference
    
    func testIsFileReferenceExternalPath() {
        let item = TestData.fileItem(mediaPath: "/Users/test/Documents/file.pdf")
        XCTAssertTrue(item.isFileReference)
    }
    
    func testIsFileReferenceInternalPath() {
        let item = TestData.fileItem(mediaPath: "/Users/test/Library/Application Support/ClipboardMenu/Media/file.pdf")
        XCTAssertFalse(item.isFileReference)
    }
    
    func testIsFileReferenceForFileStackExternal() {
        let item = TestData.fileStackItem(mediaPaths: ["/external/a.txt", "/external/b.txt"])
        XCTAssertTrue(item.isFileReference)
    }
    
    func testIsFileReferenceForFileStackInternal() {
        let item = TestData.fileStackItem(mediaPaths: [
            "/Library/ClipboardMenu/a.txt",
            "/Library/ClipboardMenu/b.txt"
        ])
        XCTAssertFalse(item.isFileReference)
    }
    
    func testIsFileReferenceFalseForText() {
        let item = TestData.textItem()
        XCTAssertFalse(item.isFileReference)
    }
    
    // MARK: - hasValidFileReference
    
    func testHasValidFileReferenceForNonFileReference() {
        // Items that are not file references always return true
        let item = TestData.textItem()
        XCTAssertTrue(item.hasValidFileReference)
    }
    
    func testHasValidFileReferenceForInternalPath() {
        // Internal paths (copied to app storage) are not file references, so always valid
        let item = TestData.fileItem(mediaPath: "/Users/test/Library/Application Support/ClipboardMenu/Media/file.pdf")
        XCTAssertTrue(item.hasValidFileReference)
    }
    
    func testHasValidFileReferenceForExistingExternalFile() throws {
        // Create a temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test_valid_reference_\(UUID().uuidString).txt")
        try "test content".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        let item = TestData.fileItem(mediaPath: tempFile.path)
        XCTAssertTrue(item.hasValidFileReference)
    }
    
    func testHasValidFileReferenceForDeletedExternalFile() {
        // Path to a file that doesn't exist
        let item = TestData.fileItem(mediaPath: "/nonexistent/path/to/deleted_file.pdf")
        XCTAssertFalse(item.hasValidFileReference)
    }
    
    func testHasValidFileReferenceForFileStackAllExist() throws {
        // Create temporary files
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile1 = tempDir.appendingPathComponent("test_stack_1_\(UUID().uuidString).txt")
        let tempFile2 = tempDir.appendingPathComponent("test_stack_2_\(UUID().uuidString).txt")
        try "content 1".write(to: tempFile1, atomically: true, encoding: .utf8)
        try "content 2".write(to: tempFile2, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: tempFile1)
            try? FileManager.default.removeItem(at: tempFile2)
        }
        
        let item = TestData.fileStackItem(mediaPaths: [tempFile1.path, tempFile2.path])
        XCTAssertTrue(item.hasValidFileReference)
    }
    
    func testHasValidFileReferenceForFileStackSomeMissing() throws {
        // Create one temporary file, reference another that doesn't exist
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile1 = tempDir.appendingPathComponent("test_stack_exists_\(UUID().uuidString).txt")
        try "content".write(to: tempFile1, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile1) }
        
        // ANY missing file should make it invalid
        let item = TestData.fileStackItem(mediaPaths: [tempFile1.path, "/nonexistent/deleted.txt"])
        XCTAssertFalse(item.hasValidFileReference)
    }
    
    func testHasValidFileReferenceForFileStackAllMissing() {
        let item = TestData.fileStackItem(mediaPaths: ["/nonexistent/a.txt", "/nonexistent/b.txt"])
        XCTAssertFalse(item.hasValidFileReference)
    }
    
    // MARK: - formattedDate
    
    func testFormattedDateReturnsString() {
        let item = TestData.textItem(createdAt: Date())
        XCTAssertFalse(item.formattedDate.isEmpty)
    }
    
    // MARK: - Codable
    
    func testCodableRoundTrip() throws {
        let item = TestData.textItem(
            text: "Test content",
            sourceApp: "TestApp",
            isFavorite: true
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let encoded = try encoder.encode(item)
        let decoded = try decoder.decode(ClipboardItem.self, from: encoded)
        
        XCTAssertEqual(decoded.id, item.id)
        XCTAssertEqual(decoded.contentType, item.contentType)
        XCTAssertEqual(decoded.textContent, item.textContent)
        XCTAssertEqual(decoded.sourceApp, item.sourceApp)
        XCTAssertEqual(decoded.isFavorite, item.isFavorite)
    }
    
    func testCodableWithAllFields() throws {
        let item = ClipboardItem(
            id: UUID(),
            contentType: .fileStack,
            textContent: "Text",
            richTextData: Data([0x01, 0x02]),
            mediaPath: "/path",
            mediaPaths: ["/a", "/b"],
            thumbnailPath: "/thumb",
            sourceApp: "App",
            createdAt: Date(),
            isFavorite: true
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let encoded = try encoder.encode(item)
        let decoded = try decoder.decode(ClipboardItem.self, from: encoded)
        
        XCTAssertEqual(decoded, item)
    }
    
    // MARK: - Equatable
    
    func testEquatableEqual() {
        let id = UUID()
        let date = Date()
        let item1 = ClipboardItem(id: id, contentType: .text, textContent: "Test", createdAt: date)
        let item2 = ClipboardItem(id: id, contentType: .text, textContent: "Test", createdAt: date)
        
        XCTAssertEqual(item1, item2)
    }
    
    func testEquatableNotEqualDifferentId() {
        let item1 = TestData.textItem(text: "Same text")
        let item2 = TestData.textItem(text: "Same text")
        
        XCTAssertNotEqual(item1, item2)
    }
    
    // MARK: - GRDB
    
    func testGRDBTableName() {
        XCTAssertEqual(ClipboardItem.databaseTableName, "clipboard_items")
    }
    
    func testGRDBColumnsExist() {
        // Verify all column expressions exist
        _ = ClipboardItem.Columns.id
        _ = ClipboardItem.Columns.contentType
        _ = ClipboardItem.Columns.textContent
        _ = ClipboardItem.Columns.richTextData
        _ = ClipboardItem.Columns.mediaPath
        _ = ClipboardItem.Columns.mediaPaths
        _ = ClipboardItem.Columns.thumbnailPath
        _ = ClipboardItem.Columns.sourceApp
        _ = ClipboardItem.Columns.createdAt
        _ = ClipboardItem.Columns.isFavorite
    }
    
    // MARK: - sizeOnDisk
    
    func testSizeOnDiskForTextItem() {
        let text = "Hello, World!"
        let item = TestData.textItem(text: text)
        
        // Size should be the UTF-8 byte count of the text
        XCTAssertEqual(item.sizeOnDisk, Int64(text.utf8.count))
    }
    
    func testSizeOnDiskForEmptyTextItem() {
        let item = ClipboardItem(contentType: .text)
        
        XCTAssertEqual(item.sizeOnDisk, 0)
    }
    
    func testSizeOnDiskForRichTextItem() {
        let text = "Rich text"
        let richData = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        let item = TestData.richTextItem(text: text, richTextData: richData)
        
        // Size should be text size + rich text data size
        let expectedSize = Int64(text.utf8.count) + Int64(richData.count)
        XCTAssertEqual(item.sizeOnDisk, expectedSize)
    }
    
    func testSizeOnDiskForNonexistentMediaPath() {
        let item = TestData.imageItem(mediaPath: "/nonexistent/path/image.png")
        
        // Should return 0 for nonexistent files (no text content either)
        XCTAssertEqual(item.sizeOnDisk, 0)
    }
    
    func testSizeOnDiskForNonexistentFileStackPaths() {
        let item = TestData.fileStackItem(mediaPaths: ["/nonexistent/a.txt", "/nonexistent/b.txt"])
        
        // Should return 0 for nonexistent files
        XCTAssertEqual(item.sizeOnDisk, 0)
    }
    
    func testSizeOnDiskCombinesTextAndRichText() {
        let text = "Test"
        let richData = Data(count: 100)
        
        let item = ClipboardItem(
            contentType: .richText,
            textContent: text,
            richTextData: richData
        )
        
        XCTAssertEqual(item.sizeOnDisk, Int64(text.utf8.count) + Int64(richData.count))
    }
    
    func testSizeOnDiskForLargeText() {
        let largeText = String(repeating: "A", count: 10000)
        let item = TestData.textItem(text: largeText)
        
        XCTAssertEqual(item.sizeOnDisk, 10000)
    }
    
    func testSizeOnDiskForUnicodeText() {
        let unicodeText = "Hello 世界 🌍"
        let item = TestData.textItem(text: unicodeText)
        
        // UTF-8 encoding: "Hello " = 6, "世界" = 6 (3 bytes each), " " = 1, "🌍" = 4
        XCTAssertEqual(item.sizeOnDisk, Int64(unicodeText.utf8.count))
    }
    
    func testSizeOnDiskForRealFile() throws {
        let tempDir = try TempDirectory()
        let fileContent = Data(repeating: 0x42, count: 500)
        let fileURL = try tempDir.createFile(name: "test.bin", content: fileContent)
        
        let item = TestData.fileItem(mediaPath: fileURL.path)
        
        XCTAssertEqual(item.sizeOnDisk, 500)
    }
    
    func testSizeOnDiskForFolder() throws {
        let tempDir = try TempDirectory()
        
        // Create a folder with some files
        let folderURL = try tempDir.createSubdirectory(name: "TestFolder")
        
        // Create files inside the folder
        let file1Content = Data(repeating: 0x41, count: 100)
        let file2Content = Data(repeating: 0x42, count: 200)
        let file3Content = Data(repeating: 0x43, count: 300)
        
        try file1Content.write(to: folderURL.appendingPathComponent("file1.txt"))
        try file2Content.write(to: folderURL.appendingPathComponent("file2.txt"))
        try file3Content.write(to: folderURL.appendingPathComponent("file3.txt"))
        
        let item = TestData.fileItem(mediaPath: folderURL.path)
        
        // Folder size should be sum of all file contents: 100 + 200 + 300 = 600
        XCTAssertEqual(item.sizeOnDisk, 600)
    }
    
    func testSizeOnDiskForNestedFolder() throws {
        let tempDir = try TempDirectory()
        
        // Create a folder with nested subfolders
        let rootFolder = try tempDir.createSubdirectory(name: "RootFolder")
        let subFolder = rootFolder.appendingPathComponent("SubFolder", isDirectory: true)
        try FileManager.default.createDirectory(at: subFolder, withIntermediateDirectories: true)
        
        // Create files at different levels
        try Data(repeating: 0x41, count: 100).write(to: rootFolder.appendingPathComponent("root.txt"))
        try Data(repeating: 0x42, count: 200).write(to: subFolder.appendingPathComponent("sub.txt"))
        
        let item = TestData.fileItem(mediaPath: rootFolder.path)
        
        // Total: 100 + 200 = 300
        XCTAssertEqual(item.sizeOnDisk, 300)
    }
    
    func testSizeOnDiskForEmptyFolder() throws {
        let tempDir = try TempDirectory()
        let emptyFolder = try tempDir.createSubdirectory(name: "EmptyFolder")
        
        let item = TestData.fileItem(mediaPath: emptyFolder.path)
        
        XCTAssertEqual(item.sizeOnDisk, 0)
    }
    
    func testSizeOnDiskForFileStackWithFolder() throws {
        let tempDir = try TempDirectory()
        
        // Create a regular file
        let fileContent = Data(repeating: 0x41, count: 150)
        let fileURL = try tempDir.createFile(name: "file.txt", content: fileContent)
        
        // Create a folder with files
        let folderURL = try tempDir.createSubdirectory(name: "Folder")
        try Data(repeating: 0x42, count: 250).write(to: folderURL.appendingPathComponent("inside.txt"))
        
        let item = TestData.fileStackItem(mediaPaths: [fileURL.path, folderURL.path])
        
        // Total: 150 (file) + 250 (folder contents) = 400
        XCTAssertEqual(item.sizeOnDisk, 400)
    }
    
    // MARK: - isCloudFile Tests
    
    func testIsCloudFileFalseForNonFileReference() {
        let item = TestData.textItem(text: "Just text")
        
        XCTAssertFalse(item.isCloudFile)
    }
    
    func testIsCloudFileFalseForInternalStoragePath() {
        // Internal storage paths (in Application Support) are not cloud files
        let item = ClipboardItem(
            contentType: .file,
            textContent: "file.txt",
            mediaPath: "/Users/test/Library/Application Support/ClipboardMenu/media/uuid_file.txt"
        )
        
        XCTAssertFalse(item.isCloudFile)
    }
    
    func testIsCloudFileFalseForLocalFile() throws {
        let tempDir = try TempDirectory()
        let fileURL = try tempDir.createFile(name: "local.txt", content: "Local content")
        
        // Use temp path which is external (not containing "ClipboardMenu")
        let item = ClipboardItem(
            contentType: .file,
            textContent: "local.txt",
            mediaPath: fileURL.path
        )
        
        // Verify it's a file reference (external path)
        XCTAssertTrue(item.isFileReference)
        // Local temp files are not cloud files
        XCTAssertFalse(item.isCloudFile)
    }
    
    func testIsCloudFileFalseForNilMediaPath() {
        // File with external-looking path but nil
        let item = ClipboardItem(
            contentType: .file,
            textContent: "file.txt",
            mediaPath: nil
        )
        
        XCTAssertFalse(item.isCloudFile)
    }
    
    func testIsCloudFileFalseForFileStackWithLocalPaths() throws {
        let tempDir = try TempDirectory()
        let file1 = try tempDir.createFile(name: "file1.txt", content: "Content 1")
        let file2 = try tempDir.createFile(name: "file2.txt", content: "Content 2")
        
        let item = ClipboardItem(
            contentType: .fileStack,
            mediaPaths: [file1.path, file2.path]
        )
        
        // Should be file reference (external paths)
        XCTAssertTrue(item.isFileReference)
        XCTAssertFalse(item.isCloudFile)
    }
    
    func testIsCloudFileFalseForFileStackWithNilPaths() {
        let item = ClipboardItem(
            contentType: .fileStack,
            mediaPaths: nil
        )
        
        XCTAssertFalse(item.isCloudFile)
    }
    
    // MARK: - isCloudFileNotDownloaded Tests
    
    func testIsCloudFileNotDownloadedFalseForNonFileReference() {
        let item = TestData.textItem(text: "Text content")
        
        XCTAssertFalse(item.isCloudFileNotDownloaded)
    }
    
    func testIsCloudFileNotDownloadedFalseForLocalFile() throws {
        let tempDir = try TempDirectory()
        let fileURL = try tempDir.createFile(name: "downloaded.txt", content: "Downloaded")
        
        let item = ClipboardItem(
            contentType: .file,
            textContent: "downloaded.txt",
            mediaPath: fileURL.path
        )
        
        // Verify it's a file reference
        XCTAssertTrue(item.isFileReference)
        // Local files are "downloaded" (available)
        XCTAssertFalse(item.isCloudFileNotDownloaded)
    }
    
    func testIsCloudFileNotDownloadedFalseForNilMediaPath() {
        let item = ClipboardItem(
            contentType: .file,
            textContent: "file.txt",
            mediaPath: nil
        )
        
        XCTAssertFalse(item.isCloudFileNotDownloaded)
    }
    
    func testIsCloudFileNotDownloadedFalseForNonexistentPath() {
        // Use external path (not containing "ClipboardMenu")
        let item = ClipboardItem(
            contentType: .file,
            textContent: "missing.txt",
            mediaPath: "/nonexistent/path/missing.txt"
        )
        
        // Verify it's a file reference
        XCTAssertTrue(item.isFileReference)
        // Non-existent files return false (can't determine cloud status)
        XCTAssertFalse(item.isCloudFileNotDownloaded)
    }
    
    func testIsCloudFileNotDownloadedFalseForFileStackWithLocalPaths() throws {
        let tempDir = try TempDirectory()
        let file1 = try tempDir.createFile(name: "stack1.txt", content: "Content 1")
        let file2 = try tempDir.createFile(name: "stack2.txt", content: "Content 2")
        
        let item = ClipboardItem(
            contentType: .fileStack,
            mediaPaths: [file1.path, file2.path]
        )
        
        XCTAssertTrue(item.isFileReference)
        XCTAssertFalse(item.isCloudFileNotDownloaded)
    }
    
    func testIsCloudFileNotDownloadedFalseForFileStackWithNilPaths() {
        let item = ClipboardItem(
            contentType: .fileStack,
            mediaPaths: nil
        )
        
        XCTAssertFalse(item.isCloudFileNotDownloaded)
    }
    
    func testIsCloudFileNotDownloadedFalseForInternalStorage() {
        let item = ClipboardItem(
            contentType: .image,
            mediaPath: "/Users/test/Library/Application Support/ClipboardMenu/media/uuid.png"
        )
        
        // Internal storage is not a file reference
        XCTAssertFalse(item.isFileReference)
        XCTAssertFalse(item.isCloudFileNotDownloaded)
    }
    
    // MARK: - bookmarkData Tests
    
    func testBookmarkDataDefaultsToNil() {
        let item = TestData.textItem()
        
        XCTAssertNil(item.bookmarkData)
    }
    
    func testBookmarkDataCanBeSet() {
        var item = TestData.fileItem()
        let testData = Data("bookmark".utf8)
        
        item.bookmarkData = testData
        
        XCTAssertEqual(item.bookmarkData, testData)
    }
    
    func testBookmarkDatasDefaultsToNil() {
        let item = TestData.fileStackItem(mediaPaths: ["/path/file1.txt"])
        
        XCTAssertNil(item.bookmarkDatas)
    }
    
    func testBookmarkDatasCanBeSet() {
        var item = TestData.fileStackItem(mediaPaths: ["/path/file1.txt", "/path/file2.txt"])
        let testDatas = [Data("bookmark1".utf8), Data("bookmark2".utf8)]
        
        item.bookmarkDatas = testDatas
        
        XCTAssertEqual(item.bookmarkDatas, testDatas)
    }
}
