import XCTest
@testable import ClipboardMenu

@MainActor
final class SizeCalculatorTests: XCTestCase {
    
    var sizeCalculator: SizeCalculator!
    var tempDir: TempDirectory!
    
    override func setUp() async throws {
        sizeCalculator = SizeCalculator()
        tempDir = try TempDirectory()
    }
    
    override func tearDown() async throws {
        sizeCalculator.cancel()
        sizeCalculator = nil
        tempDir?.cleanup()
        tempDir = nil
    }
    
    // MARK: - Initial State
    
    func testInitialState() {
        XCTAssertEqual(sizeCalculator.currentSize, 0)
        XCTAssertFalse(sizeCalculator.isCalculating)
        XCTAssertFalse(sizeCalculator.exceedsLimit)
        XCTAssertFalse(sizeCalculator.isComplete)
    }
    
    // MARK: - Text Content Size
    
    func testTextOnlyItem() async throws {
        let text = "Hello, World!"
        let item = TestData.textItem(text: text)
        
        sizeCalculator.startCalculation(for: item, limit: 1000)
        
        // Wait for completion
        await waitForCalculation()
        
        XCTAssertEqual(sizeCalculator.currentSize, Int64(text.utf8.count))
        XCTAssertTrue(sizeCalculator.isComplete)
        XCTAssertFalse(sizeCalculator.exceedsLimit)
    }
    
    func testTextExceedsLimit() async throws {
        let text = String(repeating: "A", count: 100)
        let item = TestData.textItem(text: text)
        
        sizeCalculator.startCalculation(for: item, limit: 50)
        
        await waitForCalculation()
        
        XCTAssertTrue(sizeCalculator.exceedsLimit)
        XCTAssertEqual(sizeCalculator.currentSize, 100)
    }
    
    func testRichTextItem() async throws {
        let text = "Rich text"
        let richData = Data(repeating: 0x42, count: 200)
        let item = ClipboardItem(
            contentType: .richText,
            textContent: text,
            richTextData: richData
        )
        
        sizeCalculator.startCalculation(for: item, limit: 1000)
        
        await waitForCalculation()
        
        // Should include both text and rich data size
        let expectedSize = Int64(text.utf8.count) + Int64(richData.count)
        XCTAssertEqual(sizeCalculator.currentSize, expectedSize)
    }
    
    // MARK: - File Size
    
    func testSingleFileSize() async throws {
        let content = Data(repeating: 0x41, count: 500)
        let filePath = try tempDir.createFile(name: "test.txt", content: content).path
        
        let item = TestData.fileItem(mediaPath: filePath)
        
        sizeCalculator.startCalculation(for: item, limit: 1000)
        
        await waitForCalculation()
        
        XCTAssertEqual(sizeCalculator.currentSize, 500)
        XCTAssertFalse(sizeCalculator.exceedsLimit)
    }
    
    func testFileExceedsLimit() async throws {
        let content = Data(repeating: 0x41, count: 500)
        let filePath = try tempDir.createFile(name: "test.txt", content: content).path
        
        let item = TestData.fileItem(mediaPath: filePath)
        
        sizeCalculator.startCalculation(for: item, limit: 100)
        
        await waitForCalculation()
        
        XCTAssertEqual(sizeCalculator.currentSize, 500)
        XCTAssertTrue(sizeCalculator.exceedsLimit)
    }
    
    func testNonExistentFile() async throws {
        let item = TestData.fileItem(mediaPath: "/nonexistent/path/file.txt")
        
        sizeCalculator.startCalculation(for: item, limit: 1000)
        
        await waitForCalculation()
        
        XCTAssertEqual(sizeCalculator.currentSize, 0)
        XCTAssertTrue(sizeCalculator.isComplete)
    }
    
    // MARK: - Directory Size
    
