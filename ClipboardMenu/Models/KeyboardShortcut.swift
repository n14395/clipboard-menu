import AppKit
import Carbon.HIToolbox

/// Represents a keyboard shortcut with key code and modifiers
struct KeyboardShortcut: Codable, Equatable {
    /// The virtual key code (Carbon key code)
    let keyCode: UInt32
    
    /// Modifier flags (Command, Shift, Option, Control)
    let modifiers: UInt32
    
    /// Common modifier flag constants matching Carbon/CGEventFlags
    struct Modifiers {
        static let command: UInt32 = 1 << 8   // cmdKey
        static let shift: UInt32 = 1 << 9     // shiftKey
        static let option: UInt32 = 1 << 11   // optionKey
        static let control: UInt32 = 1 << 12  // controlKey
    }
    
    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
    
    /// Creates a shortcut from an NSEvent
    init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        
        self.keyCode = UInt32(event.keyCode)
        
        var mods: UInt32 = 0
        if event.modifierFlags.contains(.command) {
            mods |= Modifiers.command
        }
        if event.modifierFlags.contains(.shift) {
            mods |= Modifiers.shift
        }
        if event.modifierFlags.contains(.option) {
            mods |= Modifiers.option
        }
        if event.modifierFlags.contains(.control) {
            mods |= Modifiers.control
        }
        
        // Require at least one modifier for global shortcuts
        guard mods != 0 else { return nil }
        
        self.modifiers = mods
    }
    
    /// Display string for the shortcut (e.g., "⌘⇧V")
    var displayString: String {
        var result = ""
        
        if modifiers & Modifiers.control != 0 {
            result += "⌃"
        }
        if modifiers & Modifiers.option != 0 {
            result += "⌥"
        }
        if modifiers & Modifiers.shift != 0 {
            result += "⇧"
        }
        if modifiers & Modifiers.command != 0 {
            result += "⌘"
        }
        
        result += keyCodeToString(keyCode)
        
        return result
    }
    
    /// Converts a key code to its string representation
    private func keyCodeToString(_ keyCode: UInt32) -> String {
        // Map common key codes to their string representations
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Grave: return "`"
        default: return "?"
        }
    }
    
    // MARK: - Default Shortcuts
    
    /// Default shortcut for clipboard history: ⌘⇧V
    static let defaultHistory = KeyboardShortcut(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: Modifiers.command | Modifiers.shift
    )
    
    /// Default shortcut for snippets: ⌘⇧S
    static let defaultSnippets = KeyboardShortcut(
        keyCode: UInt32(kVK_ANSI_S),
        modifiers: Modifiers.command | Modifiers.shift
    )
}

// MARK: - JSON Persistence

extension KeyboardShortcut {
    /// Encodes the shortcut to JSON data for UserDefaults storage
    func toData() -> Data? {
        try? JSONEncoder().encode(self)
    }
    
    /// Decodes a shortcut from JSON data
    static func fromData(_ data: Data) -> KeyboardShortcut? {
        try? JSONDecoder().decode(KeyboardShortcut.self, from: data)
    }
}
