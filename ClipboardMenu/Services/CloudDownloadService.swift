// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Combine

/// Downloads cloud (iCloud/ubiquitous) files asynchronously for snippets
/// Tracks progress for file stacks and supports cancellation
@MainActor
class CloudDownloadService: ObservableObject {
    @Published private(set) var isDownloading = false
    @Published private(set) var currentFileIndex = 0
    @Published private(set) var totalFiles = 0
    @Published private(set) var downloadingSnippetId: UUID?
    
    /// Paths that have been successfully downloaded in this session
    /// Used to override stale iCloud status for display purposes
    @Published private(set) var downloadedPaths: Set<String> = []
    
    private var downloadTask: Task<Void, Never>?
    private let pollInterval: TimeInterval = 0.5  // Check download status every 500ms
    private let downloadTimeout: TimeInterval = 3600  // 1 hour timeout per file (cloud downloads can be slow)
    private let retriggerInterval: TimeInterval = 5.0  // Re-trigger downloads every 5 seconds if stalled
    
    /// Queue of pending downloads (snippet ID and paths)
    private var pendingDownloads: [(snippetId: UUID, paths: [String])] = []
    
    /// Set of snippet IDs waiting to download (for UI to show "Waiting to download")
    var pendingDownloadIds: Set<UUID> {
        Set(pendingDownloads.map { $0.snippetId })
    }
    
    /// Reference to storage service for updating snippet state
    private weak var storageService: StorageService?
    
    /// Callback invoked when download completes or fails (for UI refresh)
    var onDownloadComplete: (() -> Void)?
    
    /// Callback invoked when download progress changes (for UI refresh)
    var onProgressUpdate: (() -> Void)?
    
    /// Initialize with storage service reference
    func configure(storageService: StorageService) {
        self.storageService = storageService
    }
    
    /// Check if a path has been downloaded in this session
    func isPathDownloaded(_ path: String) -> Bool {
        downloadedPaths.contains(path)
    }
    
    /// Start the download process for a snippet that was just created in downloading state
    /// This returns immediately - all work happens on background threads
    /// - Parameters:
    ///   - snippet: The snippet in downloading state
    ///   - cloudPaths: The paths to cloud files that need downloading
    func startDownload(for snippet: Snippet, cloudPaths: [String]) {
        // Check if all files are already downloaded - if so, copy immediately without queuing
        let allDownloaded = !cloudPaths.contains { Self.isPathCloudFileNotDownloadedSync($0) }
        
        if allDownloaded {
            print("[Download] All files already downloaded for snippet \(snippet.id), copying immediately")
            // Copy immediately in background without going through the download queue
            copyImmediately(snippetId: snippet.id)
            return
        }
        
        // If already downloading, queue this download for later
        if isDownloading {
            print("[Download] Already downloading, queuing snippet \(snippet.id)")
            pendingDownloads.append((snippetId: snippet.id, paths: cloudPaths))
            return
        }
        
        startDownloadInternal(snippetId: snippet.id, cloudPaths: cloudPaths)
    }
    
    /// Copy files immediately without waiting for download (files are already available)
    private func copyImmediately(snippetId: UUID) {
        let storageService = self.storageService
        
        Task {
            do {
                try await storageService?.completeSnippetDownloadAsync(snippetId)
                print("[Download] Immediate copy completed for snippet \(snippetId)")
            } catch {
                print("[Download] Immediate copy failed for snippet \(snippetId): \(error)")
                try? storageService?.markSnippetDownloadFailed(snippetId, error: error.localizedDescription)
            }
            onDownloadComplete?()
        }
    }
    
