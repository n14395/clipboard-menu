// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import AppKit

/// A view that captures keyboard shortcuts from user input
struct ShortcutRecorderView: View {
    @Binding var shortcut: KeyboardShortcut
    
    @State private var isRecording = false
    @State private var displayText: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack {
            Text(isRecording ? "Press shortcut..." : shortcut.displayString)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(isRecording ? .secondary : .primary)
                .frame(minWidth: 80, alignment: .leading)
            
            Spacer()
            
            if isRecording {
                Button("Cancel") {
                    isRecording = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            } else {
                Button("Record") {
                    isRecording = true
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isRecording ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isRecording ? Color.accentColor : Color(NSColor.separatorColor), lineWidth: 1)
        )
        .background(
            ShortcutRecorderKeyHandler(
                isRecording: $isRecording,
                onShortcutRecorded: { newShortcut in
                    // Defer to avoid "Publishing changes from within view updates"
                    DispatchQueue.main.async {
                        shortcut = newShortcut
                        isRecording = false
                    }
                }
            )
        )
    }
}

/// NSViewRepresentable that handles key events for shortcut recording
struct ShortcutRecorderKeyHandler: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onShortcutRecorded: (KeyboardShortcut) -> Void
    
    func makeNSView(context: Context) -> ShortcutRecorderKeyView {
        let view = ShortcutRecorderKeyView()
        view.onShortcutRecorded = onShortcutRecorded
        return view
    }
    
    func updateNSView(_ nsView: ShortcutRecorderKeyView, context: Context) {
        nsView.isRecording = isRecording
        nsView.onShortcutRecorded = onShortcutRecorded
        
        if isRecording {
            // Make this view the first responder to capture key events
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

/// Custom NSView that can become first responder and capture key events
class ShortcutRecorderKeyView: NSView {
    var isRecording: Bool = false
    var onShortcutRecorded: ((KeyboardShortcut) -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        
        // Escape cancels recording
        if event.keyCode == 53 { // Escape key
            isRecording = false
            return
        }
        
        // Create shortcut from event
        if let shortcut = KeyboardShortcut(event: event) {
            onShortcutRecorded?(shortcut)
        }
    }
    
    override func flagsChanged(with event: NSEvent) {
        // Don't process modifier-only key presses
        super.flagsChanged(with: event)
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var shortcut = KeyboardShortcut.defaultHistory
        
        var body: some View {
            VStack(spacing: 20) {
                ShortcutRecorderView(shortcut: $shortcut)
                    .frame(width: 200)
                
                Text("Current: \(shortcut.displayString)")
            }
            .padding()
        }
    }
    
    return PreviewWrapper()
}
