import SwiftUI
import AppKit

// MARK: - Color Extension for Light/Dark Mode

extension Color {
    /// Creates a color that uses different values for light and dark mode
    init(light: Color, dark: Color) {
        self.init(NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor(dark) : NSColor(light)
        }))
    }
}

// MARK: - Hover Tracking View

struct HoverTrackingView: NSViewRepresentable {
    let onHover: (Bool, CGRect) -> Void
    
    func makeNSView(context: Context) -> HoverTrackingNSView {
        let view = HoverTrackingNSView()
        view.onHover = onHover
        return view
    }
    
    func updateNSView(_ nsView: HoverTrackingNSView, context: Context) {
        nsView.onHover = onHover
    }
}

class HoverTrackingNSView: NSView {
    var onHover: ((Bool, CGRect) -> Void)?
    private var trackingArea: NSTrackingArea?
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let newArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newArea)
        trackingArea = newArea
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if let windowFrame = window?.frame {
            // Convert view frame to screen coordinates
            let viewFrameInWindow = convert(bounds, to: nil)
            let screenFrame = NSRect(
                x: windowFrame.origin.x + viewFrameInWindow.origin.x,
                y: windowFrame.origin.y + viewFrameInWindow.origin.y,
                width: viewFrameInWindow.width,
                height: viewFrameInWindow.height
            )
            onHover?(true, screenFrame)
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(false, .zero)
    }
    
    // Allow clicks to pass through to underlying SwiftUI views
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

// MARK: - File Stack Icons View

struct FileStackIconsView: View {
    let paths: [String]
    let size: CGFloat
    var downloadedPaths: Set<String> = []  // Paths known to be downloaded this session
    var isCloudNotDownloaded: Bool = false  // Pre-computed cloud status from parent
    
    private let maxIcons = 3
    private let iconOverlap: CGFloat = 0.4  // 40% overlap
    
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "webp"
    ]
    
    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "json", "xml", "html", "htm", "css", "js", "ts",
        "swift", "py", "rb", "java", "c", "cpp", "h", "hpp", "m", "mm",
        "sh", "bash", "zsh", "fish", "yaml", "yml", "toml", "ini", "cfg", "conf",
        "log", "csv", "tsv", "sql", "rs", "go", "php", "pl", "r", "lua"
    ]
    
    var body: some View {
        let displayPaths = Array(paths.prefix(maxIcons))
        let hasMore = paths.count > maxIcons
        
        let stackBackgroundColor = Color(light: Color(white: 0.78), dark: Color(white: 0.22))
        
        ZStack(alignment: .bottomTrailing) {
            // Single rounded background like single file icons
            // Use opaque colors to match the single file icon appearance
            RoundedRectangle(cornerRadius: 4)
                .fill(stackBackgroundColor)
                .frame(width: size, height: size)
            
            // Stacked file icons overlaid on the background
            // Each icon gets an opaque background to prevent ghosting when overlapped
            HStack(spacing: -(size * iconOverlap)) {
                ForEach(Array(displayPaths.enumerated()), id: \.offset) { index, path in
                    filePreview(for: path)
                        .frame(width: size * 0.5, height: size * 0.6)
                        .background(stackBackgroundColor)
                }
            }
            .frame(width: size, height: size, alignment: .center)
            
            // "+" badge if more than 3 files
            if hasMore {
                Text("+")
                    .font(.system(size: size * 0.3, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: size * 0.4, height: size * 0.4)
                    .background(Color.accentColor)
                    .clipShape(Circle())
                    .offset(x: 2, y: 2)
            }
        }
    }
    
    @ViewBuilder
    private func filePreview(for path: String) -> some View {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        
        // Use pre-computed cloud status from parent to avoid repeated file system checks
        // If cloud file not downloaded, show placeholder without touching file system (avoid triggering downloads)
        if isCloudNotDownloaded && !downloadedPaths.contains(path) {
            // Cloud file not downloaded - show blank file icon with cloud overlay
            ZStack {
                Image(systemName: "doc")
                    .font(.system(size: size * 0.5))
                    .foregroundColor(.secondary)
                
                Image(systemName: "icloud")
                    .font(.system(size: size * 0.25, weight: .semibold))
                    .foregroundColor(.orange)
                    .offset(y: size * 0.1)
            }
        } else if Self.imageExtensions.contains(ext) {
            // Image file - only load if path is in app storage (not a file reference)
            if path.contains("ClipboardMenu"), let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // File reference - show icon without loading file
                Image(systemName: "photo")
                    .font(.system(size: size * 0.4))
                    .foregroundColor(.secondary)
            }
        } else if Self.textExtensions.contains(ext) {
            // Text file - only load preview if path is in app storage
            if path.contains("ClipboardMenu"), let preview = textPreview(for: path) {
                ZStack {
                    Color(NSColor.textBackgroundColor)
                    Text(preview)
                        .font(.system(size: 4, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.7))
                        .lineLimit(nil)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(2)
                }
            } else {
                // File reference or text preview unavailable - show icon without loading file
                Image(systemName: "doc.text")
                    .font(.system(size: size * 0.4))
                    .foregroundColor(.secondary)
            }
        } else {
            // Other files - show generic icon based on extension (no file system access)
            Image(systemName: iconName(for: ext))
                .font(.system(size: size * 0.4))
                .foregroundColor(.secondary)
        }
    }
    
    private func iconName(for ext: String) -> String {
        switch ext {
        case "pdf": return "doc.richtext"
        case "zip", "tar", "gz", "rar", "7z": return "doc.zipper"
        case "app": return "app"
        case "dmg": return "externaldrive"
        case "mp3", "wav", "aac", "m4a", "flac": return "music.note"
        case "mp4", "mov", "m4v", "avi", "mkv": return "film"
        case "": return "folder"  // No extension typically means folder
        default: return "doc"
        }
    }
    
    private func textPreview(for path: String) -> String? {
        // Don't try to read cloud files that aren't downloaded (use parent's cached status)
        guard !isCloudNotDownloaded || downloadedPaths.contains(path),
              let data = FileManager.default.contents(atPath: path),
              data.count < 10000,  // Only read small files
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return String(text.prefix(200))
    }
}

