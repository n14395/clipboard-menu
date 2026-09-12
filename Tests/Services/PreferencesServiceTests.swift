import XCTest
import Combine
@testable import ClipboardMenu

@MainActor
final class PreferencesServiceTests: XCTestCase {
    
    var preferencesService: PreferencesService!
    var testDefaults: UserDefaults!
    
    override func setUp() async throws {
        // Create a separate UserDefaults suite for testing
        let suiteName = "com.clipboardmenu.tests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        preferencesService = PreferencesService(defaults: testDefaults)
    }
    
    override func tearDown() async throws {
        // Clean up the test suite
        if let suiteName = testDefaults.volatileDomainNames.first {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        preferencesService = nil
        testDefaults = nil
    }
    
    // MARK: - Default Values
    
    func testDefaultMaxHistoryItems() {
        XCTAssertEqual(preferencesService.maxHistoryItems, 25)
    }
    
    func testDefaultMaxStorageMB() {
        XCTAssertEqual(preferencesService.maxStorageMB, 10240) // 10GB
    }
    
    func testDefaultMaxItemSizeMB() {
        XCTAssertEqual(preferencesService.maxItemSizeMB, 1024) // 1GB
    }
    
    func testDefaultLaunchAtLogin() {
        XCTAssertFalse(preferencesService.launchAtLogin)
    }
    
    func testDefaultHistoryShortcut() {
        XCTAssertEqual(preferencesService.historyShortcutData, .defaultHistory)
        // Display order is: Control, Option, Shift, Command (standard macOS order)
        XCTAssertEqual(preferencesService.historyShortcutDisplay, "⇧⌘V")
    }
    
    func testDefaultSnippetsShortcut() {
        XCTAssertEqual(preferencesService.snippetsShortcutData, .defaultSnippets)
        // Display order is: Control, Option, Shift, Command (standard macOS order)
        XCTAssertEqual(preferencesService.snippetsShortcutDisplay, "⇧⌘S")
    }
    
    func testDefaultSnippetsMenuMode() {
        XCTAssertEqual(preferencesService.snippetsMenuMode, .separate)
    }
    
    func testDefaultPreviewSize() {
        XCTAssertEqual(preferencesService.previewSize, 500)
    }
    
    func testDefaultHasCompletedOnboarding() {
        XCTAssertFalse(preferencesService.hasCompletedOnboarding)
    }
    
    func testDefaultGlobalShortcutsEnabled() {
        XCTAssertFalse(preferencesService.globalShortcutsEnabled)
    }
    
    func testDefaultCompactHistoryView() {
        XCTAssertFalse(preferencesService.compactHistoryView)
    }
    
    func testDefaultCompactSnippetsView() {
        XCTAssertFalse(preferencesService.compactSnippetsView)
    }
    
    // MARK: - Computed Properties
    
    func testMaxStorageBytesConversion() {
        preferencesService.maxStorageMB = 100
        XCTAssertEqual(preferencesService.maxStorageBytes, 100 * 1024 * 1024)
    }
    
    func testMaxStorageBytesLargeValue() {
        preferencesService.maxStorageMB = 10240 // 10GB
        XCTAssertEqual(preferencesService.maxStorageBytes, Int64(10240) * 1024 * 1024)
    }
    
    func testMaxItemSizeBytesConversion() {
        preferencesService.maxItemSizeMB = 50
        XCTAssertEqual(preferencesService.maxItemSizeBytes, 50 * 1024 * 1024)
    }
    
    // MARK: - Persistence
    
    func testMaxHistoryItemsPersists() {
        preferencesService.maxHistoryItems = 500
        
        // Create new instance with same defaults
        let newService = PreferencesService(defaults: testDefaults)
        
        XCTAssertEqual(newService.maxHistoryItems, 500)
    }
    
    func testMaxStorageMBPersists() {
        preferencesService.maxStorageMB = 5000
        
        let newService = PreferencesService(defaults: testDefaults)
        
        XCTAssertEqual(newService.maxStorageMB, 5000)
    }
    
    func testHistoryShortcutPersists() {
        // Create a custom shortcut (Cmd+Opt+V)
        let customShortcut = KeyboardShortcut(
            keyCode: KeyboardShortcut.defaultHistory.keyCode,
            modifiers: KeyboardShortcut.Modifiers.command | KeyboardShortcut.Modifiers.option
        )
        preferencesService.historyShortcutData = customShortcut
        
        let newService = PreferencesService(defaults: testDefaults)
        
        XCTAssertEqual(newService.historyShortcutData, customShortcut)
        XCTAssertEqual(newService.historyShortcutDisplay, "⌥⌘V")
    }
    
    func testSnippetsMenuModePersists() {
        preferencesService.snippetsMenuMode = .integrated
        
        let newService = PreferencesService(defaults: testDefaults)
        
        XCTAssertEqual(newService.snippetsMenuMode, .integrated)
    }
    
    func testPreviewSizePersists() {
        preferencesService.previewSize = 800
        
        let newService = PreferencesService(defaults: testDefaults)
        
        XCTAssertEqual(newService.previewSize, 800)
    }
    
    func testHasCompletedOnboardingPersists() {
        preferencesService.hasCompletedOnboarding = true
        
        let newService = PreferencesService(defaults: testDefaults)
        
        XCTAssertTrue(newService.hasCompletedOnboarding)
    }
    
    func testGlobalShortcutsEnabledPersists() {
        preferencesService.globalShortcutsEnabled = true
        
        let newService = PreferencesService(defaults: testDefaults)
        
        XCTAssertTrue(newService.globalShortcutsEnabled)
    }
    
    func testCompactHistoryViewPersists() {
        preferencesService.compactHistoryView = true
        
        let newService = PreferencesService(defaults: testDefaults)
        
        XCTAssertTrue(newService.compactHistoryView)
    }
    
    func testCompactSnippetsViewPersists() {
        preferencesService.compactSnippetsView = true
        
        let newService = PreferencesService(defaults: testDefaults)
        
        XCTAssertTrue(newService.compactSnippetsView)
    }
    
    // MARK: - Reset to Defaults
    
    func testResetToDefaultsResetsAllValues() {
        // Change all values
        preferencesService.maxHistoryItems = 500
        preferencesService.maxStorageMB = 5000
        preferencesService.maxItemSizeMB = 500
        // Custom shortcuts (Cmd+Opt+V and Cmd+Opt+S)
        preferencesService.historyShortcutData = KeyboardShortcut(
            keyCode: KeyboardShortcut.defaultHistory.keyCode,
            modifiers: KeyboardShortcut.Modifiers.command | KeyboardShortcut.Modifiers.option
        )
        preferencesService.snippetsShortcutData = KeyboardShortcut(
            keyCode: KeyboardShortcut.defaultSnippets.keyCode,
            modifiers: KeyboardShortcut.Modifiers.command | KeyboardShortcut.Modifiers.option
        )
        preferencesService.snippetsMenuMode = .integrated
        preferencesService.previewSize = 800
        preferencesService.globalShortcutsEnabled = true
        preferencesService.compactHistoryView = true
        preferencesService.compactSnippetsView = true
        
        // Reset
        preferencesService.resetToDefaults()
        
        // Verify UI settings reset to defaults
        XCTAssertEqual(preferencesService.historyShortcutData, .defaultHistory)
        XCTAssertEqual(preferencesService.snippetsShortcutData, .defaultSnippets)
        XCTAssertEqual(preferencesService.snippetsMenuMode, .separate)
        XCTAssertEqual(preferencesService.previewSize, 500)
        XCTAssertFalse(preferencesService.globalShortcutsEnabled)
        XCTAssertFalse(preferencesService.compactHistoryView)
        XCTAssertFalse(preferencesService.compactSnippetsView)
        
        // Storage settings are NOT reset (by design, to avoid data loss)
        XCTAssertEqual(preferencesService.maxHistoryItems, 500)
        XCTAssertEqual(preferencesService.maxStorageMB, 5000)
        XCTAssertEqual(preferencesService.maxItemSizeMB, 500)
    }
    
    func testResetToDefaultsDoesNotResetStorageSettings() {
        // Set custom storage values
        preferencesService.maxHistoryItems = 1000
        preferencesService.maxStorageMB = 20480
        preferencesService.maxItemSizeMB = 2048
        
        preferencesService.resetToDefaults()
        
        // Storage settings should be preserved to avoid triggering deletion of history
        XCTAssertEqual(preferencesService.maxHistoryItems, 1000)
        XCTAssertEqual(preferencesService.maxStorageMB, 20480)
        XCTAssertEqual(preferencesService.maxItemSizeMB, 2048)
    }
    
    func testResetToDefaultsDoesNotResetOnboarding() {
        preferencesService.hasCompletedOnboarding = true
        
        preferencesService.resetToDefaults()
        
        // hasCompletedOnboarding is not reset
        XCTAssertTrue(preferencesService.hasCompletedOnboarding)
    }
    
    // MARK: - File System Bookmark
    
    func testFileSystemBookmarkGetSet() {
        let bookmarkData = Data([0x01, 0x02, 0x03])
        
        preferencesService.fileSystemBookmark = bookmarkData
        
        XCTAssertEqual(preferencesService.fileSystemBookmark, bookmarkData)
    }
    
    func testFileSystemBookmarkNil() {
        XCTAssertNil(preferencesService.fileSystemBookmark)
    }
    
    func testFileSystemBookmarkPersists() {
        let bookmarkData = Data([0x01, 0x02, 0x03])
        preferencesService.fileSystemBookmark = bookmarkData
        
        let newService = PreferencesService(defaults: testDefaults)
        
        XCTAssertEqual(newService.fileSystemBookmark, bookmarkData)
    }
}

// MARK: - SnippetsMenuMode Tests

final class SnippetsMenuModeTests: XCTestCase {
    
