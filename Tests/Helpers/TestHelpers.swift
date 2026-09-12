import Foundation
@testable import ClipboardMenu

/// Factory methods for creating test data
enum TestData {
    
    // MARK: - ClipboardItem Factories
    
    static func textItem(
        id: UUID = UUID(),
        text: String = "Test text content",
        sourceApp: String? = "TestApp",
        createdAt: Date = Date(),
        isFavorite: Bool = false
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            contentType: .text,
            textContent: text,
            sourceApp: sourceApp,
            createdAt: createdAt,
            isFavorite: isFavorite
        )
    }
    
    static func richTextItem(
        id: UUID = UUID(),
        text: String = "Rich text content",
        richTextData: Data = Data([0x01, 0x02, 0x03]),
        createdAt: Date = Date()
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            contentType: .richText,
            textContent: text,
            richTextData: richTextData,
            createdAt: createdAt
        )
    }
    
    static func imageItem(
        id: UUID = UUID(),
        mediaPath: String = "/tmp/test/image.png",
        thumbnailPath: String? = "/tmp/test/thumb.png",
        createdAt: Date = Date()
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            contentType: .image,
            mediaPath: mediaPath,
            thumbnailPath: thumbnailPath,
            createdAt: createdAt
        )
    }
    
    static func videoItem(
        id: UUID = UUID(),
        mediaPath: String = "/tmp/test/video.mp4",
        thumbnailPath: String? = "/tmp/test/thumb.png",
        createdAt: Date = Date()
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            contentType: .video,
            mediaPath: mediaPath,
            thumbnailPath: thumbnailPath,
            createdAt: createdAt
        )
    }
    
    static func fileItem(
        id: UUID = UUID(),
        mediaPath: String = "/tmp/test/document.pdf",
        textContent: String? = nil,
        createdAt: Date = Date()
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            contentType: .file,
            textContent: textContent,
            mediaPath: mediaPath,
            createdAt: createdAt
        )
    }
    
    static func fileStackItem(
        id: UUID = UUID(),
        mediaPaths: [String] = ["/tmp/test/file1.txt", "/tmp/test/file2.txt", "/tmp/test/file3.txt"],
        createdAt: Date = Date()
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            contentType: .fileStack,
            mediaPaths: mediaPaths,
            createdAt: createdAt
        )
    }
    
    static func textFileItem(
        id: UUID = UUID(),
        mediaPath: String = "/tmp/test/code.swift",
        createdAt: Date = Date()
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            contentType: .file,
            mediaPath: mediaPath,
            createdAt: createdAt
        )
    }
    
    // MARK: - Snippet Factories
    
    static func snippet(
        id: UUID = UUID(),
        name: String = "Test Snippet",
        contentType: ContentType = .text,
        textContent: String? = "Snippet text content",
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) -> Snippet {
        Snippet(
            id: id,
            name: name,
            contentType: contentType,
            textContent: textContent,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            sortOrder: sortOrder
        )
    }
    
    static func imageSnippet(
        id: UUID = UUID(),
        name: String = "Image Snippet",
        mediaPath: String = "/tmp/test/snippet_image.png",
        thumbnailPath: String? = "/tmp/test/snippet_thumb.png",
        sortOrder: Int = 0
    ) -> Snippet {
        Snippet(
            id: id,
            name: name,
            contentType: .image,
            mediaPath: mediaPath,
            thumbnailPath: thumbnailPath,
            sortOrder: sortOrder
        )
    }
    
    // MARK: - Batch Factories
    
    static func textItems(count: Int, prefix: String = "Item") -> [ClipboardItem] {
        (0..<count).map { index in
            textItem(
                text: "\(prefix) \(index)",
                createdAt: Date().addingTimeInterval(Double(-index * 60))
            )
        }
    }
    
    static func snippets(count: Int, prefix: String = "Snippet") -> [Snippet] {
        (0..<count).map { index in
            snippet(
                name: "\(prefix) \(index)",
                textContent: "Content for \(prefix) \(index)",
                sortOrder: index
            )
        }
    }
    
    // MARK: - Long Text Helpers
    
    static let shortText = "Short text"
    static let longText = String(repeating: "A", count: 100)
    static let multilineText = "Line 1\nLine 2\nLine 3"
    static let exactly50Chars = String(repeating: "X", count: 50)
    static let exactly51Chars = String(repeating: "X", count: 51)
    
    // MARK: - File Extensions for Testing
    
    static let textFileExtensions = ["txt", "md", "json", "swift", "py", "js"]
    static let textFilenames = ["README", "Makefile", "Dockerfile", "LICENSE"]
    static let nonTextExtensions = ["pdf", "docx", "xlsx", "zip", "exe"]
}

/// Test image data helpers
enum TestImageData {
    /// Minimal valid PNG data (1x1 transparent pixel)
    static let minimalPNG: Data = {
        Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,  // PNG signature
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,  // IHDR chunk
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,  // 1x1 dimensions
            0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,  // bit depth, color type, etc.
            0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,  // IDAT chunk
            0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
            0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
            0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,  // IEND chunk
            0x42, 0x60, 0x82
        ])
    }()
    
    /// Sample data of a specific size
    static func data(ofSize bytes: Int) -> Data {
        Data(count: bytes)
    }
}