// MARK: - Clipboard Item View

struct ClipboardItemView: View {
    let item: ClipboardItem
    let isHovered: Bool
    var isDragging: Bool = false
    let isCompact: Bool
    let thumbnailService: ThumbnailService
    var downloadedPaths: Set<String> = []  // Paths known to be downloaded this session
    let onCopy: () -> Void
    let onFavorite: () -> Void
    let onDelete: () -> Void
    var onHoverWithFrame: ((ClipboardItem, Bool, CGFloat?) -> Void)? = nil
    var shortcutNumber: Int? = nil
    /// Cached cloud status from async computation (nil = still loading, use loading indicator)
    var cachedCloudStatus: Bool? = nil
    /// Whether cloud status is currently being computed (show loading indicator)
    var isComputingCloudStatus: Bool = false
    /// Whether size is currently being calculated for starring this item
    var isCalculatingSizeForStarring: Bool = false
    
    private var iconSize: CGFloat { isCompact ? 22 : 32 }
    private var verticalPadding: CGFloat { isCompact ? 4 : 8 }
    private var buttonSize: CGFloat { isCompact ? 22 : 28 }

    var body: some View {
        // Use cached cloud status if available, otherwise show loading state for file references
        // Non-file-references are never cloud files, so default to false for them
        let isCloudNotDownloaded = cachedCloudStatus ?? false
        let showCloudLoadingIndicator = item.isFileReference && isComputingCloudStatus && cachedCloudStatus == nil
        
        // Debug: log cloud status for file references
        let _ = {
            if item.isFileReference {
                print("[ClipboardItemView] Item \(item.id): isFileReference=true, cachedCloudStatus=\(String(describing: cachedCloudStatus)), isCloudNotDownloaded=\(isCloudNotDownloaded), isCompact=\(isCompact)")
            }
        }()
        
        return HStack(spacing: 8) {
            // Content type icon or thumbnail
            contentPreview(isCloudNotDownloaded: isCloudNotDownloaded)
                .frame(width: iconSize, height: iconSize)
            
            // Link and cloud icons for file references in compact mode (between icon and text)
            if isCompact && (item.isFileReference || isCloudNotDownloaded || showCloudLoadingIndicator) {
                HStack(spacing: 2) {
                    if item.isFileReference {
                        Image(systemName: "link")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .help("File reference - original file required")
                    }
                    if showCloudLoadingIndicator {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                            .help("Checking cloud status...")
                    } else if isCloudNotDownloaded {
                        Image(systemName: "icloud")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .help("File is in iCloud - not downloaded")
                    }
                }
            }

            // Content
            if isCompact {
                if isCalculatingSizeForStarring {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.displayText)
                            .font(.system(.body))
                            .lineLimit(1)
                        Text(isCloudNotDownloaded ? "Checking Cloud Item Size" : "Checking Large File Size")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text(item.displayText)
                        .font(.system(.body))
                        .lineLimit(1)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayText)
                        .font(.system(.body))
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        if isCalculatingSizeForStarring {
                            Text(isCloudNotDownloaded ? "Checking Cloud Item Size" : "Checking Large File Size")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            if let sourceApp = item.sourceApp {
                                Text(sourceApp)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("•")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Text(item.formattedDate)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        // Link and cloud icons together at the end
                        if item.isFileReference || isCloudNotDownloaded || showCloudLoadingIndicator {
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            if item.isFileReference {
                                Image(systemName: "link")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                    .help("File reference - original file required")
                            }
                            if showCloudLoadingIndicator {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(width: 12, height: 12)
                                    .help("Checking cloud status...")
                            } else if isCloudNotDownloaded {
                                Image(systemName: "icloud")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                    .help("File is in iCloud - not downloaded")
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)
            
            // Action buttons - show when hovered OR when calculating size
            if isHovered || isCalculatingSizeForStarring {
                HStack(spacing: 2) {
                    if isCalculatingSizeForStarring {
                        // Show spinner while calculating size
                        ProgressView()
                            .controlSize(isCompact ? .mini : .small)
                            .frame(width: buttonSize, height: buttonSize)
                            .help("Calculating size...")
                    } else {
                        Button(action: onFavorite) {
                            Image(systemName: "star")
                                .font(isCompact ? .caption : .body)
                                .frame(width: buttonSize, height: buttonSize)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .help("Add to Snippets")
                    }

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(isCompact ? .caption : .body)
                            .frame(width: buttonSize, height: buttonSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                    .help("Delete")
                    .disabled(isCalculatingSizeForStarring)
                    .opacity(isCalculatingSizeForStarring ? 0.5 : 1.0)
                }
            } else if let number = shortcutNumber {
                // Show shortcut number in circle badge when not hovered
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
        .background(isHovered ? Color.secondary.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .opacity(isDragging ? 0.5 : 1.0)
        .overlay(
            HoverTrackingView { hovering, screenFrame in
                if item.needsPreview {
                    // screenFrame is in AppKit coordinates (Y=0 at bottom)
                    let centerY = screenFrame.midY
                    onHoverWithFrame?(item, hovering, hovering ? centerY : nil)
                } else {
                    onHoverWithFrame?(item, hovering, nil)
                }
            }
        )
        .onTapGesture {
            onCopy()
        }
    }

    @ViewBuilder
    private func contentPreview(isCloudNotDownloaded: Bool) -> some View {
        let cornerRadius: CGFloat = isCompact ? 3 : 4
        let iconFont: Font = isCompact ? .caption : .body
        
        switch item.contentType {
        case .text, .richText:
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.secondary.opacity(0.2))
                .overlay(
                    Image(systemName: item.contentType.systemImageName)
                        .font(iconFont)
                        .foregroundColor(.secondary)
                )

        case .image:
            if let thumbnailPath = item.thumbnailPath,
               let image = NSImage(contentsOfFile: thumbnailPath) {
                // Thumbnail is always in app storage, safe to load
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else if !item.isFileReference,
                      let mediaPath = item.mediaPath,
                      let image = NSImage(contentsOfFile: mediaPath) {
                // Only load from mediaPath if it's in app storage (not a file reference)
                // File references might be cloud files that would trigger downloads
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else if isCloudNotDownloaded {
                // Cloud file not downloaded - show cloud icon
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.secondary.opacity(0.2))
                    .overlay(
                        Image(systemName: "icloud")
                            .font(iconFont)
                            .foregroundColor(.orange)
                    )
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.secondary.opacity(0.2))
                    .overlay(
                        Image(systemName: "photo")
                            .font(iconFont)
                            .foregroundColor(.secondary)
                    )
            }

        case .video:
            ZStack {
                if let thumbnailPath = item.thumbnailPath,
                   let image = NSImage(contentsOfFile: thumbnailPath) {
                    // Thumbnail is always in app storage, safe to load
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: iconSize, height: iconSize)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                } else if isCloudNotDownloaded {
                    // Cloud file not downloaded - show cloud icon
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.secondary.opacity(0.2))
                        .overlay(
                            Image(systemName: "icloud")
                                .font(iconFont)
                                .foregroundColor(.orange)
                        )
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.secondary.opacity(0.2))
                }

                if !isCloudNotDownloaded {
                    Image(systemName: "play.fill")
                        .font(isCompact ? .system(size: 6) : .caption2)
                        .foregroundColor(.white)
                        .padding(isCompact ? 2 : 4)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
            }

        case .file:
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.secondary.opacity(0.2))
                .overlay(
                    Image(systemName: item.fileSystemImageName)
                        .font(iconFont)
                        .foregroundColor(.secondary)
                )
        
        case .fileStack:
            if let paths = item.mediaPaths, !paths.isEmpty {
                FileStackIconsView(paths: paths, size: iconSize, downloadedPaths: downloadedPaths, isCloudNotDownloaded: isCloudNotDownloaded)
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
