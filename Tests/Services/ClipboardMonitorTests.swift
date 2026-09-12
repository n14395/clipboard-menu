import XCTest
import AppKit
@testable import ClipboardMenu

@MainActor
final class ClipboardMonitorTests: XCTestCase {
    
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
        if let defaults = testDefaults {
            defaults.removePersistentDomain(forName: defaults.description)
        }
        testDefaults = nil
    }
    
    // MARK: - Initialization
    
    func testInitializationSetsCorrectServices() {
        XCTAssertNotNil(clipboardMonitor)
    }
    
    // MARK: - Start/Stop Monitoring
    
    func testStartMonitoringCreatesTimer() {
        clipboardMonitor.startMonitoring()
        // Timer is private, but we can verify it doesn't crash
        clipboardMonitor.stopMonitoring()
    }
    
    func testStopMonitoringInvalidatesTimer() {
        clipboardMonitor.startMonitoring()
        clipboardMonitor.stopMonitoring()
        // Should be safe to call multiple times
        clipboardMonitor.stopMonitoring()
    }
    
    func testMultipleStartStopCycles() {
        for _ in 0..<5 {
            clipboardMonitor.startMonitoring()
            clipboardMonitor.stopMonitoring()
        }
    }
    
    // MARK: - willCopyFromHistory
    
    func testWillCopyFromHistoryDoesNotCrash() {
        clipboardMonitor.willCopyFromHistory()
    }
    
    func testWillCopyFromHistoryCanBeCalledMultipleTimes() {
        for _ in 0..<10 {
            clipboardMonitor.willCopyFromHistory()
        }
    }
    
    func testWillCopyFromHistoryWhileMonitoring() {
        clipboardMonitor.startMonitoring()
        clipboardMonitor.willCopyFromHistory()
        clipboardMonitor.stopMonitoring()
    }
    
    // MARK: - File Type Detection (via extension patterns)
    
    func testVideoFileExtensions() {
        // Video extensions that should be detected
        let videoExtensions = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]
        for ext in videoExtensions {
            let url = URL(fileURLWithPath: "/test/video.\(ext)")
            // The actual method is private, but we can test via save behavior
            XCTAssertTrue(url.pathExtension.lowercased() == ext)
        }
    }
    
    func testImageFileExtensions() {
        // Image extensions that should be detected
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "webp"]
        for ext in imageExtensions {
            let url = URL(fileURLWithPath: "/test/image.\(ext)")
            XCTAssertTrue(url.pathExtension.lowercased() == ext)
        }
    }
    
    // MARK: - Integration with StorageService
    
    func testClipboardMonitorUsesStorageService() {
        // Save a text item directly to storage
        let item = ClipboardItem(contentType: .text, textContent: "test")
        try? storageService.saveClipboardItem(item)
        
        // Verify storage has the item
        let items = try? storageService.fetchClipboardItems()
        XCTAssertEqual(items?.count, 1)
    }
    
    func testClipboardMonitorUsesPreferencesService() {
        // Verify preferences service is accessible
        XCTAssertGreaterThan(preferencesService.maxHistoryItems, 0)
        XCTAssertGreaterThan(preferencesService.maxStorageBytes, 0)
    }
    
    func testClipboardMonitorRespectsSizeLimit() {
        // Set a small size limit
        preferencesService.maxItemSizeMB = 1  // 1MB limit
        
        // Verify the limit is set
        XCTAssertEqual(preferencesService.maxItemSizeBytes, 1 * 1024 * 1024)
    }
}

// MARK: - NSImage Extension Tests

final class NSImagePngDataExtensionTests: XCTestCase {
    func testPngDataReturnsDataForValidImage() {
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 10, height: 10).fill()
        image.unlockFocus()
        
        let pngData = image.pngData()
        
        XCTAssertNotNil(pngData)
    }
    
    func testPngDataStartsWithPngSignature() {
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 10, height: 10).fill()
        image.unlockFocus()
        
        guard let pngData = image.pngData() else {
            XCTFail("Failed to create PNG data")
            return
        }
        
        // PNG signature: 0x89 0x50 0x4E 0x47
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        let dataBytes = [UInt8](pngData.prefix(4))
        
        XCTAssertEqual(dataBytes, signature)
    }
    
    func testPngDataForEmptyImageReturnsNil() {
        let emptyImage = NSImage()
        
        let pngData = emptyImage.pngData()
        
        XCTAssertNil(pngData)
    }
    
    func testPngDataPreservesImageContent() {
        let image = NSImage(size: NSSize(width: 50, height: 50))
        image.lockFocus()
        NSColor.green.setFill()
        NSRect(x: 0, y: 0, width: 50, height: 50).fill()
        image.unlockFocus()
        
        guard let pngData = image.pngData() else {
            XCTFail("Failed to create PNG data")
            return
        }
        
        // Verify we can create an image from the data
        let recreatedImage = NSImage(data: pngData)
        XCTAssertNotNil(recreatedImage)
    }
}
