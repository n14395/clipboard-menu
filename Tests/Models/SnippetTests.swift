import XCTest
@testable import ClipboardMenu

final class SnippetTests: XCTestCase {
    
    // MARK: - Initialization
    
    func testInitWithDefaults() {
        let snippet = Snippet(contentType: .text)
        
        XCTAssertNotNil(snippet.id)
        XCTAssertEqual(snippet.name, "")
        XCTAssertEqual(snippet.contentType, .text)
        XCTAssertNil(snippet.textContent)
        XCTAssertNil(snippet.richTextData)
        XCTAssertNil(snippet.mediaPath)
        XCTAssertNil(snippet.mediaPaths)
        XCTAssertNil(snippet.thumbnailPath)
        XCTAssertEqual(snippet.sortOrder, 0)
    }
    
    func testInitWithCustomValues() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1000)
        let snippet = Snippet(
            id: id,
            name: "My Snippet",
            contentType: .richText,
            textContent: "Content",
            richTextData: Data([0x01]),
            mediaPath: "/path",
            mediaPaths: ["/a", "/b"],
            thumbnailPath: "/thumb",
            createdAt: date,
            modifiedAt: date,
            sortOrder: 5
        )
        
        XCTAssertEqual(snippet.id, id)
        XCTAssertEqual(snippet.name, "My Snippet")
        XCTAssertEqual(snippet.contentType, .richText)
        XCTAssertEqual(snippet.textContent, "Content")
        XCTAssertEqual(snippet.richTextData, Data([0x01]))
        XCTAssertEqual(snippet.mediaPath, "/path")
        XCTAssertEqual(snippet.mediaPaths, ["/a", "/b"])
        XCTAssertEqual(snippet.thumbnailPath, "/thumb")
        XCTAssertEqual(snippet.createdAt, date)
        XCTAssertEqual(snippet.modifiedAt, date)
        XCTAssertEqual(snippet.sortOrder, 5)
    }
    
    // MARK: - Init from ClipboardItem
    
    func testInitFromClipboardItemPreservesContent() {
        let item = TestData.textItem(text: "Original content")
        let snippet = Snippet(from: item)
        
        XCTAssertEqual(snippet.contentType, item.contentType)
        XCTAssertEqual(snippet.textContent, item.textContent)
    }
    
    func testInitFromClipboardItemGeneratesNewId() {
        let item = TestData.textItem()
        let snippet = Snippet(from: item)
        
        XCTAssertNotEqual(snippet.id, item.id)
    }
    
    func testInitFromClipboardItemSetsNewDates() {
        let oldDate = Date(timeIntervalSince1970: 1000)
        let item = TestData.textItem(createdAt: oldDate)
        
        let beforeCreation = Date()
        let snippet = Snippet(from: item)
        let afterCreation = Date()
        
        XCTAssertGreaterThanOrEqual(snippet.createdAt, beforeCreation)
        XCTAssertLessThanOrEqual(snippet.createdAt, afterCreation)
        XCTAssertGreaterThanOrEqual(snippet.modifiedAt, beforeCreation)
        XCTAssertLessThanOrEqual(snippet.modifiedAt, afterCreation)
    }
    
    func testInitFromClipboardItemWithEmptyNameUsesDisplayText() {
        let item = TestData.textItem(text: "The display text")
        let snippet = Snippet(from: item, name: "")
        
        XCTAssertEqual(snippet.name, "The display text")
    }
    
    func testInitFromClipboardItemWithCustomName() {
        let item = TestData.textItem(text: "Original text")
        let snippet = Snippet(from: item, name: "Custom Name")
        
        XCTAssertEqual(snippet.name, "Custom Name")
    }
    
    func testInitFromClipboardItemPreservesMediaPaths() {
        let item = TestData.fileStackItem(mediaPaths: ["/a", "/b", "/c"])
        let snippet = Snippet(from: item)
        
        XCTAssertEqual(snippet.contentType, .fileStack)
        XCTAssertEqual(snippet.mediaPaths, ["/a", "/b", "/c"])
    }
    
    func testInitFromClipboardItemPreservesRichTextData() {
        let item = TestData.richTextItem(richTextData: Data([0x01, 0x02, 0x03]))
        let snippet = Snippet(from: item)
        
        XCTAssertEqual(snippet.richTextData, Data([0x01, 0x02, 0x03]))
    }
    
    // MARK: - displayText
    
    func testDisplayTextReturnsNameWhenSet() {
        let snippet = TestData.snippet(name: "My Snippet Name", textContent: "Some content")
        XCTAssertEqual(snippet.displayText, "My Snippet Name")
    }
    
    func testDisplayTextFallsBackToTruncatedText() {
        let snippet = Snippet(name: "", contentType: .text, textContent: "This is the text content")
        XCTAssertEqual(snippet.displayText, "This is the text content")
    }
    
    func testDisplayTextTruncatesLongContent() {
        let longText = String(repeating: "A", count: 60)
        let snippet = Snippet(name: "", contentType: .text, textContent: longText)
        
        XCTAssertEqual(snippet.displayText.count, 53) // 50 + "..."
        XCTAssertTrue(snippet.displayText.hasSuffix("..."))
    }
    
    func testDisplayTextFallsBackToContentType() {
        let snippet = Snippet(name: "", contentType: .image)
        XCTAssertEqual(snippet.displayText, "Image")
    }
    
    // MARK: - fullText
    
    func testFullTextReturnsTextContent() {
        let snippet = TestData.snippet(textContent: "Full content here")
        XCTAssertEqual(snippet.fullText, "Full content here")
    }
    
    func testFullTextReturnsEmptyForNil() {
        let snippet = TestData.imageSnippet()
        XCTAssertEqual(snippet.fullText, "")
    }
    
    // MARK: - needsTextPreview
    
    func testNeedsTextPreviewForLongText() {
        let snippet = TestData.snippet(textContent: TestData.longText)
        XCTAssertTrue(snippet.needsTextPreview)
    }
    
    func testNeedsTextPreviewForMultiline() {
        let snippet = TestData.snippet(textContent: TestData.multilineText)
        XCTAssertTrue(snippet.needsTextPreview)
    }
    
    func testNeedsTextPreviewFalseForShort() {
        let snippet = TestData.snippet(textContent: TestData.shortText)
        XCTAssertFalse(snippet.needsTextPreview)
    }
    
    // MARK: - isTextFile
    
    func testIsTextFileRecognizesExtensions() {
        let snippet = Snippet(name: "Code", contentType: .file, mediaPath: "/path/file.swift")
        XCTAssertTrue(snippet.isTextFile)
    }
    
    func testIsTextFileFalseForNonFile() {
        let snippet = TestData.snippet(contentType: .text)
        XCTAssertFalse(snippet.isTextFile)
    }
    
    func testIsTextFileFalseForUnknownExtension() {
        let snippet = Snippet(name: "Doc", contentType: .file, mediaPath: "/path/file.unknown")
        XCTAssertFalse(snippet.isTextFile)
    }
    
    // MARK: - needsPreview
    
    func testNeedsPreviewForImage() {
        let snippet = TestData.imageSnippet()
        XCTAssertTrue(snippet.needsPreview)
    }
    
    func testNeedsPreviewForVideo() {
        let snippet = Snippet(name: "Video", contentType: .video, mediaPath: "/path/video.mp4")
        XCTAssertTrue(snippet.needsPreview)
    }
    
    func testNeedsPreviewForFileStack() {
        let snippet = Snippet(name: "Files", contentType: .fileStack, mediaPaths: ["/a", "/b"])
        XCTAssertTrue(snippet.needsPreview)
    }
    
    func testNeedsPreviewForLongText() {
        let snippet = TestData.snippet(textContent: TestData.longText)
        XCTAssertTrue(snippet.needsPreview)
    }
    
    func testNeedsPreviewTrueForShortText() {
        // All text items now show preview
        let snippet = TestData.snippet(textContent: TestData.shortText)
        XCTAssertTrue(snippet.needsPreview)
    }
    
    // MARK: - Codable
    
    func testCodableRoundTrip() throws {
        let snippet = TestData.snippet(
            name: "Test Snippet",
            textContent: "Content"
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let encoded = try encoder.encode(snippet)
        let decoded = try decoder.decode(Snippet.self, from: encoded)
        
        XCTAssertEqual(decoded.id, snippet.id)
        XCTAssertEqual(decoded.name, snippet.name)
        XCTAssertEqual(decoded.contentType, snippet.contentType)
        XCTAssertEqual(decoded.textContent, snippet.textContent)
        XCTAssertEqual(decoded.sortOrder, snippet.sortOrder)
    }
    
    func testCodableWithAllFields() throws {
        let snippet = Snippet(
            id: UUID(),
            name: "Full Snippet",
            contentType: .fileStack,
            textContent: "Text",
            richTextData: Data([0x01]),
            mediaPath: "/path",
            mediaPaths: ["/a", "/b"],
            thumbnailPath: "/thumb",
            createdAt: Date(),
            modifiedAt: Date(),
            sortOrder: 3
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let encoded = try encoder.encode(snippet)
        let decoded = try decoder.decode(Snippet.self, from: encoded)
        
        XCTAssertEqual(decoded, snippet)
    }
    
    // MARK: - Equatable
    
    func testEquatableEqual() {
        let id = UUID()
        let date = Date()
        let s1 = Snippet(id: id, name: "S", contentType: .text, createdAt: date, modifiedAt: date)
        let s2 = Snippet(id: id, name: "S", contentType: .text, createdAt: date, modifiedAt: date)
        
        XCTAssertEqual(s1, s2)
    }
    
    func testEquatableNotEqualDifferentId() {
        let s1 = TestData.snippet(name: "Same")
        let s2 = TestData.snippet(name: "Same")
        
        XCTAssertNotEqual(s1, s2)
    }
    
    // MARK: - GRDB
    
    func testGRDBTableName() {
        XCTAssertEqual(Snippet.databaseTableName, "snippets")
    }
    
    func testGRDBColumnsExist() {
        _ = Snippet.Columns.id
        _ = Snippet.Columns.name
        _ = Snippet.Columns.contentType
        _ = Snippet.Columns.textContent
        _ = Snippet.Columns.richTextData
        _ = Snippet.Columns.mediaPath
        _ = Snippet.Columns.mediaPaths
        _ = Snippet.Columns.thumbnailPath
        _ = Snippet.Columns.createdAt
        _ = Snippet.Columns.modifiedAt
        _ = Snippet.Columns.sortOrder
    }
    
    // MARK: - previewText
    
    func testPreviewTextReturnsTextContent() {
        let snippet = TestData.snippet(textContent: "Hello World")
        
        XCTAssertEqual(snippet.previewText, "Hello World")
    }
    
    func testPreviewTextReturnsNilForNoContent() {
        let snippet = TestData.snippet(contentType: .image, textContent: nil)
        
        XCTAssertNil(snippet.previewText)
    }
    
    func testPreviewTextLoadsTextFileContents() throws {
        // Create a temp file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test_preview_\(UUID().uuidString).txt")
        try "File contents here".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        let snippet = Snippet(contentType: .file, mediaPath: tempFile.path)
        
        XCTAssertEqual(snippet.previewText, "File contents here")
    }
    
    func testPreviewTextReturnsNilForNonexistentFile() {
        let snippet = Snippet(contentType: .file, mediaPath: "/nonexistent/file.txt")
        
        XCTAssertNil(snippet.previewText)
    }
    
    func testPreviewTextReturnsNilForNonTextFile() {
        // Binary extension, should not try to read
        let snippet = Snippet(contentType: .file, mediaPath: "/some/file.pdf")
        
        // PDF is not a text extension, so previewText should return nil
        XCTAssertNil(snippet.previewText)
    }
    
    // MARK: - isFolder
    
    func testIsFolderReturnsTrueForDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let folder = tempDir.appendingPathComponent("test_folder_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        
        let snippet = Snippet(contentType: .file, mediaPath: folder.path)
        
        XCTAssertTrue(snippet.isFolder)
    }
    
    func testIsFolderReturnsFalseForFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let file = tempDir.appendingPathComponent("test_file_\(UUID().uuidString).txt")
        try "content".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        
        let snippet = Snippet(contentType: .file, mediaPath: file.path)
        
        XCTAssertFalse(snippet.isFolder)
    }
    
    func testIsFolderReturnsTrueForPathWithoutExtension() {
        // Uses heuristic: paths without extensions are treated as folders
        let snippet = Snippet(contentType: .file, mediaPath: "/nonexistent/folder")
        
        XCTAssertTrue(snippet.isFolder)
    }
    
    func testIsFolderReturnsFalseForPathWithExtension() {
        // Uses heuristic: paths with extensions are treated as files
        let snippet = Snippet(contentType: .file, mediaPath: "/nonexistent/file.txt")
        
        XCTAssertFalse(snippet.isFolder)
    }
    
    func testIsFolderReturnsFalseForNonFileType() {
        let snippet = TestData.snippet(contentType: .text)
        
        XCTAssertFalse(snippet.isFolder)
    }
    
    // MARK: - fileSystemImageName
    
    func testFileSystemImageNameReturnsDocForFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let file = tempDir.appendingPathComponent("test_\(UUID().uuidString).txt")
        try "content".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        
        let snippet = Snippet(contentType: .file, mediaPath: file.path)
        
        XCTAssertEqual(snippet.fileSystemImageName, "doc")
    }
    
    func testFileSystemImageNameReturnsFolderFillForDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let folder = tempDir.appendingPathComponent("test_folder_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        
        let snippet = Snippet(contentType: .file, mediaPath: folder.path)
        
        XCTAssertEqual(snippet.fileSystemImageName, "folder.fill")
    }
    
    func testFileSystemImageNameReturnsFolderFillForPathWithoutExtension() {
        // Uses heuristic: paths without extensions are treated as folders
        let snippet = Snippet(contentType: .file, mediaPath: "/nonexistent/path")
        
        XCTAssertEqual(snippet.fileSystemImageName, "folder.fill")
    }
    
    func testFileSystemImageNameReturnsDocForPathWithExtension() {
        // Uses heuristic: paths with extensions are treated as files
        let snippet = Snippet(contentType: .file, mediaPath: "/nonexistent/file.txt")
        
        XCTAssertEqual(snippet.fileSystemImageName, "doc")
    }
    
    // MARK: - Download State Tests
    
    func testIsDownloadingDefaultsToFalse() {
        let snippet = Snippet(name: "Test", contentType: .text, textContent: "Content")
        
        XCTAssertFalse(snippet.isDownloading)
    }
    
    func testIsDownloadingCanBeSetTrue() {
        var snippet = Snippet(name: "Test", contentType: .text, textContent: "Content")
        snippet.isDownloading = true
        
        XCTAssertTrue(snippet.isDownloading)
    }
    
    func testDownloadErrorDefaultsToNil() {
        let snippet = Snippet(name: "Test", contentType: .text, textContent: "Content")
        
        XCTAssertNil(snippet.downloadError)
    }
    
    func testDownloadErrorCanBeSet() {
        var snippet = Snippet(name: "Test", contentType: .text, textContent: "Content")
        snippet.downloadError = "Network failure"
        
        XCTAssertEqual(snippet.downloadError, "Network failure")
    }
    
    func testDownloadFileCountDefaultsToZero() {
        let snippet = Snippet(name: "Test", contentType: .text, textContent: "Content")
        
        XCTAssertEqual(snippet.downloadFileCount, 0)
    }
    
    func testDownloadFileCountCanBeSet() {
        var snippet = Snippet(name: "Test", contentType: .text, textContent: "Content")
        snippet.downloadFileCount = 5
        
        XCTAssertEqual(snippet.downloadFileCount, 5)
    }
    
    func testCurrentDownloadIndexDefaultsToZero() {
        let snippet = Snippet(name: "Test", contentType: .text, textContent: "Content")
        
        XCTAssertEqual(snippet.currentDownloadIndex, 0)
    }
    
    func testCurrentDownloadIndexCanBeSet() {
        var snippet = Snippet(name: "Test", contentType: .text, textContent: "Content")
        snippet.currentDownloadIndex = 3
        
        XCTAssertEqual(snippet.currentDownloadIndex, 3)
    }
    
    // MARK: - Cloud Path Tests
    
    func testCloudPathDefaultsToNil() {
        let snippet = Snippet(name: "Test", contentType: .file, mediaPath: "/local/path")
        
        XCTAssertNil(snippet.cloudPath)
    }
    
    func testCloudPathCanBeSet() {
        var snippet = Snippet(name: "Test", contentType: .file, mediaPath: "/local/path")
        snippet.cloudPath = "/Users/test/Library/Mobile Documents/iCloud/file.txt"
        
        XCTAssertEqual(snippet.cloudPath, "/Users/test/Library/Mobile Documents/iCloud/file.txt")
    }
    
    func testCloudPathsDefaultsToNil() {
        let snippet = Snippet(name: "Test", contentType: .fileStack, mediaPaths: ["/local/path1", "/local/path2"])
        
        XCTAssertNil(snippet.cloudPaths)
    }
    
    func testCloudPathsCanBeSet() {
        var snippet = Snippet(name: "Test", contentType: .fileStack, mediaPaths: ["/local/path1", "/local/path2"])
        let cloudPaths = ["/cloud/file1.txt", "/cloud/file2.txt"]
        snippet.cloudPaths = cloudPaths
        
        XCTAssertEqual(snippet.cloudPaths, cloudPaths)
    }
    
    // MARK: - isCloudFile Tests
    
    func testIsCloudFileFalseForNonFileReference() {
        let snippet = Snippet(name: "Text", contentType: .text, textContent: "Content")
        
        XCTAssertFalse(snippet.isCloudFile)
    }
    
    func testIsCloudFileFalseForLocalFilePath() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let file = tempDir.appendingPathComponent("cloud_test_\(UUID().uuidString).txt")
        try "content".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        
        // Temp directory paths don't contain "ClipboardMenu" so are file references
        let snippet = Snippet(name: "Local", contentType: .file, mediaPath: file.path)
        
        XCTAssertTrue(snippet.isFileReference)
        XCTAssertFalse(snippet.isCloudFile)
    }
    
    func testIsCloudFileFalseForNilMediaPath() {
        let snippet = Snippet(name: "No Path", contentType: .file, mediaPath: nil)
        
        XCTAssertFalse(snippet.isCloudFile)
    }
    
    func testIsCloudFileFalseForFileStackWithLocalPaths() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let file1 = tempDir.appendingPathComponent("stack1_\(UUID().uuidString).txt")
        let file2 = tempDir.appendingPathComponent("stack2_\(UUID().uuidString).txt")
        try "content1".write(to: file1, atomically: true, encoding: .utf8)
        try "content2".write(to: file2, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: file1)
            try? FileManager.default.removeItem(at: file2)
        }
        
        let snippet = Snippet(name: "Stack", contentType: .fileStack, mediaPaths: [file1.path, file2.path])
        
        XCTAssertTrue(snippet.isFileReference)
        XCTAssertFalse(snippet.isCloudFile)
    }
    
    // MARK: - isCloudFileNotDownloaded Tests
    
    func testIsCloudFileNotDownloadedFalseForNonFileReference() {
        let snippet = Snippet(name: "Text", contentType: .text, textContent: "Content")
        
        XCTAssertFalse(snippet.isCloudFileNotDownloaded)
    }
    
    func testIsCloudFileNotDownloadedFalseForLocalFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let file = tempDir.appendingPathComponent("download_test_\(UUID().uuidString).txt")
        try "content".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        
        let snippet = Snippet(name: "Local", contentType: .file, mediaPath: file.path)
        
        XCTAssertTrue(snippet.isFileReference)
        XCTAssertFalse(snippet.isCloudFileNotDownloaded)
    }
    
    func testIsCloudFileNotDownloadedFalseForNilMediaPath() {
        let snippet = Snippet(name: "No Path", contentType: .file, mediaPath: nil)
        
        XCTAssertFalse(snippet.isCloudFileNotDownloaded)
    }
    
    func testIsCloudFileNotDownloadedFalseForNonexistentPath() {
        // External path (not containing "ClipboardMenu")
        let snippet = Snippet(name: "Missing", contentType: .file, mediaPath: "/nonexistent/path.txt")
        
        XCTAssertTrue(snippet.isFileReference)
        // Non-existent files return false (can't determine status)
        XCTAssertFalse(snippet.isCloudFileNotDownloaded)
    }
    
    // MARK: - isFileReference Tests
    
    func testIsFileReferenceFalseForInternalPath() {
        // Internal path containing "ClipboardMenu"
        let snippet = Snippet(name: "Test", contentType: .file, mediaPath: "/Users/test/Library/Application Support/ClipboardMenu/media/file.txt")
        
        XCTAssertFalse(snippet.isFileReference)
    }
    
    func testIsFileReferenceTrueForExternalPath() {
        // External path (not containing "ClipboardMenu")
        let snippet = Snippet(name: "Test", contentType: .file, mediaPath: "/Users/test/Documents/file.txt")
        
        XCTAssertTrue(snippet.isFileReference)
    }
    
    // MARK: - Codable with Download State Tests
    
    func testCodablePreservesDownloadState() throws {
        var original = Snippet(name: "Download Test", contentType: .file, mediaPath: "/path")
        original.isDownloading = true
        original.downloadError = "Test error"
        original.downloadFileCount = 5
        original.currentDownloadIndex = 3
        original.cloudPath = "/cloud/path"
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Snippet.self, from: data)
        
        XCTAssertEqual(decoded.isDownloading, original.isDownloading)
        XCTAssertEqual(decoded.downloadError, original.downloadError)
        XCTAssertEqual(decoded.downloadFileCount, original.downloadFileCount)
        XCTAssertEqual(decoded.currentDownloadIndex, original.currentDownloadIndex)
        XCTAssertEqual(decoded.cloudPath, original.cloudPath)
    }
    
    func testCodablePreservesCloudPaths() throws {
        var original = Snippet(name: "Cloud Stack", contentType: .fileStack, mediaPaths: ["/local/1", "/local/2"])
        original.cloudPaths = ["/cloud/1", "/cloud/2"]
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Snippet.self, from: data)
        
        XCTAssertEqual(decoded.cloudPaths, original.cloudPaths)
    }
}
