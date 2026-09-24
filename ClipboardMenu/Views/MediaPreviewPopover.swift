// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import AppKit

struct MediaPreviewPopover: View {
    let mediaPath: String?
    let contentType: ContentType
    let thumbnailService: ThumbnailService
    var maxPreviewSize: CGFloat = 500
    var previewSize: NSSize?  // Calculated size for the content
    var thumbnailPath: String?  // Pre-generated thumbnail/screenshot path (used for videos)
    var filename: String?  // Original filename to display below preview

    @State private var previewImage: NSImage?
    @State private var isCloudFile: Bool = false
    
    private let minPreviewWidth: CGFloat = 150
    private let filenameAreaHeight: CGFloat = 40  // Space reserved for filename (must match HistoryMenuView)
    
    /// Check if a path is a cloud file that isn't downloaded (without triggering download)
    private func checkIsCloudFileNotDownloaded(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey
            ])
            
            guard resourceValues.isUbiquitousItem == true else {
                return false
            }
            
            if let status = resourceValues.ubiquitousItemDownloadingStatus {
                return status == .notDownloaded
            }
            
            return false
        } catch {
            return false
        }
    }
    
    // Content dimensions (excluding padding and filename area)
    private var contentWidth: CGFloat {
        if let size = previewSize {
            return max(size.width - 16, minPreviewWidth)  // Remove padding, enforce minimum
        }
        return maxPreviewSize
    }
    
    private var imageHeight: CGFloat {
        if let size = previewSize {
            // Remove padding (16) and filename area (40) from total height
            let hasFilename = filename != nil && !filename!.isEmpty
            let filenameSpace = hasFilename ? filenameAreaHeight : 0
            return size.height - 16 - filenameSpace
        }
        return maxPreviewSize
    }

    var body: some View {
        VStack(spacing: 8) {
            Group {
                switch contentType {
                case .image:
                    imagePreview
                case .video:
                    videoPreview
                default:
                    EmptyView()
                }
            }
            .frame(width: contentWidth, height: imageHeight)
            
            if let name = filename, !name.isEmpty {
                Text(name)
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.8))
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: contentWidth)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .onAppear {
            loadPreview()
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if isCloudFile {
            // Cloud file not downloaded - show placeholder with cloud icon
            cloudFilePlaceholder(icon: "photo.fill")
        } else if let image = previewImage {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: contentWidth, height: imageHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            ProgressView()
                .frame(width: contentWidth, height: imageHeight)
        }
    }

    @ViewBuilder
    private var videoPreview: some View {
        if isCloudFile {
            // Cloud file not downloaded - show placeholder with cloud icon
            cloudFilePlaceholder(icon: "video.fill")
        } else if let image = previewImage {
            // Show video thumbnail with play icon overlay
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: contentWidth, height: imageHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                )
        } else {
            // Generic video icon placeholder when thumbnail fails
            VStack(spacing: 8) {
                Image(systemName: "video.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("Video")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: contentWidth, height: imageHeight)
        }
    }
    
    @ViewBuilder
    private func cloudFilePlaceholder(icon: String) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Image(systemName: "doc")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)
                
                Image(systemName: "icloud")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.secondary)
                    .offset(y: 8)
            }
            
            Text("In iCloud")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: contentWidth, height: imageHeight)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func loadPreview() {
        guard let path = mediaPath else { return }
        
        // Check if this is a cloud file that isn't downloaded
        if checkIsCloudFileNotDownloaded(path) {
            isCloudFile = true
            return  // Don't try to load the file
        }

        switch contentType {
        case .image:
            // Load preview-sized image
            if let image = thumbnailService.generatePreviewImage(from: path, maxSize: maxPreviewSize) {
                previewImage = image
            } else if let image = NSImage(contentsOfFile: path) {
                previewImage = image
            }

        case .video:
            // Load pre-generated video screenshot from thumbnailPath
            // Screenshots are generated at copy time; if none exists, show placeholder
            if let thumbPath = thumbnailPath,
               let image = NSImage(contentsOfFile: thumbPath) {
                previewImage = image
            }

        default:
            break
        }
    }
}