    /// Internal method to actually start a download
    private func startDownloadInternal(snippetId: UUID, cloudPaths: [String]) {
        cancel()
        
        downloadingSnippetId = snippetId
        currentFileIndex = 0
        totalFiles = cloudPaths.count
        isDownloading = true
        
        // Capture storageService and retrigger interval for use in detached task
        let storageService = self.storageService
        let retriggerInterval = self.retriggerInterval
        
        // Run the download loop inside a regular Task but do all waiting in detached tasks
        // This keeps the outer task on MainActor but doesn't block it during file waits
        downloadTask = Task { [weak self] in
            // Use defer to ALWAYS reset state and process queue, even on cancellation
            defer {
                Task { @MainActor [weak self] in
                    self?.resetAndProcessQueue()
                }
            }
            
            print("[Download] Task started for snippet \(snippetId)")
            
            // Determine which paths are cloud paths that need handling
            let isCloudItem = await Task.detached {
                cloudPaths.contains { path in
                    // Check path patterns first
                    if path.contains("/Library/Mobile Documents/") ||
                       path.contains("/iCloud Drive/") ||
                       path.contains("~Library/CloudStorage/") ||
                       path.contains("/CloudStorage/") {
                        return true
                    }
                    
                    // Also check resource values for iCloud-synced folders (Desktop/Documents)
                    let url = URL(fileURLWithPath: path)
                    do {
                        let resourceValues = try url.resourceValues(forKeys: [.isUbiquitousItemKey])
                        return resourceValues.isUbiquitousItem == true
                    } catch {
                        return false
                    }
                }
            }.value
            
            // Start downloads for ALL paths on background thread
            // This ensures we trigger downloads even if status detection is wrong
            await Task.detached {
                print("[Download] Starting downloads for \(cloudPaths.count) paths (isCloudItem: \(isCloudItem))")
                for path in cloudPaths {
                    let url = URL(fileURLWithPath: path)
                    CloudDownloadService.startDownloadRecursively(at: url)
                }
            }.value
            
            // For cloud items, we need to wait for downloads
            // For non-cloud items, we can complete immediately
            if !isCloudItem {
                print("[Download] Not a cloud item, completing immediately")
                do {
                    try await storageService?.completeSnippetDownloadAsync(snippetId)
                    self?.onDownloadComplete?()
                    print("[Download] Completion done (not cloud)")
                } catch {
                    print("[Download] Failed to complete snippet: \(error)")
                    try? storageService?.markSnippetDownloadFailed(snippetId, error: error.localizedDescription)
                    self?.onDownloadComplete?()
                }
                return
            }
            
            // Update state - wait for ALL cloud paths, not just filtered ones
            // The filter is unreliable, so we wait for everything
            self?.totalFiles = cloudPaths.count
            self?.currentFileIndex = 1
            try? storageService?.updateSnippetDownloadProgress(snippetId, currentIndex: 1, totalFiles: cloudPaths.count)
            self?.onProgressUpdate?()
            
            // Poll for each file's completion with periodic re-triggering
            // Wait for ALL paths, not just filtered ones
            let downloadResults = await Task.detached { () -> [(index: Int, path: String, result: Result<Void, DownloadError>)] in
                var results: [(index: Int, path: String, result: Result<Void, DownloadError>)] = []
                for (index, path) in cloudPaths.enumerated() {
                    if Task.isCancelled {
                        print("[Download] Task was CANCELLED at file \(index + 1)")
                        break
                    }
                    
                    let fileName = URL(fileURLWithPath: path).lastPathComponent
                    print("[Download] Waiting for file \(index + 1)/\(cloudPaths.count): \(fileName)")
                    
                    // Wait with periodic re-triggering of stalled downloads
                    let result = await CloudDownloadService.waitForDownloadWithRetrigger(
                        at: path, 
                        timeout: 3600, 
                        pollInterval: 0.5,
                        retriggerInterval: retriggerInterval
                    )
                    print("[Download] File \(index + 1) result: \(result)")
                    results.append((index: index, path: path, result: result))
                    
                    if case .failure = result {
                        break
                    }
                }
                return results
            }.value
            
            // Check for cancellation
            if Task.isCancelled {
                print("[Download] Task cancelled, not completing")
                return
            }
            
            // Process results back on MainActor
            var failed = false
            for result in downloadResults {
                self?.currentFileIndex = result.index + 1
                try? storageService?.updateSnippetDownloadProgress(snippetId, currentIndex: result.index + 1, totalFiles: cloudPaths.count)
                self?.onProgressUpdate?()
                
                if case .failure(let error) = result.result {
                    print("[Download] File \(result.index + 1) FAILED: \(error)")
                    try? storageService?.markSnippetDownloadFailed(snippetId, error: error.localizedDescription)
                    self?.onDownloadComplete?()
                    failed = true
                    break
                }
                
                self?.downloadedPaths.insert(result.path)
            }
            
            if !failed {
                print("[Download] All files done, completing...")
                do {
                    try await storageService?.completeSnippetDownloadAsync(snippetId)
                    self?.onDownloadComplete?()
                    print("[Download] Completion done")
                } catch {
                    print("[Download] Failed to complete snippet: \(error)")
                    try? storageService?.markSnippetDownloadFailed(snippetId, error: error.localizedDescription)
                    self?.onDownloadComplete?()
                }
            }
        }
    }
    
