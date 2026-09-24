// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import AppKit

// MARK: - Drop Delegate for Snippet Reordering

struct SnippetDropDelegate: DropDelegate {
    let snippet: Snippet
    let snippets: [Snippet]
    @Binding var draggingSnippetId: UUID?
    let onReorder: (Int, Int) -> Void
    
    func performDrop(info: DropInfo) -> Bool {
        draggingSnippetId = nil
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let dragId = draggingSnippetId,
              dragId != snippet.id,
              let fromIndex = snippets.firstIndex(where: { $0.id == dragId }),
              let toIndex = snippets.firstIndex(where: { $0.id == snippet.id }) else {
            return
        }
        
        if fromIndex != toIndex {
            withAnimation(.easeInOut(duration: 0.2)) {
                onReorder(fromIndex, toIndex > fromIndex ? toIndex + 1 : toIndex)
            }
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        return draggingSnippetId != nil
    }
}

// MARK: - Snippets Menu View

struct SnippetsMenuView: View {
    @ObservedObject var controller: MenuBarController
    @State private var searchText = ""
    @State private var useRegex = false
    @State private var hoveredSnippetId: UUID?
    @State private var draggingSnippetId: UUID?
    @FocusState private var isSearchFocused: Bool
    
    /// Access cloudDownloadService through controller to ensure proper observation
    private var cloudDownloadService: CloudDownloadService {
        controller.cloudDownloadService
    }

    var filteredSnippets: [Snippet] {
        if searchText.isEmpty {
            return controller.snippets
        }
        return controller.searchService.search(
            snippets: controller.snippets,
            query: searchText,
            useRegex: useRegex
        )
    }

    var body: some View {
        VisualEffectBackground {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Saved Snippets")
                        .font(.headline)
                    Spacer()
                
                // Settings button
                if #available(macOS 14.0, *) {
                    SettingsLink {
                        Image(systemName: "gearshape")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        openPreferences()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                // More options menu
                Menu {
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .help("More Options")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search snippets...", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onSubmit {
                        // Copy the first snippet when pressing Enter in search
                        if let firstSnippet = filteredSnippets.first {
                            PreviewWindowManager.shared.hidePreview()
                            controller.copySnippetToClipboard(firstSnippet)
                        }
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Toggle(isOn: $useRegex) {
                    Text("RegEx")
                        .font(.caption)
                }
                .toggleStyle(.button)
                .help("Use Regular Expression")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Snippets list (downloading/error snippets appear inline)
            if filteredSnippets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "star")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? "No snippets saved" : "No matching snippets")
                        .foregroundColor(.secondary)
                    if searchText.isEmpty {
                        Text("Favorite clipboard items to save them here")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            // Anchor for scrolling to top
                            Color.clear
                                .frame(height: 0)
                                .id("snippetsTop")
                            
                            ForEach(Array(filteredSnippets.enumerated()), id: \.element.id) { index, snippet in
                                SnippetItemView(
                                    snippet: snippet,
                                    isHovered: hoveredSnippetId == snippet.id,
                                    isDragging: draggingSnippetId == snippet.id,
                                    isCompact: controller.preferencesService.compactSnippetsView,
                                    thumbnailService: controller.thumbnailService,
                                    onCopy: {
                                        PreviewWindowManager.shared.hidePreview()
                                        controller.copySnippetToClipboard(snippet)
                                    },
                                    onDelete: { controller.deleteSnippet(snippet) },
                                    onRetryDownload: { controller.retrySnippetDownload(snippet) },
                                    onCancelDownload: { controller.cancelSnippetDownload(snippet) },
                                    onHoverWithFrame: { snippet, isHovering, screenY in
                                        hoveredSnippetId = isHovering ? snippet.id : nil
                                        handleSnippetPreviewHover(snippet: snippet, isHovering: isHovering, itemScreenY: screenY)
                                    },
                                    shortcutNumber: index < 9 ? index + 1 : nil,
                                    isPendingDownload: cloudDownloadService.pendingDownloadIds.contains(snippet.id)
                                )
                                // Force view update when download state changes
                                .id("\(snippet.id)-\(snippet.currentDownloadIndex)-\(snippet.isDownloading)")
                                .onDrag {
                                    draggingSnippetId = snippet.id
                                    return NSItemProvider(object: snippet.id.uuidString as NSString)
                                } preview: {
                                    Color.clear.frame(width: 1, height: 1)
                                }
                                .onDrop(of: [.text], delegate: SnippetDropDelegate(
                                    snippet: snippet,
                                    snippets: controller.snippets,
                                    draggingSnippetId: $draggingSnippetId,
                                    onReorder: { from, to in
                                        controller.moveSnippet(from: IndexSet(integer: from), to: to)
                                    }
                                ))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: controller.snippetsMenuOpenCount) {
                        proxy.scrollTo("snippetsTop", anchor: .top)
                        searchText = ""
                        isSearchFocused = true
                    }
                }
            }
        }
        }
        .frame(width: 350, height: controller.snippetsMenuHeight)
        .onAppear {
            // Focus the search box when the popup opens
            isSearchFocused = true
        }
        .task {
            // Backup focus request in case immediate one doesn't work
            try? await Task.sleep(for: .milliseconds(50))
            isSearchFocused = true
        }
        .onDisappear {
            PreviewWindowManager.shared.hidePreview()
        }
        .onKeyPress(characters: .decimalDigits) { press in
            guard let number = Int(press.characters), number >= 1 && number <= 9 else {
                return .ignored
            }
            let index = number - 1
            if index < filteredSnippets.count {
                PreviewWindowManager.shared.hidePreview()
                controller.copySnippetToClipboard(filteredSnippets[index])
                return .handled
            }
            return .ignored
        }
    }
    
    private func handleSnippetPreviewHover(snippet: Snippet, isHovering: Bool, itemScreenY: CGFloat? = nil) {
        if isHovering {
            let popoverFrame = controller.snippetsPopoverFrame
            PreviewWindowManager.shared.previewSize = CGFloat(controller.preferencesService.previewSize)
            
            PreviewWindowManager.shared.showPreview(
                for: snippet,
                thumbnailService: controller.thumbnailService,
                menuFrame: popoverFrame,
                itemY: itemScreenY
            )
        } else {
            PreviewWindowManager.shared.hidePreview(for: snippet.id)
        }
    }

}

