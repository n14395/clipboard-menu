// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Carbon.HIToolbox
@testable import ClipboardMenu

@MainActor
final class HotkeyServiceTests: XCTestCase {
    var hotkeyService: HotkeyService!
    
    override func setUp() async throws {
        hotkeyService = HotkeyService()
    }
    
    override func tearDown() async throws {
        hotkeyService?.cleanup()
        hotkeyService = nil
    }
    
    // MARK: - Initialization
    
    func testInitWithDefaultShortcuts() {
        let service = HotkeyService()
        
        XCTAssertEqual(service.historyShortcut, KeyboardShortcut.defaultHistory)
        XCTAssertEqual(service.snippetsShortcut, KeyboardShortcut.defaultSnippets)
        XCTAssertFalse(service.isActive)
    }
    
    func testInitWithCustomShortcuts() {
        let customHistory = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_H), modifiers: KeyboardShortcut.Modifiers.command)
        let customSnippets = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_N), modifiers: KeyboardShortcut.Modifiers.command)
        
        let service = HotkeyService(historyShortcut: customHistory, snippetsShortcut: customSnippets)
        
        XCTAssertEqual(service.historyShortcut, customHistory)
        XCTAssertEqual(service.snippetsShortcut, customSnippets)
    }
    
    // MARK: - Start/Stop
    
    func testStartSetsActiveTrue() {
        hotkeyService.start(onHistory: {}, onSnippets: {})
        
        XCTAssertTrue(hotkeyService.isActive)
    }
    
    func testStopSetsActiveFalse() {
        hotkeyService.start(onHistory: {}, onSnippets: {})
        hotkeyService.stop()
        
        XCTAssertFalse(hotkeyService.isActive)
    }
    
    func testCleanupStopsService() {
        hotkeyService.start(onHistory: {}, onSnippets: {})
        hotkeyService.cleanup()
        
        XCTAssertFalse(hotkeyService.isActive)
    }
    
    func testStartWithSnippetsDisabled() {
        hotkeyService.start(onHistory: {}, onSnippets: {}, snippetsEnabled: false)
        
        XCTAssertTrue(hotkeyService.isActive)
    }
    
    // MARK: - Update Shortcuts
    
    func testUpdateHistoryShortcut() {
        let newShortcut = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_H), modifiers: KeyboardShortcut.Modifiers.command | KeyboardShortcut.Modifiers.shift)
        
        hotkeyService.updateHistoryShortcut(newShortcut)
        
        XCTAssertEqual(hotkeyService.historyShortcut, newShortcut)
    }
    
    func testUpdateSnippetsShortcut() {
        let newShortcut = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_N), modifiers: KeyboardShortcut.Modifiers.command | KeyboardShortcut.Modifiers.option)
        
        hotkeyService.updateSnippetsShortcut(newShortcut)
        
        XCTAssertEqual(hotkeyService.snippetsShortcut, newShortcut)
    }
    
    func testUpdateHistoryShortcutWhileActive() {
        hotkeyService.start(onHistory: {}, onSnippets: {})
        
        let newShortcut = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_X), modifiers: KeyboardShortcut.Modifiers.command | KeyboardShortcut.Modifiers.shift)
        hotkeyService.updateHistoryShortcut(newShortcut)
        
        XCTAssertEqual(hotkeyService.historyShortcut, newShortcut)
        XCTAssertTrue(hotkeyService.isActive)
    }
    
    func testUpdateSnippetsShortcutWhileActive() {
        hotkeyService.start(onHistory: {}, onSnippets: {})
        
        let newShortcut = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_Y), modifiers: KeyboardShortcut.Modifiers.command | KeyboardShortcut.Modifiers.option)
        hotkeyService.updateSnippetsShortcut(newShortcut)
        
        XCTAssertEqual(hotkeyService.snippetsShortcut, newShortcut)
        XCTAssertTrue(hotkeyService.isActive)
    }
    
    // MARK: - Snippets Shortcut Enable/Disable
    
    func testSetSnippetsShortcutEnabledTrue() {
        hotkeyService.start(onHistory: {}, onSnippets: {}, snippetsEnabled: false)
        
        hotkeyService.setSnippetsShortcutEnabled(true)
        
        // Service should still be active
        XCTAssertTrue(hotkeyService.isActive)
    }
    
    func testSetSnippetsShortcutEnabledFalse() {
        hotkeyService.start(onHistory: {}, onSnippets: {}, snippetsEnabled: true)
        
        hotkeyService.setSnippetsShortcutEnabled(false)
        
        // Service should still be active (only history shortcut)
        XCTAssertTrue(hotkeyService.isActive)
    }
    
    func testSetSnippetsShortcutEnabledNoChangeWhenSameValue() {
        hotkeyService.start(onHistory: {}, onSnippets: {}, snippetsEnabled: true)
        
        // Should be a no-op
        hotkeyService.setSnippetsShortcutEnabled(true)
        
        XCTAssertTrue(hotkeyService.isActive)
    }
    
    // MARK: - Published Properties
    
    func testHistoryShortcutIsPublished() {
        let service = HotkeyService()
        
        // Test that historyShortcut property exists and is readable
        let shortcut = service.historyShortcut
        XCTAssertNotNil(shortcut)
    }
    
    func testSnippetsShortcutIsPublished() {
        let service = HotkeyService()
        
        // Test that snippetsShortcut property exists and is readable
        let shortcut = service.snippetsShortcut
        XCTAssertNotNil(shortcut)
    }
    
    func testIsActiveIsPublished() {
        let service = HotkeyService()
        
        // Test that isActive property exists and is readable
        let active = service.isActive
        XCTAssertFalse(active)
    }
    
    // MARK: - Multiple Start/Stop Cycles
    
    func testMultipleStartStopCycles() {
        for _ in 0..<5 {
            hotkeyService.start(onHistory: {}, onSnippets: {})
            XCTAssertTrue(hotkeyService.isActive)
            
            hotkeyService.stop()
            XCTAssertFalse(hotkeyService.isActive)
        }
    }
    
    func testStartAfterCleanup() {
        hotkeyService.start(onHistory: {}, onSnippets: {})
        hotkeyService.cleanup()
        
        // Should be able to start again after cleanup
        hotkeyService.start(onHistory: {}, onSnippets: {})
        XCTAssertTrue(hotkeyService.isActive)
    }
}

// MARK: - HotkeyIdentifier Tests

final class HotkeyIdentifierTests: XCTestCase {
    func testHistoryRawValue() {
        XCTAssertEqual(HotkeyIdentifier.history.rawValue, 1)
    }
    
    func testSnippetsRawValue() {
        XCTAssertEqual(HotkeyIdentifier.snippets.rawValue, 2)
    }
    
    func testIdentifiersAreUnique() {
        XCTAssertNotEqual(HotkeyIdentifier.history.rawValue, HotkeyIdentifier.snippets.rawValue)
    }
}
