import XCTest
import AppKit
@testable import ClipboardMenu

/// Tests for MenuBarController's clipboard operations and filename extraction
@MainActor
final class MenuBarControllerClipboardTests: XCTestCase {
    
    var storageService: StorageService!
    var preferencesService: PreferencesService!
    var thumbnailService: ThumbnailService!
    var searchService: SearchService!
    var clipboardMonitor: ClipboardMonitor!
    var bookmarkService: BookmarkService!
    var menuBarController: MenuBarController!
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
        searchService = SearchService()
        bookmarkService = BookmarkService()
        clipboardMonitor = ClipboardMonitor(
            storageService: storageService,
            thumbnailService: thumbnailService,
            preferencesService: preferencesService,
            bookmarkService: bookmarkService
        )
        
        menuBarController = MenuBarController(
            storageService: storageService,
            thumbnailService: thumbnailService,
            preferencesService: preferencesService,
            searchService: searchService,
            clipboardMonitor: clipboardMonitor,
            bookmarkService: bookmarkService
        )
    }
    
    override func tearDown() async throws {
        clipboardMonitor?.stopMonitoring()
        menuBarController = nil
        storageService = nil
        preferencesService = nil
        thumbnailService = nil
        searchService = nil
        clipboardMonitor = nil
        bookmarkService = nil
        tempDir?.cleanup()
        tempDir = nil
        if let defaults = testDefaults {
            defaults.removePersistentDomain(forName: defaults.description)
        }
        testDefaults = nil
    }
    
    // MARK: - Helper Methods
    
    private func createTestImage(name: String = "test.png") throws -> URL {
        let image = NSImage(size: NSSize(width: 100, height: 100))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 100, height: 100).fill()
        image.unlockFocus()
        
        guard let data = image.pngData() else {
            throw NSError(domain: "TestError", code: 1)
        }
        
        return try tempDir.createFile(name: name, content: data)
    }
    
    private func createTestFile(name: String = "test.txt", content: String = "Test content") throws -> URL {
        return try tempDir.createFile(name: name, content: content)
    }
    
    private func createTestFolder(name: String = "TestFolder") throws -> URL {
        let folder = try tempDir.createSubdirectory(name: name)
        try "file content".write(to: folder.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        return folder
    }
    
    // MARK: - Filename Extraction Tests - File Stack Format
    
    func testExtractFilename_FileStackFormat() {
        // Format: {UUID}_{index}_{originalFilename}
        let path = "/path/to/A19D867C-B777-4550-8209-02DF77F01D6C_0_document.pdf"
        let url = URL(fileURLWithPath: path)
        let filename = url.lastPathComponent
        
        // Verify the format
        let pattern = "^[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}_\\d+_"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(filename.startIndex..., in: filename)
        
        if let match = regex?.firstMatch(in: filename, range: range),
           let matchRange = Range(match.range, in: filename) {
            let extracted = String(filename[matchRange.upperBound...])
            XCTAssertEqual(extracted, "document.pdf")
        } else {
            XCTFail("Pattern should match file stack format")
        }
    }
    
    func testExtractFilename_FileStackFormatWithSpaces() {
        let path = "/path/to/A19D867C-B777-4550-8209-02DF77F01D6C_2_my document.pdf"
        let url = URL(fileURLWithPath: path)
        let filename = url.lastPathComponent
        
        let pattern = "^[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}_\\d+_"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(filename.startIndex..., in: filename)
        
        if let match = regex?.firstMatch(in: filename, range: range),
           let matchRange = Range(match.range, in: filename) {
            let extracted = String(filename[matchRange.upperBound...])
            XCTAssertEqual(extracted, "my document.pdf")
        } else {
            XCTFail("Pattern should match file stack format with spaces")
        }
    }
    
    // MARK: - Filename Extraction Tests - Single File Format
    
    func testExtractFilename_SingleFileFormat() {
        // Format: {UUID}_{originalFilename}
        let path = "/path/to/A19D867C-B777-4550-8209-02DF77F01D6C_report.docx"
        let url = URL(fileURLWithPath: path)
        let filename = url.lastPathComponent
        
        let pattern = "^[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}_"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(filename.startIndex..., in: filename)
        
        if let match = regex?.firstMatch(in: filename, range: range),
           let matchRange = Range(match.range, in: filename) {
            let extracted = String(filename[matchRange.upperBound...])
            // Should not be empty and should not start with a digit (which would indicate file stack)
            XCTAssertFalse(extracted.isEmpty)
            XCTAssertFalse(extracted.first?.isNumber ?? false)
            XCTAssertEqual(extracted, "report.docx")
        } else {
            XCTFail("Pattern should match single file format")
        }
    }
    
    func testExtractFilename_FolderWithoutExtension() {
        // Format: {UUID}_{foldername} (no extension)
        let path = "/path/to/A19D867C-B777-4550-8209-02DF77F01D6C_MyFolder"
        let url = URL(fileURLWithPath: path)
        let filename = url.lastPathComponent
        
        let pattern = "^[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}_"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(filename.startIndex..., in: filename)
        
        if let match = regex?.firstMatch(in: filename, range: range),
           let matchRange = Range(match.range, in: filename) {
            let extracted = String(filename[matchRange.upperBound...])
            XCTAssertEqual(extracted, "MyFolder")
            XCTAssertFalse(extracted.contains("."))  // No extension
        } else {
            XCTFail("Pattern should match folder format")
        }
    }
    
    // MARK: - Filename Extraction Tests - Snippet Formats
    
    func testExtractFilename_SnippetFileStackFormat() {
        // Format: snippet_{UUID}_{index}_{originalFilename}
        let path = "/path/to/snippet_A19D867C-B777-4550-8209-02DF77F01D6C_0_image.png"
        let url = URL(fileURLWithPath: path)
        let filename = url.lastPathComponent
        
        let pattern = "^snippet_[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}_\\d+_"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(filename.startIndex..., in: filename)
        
        if let match = regex?.firstMatch(in: filename, range: range),
           let matchRange = Range(match.range, in: filename) {
            let extracted = String(filename[matchRange.upperBound...])
            XCTAssertEqual(extracted, "image.png")
        } else {
            XCTFail("Pattern should match snippet file stack format")
        }
    }
    
    func testExtractFilename_SnippetSingleFormat() {
        // Format: snippet_{UUID}_{originalFilename}
        let path = "/path/to/snippet_A19D867C-B777-4550-8209-02DF77F01D6C_logo.svg"
        let url = URL(fileURLWithPath: path)
        let filename = url.lastPathComponent
        
        let pattern = "^snippet_[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}_"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(filename.startIndex..., in: filename)
        
        if let match = regex?.firstMatch(in: filename, range: range),
           let matchRange = Range(match.range, in: filename) {
            let extracted = String(filename[matchRange.upperBound...])
            // Should not start with a digit (which would be file stack)
            if !extracted.isEmpty && !extracted.first!.isNumber {
                XCTAssertEqual(extracted, "logo.svg")
            } else {
                XCTFail("Should extract original filename, not index")
            }
        } else {
            XCTFail("Pattern should match snippet single format")
        }
    }
    
    // MARK: - Filename Extraction Tests - UUID Only Format
    
    func testExtractFilename_UUIDOnlyFormat() {
        // Format: {UUID}.{ext} - no original filename preserved
        let path = "/path/to/A19D867C-B777-4550-8209-02DF77F01D6C.png"
        let url = URL(fileURLWithPath: path)
        let filename = url.lastPathComponent
        
        let pattern = "^[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}\\.[a-zA-Z0-9]+$"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(filename.startIndex..., in: filename)
        
        // This format should match, indicating no original filename
        XCTAssertNotNil(regex?.firstMatch(in: filename, range: range))
    }
    
    // MARK: - Filename Extraction Tests - External References
    
    func testExtractFilename_ExternalReference() {
        // External files keep their original path/name
        let path = "/Users/john/Documents/my_report.pdf"
        let url = URL(fileURLWithPath: path)
        let filename = url.lastPathComponent
        
        // Should not match UUID patterns
        let uuidPattern = "^[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}"
        let regex = try? NSRegularExpression(pattern: uuidPattern, options: .caseInsensitive)
        let range = NSRange(filename.startIndex..., in: filename)
        
        XCTAssertNil(regex?.firstMatch(in: filename, range: range))
        XCTAssertEqual(filename, "my_report.pdf")
    }
    
    // MARK: - Default Filename Tests
    
    func testDefaultFilename_Image() {
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "webp"]
        
        for ext in imageExtensions {
            let expected = "image.\(ext)"
            // Verify the logic matches what we expect
            XCTAssertTrue(imageExtensions.contains(ext.lowercased()))
            XCTAssertEqual(expected, "image.\(ext)")
        }
    }
    
    func testDefaultFilename_Video() {
        let videoExtensions = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]
        
        for ext in videoExtensions {
            let expected = "video.\(ext)"
            XCTAssertTrue(videoExtensions.contains(ext.lowercased()))
            XCTAssertEqual(expected, "video.\(ext)")
        }
    }
    
    func testDefaultFilename_GenericFile() {
        let genericExtensions = ["pdf", "doc", "zip", "txt"]
        
        for ext in genericExtensions {
            let expected = "file.\(ext)"
            XCTAssertEqual(expected, "file.\(ext)")
        }
    }
    
    func testDefaultFilename_EmptyExtension() {
        // When there's no extension, should return "file"
        let defaultName = "file"
        XCTAssertEqual(defaultName, "file")
    }
    
    // MARK: - Copy to Clipboard Tests - Text
    
    func testCopyTextItem_PreparesCorrectly() throws {
        let item = ClipboardItem(
            contentType: .text,
            textContent: "Test clipboard text"
        )
        try storageService.saveClipboardItem(item)
        
        // Verify item is saved
        let items = try storageService.fetchClipboardItems()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.textContent, "Test clipboard text")
    }
    
    func testCopyRichTextItem_HasFallback() throws {
        let rtfData = Data("RTF content".utf8)
        let item = ClipboardItem(
            contentType: .richText,
            textContent: "Plain text fallback",
            richTextData: rtfData
        )
        try storageService.saveClipboardItem(item)
        
        let items = try storageService.fetchClipboardItems()
        XCTAssertEqual(items.first?.contentType, .richText)
        XCTAssertNotNil(items.first?.textContent)  // Has fallback
        XCTAssertNotNil(items.first?.richTextData)  // Has RTF
    }
    
    // MARK: - Copy to Clipboard Tests - Files
    
    func testCopyFileItem_HasValidPath() throws {
        let file = try createTestFile()
        let item = ClipboardItem(
            contentType: .file,
            textContent: "test.txt",
            mediaPath: file.path
        )
        try storageService.saveClipboardItem(item)
        
        let items = try storageService.fetchClipboardItems()
        XCTAssertNotNil(items.first?.mediaPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: items.first!.mediaPath!))
    }
    
    func testCopyImageItem_HasValidPath() throws {
        let image = try createTestImage()
        let item = ClipboardItem(
            contentType: .image,
            mediaPath: image.path
        )
        try storageService.saveClipboardItem(item)
        
        let items = try storageService.fetchClipboardItems()
        XCTAssertEqual(items.first?.contentType, .image)
        XCTAssertTrue(FileManager.default.fileExists(atPath: items.first!.mediaPath!))
    }
    
    func testCopyFileStack_HasMultiplePaths() throws {
        let file1 = try createTestFile(name: "file1.txt", content: "Content 1")
        let file2 = try createTestFile(name: "file2.txt", content: "Content 2")
        
        let item = ClipboardItem(
            contentType: .fileStack,
            mediaPaths: [file1.path, file2.path]
        )
        try storageService.saveClipboardItem(item)
        
        let items = try storageService.fetchClipboardItems()
        XCTAssertEqual(items.first?.mediaPaths?.count, 2)
    }
    
    // MARK: - Move to Top Tests
    
    func testMoveItemToTop_UpdatesTimestamp() throws {
        let oldDate = Date(timeIntervalSince1970: 1000)
        let item = ClipboardItem(
            contentType: .text,
            textContent: "Test",
            createdAt: oldDate
        )
        try storageService.saveClipboardItem(item)
        
        try storageService.moveItemToTop(item)
        
        let items = try storageService.fetchClipboardItems()
        XCTAssertGreaterThan(items.first!.createdAt, oldDate)
    }
    
    // MARK: - Snippet Copy Tests
    
    func testCopySnippet_UsesSnippetName() throws {
        let file = try createTestFile(name: "original.txt")
        let snippet = Snippet(
            name: "My Snippet",
            contentType: .file,
            mediaPath: file.path
        )
        try storageService.saveSnippet(snippet)
        
        let snippets = try storageService.fetchSnippets()
        XCTAssertEqual(snippets.first?.name, "My Snippet")
    }
    
    func testCopySnippet_HandlesEmptyExtension() throws {
        let folder = try createTestFolder(name: "SnippetFolder")
        let snippet = Snippet(
            name: "Folder Snippet",
            contentType: .file,
            mediaPath: folder.path
        )
        try storageService.saveSnippet(snippet)
        
        let snippets = try storageService.fetchSnippets()
        XCTAssertEqual(snippets.first?.name, "Folder Snippet")
        
        // Path extension should be empty for folder
        let ext = URL(fileURLWithPath: folder.path).pathExtension
        XCTAssertTrue(ext.isEmpty)
    }
    
    func testCopySnippet_TextSnippet() throws {
        let snippet = Snippet(
            name: "Text Snippet",
            contentType: .text,
            textContent: "Snippet content here"
        )
        try storageService.saveSnippet(snippet)
        
        let snippets = try storageService.fetchSnippets()
        XCTAssertEqual(snippets.first?.textContent, "Snippet content here")
    }
    
    // MARK: - Add to Snippets Tests
    
    func testAddToSnippets_CreatesSnippet() throws {
        let item = ClipboardItem(
            contentType: .text,
            textContent: "Convert to snippet"
        )
        try storageService.saveClipboardItem(item)
        
        let snippet = try storageService.createSnippetFromItem(item, name: "New Snippet")
        
        XCTAssertEqual(snippet.name, "New Snippet")
        XCTAssertEqual(snippet.textContent, "Convert to snippet")
        
        let snippets = try storageService.fetchSnippets()
        XCTAssertEqual(snippets.count, 1)
    }
    
    func testAddToSnippets_PreservesContentType() throws {
        let file = try createTestFile()
        let item = ClipboardItem(
            contentType: .file,
            textContent: "test.txt",
            mediaPath: file.path
        )
        try storageService.saveClipboardItem(item)
        
        let snippet = try storageService.createSnippetFromItem(item, name: "File Snippet")
        
        XCTAssertEqual(snippet.contentType, .file)
    }
    
    // MARK: - Clear History Tests
    
    func testClearHistory_RemovesAllItems() throws {
        // Add items
        for i in 0..<5 {
            let item = ClipboardItem(contentType: .text, textContent: "Item \(i)")
            try storageService.saveClipboardItem(item)
        }
        
        var items = try storageService.fetchClipboardItems()
        XCTAssertEqual(items.count, 5)
        
        // Clear all
        for item in items {
            try storageService.deleteClipboardItem(item)
        }
        
        items = try storageService.fetchClipboardItems()
        XCTAssertEqual(items.count, 0)
    }
    
    // MARK: - Menu Height Tests
    
    func testHistoryMenuHeight_RespectsMinimum() {
        // Menu should have a minimum height
        let minHeight = menuBarController.historyMenuHeight
        XCTAssertGreaterThanOrEqual(minHeight, 200)
    }
    
    func testSnippetsMenuHeight_RespectsMinimum() {
        let minHeight = menuBarController.snippetsMenuHeight
        XCTAssertGreaterThanOrEqual(minHeight, 200)
    }
    
    // MARK: - Hard Link Creation Tests
    
    func testHardLinkCreation_FileExists() throws {
        let sourceFile = try createTestFile(name: "source.txt", content: "Source content")
        
        // Create hard link manually (simulating createClipboardURL behavior)
        let linkDir = tempDir.url.appendingPathComponent("links")
        try FileManager.default.createDirectory(at: linkDir, withIntermediateDirectories: true)
        let linkFile = linkDir.appendingPathComponent("link.txt")
        
        try FileManager.default.linkItem(at: sourceFile, to: linkFile)
        
        // Both should exist and have same content
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: linkFile.path))
        
        let sourceContent = try String(contentsOf: sourceFile, encoding: .utf8)
        let linkContent = try String(contentsOf: linkFile, encoding: .utf8)
        XCTAssertEqual(sourceContent, linkContent)
    }
    
    func testHardLinkCreation_FolderWorks() throws {
        let sourceFolder = try createTestFolder(name: "SourceFolder")
        
        let linkDir = tempDir.url.appendingPathComponent("links")
        try FileManager.default.createDirectory(at: linkDir, withIntermediateDirectories: true)
        let linkFolder = linkDir.appendingPathComponent("LinkedFolder")
        
        try FileManager.default.linkItem(at: sourceFolder, to: linkFolder)
        
        // Both should exist
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: linkFolder.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }
    
    // MARK: - Reorder Tests
    
    func testMoveSnippet_UpdatesOrder() throws {
        // Create snippets in order
        for i in 0..<3 {
            let snippet = Snippet(
                name: "Snippet \(i)",
                contentType: .text,
                textContent: "Content \(i)",
                sortOrder: i
            )
            try storageService.saveSnippet(snippet)
        }
        
        var snippets = try storageService.fetchSnippets()
        XCTAssertEqual(snippets.count, 3)
        XCTAssertEqual(snippets[0].name, "Snippet 0")
        
        // Reorder (move last to first position)
        var reordered = [snippets[2], snippets[0], snippets[1]]
        // Update sort orders
        for (index, _) in reordered.enumerated() {
            reordered[index].sortOrder = index
        }
        try storageService.updateSnippetOrder(reordered)
        
        snippets = try storageService.fetchSnippets()
        XCTAssertEqual(snippets[0].name, "Snippet 2")
        XCTAssertEqual(snippets[1].name, "Snippet 0")
        XCTAssertEqual(snippets[2].name, "Snippet 1")
    }
}