// MARK: - Snippet Item View

struct SnippetItemView: View {
    let snippet: Snippet
    let isHovered: Bool
    var isDragging: Bool = false
    var isCompact: Bool = false
    let thumbnailService: ThumbnailService
    
    let onCopy: () -> Void
    let onDelete: () -> Void
    var onRetryDownload: (() -> Void)? = nil
    var onCancelDownload: (() -> Void)? = nil
    var onHoverWithFrame: ((Snippet, Bool, CGFloat?) -> Void)? = nil
    var shortcutNumber: Int? = nil
    /// True if this snippet is queued waiting for another download to complete
    var isPendingDownload: Bool = false
    
    private var iconSize: CGFloat { isCompact ? 22 : 32 }
    private var verticalPadding: CGFloat { isCompact ? 4 : 8 }
    private var buttonSize: CGFloat { isCompact ? 22 : 28 }

    private var hoverBackground: Color {
        isDragging ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1)
    }
    
    /// Check if snippet has a download error
    private var hasError: Bool {
        snippet.downloadError != nil
    }
    
    /// Check if snippet is in a special state (downloading or error)
    private var isSpecialState: Bool {
        snippet.isDownloading || hasError
    }
    
    /// Check if snippet is a cloud file that hasn't been downloaded
    private var isCloudNotDownloaded: Bool {
        snippet.isCloudFileNotDownloaded
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Content type icon or thumbnail (show cloud icon when downloading/error)
            if snippet.isDownloading {
                downloadingIcon
                    .frame(width: iconSize, height: iconSize)
            } else if hasError {
                errorIcon
                    .frame(width: iconSize, height: iconSize)
            } else {
                contentPreview
                    .frame(width: iconSize, height: iconSize)
            }

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.displayText)
                    .font(.system(isCompact ? .callout : .body, weight: .medium))
                    .lineLimit(1)
                
                // Show status for downloading/error/cloud states
                if snippet.isDownloading {
                    HStack(spacing: 4) {
                        Image(systemName: "icloud")
                            .font(.caption)
                            .foregroundColor(.orange)
                        if isPendingDownload {
                            // Queued, waiting for another download to complete
                            Text("Waiting to download...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            // Actively downloading
                            ProgressView()
                                .controlSize(.mini)
                            if let cloudName = snippet.cloudServiceName {
                                Text("Downloading from \(cloudName)...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Copying Large \(snippet.downloadFileCount == 1 ? "File" : "Files")...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } else if let error = snippet.downloadError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(1)
                } else if isCloudNotDownloaded {
                    HStack(spacing: 4) {
                        Image(systemName: "icloud")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("File in iCloud - not downloaded")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
            
            // Action buttons
            if snippet.isDownloading {
                // Cancel button for downloading snippets
                Button(action: { onCancelDownload?() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(isCompact ? .caption : .body)
                        .frame(width: buttonSize, height: buttonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Cancel download")
            } else if hasError && isHovered {
                // Retry and delete buttons for error state
                HStack(spacing: 2) {
                    Button(action: { onRetryDownload?() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(isCompact ? .caption : .body)
                            .frame(width: buttonSize, height: buttonSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .help("Retry download")
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(isCompact ? .caption : .body)
                            .frame(width: buttonSize, height: buttonSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                    .help("Delete snippet")
                }
            } else if isHovered && !isDragging {
                // Normal delete button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(isCompact ? .caption : .body)
                        .frame(width: buttonSize, height: buttonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
            } else if let number = shortcutNumber, !isSpecialState {
                // Show shortcut number in circle badge when not hovered (only for normal snippets)
                Text("\(number)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, verticalPadding)
        .frame(minHeight: iconSize + (verticalPadding * 2))
        .background(backgroundForState)
        .contentShape(Rectangle())
        .overlay(
            HoverTrackingView { hovering, screenFrame in
                // Don't show preview for downloading/error snippets
                if snippet.needsPreview && !isSpecialState {
                    let centerY = screenFrame.midY
                    onHoverWithFrame?(snippet, hovering, hovering ? centerY : nil)
                } else {
                    onHoverWithFrame?(snippet, hovering, nil)
                }
            }
        )
        .onTapGesture {
            // Only allow copy for completed snippets
            if !isSpecialState {
                onCopy()
            }
        }
    }
    
    private var backgroundForState: Color {
        if snippet.isDownloading {
            return Color.accentColor.opacity(0.1)
        } else if hasError {
            return Color.red.opacity(0.1)
        } else if isDragging || isHovered {
            return hoverBackground
        }
        return Color.clear
    }
    
    @ViewBuilder
    private var downloadingIcon: some View {
        let cornerRadius: CGFloat = isCompact ? 3 : 4
        
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.secondary.opacity(0.2))
            
            Image(systemName: "icloud.and.arrow.down")
                .font(isCompact ? .caption : .body)
                .foregroundColor(.accentColor)
        }
    }
    
    @ViewBuilder
    private var errorIcon: some View {
        let cornerRadius: CGFloat = isCompact ? 3 : 4
        
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.red.opacity(0.2))
            
            Image(systemName: "exclamationmark.icloud")
                .font(isCompact ? .caption : .body)
                .foregroundColor(.red)
        }
    }

    @ViewBuilder
    private var contentPreview: some View {
        let cornerRadius: CGFloat = isCompact ? 3 : 4
        let iconFont: Font = isCompact ? .caption : .body
        
        switch snippet.contentType {
        case .text, .richText:
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.secondary.opacity(0.2))
                .overlay(
                    Image(systemName: snippet.contentType.systemImageName)
                        .font(iconFont)
                        .foregroundColor(.secondary)
                )

        case .image, .video:
            if let thumbnailPath = snippet.thumbnailPath,
               let image = NSImage(contentsOfFile: thumbnailPath) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.secondary.opacity(0.2))
                    .overlay(
                        Image(systemName: snippet.contentType.systemImageName)
                            .font(iconFont)
                            .foregroundColor(.secondary)
                    )
            }

        case .file:
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.secondary.opacity(0.2))
                .overlay(
                    Image(systemName: snippet.fileSystemImageName)
                        .font(iconFont)
                        .foregroundColor(.secondary)
                )
        
        case .fileStack:
            if let paths = snippet.mediaPaths, !paths.isEmpty {
                FileStackIconsView(paths: paths, size: iconSize)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.secondary.opacity(0.2))
                    .overlay(
                        Image(systemName: "doc.on.doc")
                            .font(iconFont)
                            .foregroundColor(.secondary)
                    )
            }
        }
    }
}


