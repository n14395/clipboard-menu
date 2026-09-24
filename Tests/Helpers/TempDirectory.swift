// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Manages a temporary directory for file-based tests
final class TempDirectory {
    let url: URL
    private let fileManager = FileManager.default
    
    /// Creates a new temporary directory for external files (not containing "ClipboardMenu")
    /// Use this for testing file references and external path handling
    init() throws {
        let tempBase = FileManager.default.temporaryDirectory
        let uniqueName = "TestDir_\(UUID().uuidString)"
        url = tempBase.appendingPathComponent(uniqueName, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }
    
    /// Creates a temporary directory that mimics app internal storage (contains "ClipboardMenu" in path)
    /// Use this for testing internal storage operations like media cleanup
    static func appStorage() throws -> TempDirectory {
        let tempBase = FileManager.default.temporaryDirectory
        let uniqueName = "ClipboardMenu_Test_\(UUID().uuidString)"
        let url = tempBase.appendingPathComponent(uniqueName, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return TempDirectory(url: url)
    }
    
    /// Private initializer for creating TempDirectory with a specific URL
    private init(url: URL) {
        self.url = url
    }
    
    /// Creates a file with the given name and content
    @discardableResult
    func createFile(name: String, content: Data) throws -> URL {
        let fileURL = url.appendingPathComponent(name)
        try content.write(to: fileURL)
        return fileURL
    }
    
    /// Creates a file with the given name and string content
    @discardableResult
    func createFile(name: String, content: String) throws -> URL {
        try createFile(name: name, content: Data(content.utf8))
    }
    
    /// Creates a subdirectory
    @discardableResult
    func createSubdirectory(name: String) throws -> URL {
        let dirURL = url.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
        return dirURL
    }
    
    /// Returns the path for a file (doesn't create it)
    func path(for name: String) -> String {
        url.appendingPathComponent(name).path
    }
    
    /// Returns the URL for a file (doesn't create it)
    func fileURL(for name: String) -> URL {
        url.appendingPathComponent(name)
    }
    
    /// Checks if a file exists
    func fileExists(name: String) -> Bool {
        fileManager.fileExists(atPath: path(for: name))
    }
    
    /// Gets file size
    func fileSize(name: String) -> Int64? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: path(for: name)),
              let size = attrs[.size] as? Int64 else {
            return nil
        }
        return size
    }
    
    /// Reads file content
    func readFile(name: String) -> Data? {
        fileManager.contents(atPath: path(for: name))
    }
    
    /// Lists all files in the temp directory
    func listFiles() -> [String] {
        (try? fileManager.contentsOfDirectory(atPath: url.path)) ?? []
    }
    
    /// Cleans up the temporary directory
    func cleanup() {
        try? fileManager.removeItem(at: url)
    }
    
    deinit {
        cleanup()
    }
}

/// Extension to create a TempDirectory that mimics the app's storage structure
extension TempDirectory {
    /// Creates subdirectories matching app structure (Media, Thumbnails)
    func setupAppStructure() throws -> (media: URL, thumbnails: URL, database: URL) {
        let media = try createSubdirectory(name: "Media")
        let thumbnails = try createSubdirectory(name: "Thumbnails")
        let database = fileURL(for: "clipboard.db")
        return (media, thumbnails, database)
    }
}