    func testSeparateDisplayName() {
        XCTAssertEqual(SnippetsMenuMode.separate.displayName, "Separate")
    }
    
    func testIntegratedDisplayName() {
        XCTAssertEqual(SnippetsMenuMode.integrated.displayName, "Integrated")
    }
    
    func testRawValues() {
        XCTAssertEqual(SnippetsMenuMode.separate.rawValue, "separate")
        XCTAssertEqual(SnippetsMenuMode.integrated.rawValue, "integrated")
    }
    
    func testCaseIterable() {
        let allCases = SnippetsMenuMode.allCases
        XCTAssertEqual(allCases.count, 2)
        XCTAssertTrue(allCases.contains(.separate))
        XCTAssertTrue(allCases.contains(.integrated))
    }
}

// MARK: - Storage Limit Publishing Tests

@MainActor
final class PreferencesServicePublishingTests: XCTestCase {
    var preferencesService: PreferencesService!
    var testDefaults: UserDefaults!
    
    override func setUp() async throws {
        let suiteName = "com.clipboardmenu.tests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        preferencesService = PreferencesService(defaults: testDefaults)
    }
    
    override func tearDown() async throws {
        preferencesService = nil
        testDefaults = nil
    }
    
    func testMaxHistoryItemsIsPublished() async throws {
        var receivedValues: [Int] = []
        let cancellable = preferencesService.$maxHistoryItems
            .sink { value in
                receivedValues.append(value)
            }
        
        preferencesService.maxHistoryItems = 500
        preferencesService.maxHistoryItems = 100
        
        // Allow time for Combine to publish
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Should have initial value plus two updates
        XCTAssertTrue(receivedValues.contains(500))
        XCTAssertTrue(receivedValues.contains(100))
        
        cancellable.cancel()
    }
    
