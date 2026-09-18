import SwiftUI
import AppKit
import Combine

@main
struct ClipboardMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView()
                .environmentObject(appDelegate.preferencesService)
                .environmentObject(appDelegate.storageService)
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var menuBarController: MenuBarController!
    var clipboardMonitor: ClipboardMonitor!
    var hotkeyService: HotkeyService!
    var onboardingWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    let storageService = StorageService()
    let thumbnailService = ThumbnailService()
    let preferencesService = PreferencesService()
    let searchService = SearchService()
    let bookmarkService = BookmarkService()

    override init() {
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - menu bar only app
        NSApp.setActivationPolicy(.accessory)
        #if SPARKLE
        SparkleUpdater.start()
        #endif

        // Prevent macOS from auto-terminating or suddenly killing the app while idle
        ProcessInfo.processInfo.disableAutomaticTermination("Clipboard monitoring must remain active")
        ProcessInfo.processInfo.disableSuddenTermination()

        // Handle sleep/wake to restart clipboard monitoring cleanly
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)

        // Initialize storage
        do {
            try storageService.initialize()
            // Run cleanup at startup to enforce any limits that may have changed while app was closed
            storageService.runCleanup(
                maxItems: preferencesService.maxHistoryItems,
                maxStorageBytes: preferencesService.maxStorageBytes
            )
        } catch {
            print("Failed to initialize storage: \(error)")
        }
        
        // Restore file system access from stored bookmark
        _ = FilePermissionService.shared.restoreFileSystemAccess(preferencesService: preferencesService)

        // Start clipboard monitoring
        clipboardMonitor = ClipboardMonitor(
            storageService: storageService,
            thumbnailService: thumbnailService,
            preferencesService: preferencesService
        )
        clipboardMonitor.startMonitoring()

        // Set up menu bar (pass clipboardMonitor so it can signal when copying from history)
        menuBarController = MenuBarController(
            storageService: storageService,
            thumbnailService: thumbnailService,
            preferencesService: preferencesService,
            searchService: searchService,
            clipboardMonitor: clipboardMonitor,
            bookmarkService: bookmarkService
        )
        
        // Set up global keyboard shortcuts
        setupHotkeyService()
        
        // Show onboarding if this is the first launch
        if !preferencesService.hasCompletedOnboarding {
            showOnboarding()
        }
    }
    
    private func setupHotkeyService() {
        hotkeyService = HotkeyService(
            historyShortcut: preferencesService.historyShortcutData,
            snippetsShortcut: preferencesService.snippetsShortcutData
        )
        
        // Only start hotkey monitoring if enabled in preferences
        if preferencesService.globalShortcutsEnabled {
            startHotkeyMonitoring()
        }
        
        // Observe shortcut changes from preferences
        preferencesService.$historyShortcutData
            .dropFirst() // Skip initial value
            .sink { [weak self] shortcut in
                self?.hotkeyService.updateHistoryShortcut(shortcut)
            }
            .store(in: &cancellables)
        
        preferencesService.$snippetsShortcutData
            .dropFirst() // Skip initial value
            .sink { [weak self] shortcut in
                self?.hotkeyService.updateSnippetsShortcut(shortcut)
            }
            .store(in: &cancellables)
        
        // Observe snippets menu mode changes to enable/disable snippets shortcut
        preferencesService.$snippetsMenuMode
            .dropFirst() // Skip initial value
            .sink { [weak self] mode in
                self?.hotkeyService.setSnippetsShortcutEnabled(mode != .integrated)
            }
            .store(in: &cancellables)
        
        // Observe global shortcuts enabled/disabled changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(globalShortcutsEnabledChanged),
            name: NSNotification.Name("GlobalShortcutsEnabledChanged"),
            object: nil
        )
        
        // Observe storage limit changes and run cleanup with debounce
        preferencesService.$maxHistoryItems
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] maxItems in
                guard let self = self else { return }
                self.storageService.runCleanup(
                    maxItems: maxItems,
                    maxStorageBytes: self.preferencesService.maxStorageBytes
                )
            }
            .store(in: &cancellables)
        
        preferencesService.$maxStorageMB
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.storageService.runCleanup(
                    maxItems: self.preferencesService.maxHistoryItems,
                    maxStorageBytes: self.preferencesService.maxStorageBytes
                )
            }
            .store(in: &cancellables)
    }
    
    private func startHotkeyMonitoring() {
        // Snippets shortcut is disabled in integrated mode
        let snippetsEnabled = preferencesService.snippetsMenuMode != .integrated
        
        hotkeyService.start(
            onHistory: { [weak self] in
                self?.menuBarController.toggleHistoryPopover()
            },
            onSnippets: { [weak self] in
                self?.menuBarController.toggleSnippetsPopover()
            },
            snippetsEnabled: snippetsEnabled
        )
    }
    
    @objc private func globalShortcutsEnabledChanged() {
        if preferencesService.globalShortcutsEnabled {
            // Start hotkey monitoring
            startHotkeyMonitoring()
        } else {
            // Stop hotkey monitoring
            hotkeyService.stop()
        }
    }
    
    private func showOnboarding() {
        // Show dock icon temporarily for onboarding
        NSApp.setActivationPolicy(.regular)
        
        let onboardingView = OnboardingView(preferencesService: preferencesService) { [weak self] in
            Task { @MainActor in
                self?.dismissOnboarding()
            }
        }
        
        let hostingController = NSHostingController(rootView: onboardingView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to ClipboardMenu"
        window.styleMask = [NSWindow.StyleMask.titled, NSWindow.StyleMask.closable]
        window.center()
        window.isReleasedWhenClosed = false
        
        // Handle window close button
        window.delegate = self
        
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func dismissOnboarding() {
        onboardingWindow?.close()
        onboardingWindow = nil
        
        // Hide dock icon again - back to menu bar only
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func systemWillSleep(_ notification: Notification) {
        clipboardMonitor?.stopMonitoring()
    }

    @objc private func systemDidWake(_ notification: Notification) {
        clipboardMonitor?.startMonitoring()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let alert = NSAlert()
        alert.messageText = "Quit ClipboardMenu?"
        alert.informativeText = "Clipboard monitoring will stop and you won't be able to access your clipboard history until you reopen the app."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            return .terminateNow
        } else {
            return .terminateCancel
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        clipboardMonitor?.stopMonitoring()
        hotkeyService?.cleanup()
        FilePermissionService.shared.stopAccessingSecurityScopedResource()
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === onboardingWindow else {
            return
        }
        
        // Mark onboarding as complete when user closes the window
        preferencesService.hasCompletedOnboarding = true
        
        // Reset dock policy (dismissOnboarding will be called, but window is already closing)
        DispatchQueue.main.async { [weak self] in
            self?.onboardingWindow = nil
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