    func testDirectorySize() async throws {
        let subdir = try tempDir.createSubdirectory(name: "folder")
        
        // Create files in the directory
        try Data(repeating: 0x41, count: 100).write(to: subdir.appendingPathComponent("file1.txt"))
        try Data(repeating: 0x42, count: 200).write(to: subdir.appendingPathComponent("file2.txt"))
        try Data(repeating: 0x43, count: 300).write(to: subdir.appendingPathComponent("file3.txt"))
        
        let item = TestData.fileItem(mediaPath: subdir.path)
        
        sizeCalculator.startCalculation(for: item, limit: 10000)
        
        await waitForCalculation()
        
        XCTAssertEqual(sizeCalculator.currentSize, 600)
    }
    
    func testNestedDirectorySize() async throws {
        let subdir = try tempDir.createSubdirectory(name: "outer")
        let nested = subdir.appendingPathComponent("inner", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        
        // Create files at different levels
        try Data(repeating: 0x41, count: 100).write(to: subdir.appendingPathComponent("outer_file.txt"))
        try Data(repeating: 0x42, count: 200).write(to: nested.appendingPathComponent("inner_file.txt"))
        
        let item = TestData.fileItem(mediaPath: subdir.path)
        
        sizeCalculator.startCalculation(for: item, limit: 10000)
        
        await waitForCalculation()
        
        XCTAssertEqual(sizeCalculator.currentSize, 300)
    }
    
    func testEmptyDirectory() async throws {
        let subdir = try tempDir.createSubdirectory(name: "empty")
        
        let item = TestData.fileItem(mediaPath: subdir.path)
        
        sizeCalculator.startCalculation(for: item, limit: 1000)
        
        await waitForCalculation()
        
        XCTAssertEqual(sizeCalculator.currentSize, 0)
        XCTAssertTrue(sizeCalculator.isComplete)
    }
    
    // MARK: - File Stack
    
    func testFileStackSize() async throws {
        let file1 = try tempDir.createFile(name: "file1.txt", content: Data(repeating: 0x41, count: 100)).path
        let file2 = try tempDir.createFile(name: "file2.txt", content: Data(repeating: 0x42, count: 200)).path
        let file3 = try tempDir.createFile(name: "file3.txt", content: Data(repeating: 0x43, count: 300)).path
        
        let item = TestData.fileStackItem(mediaPaths: [file1, file2, file3])
        
        sizeCalculator.startCalculation(for: item, limit: 10000)
        
        await waitForCalculation()
        
        XCTAssertEqual(sizeCalculator.currentSize, 600)
    }
    
    func testFileStackWithMixedContent() async throws {
        let file = try tempDir.createFile(name: "file.txt", content: Data(repeating: 0x41, count: 100)).path
        let folder = try tempDir.createSubdirectory(name: "folder")
        try Data(repeating: 0x42, count: 200).write(to: folder.appendingPathComponent("nested.txt"))
        
        let item = TestData.fileStackItem(mediaPaths: [file, folder.path])
        
        sizeCalculator.startCalculation(for: item, limit: 10000)
        
        await waitForCalculation()
        
        XCTAssertEqual(sizeCalculator.currentSize, 300)
    }
    
    // MARK: - State Management
    
    func testCalculatingStateIsTrueDuringCalculation() async throws {
        let subdir = try tempDir.createSubdirectory(name: "folder")
        for i in 0..<10 {
            try Data(repeating: 0x41, count: 100).write(to: subdir.appendingPathComponent("file\(i).txt"))
        }
        
        let item = TestData.fileItem(mediaPath: subdir.path)
        
        sizeCalculator.startCalculation(for: item, limit: 100000)
        
        // isCalculating should be true immediately
        XCTAssertTrue(sizeCalculator.isCalculating)
        
        await waitForCalculation()
        
        XCTAssertFalse(sizeCalculator.isCalculating)
        XCTAssertTrue(sizeCalculator.isComplete)
    }
    
    func testExceedsLimitSetEarly() async throws {
        // Create a large directory where limit will be exceeded quickly
        let subdir = try tempDir.createSubdirectory(name: "folder")
        for i in 0..<20 {
            try Data(repeating: 0x41, count: 100).write(to: subdir.appendingPathComponent("file\(i).txt"))
        }
        
        let item = TestData.fileItem(mediaPath: subdir.path)
        
        // Set a low limit that will be exceeded early
        sizeCalculator.startCalculation(for: item, limit: 150)
        
        await waitForCalculation()
        
        // Should have set exceedsLimit to true
        XCTAssertTrue(sizeCalculator.exceedsLimit)
    }
    
    // MARK: - Reset
    
    func testReset() async throws {
        let item = TestData.textItem(text: "test")
        
        sizeCalculator.startCalculation(for: item, limit: 1)
        await waitForCalculation()
        
        // Verify state before reset
        XCTAssertGreaterThan(sizeCalculator.currentSize, 0)
        XCTAssertTrue(sizeCalculator.exceedsLimit)
        XCTAssertTrue(sizeCalculator.isComplete)
        
        sizeCalculator.reset()
        
        XCTAssertEqual(sizeCalculator.currentSize, 0)
        XCTAssertFalse(sizeCalculator.isCalculating)
        XCTAssertFalse(sizeCalculator.exceedsLimit)
        XCTAssertFalse(sizeCalculator.isComplete)
    }
    
    // MARK: - Cancel
    
    func testCancel() async throws {
        let item = TestData.textItem(text: "test")
        
        sizeCalculator.startCalculation(for: item, limit: 1000)
        sizeCalculator.cancel()
        
        XCTAssertFalse(sizeCalculator.isCalculating)
    }
    
    func testStartNewCalculationResetsState() async throws {
        // First calculation completes
        let text1 = String(repeating: "A", count: 100)
        let item1 = TestData.textItem(text: text1)
        
        sizeCalculator.startCalculation(for: item1, limit: 1000)
        await waitForCalculation()
        
        XCTAssertEqual(sizeCalculator.currentSize, 100)
        XCTAssertTrue(sizeCalculator.isComplete)
        
        // Start second calculation - should reset state
        let text2 = String(repeating: "B", count: 50)
        let item2 = TestData.textItem(text: text2)
        
        sizeCalculator.startCalculation(for: item2, limit: 1000)
        await waitForCalculation()
        
        // Should have the size of item2 only (state was reset)
        XCTAssertEqual(sizeCalculator.currentSize, 50)
        XCTAssertTrue(sizeCalculator.isComplete)
    }
    
    // MARK: - Combined Content
    
    func testTextAndFileItem() async throws {
        let text = "Hello"
        let fileContent = Data(repeating: 0x41, count: 100)
        let filePath = try tempDir.createFile(name: "test.txt", content: fileContent).path
        
        let item = ClipboardItem(
            contentType: .file,
            textContent: text,
            mediaPath: filePath
        )
        
        sizeCalculator.startCalculation(for: item, limit: 1000)
        
        await waitForCalculation()
        
        // Should include both text and file size
        let expectedSize = Int64(text.utf8.count) + 100
        XCTAssertEqual(sizeCalculator.currentSize, expectedSize)
    }
    
    // MARK: - Edge Cases
    
    func testEmptyTextItem() async throws {
        let item = TestData.textItem(text: "")
        
        sizeCalculator.startCalculation(for: item, limit: 1000)
        
        await waitForCalculation()
        
        XCTAssertEqual(sizeCalculator.currentSize, 0)
        XCTAssertTrue(sizeCalculator.isComplete)
    }
    
    func testExactlyAtLimit() async throws {
        let text = String(repeating: "A", count: 100)
        let item = TestData.textItem(text: text)
        
        sizeCalculator.startCalculation(for: item, limit: 100)
        
        await waitForCalculation()
        
        // Should NOT exceed limit when exactly at limit
        XCTAssertFalse(sizeCalculator.exceedsLimit)
        XCTAssertEqual(sizeCalculator.currentSize, 100)
    }
    
    func testOneByteOverLimit() async throws {
        let text = String(repeating: "A", count: 101)
        let item = TestData.textItem(text: text)
        
        sizeCalculator.startCalculation(for: item, limit: 100)
        
        await waitForCalculation()
        
        XCTAssertTrue(sizeCalculator.exceedsLimit)
    }
    
    // MARK: - Cloud File Support
    
    func testIsCloudFileFalseByDefault() async throws {
        let item = TestData.textItem(text: "test")
        
        sizeCalculator.startCalculation(for: item, limit: 1000)
        
        // isCloudFile should be false when includeCloudFiles is not set
        XCTAssertFalse(sizeCalculator.isCloudFile)
        
        await waitForCalculation()
        
        XCTAssertFalse(sizeCalculator.isCloudFile)
    }
    
    func testIsCloudFileTrueWhenIncludeCloudFilesSet() async throws {
        let item = TestData.textItem(text: "test")
        
        sizeCalculator.startCalculation(for: item, limit: 1000, includeCloudFiles: true)
        
        // isCloudFile should be true when includeCloudFiles is set
        XCTAssertTrue(sizeCalculator.isCloudFile)
        
        await waitForCalculation()
        
        XCTAssertTrue(sizeCalculator.isCloudFile)
    }
    
    func testIncludeCloudFilesDoesNotAffectLocalFiles() async throws {
        // Create a local file (not in iCloud)
        let content = Data(repeating: 0x41, count: 500)
        let filePath = try tempDir.createFile(name: "local.txt", content: content).path
        
        let item = TestData.fileItem(mediaPath: filePath)
        
        // Calculate with includeCloudFiles = true
        sizeCalculator.startCalculation(for: item, limit: 1000, includeCloudFiles: true)
        
        await waitForCalculation()
        
        // Should still calculate size correctly for local files
        XCTAssertEqual(sizeCalculator.currentSize, 500)
        XCTAssertTrue(sizeCalculator.isComplete)
    }
    
    func testIncludeCloudFilesWithDirectory() async throws {
        // Create a local directory (not in iCloud)
        let subdir = try tempDir.createSubdirectory(name: "folder")
        try Data(repeating: 0x41, count: 100).write(to: subdir.appendingPathComponent("file1.txt"))
        try Data(repeating: 0x42, count: 200).write(to: subdir.appendingPathComponent("file2.txt"))
        
        let item = TestData.fileItem(mediaPath: subdir.path)
        
        // Calculate with includeCloudFiles = true
        sizeCalculator.startCalculation(for: item, limit: 1000, includeCloudFiles: true)
        
        await waitForCalculation()
        
        // Should still calculate size correctly for local directories
        XCTAssertEqual(sizeCalculator.currentSize, 300)
        XCTAssertTrue(sizeCalculator.isComplete)
    }
    
    func testResetClearsIsCloudFile() async throws {
        let item = TestData.textItem(text: "test")
        
        sizeCalculator.startCalculation(for: item, limit: 1000, includeCloudFiles: true)
        await waitForCalculation()
        
        XCTAssertTrue(sizeCalculator.isCloudFile)
        
        sizeCalculator.reset()
        
        XCTAssertFalse(sizeCalculator.isCloudFile)
    }
    
    func testNewCalculationResetsIsCloudFile() async throws {
        let item = TestData.textItem(text: "test")
        
        // Start with includeCloudFiles = true
        sizeCalculator.startCalculation(for: item, limit: 1000, includeCloudFiles: true)
        await waitForCalculation()
        
        XCTAssertTrue(sizeCalculator.isCloudFile)
        
        // Start new calculation with includeCloudFiles = false
        sizeCalculator.startCalculation(for: item, limit: 1000, includeCloudFiles: false)
        
        // isCloudFile should be reset
        XCTAssertFalse(sizeCalculator.isCloudFile)
    }
    
    // MARK: - Helpers
    
    private func waitForCalculation(timeout: TimeInterval = 5.0) async {
        let start = Date()
        while sizeCalculator.isCalculating && Date().timeIntervalSince(start) < timeout {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
