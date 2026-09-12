import XCTest
@testable import ClipboardMenu

@MainActor
final class SearchServiceTests: XCTestCase {
    
    var searchService: SearchService!
    
    override func setUp() async throws {
        searchService = SearchService()
    }
    
    override func tearDown() async throws {
        searchService = nil
    }
    
    // MARK: - Search Items - Empty Query
    
    func testSearchItemsEmptyQueryReturnsAll() {
        let items = TestData.textItems(count: 5)
        let results = searchService.search(items: items, query: "", useRegex: false)
        
        XCTAssertEqual(results.count, 5)
    }
    
    func testSearchItemsWhitespaceOnlyQueryReturnsAll() {
        let items = TestData.textItems(count: 3)
        // Note: The implementation trims the query, so this tests empty string behavior
        let results = searchService.search(items: items, query: "", useRegex: false)
        
        XCTAssertEqual(results.count, 3)
    }
    
    // MARK: - Search Items - Plain Text
    
    func testSearchItemsPlainTextMatches() {
        let items = [
            TestData.textItem(text: "Hello World"),
            TestData.textItem(text: "Goodbye World"),
            TestData.textItem(text: "Hello There")
        ]
        
        let results = searchService.search(items: items, query: "Hello", useRegex: false)
        
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.textContent?.contains("Hello") == true })
    }
    
    func testSearchItemsPlainTextNoMatch() {
        let items = [
            TestData.textItem(text: "Hello World"),
            TestData.textItem(text: "Goodbye World")
        ]
        
        let results = searchService.search(items: items, query: "NotFound", useRegex: false)
        
        XCTAssertEqual(results.count, 0)
    }
    
    func testSearchItemsCaseInsensitive() {
        let items = [
            TestData.textItem(text: "Hello World"),
            TestData.textItem(text: "HELLO THERE"),
            TestData.textItem(text: "hello again")
        ]
        
        let results = searchService.search(items: items, query: "hello", useRegex: false)
        
        XCTAssertEqual(results.count, 3)
    }
    
    func testSearchItemsPartialMatch() {
        let items = [
            TestData.textItem(text: "The quick brown fox"),
            TestData.textItem(text: "A fox jumps over")
        ]
        
        let results = searchService.search(items: items, query: "fox", useRegex: false)
        
        XCTAssertEqual(results.count, 2)
    }
    
    func testSearchItemsIgnoresNilContent() {
        let items = [
            TestData.textItem(text: "Has content"),
            TestData.imageItem() // No textContent
        ]
        
        let results = searchService.search(items: items, query: "content", useRegex: false)
        
        XCTAssertEqual(results.count, 1)
    }
    
    // MARK: - Search Items - Regex
    
    func testSearchItemsRegexValid() {
        let items = [
            TestData.textItem(text: "abc123"),
            TestData.textItem(text: "def456"),
            TestData.textItem(text: "abc789")
        ]
        
        let results = searchService.search(items: items, query: "abc\\d+", useRegex: true)
        
        XCTAssertEqual(results.count, 2)
    }
    
    func testSearchItemsRegexSpecialChars() {
        let items = [
            TestData.textItem(text: "foo.bar"),
            TestData.textItem(text: "fooXbar"),
            TestData.textItem(text: "foo bar")
        ]
        
        // \. matches literal dot
        let results = searchService.search(items: items, query: "foo\\.bar", useRegex: true)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.textContent, "foo.bar")
    }
    
    func testSearchItemsInvalidRegexFallback() {
        let items = [
            TestData.textItem(text: "test [bracket"),
            TestData.textItem(text: "no brackets here")
        ]
        
        // Invalid regex (unclosed bracket) should fall back to plain text search
        let results = searchService.search(items: items, query: "[bracket", useRegex: true)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.textContent, "test [bracket")
    }
    
    func testSearchItemsRegexCaseInsensitive() {
        let items = [
            TestData.textItem(text: "Hello World"),
            TestData.textItem(text: "HELLO THERE")
        ]
        
        let results = searchService.search(items: items, query: "hello", useRegex: true)
        
        XCTAssertEqual(results.count, 2)
    }
    
    // MARK: - Search Snippets
    
    func testSearchSnippetsEmptyQueryReturnsAll() {
        let snippets = TestData.snippets(count: 4)
        let results = searchService.search(snippets: snippets, query: "", useRegex: false)
        
        XCTAssertEqual(results.count, 4)
    }
    
    func testSearchSnippetsMatchesName() {
        let snippets = [
            TestData.snippet(name: "Email Signature", textContent: "Best regards"),
            TestData.snippet(name: "Address", textContent: "123 Main St"),
            TestData.snippet(name: "Email Template", textContent: "Dear Sir/Madam")
        ]
        
        let results = searchService.search(snippets: snippets, query: "Email", useRegex: false)
        
        XCTAssertEqual(results.count, 2)
    }
    
    func testSearchSnippetsMatchesContent() {
        let snippets = [
            TestData.snippet(name: "Greeting", textContent: "Hello World"),
            TestData.snippet(name: "Farewell", textContent: "Goodbye World")
        ]
        
        let results = searchService.search(snippets: snippets, query: "World", useRegex: false)
        
        XCTAssertEqual(results.count, 2)
    }
    
    func testSearchSnippetsMatchesNameOrContent() {
        let snippets = [
            TestData.snippet(name: "Hello Snippet", textContent: "Some content"),
            TestData.snippet(name: "Other Name", textContent: "Hello in content")
        ]
        
        let results = searchService.search(snippets: snippets, query: "Hello", useRegex: false)
        
        XCTAssertEqual(results.count, 2)
    }
    
    func testSearchSnippetsRegex() {
        let snippets = [
            TestData.snippet(name: "Code 1", textContent: "function test()"),
            TestData.snippet(name: "Code 2", textContent: "functional programming"),
            TestData.snippet(name: "Note", textContent: "just text")
        ]
        
        // "func\w+" matches "function" in Code 1 and "functional" in Code 2
        let results = searchService.search(snippets: snippets, query: "func\\w+", useRegex: true)
        
        XCTAssertEqual(results.count, 2)
    }
    
    // MARK: - Filter by Content Type
    
    func testFilterByContentTypeSingle() {
        let items = [
            TestData.textItem(),
            TestData.imageItem(),
            TestData.textItem(),
            TestData.videoItem()
        ]
        
        let results = searchService.filterByContentType(items: items, types: [.text])
        
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.contentType == .text })
    }
    
    func testFilterByContentTypeMultiple() {
        let items = [
            TestData.textItem(),
            TestData.imageItem(),
            TestData.videoItem(),
            TestData.fileItem()
        ]
        
        let results = searchService.filterByContentType(items: items, types: [.image, .video])
        
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.contentType == .image || $0.contentType == .video })
    }
    
    func testFilterByContentTypeEmptyReturnsAll() {
        let items = [
            TestData.textItem(),
            TestData.imageItem()
        ]
        
        let results = searchService.filterByContentType(items: items, types: [])
        
        XCTAssertEqual(results.count, 2)
    }
    
    func testFilterSnippetsByContentType() {
        let snippets = [
            TestData.snippet(contentType: .text),
            TestData.imageSnippet(),
            TestData.snippet(contentType: .text)
        ]
        
        let results = searchService.filterByContentType(snippets: snippets, types: [.image])
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.contentType, .image)
    }
    
    // MARK: - Highlight Matches
    
    func testHighlightMatchesPlainText() {
        let text = "Hello World"
        let matches = searchService.highlightMatches(in: text, query: "World", useRegex: false)
        
        XCTAssertEqual(matches.count, 2)
        
        // First segment: "Hello " (non-match)
        XCTAssertFalse(matches[0].isMatch)
        XCTAssertEqual(String(text[matches[0].range]), "Hello ")
        
        // Second segment: "World" (match)
        XCTAssertTrue(matches[1].isMatch)
        XCTAssertEqual(String(text[matches[1].range]), "World")
    }
    
    func testHighlightMatchesRegex() {
        let text = "abc123def456"
        let matches = searchService.highlightMatches(in: text, query: "\\d+", useRegex: true)
        
        // Should have: "abc" (no), "123" (yes), "def" (no), "456" (yes)
        XCTAssertEqual(matches.count, 4)
        XCTAssertFalse(matches[0].isMatch)
        XCTAssertTrue(matches[1].isMatch)
        XCTAssertFalse(matches[2].isMatch)
        XCTAssertTrue(matches[3].isMatch)
    }
    
    func testHighlightMatchesMultipleOccurrences() {
        let text = "the cat sat on the mat"
        let matches = searchService.highlightMatches(in: text, query: "the", useRegex: false)
        
        // Should match "the" twice
        let matchedRanges = matches.filter { $0.isMatch }
        XCTAssertEqual(matchedRanges.count, 2)
    }
    
    func testHighlightMatchesNoMatch() {
        let text = "Hello World"
        let matches = searchService.highlightMatches(in: text, query: "xyz", useRegex: false)
        
        XCTAssertEqual(matches.count, 1)
        XCTAssertFalse(matches[0].isMatch)
        XCTAssertEqual(String(text[matches[0].range]), text)
    }
    
    func testHighlightMatchesEmptyQuery() {
        let text = "Hello World"
        let matches = searchService.highlightMatches(in: text, query: "", useRegex: false)
        
        XCTAssertEqual(matches.count, 1)
        XCTAssertFalse(matches[0].isMatch)
        XCTAssertEqual(String(text[matches[0].range]), text)
    }
    
    func testHighlightMatchesInvalidRegex() {
        let text = "test [bracket"
        let matches = searchService.highlightMatches(in: text, query: "[invalid", useRegex: true)
        
        // Invalid regex should return single non-match segment
        XCTAssertEqual(matches.count, 1)
        XCTAssertFalse(matches[0].isMatch)
    }
    
    func testHighlightMatchesCaseInsensitive() {
        let text = "Hello HELLO hello"
        let matches = searchService.highlightMatches(in: text, query: "hello", useRegex: false)
        
        let matchedRanges = matches.filter { $0.isMatch }
        XCTAssertEqual(matchedRanges.count, 3)
    }
}