    /// Reset state and process next queued download if any
    private func resetAndProcessQueue() {
        reset()
        
        // Process next queued download if any
        if let next = pendingDownloads.first {
            pendingDownloads.removeFirst()
            print("[Download] Processing queued download for snippet \(next.snippetId)")
            startDownloadInternal(snippetId: next.snippetId, cloudPaths: next.paths)
        }
    }
    
    /// Retry a failed download for a snippet
    func retryDownload(for snippet: Snippet) {
        // Get the cloud paths from the snippet
        var cloudPaths: [String] = []
        if let paths = snippet.cloudPaths {
            cloudPaths = paths
        } else if let path = snippet.cloudPath {
            cloudPaths = [path]
        }
        
        guard !cloudPaths.isEmpty else { return }
        
        // Clear the error and mark as downloading
        try? storageService?.clearSnippetDownloadError(snippet.id)
        
        // Start the download
        var updatedSnippet = snippet
        updatedSnippet.isDownloading = true
        updatedSnippet.downloadError = nil
        startDownload(for: updatedSnippet, cloudPaths: cloudPaths)
    }
    
    /// Cancel the current download and delete the snippet
    func cancelAndDelete() {
        guard let snippetId = downloadingSnippetId else {
            reset()
            return
        }
        
        downloadTask?.cancel()
        downloadTask = nil
        
        // Delete the snippet
        try? storageService?.deleteSnippet(id: snippetId)
        
        // Reset and process the next queued download
        resetAndProcessQueue()
        onDownloadComplete?()
    }
    
