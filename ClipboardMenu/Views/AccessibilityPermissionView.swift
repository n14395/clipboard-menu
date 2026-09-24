// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// A sheet that confirms enabling global shortcuts
/// Note: Using Carbon RegisterEventHotKey API, no accessibility permission is needed
struct AccessibilityPermissionView: View {
    @Binding var isPresented: Bool
    var onPermissionGranted: () -> Void
    var onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Icon
            Image(systemName: "keyboard")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            
            // Title
            Text("Enable Global Shortcuts")
                .font(.headline)
            
            // Description
            Text("Global keyboard shortcuts let you quickly access your clipboard history and snippets from any app.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            // Shortcuts info
            VStack(alignment: .leading, spacing: 12) {
                shortcutRow(
                    shortcut: KeyboardShortcut.defaultHistory.displayString,
                    description: "Open clipboard history"
                )
                shortcutRow(
                    shortcut: KeyboardShortcut.defaultSnippets.displayString,
                    description: "Open snippets"
                )
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            Text("You can customize these shortcuts in Preferences.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Enable Shortcuts") {
                    onPermissionGranted()
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
    
    private func shortcutRow(shortcut: String, description: String) -> some View {
        HStack {
            Text(shortcut)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.tertiaryLabelColor).opacity(0.2))
                .cornerRadius(4)
            
            Text(description)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    AccessibilityPermissionView(
        isPresented: .constant(true),
        onPermissionGranted: {},
        onCancel: {}
    )
}
