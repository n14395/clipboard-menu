import AppKit
import Foundation

/// Protocol for file permission service to enable testing
@MainActor
protocol FilePermissionServiceProtocol {
    var hasFileSystemAccess: Bool { get }
    var hasRootAccess: Bool { get }
    func requestHomeDirectoryAccess(preferencesService: PreferencesService) -> Bool
    func requestRootAccess(preferencesService: PreferencesService) -> Bool
    func restoreFileSystemAccess(preferencesService: PreferencesService) -> Bool
    func stopAccessingSecurityScopedResource()
    func canRead(path: String) -> Bool
    func canReadAll(paths: [String]) -> Bool
    func isPathOutsideHomeDirectory(_ path: String) -> Bool
    func needsRootAccess(for path: String) -> Bool
    @discardableResult func requestAccess(to path: String, message: String?) -> Bool
    @discardableResult func requestAccess(to url: URL, message: String?) -> Bool
    @discardableResult func requestFolderAccess(for paths: [String], message: String?) -> Bool
}

/// Service to handle file permission requests for sandboxed apps
@MainActor
class FilePermissionService: FilePermissionServiceProtocol {
    static let shared = FilePermissionService()
    
    /// Currently active security-scoped URL for home directory access
    private var activeHomeSecurityScopedURL: URL?
    
    /// Currently active security-scoped URL for root file system access
    private var activeRootSecurityScopedURL: URL?
    
    /// Cached home directory path for performance
    private let homeDirectoryPath: String
    
    private init() {
        self.homeDirectoryPath = FileManager.default.homeDirectoryForCurrentUser.path
    }
    
    // MARK: - Security-Scoped Bookmark Management
    
    /// Request access to the user's home directory and store a security-scoped bookmark
    /// Returns true if access was granted
    func requestHomeDirectoryAccess(preferencesService: PreferencesService) -> Bool {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        
        let panel = NSOpenPanel()
        panel.message = "ClipboardMenu needs access to your files to preview and paste copied files."
        panel.prompt = "Grant Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = homeURL
        panel.treatsFilePackagesAsDirectories = true
        
        let response = panel.runModal()
        
        if response == .OK, let selectedURL = panel.url {
            // Create a security-scoped bookmark
            do {
                let bookmarkData = try selectedURL.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                preferencesService.fileSystemBookmark = bookmarkData
                
                // Start accessing the resource
                startAccessingHomeSecurityScopedResource(from: bookmarkData)
                
                return true
            } catch {
                print("Failed to create security-scoped bookmark for home directory: \(error)")
                return false
            }
        }
        
        return false
    }
    
    /// Request access to the root file system and store a security-scoped bookmark
    /// This is called when the user tries to access files outside their home directory
    /// Returns true if access was granted
    func requestRootAccess(preferencesService: PreferencesService) -> Bool {
        let panel = NSOpenPanel()
        panel.message = "ClipboardMenu needs access to files outside your home folder. Please select your main disk (e.g., Macintosh HD)."
        panel.prompt = "Grant Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/")
        panel.treatsFilePackagesAsDirectories = true
        
        let response = panel.runModal()
        
        if response == .OK, let selectedURL = panel.url {
            // Create a security-scoped bookmark
            do {
                let bookmarkData = try selectedURL.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                preferencesService.rootFileSystemBookmark = bookmarkData
                
                // Start accessing the resource
                startAccessingRootSecurityScopedResource(from: bookmarkData)
                
                return true
            } catch {
                print("Failed to create security-scoped bookmark for root: \(error)")
                return false
            }
        }
        
