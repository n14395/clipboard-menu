import AppKit
import Carbon.HIToolbox
import Combine

/// Identifier for registered hotkeys
enum HotkeyIdentifier: UInt32 {
    case history = 1
    case snippets = 2
}

/// Service for managing global keyboard shortcuts using the Carbon Event API
/// This approach works within the App Sandbox without requiring accessibility permissions
@MainActor
class HotkeyService: ObservableObject {
    /// Callback type for hotkey events
    typealias HotkeyCallback = () -> Void
    
    /// Current registered shortcuts
    @Published private(set) var historyShortcut: KeyboardShortcut
    @Published private(set) var snippetsShortcut: KeyboardShortcut
    
    /// Whether the service is currently active
    @Published private(set) var isActive: Bool = false
    
    /// Callbacks for each hotkey
    private var historyCallback: HotkeyCallback?
    private var snippetsCallback: HotkeyCallback?
    
    /// Carbon hotkey references
    private var historyHotkeyRef: EventHotKeyRef?
    private var snippetsHotkeyRef: EventHotKeyRef?
    
    /// Event handler reference
    private var eventHandlerRef: EventHandlerRef?
    
    /// Singleton instance needed for Carbon callback
    private static var sharedInstance: HotkeyService?
    
    init(
        historyShortcut: KeyboardShortcut = .defaultHistory,
        snippetsShortcut: KeyboardShortcut = .defaultSnippets
    ) {
        self.historyShortcut = historyShortcut
        self.snippetsShortcut = snippetsShortcut
    }
    
    // MARK: - Public API
    
    /// Whether snippets shortcut is enabled (disabled in integrated mode)
    private var snippetsShortcutEnabled: Bool = true
    
    /// Starts monitoring for global hotkeys
    /// - Parameters:
    ///   - onHistory: Callback when history shortcut is pressed
    ///   - onSnippets: Callback when snippets shortcut is pressed
    ///   - snippetsEnabled: Whether to register the snippets shortcut (false in integrated mode)
    func start(onHistory: @escaping HotkeyCallback, onSnippets: @escaping HotkeyCallback, snippetsEnabled: Bool = true) {
        self.historyCallback = onHistory
        self.snippetsCallback = onSnippets
        self.snippetsShortcutEnabled = snippetsEnabled
        
        // Store reference for Carbon callback
        HotkeyService.sharedInstance = self
        
        // Install event handler
        installEventHandler()
        
        // Register hotkeys
        registerHotkey(shortcut: historyShortcut, id: .history, ref: &historyHotkeyRef)
        if snippetsEnabled {
            registerHotkey(shortcut: snippetsShortcut, id: .snippets, ref: &snippetsHotkeyRef)
        }
        
        isActive = true
    }
    
    /// Updates whether the snippets shortcut is enabled
    func setSnippetsShortcutEnabled(_ enabled: Bool) {
        guard snippetsShortcutEnabled != enabled else { return }
        
        snippetsShortcutEnabled = enabled
        
        if enabled && isActive {
            // Register the snippets shortcut
            registerHotkey(shortcut: snippetsShortcut, id: .snippets, ref: &snippetsHotkeyRef)
        } else if !enabled {
            // Unregister the snippets shortcut
            if let ref = snippetsHotkeyRef {
                UnregisterEventHotKey(ref)
                snippetsHotkeyRef = nil
            }
        }
    }
    
    /// Stops monitoring for global hotkeys
    func stop() {
        unregisterAllHotkeys()
        removeEventHandler()
        HotkeyService.sharedInstance = nil
        isActive = false
    }
    
    /// Updates the history shortcut
    func updateHistoryShortcut(_ shortcut: KeyboardShortcut) {
        let wasActive = isActive
        
        // Unregister old hotkey
        if let ref = historyHotkeyRef {
            UnregisterEventHotKey(ref)
            historyHotkeyRef = nil
        }
        
        historyShortcut = shortcut
        
        // Register new hotkey if service is active
        if wasActive {
            registerHotkey(shortcut: shortcut, id: .history, ref: &historyHotkeyRef)
        }
    }
    
    /// Updates the snippets shortcut
    func updateSnippetsShortcut(_ shortcut: KeyboardShortcut) {
        let wasActive = isActive
        
        // Unregister old hotkey
        if let ref = snippetsHotkeyRef {
            UnregisterEventHotKey(ref)
            snippetsHotkeyRef = nil
        }
        
        snippetsShortcut = shortcut
        
        // Register new hotkey if service is active and snippets shortcut is enabled
        if wasActive && snippetsShortcutEnabled {
            registerHotkey(shortcut: shortcut, id: .snippets, ref: &snippetsHotkeyRef)
        }
    }
    
    /// Call this method before releasing the service to clean up
    func cleanup() {
        stop()
    }
    
    // MARK: - Private Methods
    
    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                return HotkeyService.handleHotKeyEvent(event)
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
        
        if status != noErr {
            print("HotkeyService: Failed to install event handler: \(status)")
        }
    }
    
    private func removeEventHandler() {
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }
    
    private func registerHotkey(shortcut: KeyboardShortcut, id: HotkeyIdentifier, ref: inout EventHotKeyRef?) {
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C4950), id: id.rawValue) // 'CLIP'
        
        // Convert our modifier flags to Carbon modifier flags
        let carbonModifiers = carbonModifierFlags(from: shortcut.modifiers)
        
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        
        if status != noErr {
            print("HotkeyService: Failed to register hotkey \(id): \(status)")
        }
    }
    
    private func unregisterAllHotkeys() {
        if let ref = historyHotkeyRef {
            UnregisterEventHotKey(ref)
            historyHotkeyRef = nil
        }
        if let ref = snippetsHotkeyRef {
            UnregisterEventHotKey(ref)
            snippetsHotkeyRef = nil
        }
    }
    
    /// Convert our modifier flags to Carbon modifier flags
    private func carbonModifierFlags(from modifiers: UInt32) -> UInt32 {
        var carbonMods: UInt32 = 0
        
        if modifiers & KeyboardShortcut.Modifiers.command != 0 {
            carbonMods |= UInt32(cmdKey)
        }
        if modifiers & KeyboardShortcut.Modifiers.shift != 0 {
            carbonMods |= UInt32(shiftKey)
        }
        if modifiers & KeyboardShortcut.Modifiers.option != 0 {
            carbonMods |= UInt32(optionKey)
        }
        if modifiers & KeyboardShortcut.Modifiers.control != 0 {
            carbonMods |= UInt32(controlKey)
        }
        
        return carbonMods
    }
    
    /// Static handler for Carbon events
    private static func handleHotKeyEvent(_ event: EventRef?) -> OSStatus {
        guard let event = event else { return OSStatus(eventNotHandledErr) }
        
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            UInt32(kEventParamDirectObject),
            UInt32(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        
        guard status == noErr else { return status }
        
        // Dispatch to main actor
        Task { @MainActor in
            guard let instance = HotkeyService.sharedInstance else { return }
            
            switch hotKeyID.id {
            case HotkeyIdentifier.history.rawValue:
                instance.historyCallback?()
            case HotkeyIdentifier.snippets.rawValue:
                instance.snippetsCallback?()
            default:
                break
            }
        }
        
        return noErr
    }
}