    func testMaxStorageMBIsPublished() async throws {
        var receivedValues: [Int] = []
        let cancellable = preferencesService.$maxStorageMB
            .sink { value in
                receivedValues.append(value)
            }
        
        preferencesService.maxStorageMB = 5000
        preferencesService.maxStorageMB = 2000
        
        // Allow time for Combine to publish
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Should have initial value plus two updates
        XCTAssertTrue(receivedValues.contains(5000))
        XCTAssertTrue(receivedValues.contains(2000))
        
        cancellable.cancel()
    }
    
    func testMaxStorageBytesUpdatesWithMaxStorageMB() {
        preferencesService.maxStorageMB = 100
        XCTAssertEqual(preferencesService.maxStorageBytes, 100 * 1024 * 1024)
        
        preferencesService.maxStorageMB = 500
        XCTAssertEqual(preferencesService.maxStorageBytes, 500 * 1024 * 1024)
    }
    
    func testMaxItemSizeBytesUpdatesWithMaxItemSizeMB() {
        preferencesService.maxItemSizeMB = 50
        XCTAssertEqual(preferencesService.maxItemSizeBytes, 50 * 1024 * 1024)
        
        preferencesService.maxItemSizeMB = 200
        XCTAssertEqual(preferencesService.maxItemSizeBytes, 200 * 1024 * 1024)
    }
}
