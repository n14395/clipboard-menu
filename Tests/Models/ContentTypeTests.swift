import XCTest
@testable import ClipboardMenu

final class ContentTypeTests: XCTestCase {
    
    // MARK: - Display Names
    
    func testTextDisplayName() {
        XCTAssertEqual(ContentType.text.displayName, "Text")
    }
    
    func testRichTextDisplayName() {
        XCTAssertEqual(ContentType.richText.displayName, "Rich Text")
    }
    
    func testImageDisplayName() {
        XCTAssertEqual(ContentType.image.displayName, "Image")
    }
    
    func testVideoDisplayName() {
        XCTAssertEqual(ContentType.video.displayName, "Video")
    }
    
    func testFileDisplayName() {
        XCTAssertEqual(ContentType.file.displayName, "File")
    }
    
    func testFileStackDisplayName() {
        XCTAssertEqual(ContentType.fileStack.displayName, "Files")
    }
    
    func testAllDisplayNamesNotEmpty() {
        for type in ContentType.allCases {
            XCTAssertFalse(type.displayName.isEmpty, "\(type) has empty display name")
        }
    }
    
    // MARK: - System Image Names
    
    func testTextSystemImageName() {
        XCTAssertEqual(ContentType.text.systemImageName, "text.alignleft")
    }
    
    func testRichTextSystemImageName() {
        XCTAssertEqual(ContentType.richText.systemImageName, "text.badge.star")
    }
    
    func testImageSystemImageName() {
        XCTAssertEqual(ContentType.image.systemImageName, "photo")
    }
    
    func testVideoSystemImageName() {
        XCTAssertEqual(ContentType.video.systemImageName, "video")
    }
    
    func testFileSystemImageName() {
        XCTAssertEqual(ContentType.file.systemImageName, "doc")
    }
    
    func testFileStackSystemImageName() {
        XCTAssertEqual(ContentType.fileStack.systemImageName, "doc.on.doc")
    }
    
    func testAllSystemImageNamesNotEmpty() {
        for type in ContentType.allCases {
            XCTAssertFalse(type.systemImageName.isEmpty, "\(type) has empty system image name")
        }
    }
    
    // MARK: - Raw Values
    
    func testRawValuesStable() {
        // These raw values are stored in the database, so they must not change
        XCTAssertEqual(ContentType.text.rawValue, "text")
        XCTAssertEqual(ContentType.richText.rawValue, "richText")
        XCTAssertEqual(ContentType.image.rawValue, "image")
        XCTAssertEqual(ContentType.video.rawValue, "video")
        XCTAssertEqual(ContentType.file.rawValue, "file")
        XCTAssertEqual(ContentType.fileStack.rawValue, "fileStack")
    }
    
    func testRawValueRoundTrip() {
        for type in ContentType.allCases {
            let fromRawValue = ContentType(rawValue: type.rawValue)
            XCTAssertEqual(fromRawValue, type, "Round-trip failed for \(type)")
        }
    }
    
    // MARK: - CaseIterable
    
    func testCaseIterableIncludesAllCases() {
        let allCases = ContentType.allCases
        XCTAssertEqual(allCases.count, 6)
        XCTAssertTrue(allCases.contains(.text))
        XCTAssertTrue(allCases.contains(.richText))
        XCTAssertTrue(allCases.contains(.image))
        XCTAssertTrue(allCases.contains(.video))
        XCTAssertTrue(allCases.contains(.file))
        XCTAssertTrue(allCases.contains(.fileStack))
    }
    
    // MARK: - Codable
    
    func testCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        for type in ContentType.allCases {
            let encoded = try encoder.encode(type)
            let decoded = try decoder.decode(ContentType.self, from: encoded)
            XCTAssertEqual(decoded, type, "Codable round-trip failed for \(type)")
        }
    }
}