    /// Cancel without deleting (for cleanup)
    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        // Don't call resetAndProcessQueue here - cancel is called before starting new downloads
        reset()
    }
    
    /// Clear the pending download queue
    func clearQueue() {
        pendingDownloads.removeAll()
    }
    
    /// Remove a specific snippet from the pending download queue
    func removeFromQueue(snippetId: UUID) {
        pendingDownloads.removeAll { $0.snippetId == snippetId }
    }
    
    /// Reset state after completion or cancellation
    private func reset() {
        isDownloading = false
        downloadingSnippetId = nil
        currentFileIndex = 0
        totalFiles = 0
    }
    
    // MARK: - Cloud Path Checking
    
    /// Filter paths to only those that actually need downloading - synchronous version for detached tasks
    private nonisolated static func filterPathsNeedingDownloadSync(_ paths: [String]) -> [String] {
        paths.filter { isPathCloudFileNotDownloadedSync($0) }
    }
    
    /// Check if a path is a cloud file not downloaded - synchronous, call from background only
    nonisolated static func isPathCloudFileNotDownloadedSync(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        
        // First check by path - common iCloud/cloud storage locations
        let isCloudPath = path.contains("/Library/Mobile Documents/") ||
                          path.contains("/iCloud Drive/") ||
                          path.contains("~Library/CloudStorage/") ||
                          path.contains("/CloudStorage/")
        
        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemIsDownloadingKey,
                .isDirectoryKey
            ])
            
            // Check if it's a cloud item (by resource value or path)
            let isUbiquitous = resourceValues.isUbiquitousItem == true || isCloudPath
            
            // Not a cloud item - it's available locally
            guard isUbiquitous else {
                return false
            }
            
            // If actively downloading, it needs download
            if resourceValues.ubiquitousItemIsDownloading == true {
                return true
            }
            
            // Check download status
            // .current = fully up to date, .downloaded = available locally (both mean downloaded)
            // .notDownloaded = needs to be downloaded
            if let status = resourceValues.ubiquitousItemDownloadingStatus {
                if status == .current || status == .downloaded {
                    // File is downloaded - but for folders, check contents too
                    if resourceValues.isDirectory == true {
                        return isFolderContentsNotDownloadedSync(url)
                    }
                    return false  // File is downloaded
                }
                // Status is .notDownloaded or something else - needs download
                return true
            }
            
            // If it's a folder with no status, do a quick check for undownloaded contents
            if resourceValues.isDirectory == true {
                return isFolderContentsNotDownloadedSync(url)
            }
            
            // No status available - for cloud paths, assume needs download
            return isCloudPath
        } catch {
            // On error, if it's a cloud path, assume needs download
            return isCloudPath
        }
    }
    
    /// Check folder contents for undownloaded files - synchronous, call from background only
    /// IMPORTANT: Does NOT use fileExists() to avoid triggering downloads
    private nonisolated static func isFolderContentsNotDownloadedSync(_ folderURL: URL) -> Bool {
        let fileManager = FileManager.default
        
        // Check if folder is in a cloud path
        let folderPath = folderURL.path
        let isCloudPath = folderPath.contains("/Library/Mobile Documents/") ||
                          folderPath.contains("/iCloud Drive/") ||
                          folderPath.contains("~Library/CloudStorage/") ||
                          folderPath.contains("/CloudStorage/")
        
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemIsDownloadingKey,
                .isDirectoryKey,
                .fileSizeKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            // Can't enumerate - if cloud path, assume needs download
            return isCloudPath
        }
        
        var checkedCount = 0
        let maxCheck = 100  // Limit scan for performance
        
        for case let fileURL as URL in enumerator {
            checkedCount += 1
            if checkedCount > maxCheck { break }
            
            do {
                let values = try fileURL.resourceValues(forKeys: [
                    .isUbiquitousItemKey,
                    .ubiquitousItemDownloadingStatusKey,
                    .ubiquitousItemIsDownloadingKey,
                    .isDirectoryKey,
                    .fileSizeKey
                ])
                
                // Skip directories - we only care about actual file contents
                if values.isDirectory == true {
                    continue
                }
                
                // Check if this is a cloud file (by resource value or path)
                let isUbiquitous = values.isUbiquitousItem == true || isCloudPath
                
                if isUbiquitous {
                    let status = values.ubiquitousItemDownloadingStatus
                    let isDownloading = values.ubiquitousItemIsDownloading ?? false
                    
                    // If actively downloading, not complete
                    if isDownloading {
                        return true
                    }
                    
                    // If status is .current or .downloaded, it's available
                    if let status = status {
                        if status == .current || status == .downloaded {
                            continue
                        }
                        // Status is something else (e.g., .notDownloaded) - needs download
                        return true
                    }
                    
                    // No status - check if file size is available (indicates file is downloaded)
                    if values.fileSize != nil {
                        continue
                    }
                    
                    // Otherwise, assume not downloaded
                    return true
                }
            } catch {
                // On error for cloud paths, assume needs download
                if isCloudPath {
                    return true
                }
                continue
            }
        }
        
        return false
    }
    
    // MARK: - Download Polling
    
    private enum DownloadError: LocalizedError {
        case downloadFailed(String)
        case timeout
        case cancelled
        
        var errorDescription: String? {
            switch self {
            case .downloadFailed(let reason):
                return reason
            case .timeout:
                return "Download timed out"
            case .cancelled:
                return "Download was cancelled"
            }
        }
    }
    
    /// Wait for a cloud file download to complete by polling - static version for detached tasks
    private nonisolated static func waitForDownloadStatic(at path: String, timeout: TimeInterval, pollInterval: TimeInterval) async -> Result<Void, DownloadError> {
        let url = URL(fileURLWithPath: path)
        let startTime = Date()
        
        while true {
            if Task.isCancelled {
                return .failure(.cancelled)
            }
            
            if Date().timeIntervalSince(startTime) > timeout {
                return .failure(.timeout)
            }
            
            // Check download status (we're already on background thread in detached task)
            let status = checkDownloadStatusSync(at: url)
            
            switch status {
            case .complete:
                return .success(())
            case .error(let message):
                return .failure(.downloadFailed(message))
            case .inProgress:
                break
            }
            
            try? await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }
    }
    
    /// Wait for a cloud file download with periodic re-triggering if stalled
    /// This helps recover from cases where iCloud stops downloading
    private nonisolated static func waitForDownloadWithRetrigger(
        at path: String, 
        timeout: TimeInterval, 
        pollInterval: TimeInterval,
        retriggerInterval: TimeInterval
    ) async -> Result<Void, DownloadError> {
        let url = URL(fileURLWithPath: path)
        let startTime = Date()
        var lastRetriggerTime = startTime
        
        while true {
            if Task.isCancelled {
                return .failure(.cancelled)
            }
            
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed > timeout {
                return .failure(.timeout)
            }
            
            // Check download status
            let status = checkDownloadStatusSync(at: url)
            
            switch status {
            case .complete:
                return .success(())
            case .error(let message):
                return .failure(.downloadFailed(message))
            case .inProgress:
                // Check if we should re-trigger the download
                let timeSinceRetrigger = Date().timeIntervalSince(lastRetriggerTime)
                if timeSinceRetrigger >= retriggerInterval {
                    print("[Download] Re-triggering stalled download for: \(url.lastPathComponent)")
                    startDownloadRecursively(at: url)
                    lastRetriggerTime = Date()
                }
            }
            
            try? await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }
    }
    
    private enum DownloadStatus {
        case complete
        case inProgress
        case error(String)
    }
    
    private nonisolated static func checkDownloadStatusSync(at url: URL) -> DownloadStatus {
        let path = url.path
        
        // Check if this is an iCloud path specifically (includes synced Desktop/Documents)
        let isICloudPathByLocation = path.contains("/Library/Mobile Documents/") ||
                                     path.contains("/iCloud Drive/")
        
        // Check if this is another cloud provider (OneDrive, Google Drive, Dropbox, etc.)
        let isOtherCloudPath = path.contains("/CloudStorage/")
        
        let isCloudPathByLocation = isICloudPathByLocation || isOtherCloudPath
        
        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemDownloadingErrorKey,
                .isDirectoryKey,
                .ubiquitousItemIsDownloadingKey,
                .fileSizeKey,
                .totalFileSizeKey
            ])
            
            // Determine if this is a cloud file (by resource value OR path)
            let isCloudFile = resourceValues.isUbiquitousItem == true || isCloudPathByLocation
            
            let isDirectory = resourceValues.isDirectory ?? false
            
            // For non-iCloud cloud providers (OneDrive, Google Drive, Dropbox, etc.)
            // The ubiquitous* APIs don't work. Instead, we check if we can read the file.
            // These providers download files on-demand when accessed.
            if isOtherCloudPath && resourceValues.isUbiquitousItem != true {
                if isDirectory {
                    // For directories, check if we can enumerate and read contents
                    return verifyDirectoryReadable(at: url) ? .complete : .inProgress
                } else {
                    // For files, try to read them - this may trigger download
                    return verifyFileReadable(at: url) ? .complete : .inProgress
                }
            }
            
            let status = resourceValues.ubiquitousItemDownloadingStatus
            let isCurrentlyDownloading = resourceValues.ubiquitousItemIsDownloading ?? false
            let fileSize = resourceValues.fileSize
            let totalFileSize = resourceValues.totalFileSize
            
            // If it's not a cloud file, verify we can actually read it
            if !isCloudFile {
                // For local files, verify accessibility
                if isDirectory {
                    return .complete
                }
                // Try to verify local file is readable
                if FileManager.default.isReadableFile(atPath: path) {
                    return .complete
                }
                // Can't read the file - treat as error
                return .error("File is not readable")
            }
            
            // It's an iCloud file - check for errors
            if let error = resourceValues.ubiquitousItemDownloadingError {
                return .error(error.localizedDescription)
            }
            
            // If actively downloading, it's in progress
            if isCurrentlyDownloading {
                return .inProgress
            }
            
            // Check download status - .current means fully up to date, .downloaded means available locally
            if let status = status {
                if status == .current || status == .downloaded {
                    // For folders, also check that contents are downloaded
                    if isDirectory {
                        let contentsNotDownloaded = isFolderContentsNotDownloadedSync(url)
                        if contentsNotDownloaded {
                            return .inProgress
                        }
                    } else {
                        // For files, verify by comparing fileSize with totalFileSize
                        // If they differ significantly, the file is a stub (not fully downloaded)
                        if let local = fileSize, let total = totalFileSize {
                            if total > 0 && local < total {
                                // File is a stub - not fully downloaded despite status
                                return .inProgress
                            }
                        }
                        // Also verify we can actually read the file
                        if !verifyFileReadable(at: url) {
                            return .inProgress
                        }
                    }
                    return .complete
                }
            }
            
            // For directories without clear status, check contents
            if isDirectory {
                let contentsNotDownloaded = isFolderContentsNotDownloadedSync(url)
                if !contentsNotDownloaded {
                    return .complete
                }
            }
            
            // Still in progress - either downloading or waiting
            return .inProgress
        } catch {
            // If we can't read resource values, assume in progress for cloud paths
            return isCloudPathByLocation ? .inProgress : .complete
        }
    }
    
    /// Verify a directory is readable by checking if we can enumerate its contents
    private nonisolated static func verifyDirectoryReadable(at url: URL) -> Bool {
        let fm = FileManager.default
        
        // Try to get directory contents
        guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return false
        }
        
        // For non-empty directories, verify at least one file is readable
        if contents.isEmpty {
            return true  // Empty directory is fine
        }
        
        // Check first few files
        for fileURL in contents.prefix(3) {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: fileURL.path, isDirectory: &isDir) {
                if !isDir.boolValue {
                    // It's a file - try to verify it's readable
                    if verifyFileReadable(at: fileURL) {
                        return true
                    }
                }
            }
        }
        
        // If we couldn't verify any file, assume not ready
        return contents.allSatisfy { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
    }
    
    /// Verify a file is actually readable by attempting to open it
    /// This catches cases where iCloud reports a file as downloaded but it's actually a stub
    private nonisolated static func verifyFileReadable(at url: URL) -> Bool {
        // Try to open the file for reading
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        
        // Try to read a small amount of data
        defer { try? handle.close() }
        
        do {
            // Read just 1 byte to verify file is accessible
            _ = try handle.read(upToCount: 1)
            // If we got data or file is empty (nil/empty data is ok for empty files), it's readable
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Recursive Download
    
    /// Start downloading a cloud item, recursively downloading all contents if it's a directory
    private nonisolated static func startDownloadRecursively(at url: URL) {
        let fileManager = FileManager.default
        let path = url.path
        
        // Check if this is an iCloud path specifically
        let isICloudPath = path.contains("/Library/Mobile Documents/") ||
                           path.contains("/iCloud Drive/")
        
        // Check if this is another cloud provider (OneDrive, Google Drive, Dropbox, etc.)
        let isOtherCloudPath = path.contains("/CloudStorage/")
        
        let isCloudPath = isICloudPath || isOtherCloudPath
        
        // For non-iCloud cloud providers, we can't use startDownloadingUbiquitousItem
        // Instead, accessing the file will trigger the download automatically
        if isOtherCloudPath && !isICloudPath {
            print("[Download] Non-iCloud cloud file detected, triggering download by access: \(url.lastPathComponent)")
            triggerDownloadByAccess(at: url)
            return
        }
        
        // For iCloud, use the standard API
        do {
            try fileManager.startDownloadingUbiquitousItem(at: url)
            print("[Download] Started iCloud download for: \(url.lastPathComponent)")
        } catch {
            print("[Download] Failed to start iCloud download for \(url.lastPathComponent): \(error)")
            // Continue anyway - might still be able to download contents
        }
        
        // Check if it's a directory using resource values (avoids fileExists which can trigger downloads)
        do {
            let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard resourceValues.isDirectory == true else {
                return  // Not a directory, we're done
            }
        } catch {
            // Can't determine if directory - try to enumerate anyway for cloud paths
            if !isCloudPath {
                return
            }
        }
        
        // Enumerate and download all contents
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemIsDownloadingKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            print("[Download] Failed to enumerate directory: \(url.lastPathComponent)")
            return
        }
        
        var downloadCount = 0
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [
                    .isUbiquitousItemKey,
                    .ubiquitousItemDownloadingStatusKey,
                    .ubiquitousItemIsDownloadingKey
                ])
                
                // Check if it's a cloud item (by resource value or path)
                let isUbiquitous = resourceValues.isUbiquitousItem == true || isCloudPath
                
                // Only start download if it's a cloud item that's not downloaded
                if isUbiquitous {
                    // Skip if already downloading
                    if resourceValues.ubiquitousItemIsDownloading == true {
                        continue
                    }
                    
                    let status = resourceValues.ubiquitousItemDownloadingStatus
                    if status != .current && status != .downloaded {
                        try fileManager.startDownloadingUbiquitousItem(at: fileURL)
                        downloadCount += 1
                    }
                }
            } catch {
                // Try to start download anyway for cloud paths
                if isCloudPath {
                    try? fileManager.startDownloadingUbiquitousItem(at: fileURL)
                    downloadCount += 1
                }
            }
        }
        
        if downloadCount > 0 {
            print("[Download] Started download for \(downloadCount) items in \(url.lastPathComponent)")
        }
    }
    
    /// Trigger download for non-iCloud cloud providers by accessing the file
    /// OneDrive, Google Drive, Dropbox, etc. download files on-demand when accessed
    private nonisolated static func triggerDownloadByAccess(at url: URL) {
        let fileManager = FileManager.default
        
        // Check if it's a directory
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        
        if !exists {
            print("[Download] File doesn't exist: \(url.lastPathComponent)")
            return
        }
        
        if isDirectory.boolValue {
            // For directories, enumerate and trigger download for each file
            guard let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                print("[Download] Failed to enumerate directory: \(url.lastPathComponent)")
                return
            }
            
            var triggerCount = 0
            for case let fileURL as URL in enumerator {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue {
                    // It's a file - try to open it briefly to trigger download
                    if let handle = try? FileHandle(forReadingFrom: fileURL) {
                        _ = try? handle.read(upToCount: 1)
                        try? handle.close()
                        triggerCount += 1
                    }
                }
            }
            print("[Download] Triggered download for \(triggerCount) files in \(url.lastPathComponent)")
        } else {
            // For single files, just try to open and read
            if let handle = try? FileHandle(forReadingFrom: url) {
                _ = try? handle.read(upToCount: 1)
                try? handle.close()
                print("[Download] Triggered download for file: \(url.lastPathComponent)")
            }
        }
    }
}
