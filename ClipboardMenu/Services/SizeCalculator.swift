// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Combine

/// Calculates the size of a ClipboardItem asynchronously, reporting progress incrementally
/// Supports cancellation and notifies when the size exceeds a specified limit
@MainActor
class SizeCalculator: ObservableObject {
    @Published private(set) var currentSize: Int64 = 0
    @Published private(set) var isCalculating = false
    @Published private(set) var exceedsLimit = false
    @Published private(set) var isComplete = false
    
    /// Whether we're calculating size for a cloud file (affects messaging)
    @Published private(set) var isCloudFile = false
    
    private var calculationTask: Task<Void, Never>?
    private var limit: Int64 = 0
    
    /// Start calculating the size of an item
    /// - Parameters:
    ///   - item: The clipboard item to calculate size for
    ///   - limit: The size limit in bytes - exceedsLimit will be set to true if exceeded
    ///   - includeCloudFiles: If true, include cloud file sizes even if not downloaded (for pre-download warnings)
    func startCalculation(for item: ClipboardItem, limit: Int64, includeCloudFiles: Bool = false) {
        cancel()
        
        self.limit = limit
        self.currentSize = 0
        self.isCalculating = true
        self.exceedsLimit = false
        self.isComplete = false
        self.isCloudFile = includeCloudFiles
        
        calculationTask = Task { [weak self] in
            guard let self = self else { return }
            
            // First add text/richText sizes (instant)
            if let text = item.textContent {
                self.addSize(Int64(text.utf8.count))
            }
            if let richData = item.richTextData {
                self.addSize(Int64(richData.count))
            }
            
            // Calculate media path size (may be slow for folders)
            if let mediaPath = item.mediaPath {
                await self.calculatePathSizeAsync(mediaPath, includeCloudFiles: includeCloudFiles)
            }
            
            // Calculate file stack paths
            if let paths = item.mediaPaths {
                for path in paths {
                    guard !Task.isCancelled else { break }
                    await self.calculatePathSizeAsync(path, includeCloudFiles: includeCloudFiles)
                }
            }
            
            if !Task.isCancelled {
                self.isCalculating = false
                self.isComplete = true
            }
        }
    }
    
    /// Cancel the current calculation
    func cancel() {
        calculationTask?.cancel()
        calculationTask = nil
        isCalculating = false
    }
    
    /// Reset state for reuse
    func reset() {
        cancel()
        currentSize = 0
        exceedsLimit = false
        isComplete = false
        isCloudFile = false
    }
    
    private func addSize(_ size: Int64) {
        currentSize += size
        checkLimit()
    }
    
    private func checkLimit() {
        if currentSize > limit && !exceedsLimit {
            exceedsLimit = true
        }
    }
    
    private func calculatePathSizeAsync(_ path: String, includeCloudFiles: Bool = false) async {
        let url = URL(fileURLWithPath: path)
        
        // Use resource values instead of fileExists to avoid triggering iCloud downloads
        do {
            let keys: Set<URLResourceKey> = [
                .isDirectoryKey,
                .fileSizeKey,
                .totalFileSizeKey,
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey
            ]
            
            let resourceValues = try url.resourceValues(forKeys: keys)
            
            let isCloudItem = resourceValues.isUbiquitousItem == true
            var isDownloaded = true
            
            // Check if this is a cloud file that's not downloaded
            if isCloudItem {
                if let status = resourceValues.ubiquitousItemDownloadingStatus {
                    isDownloaded = (status == .current || status == .downloaded)
                }
            }
            
            // Skip cloud files unless we're explicitly including them
            if isCloudItem && !isDownloaded && !includeCloudFiles {
                return
            }
            
            let isDirectory = resourceValues.isDirectory ?? false
            
            if isDirectory {
                // Stream files incrementally from background thread
                for await size in enumerateFileSizesAsync(in: url, includeCloudFiles: includeCloudFiles) {
                    guard !Task.isCancelled else { break }
                    addSize(size)
                }
            } else {
                // For cloud files not downloaded, use totalFileSize which includes expected size
                // For downloaded files, use fileSize
                let size: Int64
                if isCloudItem && !isDownloaded {
                    // totalFileSize gives the expected size of the file when fully downloaded
                    size = Int64(resourceValues.totalFileSize ?? resourceValues.fileSize ?? 0)
                } else {
                    size = Int64(resourceValues.fileSize ?? 0)
                }
                addSize(size)
            }
        } catch {
            // If we can't read resource values, skip this path
            return
        }
    }
    
    /// Enumerate file sizes in a directory asynchronously, streaming results as they're found
    /// Runs enumeration on a background thread to avoid blocking the main thread
    /// - Parameters:
    ///   - url: The directory URL to enumerate
    ///   - includeCloudFiles: If true, include sizes for cloud files even if not downloaded
    private nonisolated func enumerateFileSizesAsync(in url: URL, includeCloudFiles: Bool = false) -> AsyncStream<Int64> {
        AsyncStream { continuation in
            // Use DispatchQueue to run enumeration on background thread (not async context)
            DispatchQueue.global(qos: .userInitiated).async {
                let fileManager = FileManager.default
                
                guard let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: [
                        .fileSizeKey,
                        .totalFileSizeKey,
                        .isDirectoryKey,
                        .isUbiquitousItemKey,
                        .ubiquitousItemDownloadingStatusKey
                    ],
                    options: [.skipsHiddenFiles]
                ) else {
                    continuation.finish()
                    return
                }
                
                for case let fileURL as URL in enumerator {
                    // Get file properties
                    guard let resourceValues = try? fileURL.resourceValues(forKeys: [
                        .fileSizeKey,
                        .totalFileSizeKey,
                        .isDirectoryKey,
                        .isUbiquitousItemKey,
                        .ubiquitousItemDownloadingStatusKey
                    ]) else {
                        continue
                    }
                    
                    // Skip directories
                    if resourceValues.isDirectory == true {
                        continue
                    }
                    
                    let isCloudItem = resourceValues.isUbiquitousItem == true
                    var isDownloaded = true
                    
                    // Check cloud file download status
                    if isCloudItem {
                        if let status = resourceValues.ubiquitousItemDownloadingStatus {
                            isDownloaded = (status == .current || status == .downloaded)
                        }
                    }
                    
                    // Skip cloud files that aren't downloaded unless we're including them
                    if isCloudItem && !isDownloaded && !includeCloudFiles {
                        continue
                    }
                    
                    // Yield file size - use totalFileSize for cloud files, fileSize otherwise
                    let fileSize: Int64
                    if isCloudItem && !isDownloaded {
                        fileSize = Int64(resourceValues.totalFileSize ?? resourceValues.fileSize ?? 0)
                    } else {
                        fileSize = Int64(resourceValues.fileSize ?? 0)
                    }
                    
                    if fileSize > 0 {
                        continuation.yield(fileSize)
                    }
                }
                
                continuation.finish()
            }
        }
    }
}
