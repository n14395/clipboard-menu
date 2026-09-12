import Foundation
import SwiftUI
import ServiceManagement

enum SnippetsMenuMode: String, CaseIterable {
    case separate = "separate"
    case integrated = "integrated"
    
    var displayName: String {
        switch self {
        case .separate: return "Separate"
        case .integrated: return "Integrated"
        }
    }
}

@MainActor
class PreferencesService: ObservableObject {
    private let defaults: UserDefaults

    // Keys
    private enum Keys {
        static let maxHistoryItems = "maxHistoryItems"
        static let maxStorageMB = "maxStorageMB"
        static let maxItemSizeMB = "maxItemSizeMB"

        static let launchAtLogin = "launchAtLogin"
        static let historyShortcutData = "historyShortcutData"
        static let snippetsShortcutData = "snippetsShortcutData"
        static let snippetsMenuMode = "snippetsMenuMode"
        static let previewSize = "previewSize"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let fileSystemBookmark = "fileSystemBookmark"
        static let rootFileSystemBookmark = "rootFileSystemBookmark"
        static let globalShortcutsEnabled = "globalShortcutsEnabled"
        static let compactHistoryView = "compactHistoryView"
        static let compactSnippetsView = "compactSnippetsView"
    }

    // Published properties
    @Published var maxHistoryItems: Int {
        didSet { defaults.set(maxHistoryItems, forKey: Keys.maxHistoryItems) }
    }

    @Published var maxStorageMB: Int {
        didSet { defaults.set(maxStorageMB, forKey: Keys.maxStorageMB) }
    }

    @Published var maxItemSizeMB: Int {
        didSet { defaults.set(maxItemSizeMB, forKey: Keys.maxItemSizeMB) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            updateLaunchAtLogin()
        }
    }

    /// Display string for history shortcut (computed from structured data)
    var historyShortcutDisplay: String {
        historyShortcutData.displayString
    }
    
    /// Display string for snippets shortcut (computed from structured data)
    var snippetsShortcutDisplay: String {
        snippetsShortcutData.displayString
    }
    
    /// Structured keyboard shortcut for clipboard history
    @Published var historyShortcutData: KeyboardShortcut {
        didSet {
            if let data = historyShortcutData.toData() {
                defaults.set(data, forKey: Keys.historyShortcutData)
            }
        }
    }
    
    /// Structured keyboard shortcut for snippets
    @Published var snippetsShortcutData: KeyboardShortcut {
        didSet {
            if let data = snippetsShortcutData.toData() {
                defaults.set(data, forKey: Keys.snippetsShortcutData)
            }
        }
    }

    @Published var snippetsMenuMode: SnippetsMenuMode {
        didSet { defaults.set(snippetsMenuMode.rawValue, forKey: Keys.snippetsMenuMode) }
    }
    
    @Published var previewSize: Int {
        didSet { defaults.set(previewSize, forKey: Keys.previewSize) }
    }
    
    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }
    
    /// Whether global keyboard shortcuts are enabled (requires accessibility permission)
    @Published var globalShortcutsEnabled: Bool {
        didSet { defaults.set(globalShortcutsEnabled, forKey: Keys.globalShortcutsEnabled) }
    }
    
    /// Compact view mode for clipboard history menu
    @Published var compactHistoryView: Bool {
        didSet { defaults.set(compactHistoryView, forKey: Keys.compactHistoryView) }
    }
    
    /// Compact view mode for snippets menu
    @Published var compactSnippetsView: Bool {
        didSet { defaults.set(compactSnippetsView, forKey: Keys.compactSnippetsView) }
    }
    
    /// Security-scoped bookmark for home directory access
    var fileSystemBookmark: Data? {
        get { defaults.data(forKey: Keys.fileSystemBookmark) }
        set { defaults.set(newValue, forKey: Keys.fileSystemBookmark) }
    }
    
    /// Security-scoped bookmark for root file system access (escalated permissions)
    var rootFileSystemBookmark: Data? {
        get { defaults.data(forKey: Keys.rootFileSystemBookmark) }
        set { defaults.set(newValue, forKey: Keys.rootFileSystemBookmark) }
    }

    // Computed property for storage in bytes
    var maxStorageBytes: Int64 {
        Int64(maxStorageMB) * 1024 * 1024
    }
    
    // Computed property for max item size in bytes
    var maxItemSizeBytes: Int64 {
        Int64(maxItemSizeMB) * 1024 * 1024
    }

    /// Default initializer using standard UserDefaults
    convenience init() {
        self.init(defaults: .standard)
    }
    
    /// Initializer for testing with custom UserDefaults
    /// - Parameter defaults: The UserDefaults instance to use
    init(defaults: UserDefaults) {
        self.defaults = defaults
        // Load from UserDefaults with defaults
        self.maxHistoryItems = defaults.object(forKey: Keys.maxHistoryItems) as? Int ?? 25
        self.maxStorageMB = defaults.object(forKey: Keys.maxStorageMB) as? Int ?? 10240 // 10GB default
        self.maxItemSizeMB = defaults.object(forKey: Keys.maxItemSizeMB) as? Int ?? 1024 // 1GB default
        self.launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        
        // Load structured shortcuts (with fallback to defaults)
        if let historyData = defaults.data(forKey: Keys.historyShortcutData),
           let shortcut = KeyboardShortcut.fromData(historyData) {
            self.historyShortcutData = shortcut
        } else {
            self.historyShortcutData = .defaultHistory
        }
        
        if let snippetsData = defaults.data(forKey: Keys.snippetsShortcutData),
           let shortcut = KeyboardShortcut.fromData(snippetsData) {
            self.snippetsShortcutData = shortcut
        } else {
            self.snippetsShortcutData = .defaultSnippets
        }
        
        if let modeString = defaults.string(forKey: Keys.snippetsMenuMode),
           let mode = SnippetsMenuMode(rawValue: modeString) {
            self.snippetsMenuMode = mode
        } else {
            self.snippetsMenuMode = .separate
        }
        
        self.previewSize = defaults.object(forKey: Keys.previewSize) as? Int ?? 500
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        self.globalShortcutsEnabled = defaults.bool(forKey: Keys.globalShortcutsEnabled) // Default false
        self.compactHistoryView = defaults.bool(forKey: Keys.compactHistoryView) // Default false
        self.compactSnippetsView = defaults.bool(forKey: Keys.compactSnippetsView) // Default false
    }

    private func updateLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update launch at login: \(error)")
        }
    }

    /// Resets all settings to defaults except storage limits (to avoid deleting history items)
    func resetToDefaults() {
        launchAtLogin = false
        historyShortcutData = .defaultHistory
        snippetsShortcutData = .defaultSnippets
        snippetsMenuMode = .separate
        previewSize = 500
        globalShortcutsEnabled = false
        compactHistoryView = false
        compactSnippetsView = false
        // Note: Storage settings (maxHistoryItems, maxStorageMB, maxItemSizeMB) are NOT reset
        // to avoid triggering deletion of existing history items
    }

}
