// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import AppKit
import Combine

@MainActor
class MenuBarController: NSObject, ObservableObject {
    private var historyStatusItem: NSStatusItem?
    private var snippetsStatusItem: NSStatusItem?
    private var historyPopover: NSPopover?
    private var snippetsPopover: NSPopover?
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    let storageService: StorageService
    let thumbnailService: ThumbnailService
    let preferencesService: PreferencesService
    let searchService: SearchService
    let clipboardMonitor: ClipboardMonitor
    let bookmarkService: BookmarkService
    let cloudDownloadService = CloudDownloadService()

    @Published var clipboardItems: [ClipboardItem] = []
    @Published var snippets: [Snippet] = []
    @Published var historyMenuOpenCount: Int = 0
    @Published var snippetsMenuOpenCount: Int = 0
    
    /// Cache for cloud download status of clipboard items (computed async to avoid blocking UI)
    @Published var cloudStatusCache: [UUID: Bool] = [:]
    /// Whether cloud status is currently being computed
    @Published var isComputingCloudStatus: Bool = false
    
    // Menu sizing constants
    private let menuWidth: CGFloat = 350
    private let menuMinHeight: CGFloat = 250
    private let headerHeight: CGFloat = 120 // Approximate height of header, search, filters
    
    // Row heights based on compact mode
    // Compact: icon (22) + padding (4*2) + spacing = ~32px
    // Non-compact: icon (32) + padding (8*2) + two lines of text = ~52px
    private var historyItemRowHeight: CGFloat {
        preferencesService.compactHistoryView ? 32 : 52
    }
    
    private var snippetsItemRowHeight: CGFloat {
        preferencesService.compactSnippetsView ? 32 : 52
    }
    
    /// Calculate the optimal menu height based on item count and screen size
    var historyMenuHeight: CGFloat {
        guard let screen = NSScreen.main else { return 450 }
        let maxHeight = screen.visibleFrame.height * 2 / 3
        
        var contentHeight = headerHeight
        
        // Add height for history items
        contentHeight += CGFloat(clipboardItems.count) * historyItemRowHeight
        
        // Add height for integrated snippets
        if preferencesService.snippetsMenuMode == .integrated {
            contentHeight += CGFloat(snippets.count) * snippetsItemRowHeight
            if !snippets.isEmpty {
                contentHeight += 30 // For the "Snippets" section header
            }
            if !clipboardItems.isEmpty && !snippets.isEmpty {
                contentHeight += 30 // For the "History" section header
            }
        }
        
        return min(max(contentHeight, menuMinHeight), maxHeight)
    }
    
    /// Calculate the optimal snippets menu height based on item count and screen size
    var snippetsMenuHeight: CGFloat {
        guard let screen = NSScreen.main else { return 450 }
        let maxHeight = screen.visibleFrame.height * 2 / 3
        
        let contentHeight = headerHeight + (CGFloat(snippets.count) * snippetsItemRowHeight)
        return min(max(contentHeight, menuMinHeight), maxHeight)
    }

    init(
        storageService: StorageService,
        thumbnailService: ThumbnailService,
        preferencesService: PreferencesService,
        searchService: SearchService,
        clipboardMonitor: ClipboardMonitor,
        bookmarkService: BookmarkService
    ) {
        self.storageService = storageService
        self.thumbnailService = thumbnailService
        self.preferencesService = preferencesService
        self.searchService = searchService
        self.clipboardMonitor = clipboardMonitor
        self.bookmarkService = bookmarkService
        super.init()
        
        // Configure cloud download service with storage service reference
        cloudDownloadService.configure(storageService: storageService)
        cloudDownloadService.onDownloadComplete = { [weak self] in
            print("[onDownloadComplete] Calling loadData")
            self?.loadData()
            print("[onDownloadComplete] loadData finished")
        }
        cloudDownloadService.onProgressUpdate = { [weak self] in
            self?.refreshData()
        }
        
        // Clean up any incomplete downloads from previous session
        if let count = try? storageService.deleteIncompleteDownloads(), count > 0 {
            print("Cleaned up \(count) incomplete snippet download(s)")
        }

        setupHistoryStatusItem()
        updateSnippetsStatusItemVisibility()
        setupEventMonitor()
        loadData()

        // Observe storage changes via NotificationCenter (legacy)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadData),
            name: NSNotification.Name("ClipboardDataChanged"),
            object: nil
        )
        
