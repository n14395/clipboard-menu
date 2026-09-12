import AppKit
import SwiftUI

// MARK: - Rich Text Preview View

struct RichTextPreviewView: View {
    let attributedString: NSAttributedString
    let size: NSSize

    var body: some View {
        RichTextDocumentView(attributedString: attributedString)
            .frame(width: size.width, height: size.height)
    }
}

// MARK: - Rich Text Document View

/// Renders RTF with its original formatting. Any foreground colour that would be
/// unreadable against the popover behind it is swapped for one that isn't - word
/// processors write explicit black text into RTF, which vanishes against the
/// dark mode popover.
struct RichTextDocumentView: NSViewRepresentable {
    let attributedString: NSAttributedString

    private static let contentInset = NSSize(width: 12, height: 12)
    private static let minimumContrastRatio: CGFloat = 3.0

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = Self.contentInset
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let legible = Self.makeLegible(attributedString, in: scrollView.effectiveAppearance)
        textView.textStorage?.setAttributedString(legible)
    }

    // MARK: - Legibility

    /// Returns a copy of `source` whose text colours all meet a minimum contrast
    /// against the surface they will be drawn on.
    static func makeLegible(_ source: NSAttributedString, in appearance: NSAppearance) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: source)

        appearance.performAsCurrentDrawingAppearance {
            let surface = NSColor.windowBackgroundColor
            let defaultForeground = NSColor.labelColor
            let fullRange = NSRange(location: 0, length: result.length)

            result.enumerateAttributes(in: fullRange) { attributes, range, _ in
                let highlight = attributes[.backgroundColor] as? NSColor
                let background = isVisible(highlight) ? highlight! : surface

                guard let foreground = attributes[.foregroundColor] as? NSColor else {
                    // No explicit colour - pin it to the label colour so it tracks the appearance
                    result.addAttribute(.foregroundColor, value: defaultForeground, range: range)
                    return
                }

                guard contrastRatio(foreground, background) < minimumContrastRatio else { return }

                let replacement = isVisible(highlight)
                    ? (relativeLuminance(background) > 0.5 ? NSColor.black : NSColor.white)
                    : defaultForeground
                result.addAttribute(.foregroundColor, value: replacement, range: range)
            }
        }

        return result
    }

    private static func isVisible(_ color: NSColor?) -> Bool {
        guard let color = color else { return false }
        return (color.usingColorSpace(.sRGB)?.alphaComponent ?? 0) > 0.05
    }

    /// WCAG relative luminance, used to compare colours regardless of hue.
    private static func relativeLuminance(_ color: NSColor) -> CGFloat {
        guard let rgb = color.usingColorSpace(.sRGB) else { return 0.5 }
        func linear(_ component: CGFloat) -> CGFloat {
            component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.redComponent)
            + 0.7152 * linear(rgb.greenComponent)
            + 0.0722 * linear(rgb.blueComponent)
    }

    private static func contrastRatio(_ first: NSColor, _ second: NSColor) -> CGFloat {
        let a = relativeLuminance(first)
        let b = relativeLuminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
