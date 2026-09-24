// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Carbon.HIToolbox
@testable import ClipboardMenu

final class KeyboardShortcutTests: XCTestCase {
    
    // MARK: - Initialization
    
    func testInitWithKeyCodeAndModifiers() {
        let shortcut = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: KeyboardShortcut.Modifiers.command)
        
        XCTAssertEqual(shortcut.keyCode, UInt32(kVK_ANSI_V))
        XCTAssertEqual(shortcut.modifiers, KeyboardShortcut.Modifiers.command)
    }
    
    func testInitWithMultipleModifiers() {
        let modifiers = KeyboardShortcut.Modifiers.command | KeyboardShortcut.Modifiers.shift
        let shortcut = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: modifiers)
        
        XCTAssertEqual(shortcut.modifiers, modifiers)
    }
    
    // MARK: - Default Shortcuts
    
    func testDefaultHistoryShortcut() {
        let shortcut = KeyboardShortcut.defaultHistory
        
        XCTAssertEqual(shortcut.keyCode, UInt32(kVK_ANSI_V))
        XCTAssertEqual(shortcut.modifiers, KeyboardShortcut.Modifiers.command | KeyboardShortcut.Modifiers.shift)
    }
    
    func testDefaultSnippetsShortcut() {
        let shortcut = KeyboardShortcut.defaultSnippets
        
        XCTAssertEqual(shortcut.keyCode, UInt32(kVK_ANSI_S))
        XCTAssertEqual(shortcut.modifiers, KeyboardShortcut.Modifiers.command | KeyboardShortcut.Modifiers.shift)
    }
    
    // MARK: - Modifiers Constants
    
    func testModifierCommandValue() {
        XCTAssertEqual(KeyboardShortcut.Modifiers.command, 1 << 8)
    }
    
    func testModifierShiftValue() {
        XCTAssertEqual(KeyboardShortcut.Modifiers.shift, 1 << 9)
    }
    
    func testModifierOptionValue() {
        XCTAssertEqual(KeyboardShortcut.Modifiers.option, 1 << 11)
    }
    
    func testModifierControlValue() {
        XCTAssertEqual(KeyboardShortcut.Modifiers.control, 1 << 12)
    }
    
    // MARK: - Display String
    
    func testDisplayStringCommandV() {
        let shortcut = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: KeyboardShortcut.Modifiers.command)
        XCTAssertEqual(shortcut.displayString, "⌘V")
    }
    
    func testDisplayStringCommandShiftV() {
        let shortcut = KeyboardShortcut.defaultHistory
        XCTAssertEqual(shortcut.displayString, "⇧⌘V")
    }
    
    func testDisplayStringCommandShiftS() {
        let shortcut = KeyboardShortcut.defaultSnippets
        XCTAssertEqual(shortcut.displayString, "⇧⌘S")
    }
    
    func testDisplayStringAllModifiers() {
        let modifiers = KeyboardShortcut.Modifiers.command | 
                        KeyboardShortcut.Modifiers.shift | 
                        KeyboardShortcut.Modifiers.option | 
                        KeyboardShortcut.Modifiers.control
        let shortcut = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: modifiers)
        XCTAssertEqual(shortcut.displayString, "⌃⌥⇧⌘A")
    }
    
    func testDisplayStringControlOption() {
        let modifiers = KeyboardShortcut.Modifiers.control | KeyboardShortcut.Modifiers.option
        let shortcut = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: modifiers)
        XCTAssertEqual(shortcut.displayString, "⌃⌥C")
    }
    
    // MARK: - Key Code to String Mapping
    
    func testDisplayStringLetterKeys() {
        let letters = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"),
            (kVK_ANSI_D, "D"), (kVK_ANSI_E, "E"), (kVK_ANSI_F, "F"),
            (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"), (kVK_ANSI_I, "I"),
            (kVK_ANSI_J, "J"), (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"),
            (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"),
            (kVK_ANSI_P, "P"), (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"),
            (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"), (kVK_ANSI_U, "U"),
            (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"),
            (kVK_ANSI_Y, "Y"), (kVK_ANSI_Z, "Z")
        ]
        
        for (keyCode, expected) in letters {
            let shortcut = KeyboardShortcut(keyCode: UInt32(keyCode), modifiers: KeyboardShortcut.Modifiers.command)
            XCTAssertTrue(shortcut.displayString.hasSuffix(expected), "Expected \(expected) but got \(shortcut.displayString)")
        }
    }
    
    func testDisplayStringNumberKeys() {
        let numbers = [
            (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"),
            (kVK_ANSI_3, "3"), (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"),
            (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"), (kVK_ANSI_8, "8"),
            (kVK_ANSI_9, "9")
        ]
        
        for (keyCode, expected) in numbers {
            let shortcut = KeyboardShortcut(keyCode: UInt32(keyCode), modifiers: KeyboardShortcut.Modifiers.command)
            XCTAssertTrue(shortcut.displayString.hasSuffix(expected), "Expected \(expected) but got \(shortcut.displayString)")
        }
    }
    
    func testDisplayStringSpecialKeys() {
        let specialKeys: [(Int, String)] = [
            (kVK_Return, "↩"),
            (kVK_Tab, "⇥"),
            (kVK_Space, "Space"),
            (kVK_Delete, "⌫"),
            (kVK_Escape, "⎋"),
            (kVK_LeftArrow, "←"),
            (kVK_RightArrow, "→"),
            (kVK_UpArrow, "↑"),
            (kVK_DownArrow, "↓")
        ]
        
        for (keyCode, expected) in specialKeys {
            let shortcut = KeyboardShortcut(keyCode: UInt32(keyCode), modifiers: KeyboardShortcut.Modifiers.command)
            XCTAssertTrue(shortcut.displayString.hasSuffix(expected), "Expected \(expected) but got \(shortcut.displayString)")
        }
    }
    
    func testDisplayStringFunctionKeys() {
        let functionKeys: [(Int, String)] = [
            (kVK_F1, "F1"), (kVK_F2, "F2"), (kVK_F3, "F3"),
            (kVK_F4, "F4"), (kVK_F5, "F5"), (kVK_F6, "F6"),
            (kVK_F7, "F7"), (kVK_F8, "F8"), (kVK_F9, "F9"),
            (kVK_F10, "F10"), (kVK_F11, "F11"), (kVK_F12, "F12")
        ]
        
        for (keyCode, expected) in functionKeys {
            let shortcut = KeyboardShortcut(keyCode: UInt32(keyCode), modifiers: KeyboardShortcut.Modifiers.command)
            XCTAssertTrue(shortcut.displayString.hasSuffix(expected), "Expected \(expected) but got \(shortcut.displayString)")
        }
    }
    
    func testDisplayStringUnknownKeyCode() {
        let shortcut = KeyboardShortcut(keyCode: 999, modifiers: KeyboardShortcut.Modifiers.command)
        XCTAssertTrue(shortcut.displayString.hasSuffix("?"))
    }
    
    // MARK: - Equatable
    
    func testEquatableEqual() {
        let shortcut1 = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: KeyboardShortcut.Modifiers.command)
        let shortcut2 = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: KeyboardShortcut.Modifiers.command)
        
        XCTAssertEqual(shortcut1, shortcut2)
    }
    
    func testEquatableNotEqualDifferentKey() {
        let shortcut1 = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: KeyboardShortcut.Modifiers.command)
        let shortcut2 = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: KeyboardShortcut.Modifiers.command)
        
        XCTAssertNotEqual(shortcut1, shortcut2)
    }
    
    func testEquatableNotEqualDifferentModifiers() {
        let shortcut1 = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: KeyboardShortcut.Modifiers.command)
        let shortcut2 = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: KeyboardShortcut.Modifiers.command | KeyboardShortcut.Modifiers.shift)
        
        XCTAssertNotEqual(shortcut1, shortcut2)
    }
    
    // MARK: - Codable
    
    func testCodableRoundTrip() throws {
        let original = KeyboardShortcut.defaultHistory
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(KeyboardShortcut.self, from: encoded)
        
        XCTAssertEqual(decoded, original)
    }
    
    func testCodableWithAllModifiers() throws {
        let modifiers = KeyboardShortcut.Modifiers.command | 
                        KeyboardShortcut.Modifiers.shift | 
                        KeyboardShortcut.Modifiers.option | 
                        KeyboardShortcut.Modifiers.control
        let original = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_X), modifiers: modifiers)
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(KeyboardShortcut.self, from: encoded)
        
        XCTAssertEqual(decoded, original)
    }
    
    // MARK: - Data Persistence
    
    func testToDataReturnsData() {
        let shortcut = KeyboardShortcut.defaultHistory
        let data = shortcut.toData()
        
        XCTAssertNotNil(data)
    }
    
    func testFromDataReturnsShortcut() {
        let original = KeyboardShortcut.defaultHistory
        let data = original.toData()!
        
        let restored = KeyboardShortcut.fromData(data)
        
        XCTAssertEqual(restored, original)
    }
    
    func testFromDataInvalidDataReturnsNil() {
        let invalidData = "not valid json".data(using: .utf8)!
        
        let result = KeyboardShortcut.fromData(invalidData)
        
        XCTAssertNil(result)
    }
    
    func testToDataFromDataRoundTrip() {
        let shortcuts = [
            KeyboardShortcut.defaultHistory,
            KeyboardShortcut.defaultSnippets,
            KeyboardShortcut(keyCode: UInt32(kVK_F1), modifiers: KeyboardShortcut.Modifiers.control)
        ]
        
        for original in shortcuts {
            guard let data = original.toData() else {
                XCTFail("Failed to encode shortcut")
                continue
            }
            guard let restored = KeyboardShortcut.fromData(data) else {
                XCTFail("Failed to decode shortcut")
                continue
            }
            XCTAssertEqual(restored, original)
        }
    }
}