        return false
    }
    
    /// Restore file system access from stored bookmarks
    /// Call this at app launch to restore previously granted access
    func restoreFileSystemAccess(preferencesService: PreferencesService) -> Bool {
        var restoredAny = false
        
        // Restore home directory access
        if let homeBookmark = preferencesService.fileSystemBookmark {
            if startAccessingHomeSecurityScopedResource(from: homeBookmark) {
                restoredAny = true
            }
        }
        
        // Restore root access if available
        if let rootBookmark = preferencesService.rootFileSystemBookmark {
            if startAccessingRootSecurityScopedResource(from: rootBookmark) {
                restoredAny = true
            }
        }
        
        return restoredAny
    }
    
    /// Start accessing a security-scoped resource for home directory from bookmark data
    @discardableResult
    private func startAccessingHomeSecurityScopedResource(from bookmarkData: Data) -> Bool {
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                print("Home directory security-scoped bookmark is stale, may need to request access again")
            }
            
            if url.startAccessingSecurityScopedResource() {
                activeHomeSecurityScopedURL = url
                return true
            } else {
                print("Failed to start accessing home directory security-scoped resource")
                return false
            }
        } catch {
            print("Failed to resolve home directory security-scoped bookmark: \(error)")
            return false
        }
    }
    
    /// Start accessing a security-scoped resource for root from bookmark data
    @discardableResult
    private func startAccessingRootSecurityScopedResource(from bookmarkData: Data) -> Bool {
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                print("Root security-scoped bookmark is stale, may need to request access again")
            }
            
            if url.startAccessingSecurityScopedResource() {
                activeRootSecurityScopedURL = url
                return true
            } else {
                print("Failed to start accessing root security-scoped resource")
                return false
            }
        } catch {
            print("Failed to resolve root security-scoped bookmark: \(error)")
            return false
        }
    }
    
    /// Stop accessing all security-scoped resources (call when app terminates)
    func stopAccessingSecurityScopedResource() {
        activeHomeSecurityScopedURL?.stopAccessingSecurityScopedResource()
        activeHomeSecurityScopedURL = nil
        
        activeRootSecurityScopedURL?.stopAccessingSecurityScopedResource()
        activeRootSecurityScopedURL = nil
    }
    
    /// Check if we have any file system access (home directory)
    var hasFileSystemAccess: Bool {
        activeHomeSecurityScopedURL != nil || activeRootSecurityScopedURL != nil
    }
    
    /// Check if we have root file system access
    var hasRootAccess: Bool {
        activeRootSecurityScopedURL != nil
    }
    
    // MARK: - Path Analysis
    
    /// Check if a path is outside the user's home directory
    func isPathOutsideHomeDirectory(_ path: String) -> Bool {
        // Resolve symlinks and normalize the path
        let resolvedPath = (path as NSString).resolvingSymlinksInPath
        let resolvedHome = (homeDirectoryPath as NSString).resolvingSymlinksInPath
        
        return !resolvedPath.hasPrefix(resolvedHome)
    }
    
    /// Check if we need root access to read a path
    /// Returns true if the path is outside home directory AND we don't have root access
    func needsRootAccess(for path: String) -> Bool {
        return isPathOutsideHomeDirectory(path) && !hasRootAccess
    }
    
    /// Check if the app can read a file at the given path
    /// For cloud files, checks metadata without triggering downloads
    func canRead(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        
        // First check if this is an iCloud file using resource values (doesn't trigger download)
        do {
            let resourceValues = try url.resourceValues(forKeys: [.isUbiquitousItemKey])
            if resourceValues.isUbiquitousItem == true {
                // It's a cloud file - consider it "readable" (the system will handle download when accessed)
                // We don't want to trigger a download just to check readability
                return true
            }
        } catch {
            // If we can't check, fall through to regular check
        }
        
        // For non-cloud files, use standard readability check
        return FileManager.default.isReadableFile(atPath: path)
    }
    
    /// Check if the app can read all files in the given paths
    func canReadAll(paths: [String]) -> Bool {
        return paths.allSatisfy { canRead(path: $0) }
    }
    
    /// Request permission to access a file by showing an open panel
    /// Returns true if permission was granted
    @discardableResult
    func requestAccess(to path: String, message: String? = nil) -> Bool {
        let url = URL(fileURLWithPath: path)
        return requestAccess(to: url, message: message)
    }
    
    /// Request permission to access a URL by showing an open panel
    /// Returns true if permission was granted
    @discardableResult
    func requestAccess(to url: URL, message: String? = nil) -> Bool {
        // If we already have access, no need to ask
        if FileManager.default.isReadableFile(atPath: url.path) {
            return true
        }
        
        let panel = NSOpenPanel()
        panel.message = message ?? "ClipboardMenu needs access to this file to complete the action."
        panel.prompt = "Grant Access"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = url.deletingLastPathComponent()
        panel.allowedContentTypes = []
        
        // Pre-select the file we need access to
        if #available(macOS 14.0, *) {
            panel.allowedContentTypes = [.item]
        }
        
        let response = panel.runModal()
        
        if response == .OK, let selectedURL = panel.url {
            // Check if user selected the correct file or its parent
            if selectedURL.path == url.path || url.path.hasPrefix(selectedURL.path) {
                return true
            }
        }
        
        return false
    }
    
    /// Request permission to access a folder containing the given files
    /// Returns true if permission was granted
    @discardableResult
    func requestFolderAccess(for paths: [String], message: String? = nil) -> Bool {
        guard !paths.isEmpty else { return true }
        
        // Find the common parent directory
        let urls = paths.map { URL(fileURLWithPath: $0) }
        var commonParent = urls[0].deletingLastPathComponent()
        
        for url in urls.dropFirst() {
            while !url.path.hasPrefix(commonParent.path) && commonParent.path != "/" {
                commonParent = commonParent.deletingLastPathComponent()
            }
        }
        
        // If we already have access to all files, no need to ask
        if canReadAll(paths: paths) {
            return true
        }
        
        let panel = NSOpenPanel()
        panel.message = message ?? "ClipboardMenu needs access to this folder to complete the action."
        panel.prompt = "Grant Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = commonParent
        
        let response = panel.runModal()
        
        if response == .OK, let selectedURL = panel.url {
            // Check if all our paths are under the selected folder
            let selectedPath = selectedURL.path
            if paths.allSatisfy({ $0.hasPrefix(selectedPath) }) {
                return true
            }
        }
        
        return false
    }
}