        // Observe storage changes via Combine (for real-time updates like cloud downloads)
        // Debounce to avoid rapid reload cycles
        storageService.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshData()
            }
            .store(in: &cancellables)
        
        // Observe snippets menu mode changes
        preferencesService.$snippetsMenuMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateSnippetsStatusItemVisibility()
            }
            .store(in: &cancellables)
        
        // Forward cloudDownloadService changes to trigger view updates
        // This is needed because SwiftUI doesn't automatically observe nested ObservableObjects
        cloudDownloadService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Setup

    private func setupHistoryStatusItem() {
        historyStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = historyStatusItem?.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard History")
            button.action = #selector(toggleHistoryPopover)
            button.target = self
        }

        historyPopover = NSPopover()
        historyPopover?.contentSize = NSSize(width: menuWidth, height: historyMenuHeight)
        historyPopover?.behavior = .transient
        historyPopover?.animates = true

        let historyView = HistoryMenuView(controller: self)
        historyPopover?.contentViewController = NSHostingController(rootView: historyView)
    }

    private func setupSnippetsStatusItem() {
        snippetsStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = snippetsStatusItem?.button {
            button.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: "Snippets")
            button.action = #selector(toggleSnippetsPopover)
            button.target = self
        }

        snippetsPopover = NSPopover()
        snippetsPopover?.contentSize = NSSize(width: menuWidth, height: snippetsMenuHeight)
        snippetsPopover?.behavior = .transient
        snippetsPopover?.animates = true

        let snippetsView = SnippetsMenuView(controller: self)
        snippetsPopover?.contentViewController = NSHostingController(rootView: snippetsView)
    }
    
    private func updateSnippetsStatusItemVisibility() {
        switch preferencesService.snippetsMenuMode {
        case .separate:
            // Show separate snippets status item if not already visible
            if snippetsStatusItem == nil {
                setupSnippetsStatusItem()
            }
        case .integrated:
            // Hide snippets status item - remove from status bar
            if let item = snippetsStatusItem {
                NSStatusBar.system.removeStatusItem(item)
                snippetsStatusItem = nil
                snippetsPopover = nil
            }
        }
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopovers()
        }
    }

    // MARK: - Actions

    @objc func toggleHistoryPopover() {
        guard let button = historyStatusItem?.button else { return }

        if let popover = historyPopover {
            if popover.isShown {
                popover.performClose(nil)
                PreviewWindowManager.shared.hidePreview()
            } else {
                snippetsPopover?.performClose(nil)
                PreviewWindowManager.shared.hidePreview()
                // Check clipboard for new content before showing
                clipboardMonitor.checkClipboardNow()
                loadData()
                // Update popover size based on current content
                popover.contentSize = NSSize(width: menuWidth, height: historyMenuHeight)
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                // Signal to reset scroll position
                historyMenuOpenCount += 1
                // Activate the app to bring popover to front
                NSApp.activate(ignoringOtherApps: true)
                
                // Run expensive operations async AFTER showing the menu for better responsiveness
                computeCloudStatusAsync()
                cleanupInvalidFileReferencesAsync()
            }
        }
    }

    @objc func toggleSnippetsPopover() {
        // For integrated mode, toggle history popover instead (which contains snippets)
        if preferencesService.snippetsMenuMode == .integrated {
            toggleHistoryPopover()
            return
        }
        
        guard let button = snippetsStatusItem?.button else { return }

        if let popover = snippetsPopover {
            if popover.isShown {
                popover.performClose(nil)
                PreviewWindowManager.shared.hidePreview()
            } else {
                historyPopover?.performClose(nil)
                PreviewWindowManager.shared.hidePreview()
                loadData()
                // Update popover size based on current content
                popover.contentSize = NSSize(width: menuWidth, height: snippetsMenuHeight)
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                // Signal to reset scroll position
                snippetsMenuOpenCount += 1
                // Activate the app to bring popover to front
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    

    private func closePopovers() {
        historyPopover?.performClose(nil)
        snippetsPopover?.performClose(nil)
        PreviewWindowManager.shared.hidePreview()
    }

    // MARK: - Popover Window Access
    
    var historyPopoverFrame: NSRect? {
        guard let popover = historyPopover, popover.isShown else { return nil }
        return popover.contentViewController?.view.window?.frame
    }
    
    var snippetsPopoverFrame: NSRect? {
        guard let popover = snippetsPopover, popover.isShown else { return nil }
        return popover.contentViewController?.view.window?.frame
    }

    // MARK: - Data

    @objc private func reloadData() {
        loadData()
    }

    func loadData() {
        do {
            // NOTE: Invalid file reference cleanup moved to async (cleanupInvalidFileReferencesAsync)
            // to avoid blocking the UI when opening the menu
            
            clipboardItems = try storageService.fetchClipboardItems(limit: preferencesService.maxHistoryItems)
            snippets = try storageService.fetchSnippets()
            print("[loadData] Loaded \(snippets.count) snippets, first isDownloading: \(snippets.first?.isDownloading ?? false)")
            objectWillChange.send()
        } catch {
            print("Failed to load data: \(error)")
        }
    }
    
    /// Refresh data without cleanup (used for reactive updates to avoid triggering loops)
    private func refreshData() {
        do {
            clipboardItems = try storageService.fetchClipboardItems(limit: preferencesService.maxHistoryItems)
            snippets = try storageService.fetchSnippets()
            objectWillChange.send()
        } catch {
            print("Failed to refresh data: \(error)")
        }
    }
    
    // MARK: - Async Background Operations
    
    /// Runs invalid file reference cleanup asynchronously after the menu is displayed
    /// This avoids blocking the UI while performing file system checks
    private func cleanupInvalidFileReferencesAsync() {
        let storageService = self.storageService
        Task.detached(priority: .utility) {
            do {
                let removedCount = try await storageService.removeInvalidFileReferencesAsync()
                if removedCount > 0 {
                    // Refresh data on main thread if items were removed
                    await MainActor.run { [weak self] in
                        self?.refreshData()
                    }
                }
            } catch {
                print("Failed to cleanup invalid file references: \(error)")
            }
        }
    }
    
    /// Computes cloud download status for all file reference items asynchronously
    /// Results are cached in cloudStatusCache and the view updates reactively
    func computeCloudStatusAsync() {
        // Mark as computing
        isComputingCloudStatus = true
        
        // Capture current items before going async
        let items = clipboardItems
        
        Task {
            // Perform file system checks off the main actor
            let cache = await Task.detached(priority: .userInitiated) {
                var result: [UUID: Bool] = [:]
                for item in items {
                    // Only check file references - others are always available
                    if item.isFileReference {
                        // Show cloud icon for any cloud file reference (matches detection used when storing)
                        let isCloudFile = item.isCloudFile
                        result[item.id] = isCloudFile
                    }
                }
                return result
            }.value
            
            // Update state on main actor (we're already on MainActor due to class annotation)
            self.cloudStatusCache = cache
            self.isComputingCloudStatus = false
            print("[CloudStatus] Cache updated with \(cache.filter { $0.value }.count) cloud files out of \(cache.count) file references")
        }
    }

    // MARK: - Clipboard Operations
    
    /// Extract the original filename from a storage path
    /// Storage format for file stacks: {UUID}_{index}_{originalFilename}
    /// Storage format for single files with name: {UUID}_{originalFilename}
    /// Storage format for single files without name: {UUID}.{ext}
    /// Snippet storage format: snippet_{UUID}_{index}_{originalFilename} or snippet_{UUID}.{ext}
    /// For file references (original paths), returns the filename directly
    private func extractOriginalFilename(from storagePath: String) -> String? {
        let url = URL(fileURLWithPath: storagePath)
        let filename = url.lastPathComponent
        
        // Check if this is a snippet file stack format: snippet_{UUID}_{index}_{originalFilename}
        let snippetFileStackPattern = "^snippet_[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}_\\d+_"
        if let regex = try? NSRegularExpression(pattern: snippetFileStackPattern, options: .caseInsensitive) {
            let range = NSRange(filename.startIndex..., in: filename)
            if let match = regex.firstMatch(in: filename, range: range) {
                let matchEnd = Range(match.range, in: filename)!.upperBound
                return String(filename[matchEnd...])
            }
        }
        
        // Check if this is a snippet single file format with name: snippet_{UUID}_{originalFilename}
        let snippetSingleWithNamePattern = "^snippet_[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}_"
        if let regex = try? NSRegularExpression(pattern: snippetSingleWithNamePattern, options: .caseInsensitive) {
            let range = NSRange(filename.startIndex..., in: filename)
            if let match = regex.firstMatch(in: filename, range: range) {
                let matchEnd = Range(match.range, in: filename)!.upperBound
                let remainder = String(filename[matchEnd...])
                // Check it's not a file stack format (which has digit_ after UUID_)
                if !remainder.isEmpty && !remainder.first!.isNumber {
                    return remainder
                }
            }
        }
        
        // Check if this is an old snippet single file format: snippet_{UUID}.{ext}
        let snippetSinglePattern = "^snippet_[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}\\.[a-zA-Z0-9]+$"
        if let regex = try? NSRegularExpression(pattern: snippetSinglePattern, options: .caseInsensitive) {
            let range = NSRange(filename.startIndex..., in: filename)
            if regex.firstMatch(in: filename, range: range) != nil {
                // This is a snippet UUID-only filename, return nil to use default
                return nil
            }
        }
        
        // Check if this is a file stack format: {UUID}_{index}_{originalFilename}
        // UUID is 36 chars (8-4-4-4-12 with hyphens)
        let fileStackPattern = "^[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}_\\d+_"
        if let regex = try? NSRegularExpression(pattern: fileStackPattern, options: .caseInsensitive) {
            let range = NSRange(filename.startIndex..., in: filename)
            if let match = regex.firstMatch(in: filename, range: range) {
                let matchEnd = Range(match.range, in: filename)!.upperBound
                return String(filename[matchEnd...])
            }
        }
        
        // Check if this is a single file format with original name: {UUID}_{originalFilename}
        let singleFilePattern = "^[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}_"
        if let regex = try? NSRegularExpression(pattern: singleFilePattern, options: .caseInsensitive) {
            let range = NSRange(filename.startIndex..., in: filename)
            if let match = regex.firstMatch(in: filename, range: range) {
                let matchEnd = Range(match.range, in: filename)!.upperBound
                let remainder = String(filename[matchEnd...])
                // Make sure it's not just an extension (i.e., has more than just ".ext")
                if remainder.contains(".") || !remainder.isEmpty {
                    return remainder
                }
            }
        }
        
        // Check if this is a UUID-only format: {UUID}.{ext}
        // If so, return nil to trigger default filename generation
        let uuidOnlyPattern = "^[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}\\.[a-zA-Z0-9]+$"
        if let regex = try? NSRegularExpression(pattern: uuidOnlyPattern, options: .caseInsensitive) {
            let range = NSRange(filename.startIndex..., in: filename)
            if regex.firstMatch(in: filename, range: range) != nil {
                // This is a UUID-only filename, return nil to use default
                return nil
            }
        }
        
        // Not a storage format - this is likely a file reference with original path
        // Use the filename directly
        return filename
    }
    
    /// Generate a default filename based on file extension
    private func defaultFilename(for ext: String) -> String {
        if ext.isEmpty {
            return "file"
        }
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "webp"]
        let videoExtensions = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]
        let lowercaseExt = ext.lowercased()
        
        if imageExtensions.contains(lowercaseExt) {
            return "image.\(ext)"
        } else if videoExtensions.contains(lowercaseExt) {
            return "video.\(ext)"
        } else {
            return "file.\(ext)"
        }
    }
    
    /// Create a temporary hard link with the original filename for clipboard operations
    /// Returns the URL to use for the clipboard (either hard link or original)
    private func createClipboardURL(for storagePath: String, preferredName: String?) -> URL {
        let originalURL = URL(fileURLWithPath: storagePath)
        
        // Determine the filename to use
        let targetFilename: String
        if let name = preferredName, !name.isEmpty {
            targetFilename = name
        } else if let extracted = extractOriginalFilename(from: storagePath) {
            targetFilename = extracted
        } else {
            // No original filename available, use a default based on file type
            targetFilename = defaultFilename(for: originalURL.pathExtension)
        }
        
        // Create a temporary directory for this paste operation
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardMenu")
            .appendingPathComponent(UUID().uuidString)
        
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let linkURL = tempDir.appendingPathComponent(targetFilename)
            // Use hard link so the file appears as a real file, not a link
            try FileManager.default.linkItem(at: originalURL, to: linkURL)
            return linkURL
        } catch {
            print("Failed to create hard link: \(error)")
            return originalURL
        }
    }
    
    /// Create clipboard URLs for multiple files (file stacks)
    private func createClipboardURLs(for storagePaths: [String]) -> [URL] {
        // Create a shared temp directory for this paste operation
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardMenu")
            .appendingPathComponent(UUID().uuidString)
        
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            print("Failed to create temp directory: \(error)")
            // Fallback: create individual temp directories for each file
            return storagePaths.enumerated().map { index, storagePath in
                createClipboardURL(for: storagePath, preferredName: nil)
            }
        }
        
        return storagePaths.enumerated().map { index, storagePath -> URL in
            let originalURL = URL(fileURLWithPath: storagePath)
            
            // Determine the filename to use
            let targetFilename: String
            if let originalFilename = extractOriginalFilename(from: storagePath) {
                targetFilename = originalFilename
            } else {
                // No original filename, generate a default with index to avoid collisions
                let ext = originalURL.pathExtension
                let baseName = defaultFilename(for: ext)
                let nameWithoutExt = (baseName as NSString).deletingPathExtension
                targetFilename = ext.isEmpty ? "\(nameWithoutExt)_\(index + 1)" : "\(nameWithoutExt)_\(index + 1).\(ext)"
            }
            
            let linkURL = tempDir.appendingPathComponent(targetFilename)
            do {
                // Use hard link so the file appears as a real file, not a link
                try FileManager.default.linkItem(at: originalURL, to: linkURL)
                return linkURL
            } catch {
                print("Failed to create hard link for \(targetFilename): \(error)")
                // Fallback to individual temp directory
                return createClipboardURL(for: storagePath, preferredName: nil)
            }
        }
    }

    /// Show an alert asking the user to grant broader file system access for files outside their home directory
    /// Returns true if the user granted access, false if they cancelled
    private func requestRootAccessWithAlert() -> Bool {
        let alert = NSAlert()
        alert.messageText = "File Access Required"
        alert.informativeText = "This file is located outside your home folder. To access it, ClipboardMenu needs broader file system permissions.\n\nWould you like to grant access now?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Grant Access")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            return FilePermissionService.shared.requestRootAccess(preferencesService: preferencesService)
        }
        
        return false
    }
    
    /// Check if any paths need root access and request it if necessary
    /// Returns true if we have access (either already had it or user granted it), false if user cancelled
    private func ensureRootAccessIfNeeded(for paths: [String]) -> Bool {
        let pathsNeedingRoot = paths.filter { FilePermissionService.shared.needsRootAccess(for: $0) }
        
        if pathsNeedingRoot.isEmpty {
            return true  // No root access needed
        }
        
        // We need root access - ask the user
        return requestRootAccessWithAlert()
    }
    
    /// Try to acquire file access using security-scoped bookmarks, falling back to user permission request
    /// Returns URLs that have been accessed (may need to stop accessing later) and whether access was granted
    private func acquireFileAccess(
        for item: ClipboardItem
    ) -> (accessedURLs: [URL], granted: Bool) {
        var accessedURLs: [URL] = []
        
        // File stack with bookmarks
        if let paths = item.mediaPaths, !paths.isEmpty {
            // Try bookmarks first
            if let bookmarks = item.bookmarkDatas, bookmarks.count == paths.count {
                var allResolved = true
                for bookmark in bookmarks {
                    if let (url, _) = bookmarkService.resolveBookmark(bookmark) {
                        if bookmarkService.startAccessing(url) {
                            accessedURLs.append(url)
                        } else {
                            allResolved = false
                            break
                        }
                    } else {
                        allResolved = false
                        break
                    }
                }
                
                if allResolved {
                    return (accessedURLs, true)
                }
                
                // Bookmarks failed, stop any we started and fall back
                accessedURLs.forEach { bookmarkService.stopAccessing($0) }
                accessedURLs.removeAll()
            }
            
            // Fall back to FilePermissionService
            let inaccessiblePaths = paths.filter { !FilePermissionService.shared.canRead(path: $0) }
            if !inaccessiblePaths.isEmpty {
                // Check if we need root access for any of these paths
                if !ensureRootAccessIfNeeded(for: inaccessiblePaths) {
                    return ([], false)
                }
                
                // Now try to get folder access (may still need user to select folder even with root access)
                if !FilePermissionService.shared.requestFolderAccess(
                    for: inaccessiblePaths,
                    message: "ClipboardMenu needs access to these files to copy them to the clipboard."
                ) {
                    return ([], false)
                }
            }
            return ([], true)
        }
        
        // Single file with bookmark
        if let mediaPath = item.mediaPath, item.contentType != .text && item.contentType != .richText {
            // Try bookmark first
            if let bookmark = item.bookmarkData {
                if let (url, _) = bookmarkService.resolveBookmark(bookmark) {
                    if bookmarkService.startAccessing(url) {
                        return ([url], true)
                    }
                }
                // Bookmark failed, fall back
            }
            
            // Fall back to FilePermissionService
            if !FilePermissionService.shared.canRead(path: mediaPath) {
                // Check if we need root access for this path
                if !ensureRootAccessIfNeeded(for: [mediaPath]) {
                    return ([], false)
                }
                
                if !FilePermissionService.shared.requestAccess(
                    to: mediaPath,
                    message: "ClipboardMenu needs access to this file to copy it to the clipboard."
                ) {
                    return ([], false)
                }
            }
            return ([], true)
        }
        
        // Text/richText - no file access needed
        return ([], true)
    }
    
    /// Release file access for URLs that were accessed via security-scoped bookmarks
    private func releaseFileAccess(_ urls: [URL]) {
        for url in urls {
            bookmarkService.stopAccessing(url)
        }
    }
    
    /// Try to acquire file access using security-scoped bookmarks for snippets, falling back to user permission request
    /// Returns URLs that have been accessed (may need to stop accessing later) and whether access was granted
    private func acquireFileAccess(
        for snippet: Snippet
    ) -> (accessedURLs: [URL], granted: Bool) {
        var accessedURLs: [URL] = []
        
        // File stack with bookmarks
        if let paths = snippet.mediaPaths, !paths.isEmpty {
            // Try bookmarks first
            if let bookmarks = snippet.bookmarkDatas, bookmarks.count == paths.count {
                var allResolved = true
                for bookmark in bookmarks {
                    if let (url, _) = bookmarkService.resolveBookmark(bookmark) {
                        if bookmarkService.startAccessing(url) {
                            accessedURLs.append(url)
                        } else {
                            allResolved = false
                            break
                        }
                    } else {
                        allResolved = false
                        break
                    }
                }
                
                if allResolved {
                    return (accessedURLs, true)
                }
                
                // Bookmarks failed, stop any we started and fall back
                accessedURLs.forEach { bookmarkService.stopAccessing($0) }
                accessedURLs.removeAll()
            }
            
            // Fall back to FilePermissionService
            let inaccessiblePaths = paths.filter { !FilePermissionService.shared.canRead(path: $0) }
            if !inaccessiblePaths.isEmpty {
                // Check if we need root access for any of these paths
                if !ensureRootAccessIfNeeded(for: inaccessiblePaths) {
                    return ([], false)
                }
                
                if !FilePermissionService.shared.requestFolderAccess(
                    for: inaccessiblePaths,
                    message: "ClipboardMenu needs access to these files to copy them to the clipboard."
                ) {
                    return ([], false)
                }
            }
            return ([], true)
        }
        
        // Single file with bookmark
        if let mediaPath = snippet.mediaPath, snippet.contentType != .text && snippet.contentType != .richText {
            // Try bookmark first
            if let bookmark = snippet.bookmarkData {
                if let (url, _) = bookmarkService.resolveBookmark(bookmark) {
                    if bookmarkService.startAccessing(url) {
                        return ([url], true)
                    }
                }
                // Bookmark failed, fall back
            }
            
            // Fall back to FilePermissionService
            if !FilePermissionService.shared.canRead(path: mediaPath) {
                // Check if we need root access for this path
                if !ensureRootAccessIfNeeded(for: [mediaPath]) {
                    return ([], false)
                }
                
                if !FilePermissionService.shared.requestAccess(
                    to: mediaPath,
                    message: "ClipboardMenu needs access to this file to copy it to the clipboard."
                ) {
                    return ([], false)
                }
            }
            return ([], true)
        }
        
        // Text/richText - no file access needed
        return ([], true)
    }
    
    func copyItemToClipboard(_ item: ClipboardItem) {
        // Check if this is an undownloaded cloud file reference
        // Use cached status if available, otherwise check directly (but this is a one-time check on user action)
        let isCloudNotDownloaded = cloudStatusCache[item.id] ?? item.isCloudFileNotDownloaded
        
        // For cloud file references that aren't downloaded, just put the URL on the clipboard
        // without trying to acquire access or read the file (which would trigger download)
        if item.isFileReference && isCloudNotDownloaded {
            clipboardMonitor.willCopyFromHistory()
            
            do {
                try storageService.moveItemToTop(item)
            } catch {
                print("Failed to move item to top: \(error)")
            }
            
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            
            if item.contentType == .fileStack, let mediaPaths = item.mediaPaths {
                let urls = mediaPaths.map { URL(fileURLWithPath: $0) }
                pasteboard.writeObjects(urls.map { $0 as NSURL })
            } else if let mediaPath = item.mediaPath {
                let url = URL(fileURLWithPath: mediaPath)
                pasteboard.writeObjects([url as NSURL])
            }
            
            closePopovers()
            return
        }
        
        // Acquire file access (via bookmarks or user permission)
        let (accessedURLs, granted) = acquireFileAccess(for: item)
        guard granted else { return }
        
        defer {
            // Release any bookmark-based access when done
            releaseFileAccess(accessedURLs)
        }
        
        // Tell the monitor to skip the next clipboard change (we're copying from history)
        clipboardMonitor.willCopyFromHistory()
        
        // Move this item to the top of the history
        do {
            try storageService.moveItemToTop(item)
        } catch {
            print("Failed to move item to top: \(error)")
        }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.contentType {
        case .text:
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }

        case .richText:
            if let rtfData = item.richTextData {
                pasteboard.setData(rtfData, forType: .rtf)
            }
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }

        case .image:
            if let mediaPath = item.mediaPath {
                let url = createClipboardURL(for: mediaPath, preferredName: nil)
                // Write file URL using writeObjects for proper sandbox support
                pasteboard.writeObjects([url as NSURL])
                // Only try to read image data if it's not a file reference (stored in app storage)
                if !item.isFileReference, let image = NSImage(contentsOfFile: mediaPath) {
                    // Also provide image data for apps that prefer it
                    if let tiffData = image.tiffRepresentation {
                        pasteboard.setData(tiffData, forType: .tiff)
                    }
                }
            }

        case .video, .file:
            if let mediaPath = item.mediaPath {
                let url = createClipboardURL(for: mediaPath, preferredName: nil)
                // Write file URL using writeObjects for proper sandbox support
                pasteboard.writeObjects([url as NSURL])
            }
        
        case .fileStack:
            if let mediaPaths = item.mediaPaths {
                let urls = createClipboardURLs(for: mediaPaths)
                // Write file URLs using writeObjects for proper sandbox support
                pasteboard.writeObjects(urls.map { $0 as NSURL })
            }
        }

        closePopovers()
    }

    func copySnippetToClipboard(_ snippet: Snippet) {
        // Acquire file access (via bookmarks or user permission)
        let (accessedURLs, granted) = acquireFileAccess(for: snippet)
        guard granted else { return }
        
        defer {
            // Release any bookmark-based access when done
            releaseFileAccess(accessedURLs)
        }
        
        // Tell the monitor to skip the next clipboard change (we're copying from snippets)
        clipboardMonitor.willCopyFromHistory()
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch snippet.contentType {
        case .text, .richText:
            if let text = snippet.textContent {
                pasteboard.setString(text, forType: .string)
            }

        case .image:
            if let mediaPath = snippet.mediaPath {
                // Create a filename from snippet name with proper extension
                let ext = URL(fileURLWithPath: mediaPath).pathExtension.lowercased()
                let preferredName: String?
                if snippet.name.isEmpty {
                    preferredName = nil
                } else if ext.isEmpty {
                    // No extension - use name as-is without adding a dot
                    preferredName = snippet.name
                } else if snippet.name.lowercased().hasSuffix(".\(ext)") {
                    // Name already has the extension - use as-is
                    preferredName = snippet.name
                } else {
                    preferredName = "\(snippet.name).\(ext)"
                }
                let url = createClipboardURL(for: mediaPath, preferredName: preferredName)
                // Write file URL using writeObjects for proper sandbox support
                pasteboard.writeObjects([url as NSURL])
                if let image = NSImage(contentsOfFile: mediaPath) {
                    // Also provide image data for apps that prefer it
                    if let tiffData = image.tiffRepresentation {
                        pasteboard.setData(tiffData, forType: .tiff)
                    }
                }
            }

        case .video, .file:
            if let mediaPath = snippet.mediaPath {
                // Create a filename from snippet name with proper extension
                let ext = URL(fileURLWithPath: mediaPath).pathExtension.lowercased()
                let preferredName: String?
                if snippet.name.isEmpty {
                    preferredName = nil
                } else if ext.isEmpty {
                    // No extension (e.g., folder) - use name as-is without adding a dot
                    preferredName = snippet.name
                } else if snippet.name.lowercased().hasSuffix(".\(ext)") {
                    // Name already has the extension - use as-is
                    preferredName = snippet.name
                } else {
                    preferredName = "\(snippet.name).\(ext)"
                }
                let url = createClipboardURL(for: mediaPath, preferredName: preferredName)
                // Write file URL using writeObjects for proper sandbox support
                pasteboard.writeObjects([url as NSURL])
            }
        
        case .fileStack:
            if let mediaPaths = snippet.mediaPaths {
                let urls = createClipboardURLs(for: mediaPaths)
                // Write file URLs using writeObjects for proper sandbox support
                pasteboard.writeObjects(urls.map { $0 as NSURL })
            }
        }

        closePopovers()
    }

    // MARK: - Snippet Operations
    
    /// Opens the snippets menu if it's in separate mode
    /// Used when starting a cloud download to show the download progress
    func openSnippetsMenuIfSeparate() {
        guard preferencesService.snippetsMenuMode == .separate else { return }
        
        historyPopover?.performClose(nil)
        if let button = snippetsStatusItem?.button, let popover = snippetsPopover {
            popover.contentSize = NSSize(width: menuWidth, height: snippetsMenuHeight)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func addToSnippets(_ item: ClipboardItem) {
        // For file references, always use async flow to avoid blocking UI
        if item.isFileReference {
            addCloudSnippet(from: item)
            return
        }
        
        // Check if we need file access for file-based items
        if let paths = item.mediaPaths, !paths.isEmpty {
            // File stack - check access to all files
            let inaccessiblePaths = paths.filter { !FilePermissionService.shared.canRead(path: $0) }
            if !inaccessiblePaths.isEmpty {
                // Check if we need root access for any of these paths
                if !ensureRootAccessIfNeeded(for: inaccessiblePaths) {
                    return // User denied access
                }
                
                if !FilePermissionService.shared.requestFolderAccess(
                    for: inaccessiblePaths,
                    message: "ClipboardMenu needs access to these files to save them as a snippet."
                ) {
                    return // User denied access
                }
            }
        } else if let mediaPath = item.mediaPath {
            // Single file - check access
            if !FilePermissionService.shared.canRead(path: mediaPath) {
                // Check if we need root access for this path
                if !ensureRootAccessIfNeeded(for: [mediaPath]) {
                    return // User denied access
                }
                
                if !FilePermissionService.shared.requestAccess(
                    to: mediaPath,
                    message: "ClipboardMenu needs access to this file to save it as a snippet."
                ) {
                    return // User denied access
                }
            }
        }
        
        do {
            _ = try storageService.createSnippetFromItem(item)
            loadData()
            
            // If snippets menu is separate, open it to show the new snippet
            if preferencesService.snippetsMenuMode == .separate {
                historyPopover?.performClose(nil)
                if let button = snippetsStatusItem?.button, let popover = snippetsPopover {
                    popover.contentSize = NSSize(width: menuWidth, height: snippetsMenuHeight)
                    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                }
            }
        } catch {
            print("Failed to add to snippets: \(error)")
        }
    }
    
    /// Add a file as a snippet, handling both cloud and local files asynchronously
    /// The snippet is created immediately and file copying happens in the background
    func addCloudSnippet(from item: ClipboardItem) {
        // Get paths for the files
        var filePaths: [String] = []
        if item.contentType == .fileStack, let paths = item.mediaPaths {
            filePaths = paths
        } else if let path = item.mediaPath {
            filePaths = [path]
        }
        
        // Count files
        let fileCount = filePaths.isEmpty ? 0 : filePaths.count
        
        do {
            // Create snippet immediately in downloading state
            let snippet = try storageService.createDownloadingSnippet(from: item, fileCount: fileCount)
            loadData()
            
            // Start the download/copy process in background
            cloudDownloadService.startDownload(for: snippet, cloudPaths: filePaths)
            
            // Open snippets menu if separate
            openSnippetsMenuIfSeparate()
        } catch {
            print("Failed to create snippet: \(error)")
        }
    }
    
    /// Retry a failed cloud download for a snippet
    func retrySnippetDownload(_ snippet: Snippet) {
        cloudDownloadService.retryDownload(for: snippet)
    }
    
    /// Cancel a downloading snippet and delete it
    func cancelSnippetDownload(_ snippet: Snippet) {
        // If this is the snippet currently being downloaded, use the service's cancel
        if cloudDownloadService.downloadingSnippetId == snippet.id {
            cloudDownloadService.cancelAndDelete()
        } else {
            // Remove from pending queue if it's waiting
            cloudDownloadService.removeFromQueue(snippetId: snippet.id)
            // Delete the snippet
            try? storageService.deleteSnippet(id: snippet.id)
        }
        loadData()
    }

    func deleteItem(_ item: ClipboardItem) {
        do {
            try storageService.deleteClipboardItem(item)
            loadData()
        } catch {
            print("Failed to delete item: \(error)")
        }
    }

    func deleteSnippet(_ snippet: Snippet) {
        do {
            try storageService.deleteSnippet(snippet)
            loadData()
        } catch {
            print("Failed to delete snippet: \(error)")
        }
    }
    
    func moveSnippet(from source: IndexSet, to destination: Int) {
        var reorderedSnippets = snippets
        reorderedSnippets.move(fromOffsets: source, toOffset: destination)
        
        do {
            try storageService.updateSnippetOrder(reorderedSnippets)
            snippets = reorderedSnippets
            objectWillChange.send()
        } catch {
            print("Failed to reorder snippets: \(error)")
        }
    }
    
    func moveClipboardItem(from source: IndexSet, to destination: Int) {
        var reorderedItems = clipboardItems
        reorderedItems.move(fromOffsets: source, toOffset: destination)
        
        do {
            try storageService.updateClipboardItemOrder(reorderedItems)
            clipboardItems = reorderedItems
            objectWillChange.send()
        } catch {
            print("Failed to reorder clipboard items: \(error)")
        }
    }

    func clearHistory() {
        do {
            for item in clipboardItems {
                try storageService.deleteClipboardItem(item)
            }
            loadData()
        } catch {
            print("Failed to clear history: \(error)")
        }
    }
}

// MARK: - Visual Effect Background

/// A SwiftUI view that provides a frosted glass background using NSVisualEffectView
struct VisualEffectBackground<Content: View>: NSViewRepresentable {
    let content: Content
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    
    init(material: NSVisualEffectView.Material = .popover, blendingMode: NSVisualEffectView.BlendingMode = .behindWindow, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.material = material
        self.blendingMode = blendingMode
    }
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.state = .active
        visualEffectView.blendingMode = blendingMode
        
        // Create hosting view for SwiftUI content
        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.addSubview(hostingView)
        
        // Pin to edges
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor)
        ])
        
        return visualEffectView
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        
        // Update the hosted SwiftUI content
        if let hostingView = nsView.subviews.first as? NSHostingView<Content> {
            hostingView.rootView = content
        }
    }
}
