import XCTest
import AppKit
@testable import ClipboardMenu

@MainActor
final class ThumbnailServiceTests: XCTestCase {
    var thumbnailService: ThumbnailService!
    
    override func setUp() async throws {
        thumbnailService = ThumbnailService()
    }
    
    override func tearDown() async throws {
        thumbnailService = nil
    }
    
    // MARK: - Test Helpers
    
    /// Creates a simple test image with the given size
    private func createTestImage(width: Int, height: Int, color: NSColor = .red) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        return image
    }
    
    /// Creates test image data
    private func createTestImageData(width: Int, height: Int) -> Data? {
        let image = createTestImage(width: width, height: height)
        return image.pngData()
    }
    
    // MARK: - generateThumbnail(from image:)
    
    func testGenerateThumbnailScalesDownLargeImage() {
        let largeImage = createTestImage(width: 1000, height: 800)
        let maxSize: CGFloat = 200
        
        let thumbnailData = thumbnailService.generateThumbnail(from: largeImage, maxSize: maxSize)
        
        XCTAssertNotNil(thumbnailData)
        
        if let data = thumbnailData, let thumbnail = NSImage(data: data) {
            // The longer dimension should be scaled to maxSize
            XCTAssertLessThanOrEqual(thumbnail.size.width, maxSize + 1) // Allow small rounding error
            XCTAssertLessThanOrEqual(thumbnail.size.height, maxSize + 1)
        }
    }
    
    func testGenerateThumbnailMaintainsAspectRatio() {
        let wideImage = createTestImage(width: 1000, height: 500)
        let maxSize: CGFloat = 200
        
        let thumbnailData = thumbnailService.generateThumbnail(from: wideImage, maxSize: maxSize)
        
        XCTAssertNotNil(thumbnailData)
        
        if let data = thumbnailData, let thumbnail = NSImage(data: data) {
            // Original aspect ratio is 2:1
            let aspectRatio = thumbnail.size.width / thumbnail.size.height
            XCTAssertEqual(aspectRatio, 2.0, accuracy: 0.1)
        }
    }
    
    func testGenerateThumbnailTallImage() {
        let tallImage = createTestImage(width: 500, height: 1000)
        let maxSize: CGFloat = 200
        
        let thumbnailData = thumbnailService.generateThumbnail(from: tallImage, maxSize: maxSize)
        
        XCTAssertNotNil(thumbnailData)
        
        if let data = thumbnailData, let thumbnail = NSImage(data: data) {
            // Height should be scaled to maxSize
            XCTAssertEqual(thumbnail.size.height, maxSize, accuracy: 1)
            // Width should be half (aspect ratio 1:2)
            XCTAssertEqual(thumbnail.size.width, maxSize / 2, accuracy: 1)
        }
    }
    
    func testGenerateThumbnailSquareImage() {
        let squareImage = createTestImage(width: 800, height: 800)
        let maxSize: CGFloat = 100
        
        let thumbnailData = thumbnailService.generateThumbnail(from: squareImage, maxSize: maxSize)
        
        XCTAssertNotNil(thumbnailData)
        
        if let data = thumbnailData, let thumbnail = NSImage(data: data) {
            XCTAssertEqual(thumbnail.size.width, maxSize, accuracy: 1)
            XCTAssertEqual(thumbnail.size.height, maxSize, accuracy: 1)
        }
    }
    
    func testGenerateThumbnailReturnsNilForZeroSizeImage() {
        let emptyImage = NSImage(size: .zero)
        
        let result = thumbnailService.generateThumbnail(from: emptyImage, maxSize: 100)
        
        XCTAssertNil(result)
    }
    
    func testGenerateThumbnailReturnsNilForNegativeWidth() {
        let invalidImage = NSImage(size: NSSize(width: -100, height: 100))
        
        let result = thumbnailService.generateThumbnail(from: invalidImage, maxSize: 100)
        
        XCTAssertNil(result)
    }
    
    func testGenerateThumbnailReturnsPNGData() {
        let image = createTestImage(width: 200, height: 200)
        
        let thumbnailData = thumbnailService.generateThumbnail(from: image, maxSize: 100)
        
        XCTAssertNotNil(thumbnailData)
        
        // PNG files start with specific magic bytes
        if let data = thumbnailData {
            let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47] // PNG signature
            let dataBytes = [UInt8](data.prefix(4))
            XCTAssertEqual(dataBytes, pngSignature, "Output should be PNG format")
        }
    }
    
    // MARK: - generateImageThumbnail(from data:)
    
    func testGenerateImageThumbnailFromData() {
        let imageData = createTestImageData(width: 500, height: 500)!
        
        let thumbnailData = thumbnailService.generateImageThumbnail(from: imageData, maxSize: 100)
        
        XCTAssertNotNil(thumbnailData)
    }
    
    func testGenerateImageThumbnailFromInvalidDataReturnsNil() {
        let invalidData = "not an image".data(using: .utf8)!
        
        let result = thumbnailService.generateImageThumbnail(from: invalidData, maxSize: 100)
        
        XCTAssertNil(result)
    }
    
    func testGenerateImageThumbnailFromEmptyDataReturnsNil() {
        let emptyData = Data()
        
        let result = thumbnailService.generateImageThumbnail(from: emptyData, maxSize: 100)
        
        XCTAssertNil(result)
    }
    
    // MARK: - generatePreviewImage(from image:)
    
    func testGeneratePreviewImageScalesLargeImage() {
        let largeImage = createTestImage(width: 2000, height: 1000)
        let maxSize: CGFloat = 500
        
        let preview = thumbnailService.generatePreviewImage(from: largeImage, maxSize: maxSize)
        
        XCTAssertNotNil(preview)
        XCTAssertLessThanOrEqual(preview!.size.width, maxSize + 1)
        XCTAssertLessThanOrEqual(preview!.size.height, maxSize + 1)
    }
    
    func testGeneratePreviewImageReturnsOriginalForSmallImage() {
        let smallImage = createTestImage(width: 100, height: 80)
        let maxSize: CGFloat = 500
        
        let preview = thumbnailService.generatePreviewImage(from: smallImage, maxSize: maxSize)
        
        XCTAssertNotNil(preview)
        // Small images should be returned as-is
        XCTAssertEqual(preview!.size.width, 100)
        XCTAssertEqual(preview!.size.height, 80)
    }
    
    func testGeneratePreviewImageReturnsOriginalWhenExactlyMaxSize() {
        let exactImage = createTestImage(width: 500, height: 500)
        let maxSize: CGFloat = 500
        
        let preview = thumbnailService.generatePreviewImage(from: exactImage, maxSize: maxSize)
        
        XCTAssertNotNil(preview)
        XCTAssertEqual(preview!.size.width, 500)
        XCTAssertEqual(preview!.size.height, 500)
    }
    
    func testGeneratePreviewImageMaintainsAspectRatio() {
        let wideImage = createTestImage(width: 1600, height: 900)
        let maxSize: CGFloat = 400
        
        let preview = thumbnailService.generatePreviewImage(from: wideImage, maxSize: maxSize)
        
        XCTAssertNotNil(preview)
        
        // Original aspect ratio is 16:9
        let originalRatio = 1600.0 / 900.0
        let previewRatio = preview!.size.width / preview!.size.height
        XCTAssertEqual(previewRatio, originalRatio, accuracy: 0.01)
    }
    
    func testGeneratePreviewImageReturnsNilForZeroSizeImage() {
        let emptyImage = NSImage(size: .zero)
        
        let result = thumbnailService.generatePreviewImage(from: emptyImage, maxSize: 100)
        
        XCTAssertNil(result)
    }
    
    // MARK: - generatePreviewImage(from path:)
    
    func testGeneratePreviewImageFromNonexistentPathReturnsNil() {
        let result = thumbnailService.generatePreviewImage(from: "/nonexistent/path/image.png", maxSize: 100)
        
        XCTAssertNil(result)
    }
    
    // MARK: - Different Max Sizes
    
    func testGenerateThumbnailWithVerySmallMaxSize() {
        let image = createTestImage(width: 1000, height: 1000)
        let maxSize: CGFloat = 10
        
        let thumbnailData = thumbnailService.generateThumbnail(from: image, maxSize: maxSize)
        
        XCTAssertNotNil(thumbnailData)
        
        if let data = thumbnailData, let thumbnail = NSImage(data: data) {
            XCTAssertEqual(thumbnail.size.width, maxSize, accuracy: 1)
            XCTAssertEqual(thumbnail.size.height, maxSize, accuracy: 1)
        }
    }
    
    func testGenerateThumbnailWithLargeMaxSize() {
        let image = createTestImage(width: 100, height: 100)
        let maxSize: CGFloat = 1000
        
        let thumbnailData = thumbnailService.generateThumbnail(from: image, maxSize: maxSize)
        
        XCTAssertNotNil(thumbnailData)
        
        // Even with large maxSize, image should scale up
        if let data = thumbnailData, let thumbnail = NSImage(data: data) {
            XCTAssertEqual(thumbnail.size.width, maxSize, accuracy: 1)
            XCTAssertEqual(thumbnail.size.height, maxSize, accuracy: 1)
        }
    }
    
    // MARK: - generateVideoPreviewImage Tests
    
    func testGenerateVideoPreviewImageFromNonexistentPathReturnsNil() {
        let result = thumbnailService.generateVideoPreviewImage(from: "/nonexistent/video.mp4", maxSize: 100)
        
        XCTAssertNil(result)
    }
    
    func testGenerateVideoPreviewImageFromInvalidFileReturnsNil() throws {
        // Create a temporary file with non-video content
        let tempDir = FileManager.default.temporaryDirectory
        let fakeVideoPath = tempDir.appendingPathComponent("fake_preview_\(UUID().uuidString).mp4").path
        try "not a video".write(toFile: fakeVideoPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: fakeVideoPath) }
        
        let result = thumbnailService.generateVideoPreviewImage(from: fakeVideoPath, maxSize: 100)
        
        XCTAssertNil(result)
    }
    
    func testGenerateVideoPreviewImageFromEmptyFileReturnsNil() throws {
        // Create an empty file with video extension
        let tempDir = FileManager.default.temporaryDirectory
        let emptyVideoPath = tempDir.appendingPathComponent("empty_preview_\(UUID().uuidString).mp4").path
        FileManager.default.createFile(atPath: emptyVideoPath, contents: Data(), attributes: nil)
        defer { try? FileManager.default.removeItem(atPath: emptyVideoPath) }
        
        let result = thumbnailService.generateVideoPreviewImage(from: emptyVideoPath, maxSize: 100)
        
        XCTAssertNil(result)
    }
    
    func testGenerateVideoPreviewImageFromDirectoryReturnsNil() {
        // Try to generate preview from a directory
        let tempDir = FileManager.default.temporaryDirectory
        
        let result = thumbnailService.generateVideoPreviewImage(from: tempDir.path, maxSize: 100)
        
        XCTAssertNil(result)
    }
}

// MARK: - NSImage PNG Extension for Tests

extension NSImage {
    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
