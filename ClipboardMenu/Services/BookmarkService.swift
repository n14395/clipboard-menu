import Foundation

/// Service for creating and resolving security-scoped bookmarks for file access
/// Security-scoped bookmarks allow sandboxed apps to maintain access to files
/// across app launches, even when those files are outside the app's sandbox
class BookmarkService {
    
    // MARK: - Bookmark Creation
    
    /// Create a security-scoped bookmark for a file URL
    /// - Parameter url: The file URL to create a bookmark for
    /// - Returns: The bookmark data, or nil if creation failed
    func createBookmark(for url: URL) -> Data? {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return bookmarkData
        } catch {
            print("Failed to create bookmark for \(url.path): \(error)")
            return nil
        }
    }
    
    // MARK: - Bookmark Resolution
    
    /// Resolve a security-scoped bookmark to get access to the file
    /// - Parameter bookmarkData: The bookmark data to resolve
    /// - Returns: A tuple containing the resolved URL and whether access was started
    func resolveBookmark(_ bookmarkData: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return (url, isStale)
        } catch {
            print("Failed to resolve bookmark: \(error)")
            return nil
        }
    }
    
    // MARK: - Access Management
    
    /// Start accessing a security-scoped resource
    /// Must be balanced with a call to stopAccessing
    /// - Parameter url: The URL that was resolved from a bookmark
    /// - Returns: True if access was started successfully
    @discardableResult
    func startAccessing(_ url: URL) -> Bool {
        return url.startAccessingSecurityScopedResource()
    }
    
    /// Stop accessing a security-scoped resource
    /// - Parameter url: The URL that was previously accessed
    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}
