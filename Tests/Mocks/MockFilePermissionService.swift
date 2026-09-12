import Foundation
@testable import ClipboardMenu

/// Mock implementation of FilePermissionServiceProtocol for testing
@MainActor
final class MockFilePermissionService: FilePermissionServiceProtocol {
    
    // MARK: - Mock State
    
    /// Paths that the mock considers readable
    var readablePaths: Set<String> = []
    
    /// Whether home directory access has been "granted"
    var _hasFileSystemAccess: Bool = false
    
    /// Whether root file system access has been "granted"
    var _hasRootAccess: Bool = false
    
    /// Paths that were requested for access
    var requestedPaths: [String] = []
    
    /// URLs that were requested for access
    var requestedURLs: [URL] = []
    
    /// Whether access requests should succeed
    var shouldGrantAccess: Bool = true
    
    /// Number of times various methods were called
    var requestHomeDirectoryAccessCallCount = 0
    var requestRootAccessCallCount = 0
    var restoreFileSystemAccessCallCount = 0
    var stopAccessingCallCount = 0
    
    /// Mock home directory path for testing
    var mockHomeDirectoryPath = "/Users/testuser"
    
    // MARK: - FilePermissionServiceProtocol
    
    var hasFileSystemAccess: Bool {
        _hasFileSystemAccess || _hasRootAccess
    }
    
    var hasRootAccess: Bool {
        _hasRootAccess
    }
    
    func requestHomeDirectoryAccess(preferencesService: PreferencesService) -> Bool {
        requestHomeDirectoryAccessCallCount += 1
        if shouldGrantAccess {
            _hasFileSystemAccess = true
        }
        return shouldGrantAccess
    }
    
    func requestRootAccess(preferencesService: PreferencesService) -> Bool {
        requestRootAccessCallCount += 1
        if shouldGrantAccess {
            _hasRootAccess = true
        }
        return shouldGrantAccess
    }
    
    func restoreFileSystemAccess(preferencesService: PreferencesService) -> Bool {
        restoreFileSystemAccessCallCount += 1
        return _hasFileSystemAccess || _hasRootAccess
    }
    
    func stopAccessingSecurityScopedResource() {
        stopAccessingCallCount += 1
        _hasFileSystemAccess = false
        _hasRootAccess = false
    }
    
    func canRead(path: String) -> Bool {
        readablePaths.contains(path)
    }
    
    func canReadAll(paths: [String]) -> Bool {
        paths.allSatisfy { canRead(path: $0) }
    }
    
    func isPathOutsideHomeDirectory(_ path: String) -> Bool {
        !path.hasPrefix(mockHomeDirectoryPath)
    }
    
    func needsRootAccess(for path: String) -> Bool {
        isPathOutsideHomeDirectory(path) && !hasRootAccess
    }
    
    @discardableResult
    func requestAccess(to path: String, message: String?) -> Bool {
        requestedPaths.append(path)
        if shouldGrantAccess {
            readablePaths.insert(path)
        }
        return shouldGrantAccess
    }
    
    @discardableResult
    func requestAccess(to url: URL, message: String?) -> Bool {
        requestedURLs.append(url)
        if shouldGrantAccess {
            readablePaths.insert(url.path)
        }
        return shouldGrantAccess
    }
    
    @discardableResult
    func requestFolderAccess(for paths: [String], message: String?) -> Bool {
        requestedPaths.append(contentsOf: paths)
        if shouldGrantAccess {
            for path in paths {
                readablePaths.insert(path)
            }
        }
        return shouldGrantAccess
    }
    
    // MARK: - Test Helpers
    
    /// Reset all mock state
    func reset() {
        readablePaths = []
        _hasFileSystemAccess = false
        _hasRootAccess = false
        requestedPaths = []
        requestedURLs = []
        shouldGrantAccess = true
        requestHomeDirectoryAccessCallCount = 0
        requestRootAccessCallCount = 0
        restoreFileSystemAccessCallCount = 0
        stopAccessingCallCount = 0
    }
    
    /// Mark paths as readable
    func grantAccess(to paths: [String]) {
        for path in paths {
            readablePaths.insert(path)
        }
    }
}
