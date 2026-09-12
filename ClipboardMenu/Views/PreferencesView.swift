import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var preferencesService: PreferencesService
    @EnvironmentObject var storageService: StorageService

    var body: some View {
        TabView {
            GeneralPreferencesView()
                .environmentObject(preferencesService)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            DisplayPreferencesView()
                .environmentObject(preferencesService)
                .environmentObject(storageService)
                .tabItem {
                    Label("Display", systemImage: "rectangle.on.rectangle")
                }

            KeyboardShortcutsPreferencesView()
                .environmentObject(preferencesService)
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            StoragePreferencesView()
                .environmentObject(preferencesService)
                .environmentObject(storageService)
                .tabItem {
                    Label("Storage", systemImage: "internaldrive")
                }
        }
        .frame(width: 480, height: 420)
    }
}

struct GeneralPreferencesView: View {
    @EnvironmentObject var preferencesService: PreferencesService
    
    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $preferencesService.launchAtLogin)

                Picker("Snippets Menu", selection: $preferencesService.snippetsMenuMode) {
                    ForEach(SnippetsMenuMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Button("Reset to Defaults") {
                    showResetConfirmation = true
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Reset to Defaults?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                preferencesService.resetToDefaults()
            }
        } message: {
            Text("This will reset general settings, display preferences, and keyboard shortcuts to their default values. Storage limits will not be changed, and your history and snippets will not be affected.")
        }
    }
}

struct DisplayPreferencesView: View {
    @EnvironmentObject var preferencesService: PreferencesService
    @EnvironmentObject var storageService: StorageService
    
    @State private var isRecalculating = false
    @State private var previousPreviewSize: Int = 0
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Preview Popup Size:")
                        Slider(
                            value: Binding(
                                get: { Double(preferencesService.previewSize) },
                                set: { preferencesService.previewSize = Int($0) }
                            ),
                            in: 200...800,
                            step: 50,
                            onEditingChanged: { editing in
                                if !editing {
                                    scheduleRecalculation()
                                }
                            }
                        )
                        .disabled(isRecalculating)
                        Text("\(preferencesService.previewSize)px")
                            .frame(width: 60, alignment: .trailing)
                    }
                    
                    if isRecalculating {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                            Text("Recalculating Previews...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Previews")
            }
            
            Section {
                Toggle("Compact Clipboard History", isOn: $preferencesService.compactHistoryView)
                Toggle("Compact Snippets Menu", isOn: $preferencesService.compactSnippetsView)
            } header: {
                Text("Compact Mode")
            } footer: {
                Text("Compact mode shows smaller icons and single-line items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            previousPreviewSize = preferencesService.previewSize
        }
    }
    
    private func scheduleRecalculation() {
        // Cancel any pending recalculation (handles rapid arrow key presses)
        debounceTask?.cancel()
        
        let newSize = preferencesService.previewSize
        guard newSize != previousPreviewSize else { return }
        
        // Short debounce to coalesce rapid changes (arrow keys) while still feeling responsive
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            guard !Task.isCancelled else { return }
            await recalculatePreviews(newSize: newSize)
        }
    }
    
    @MainActor
    private func recalculatePreviews(newSize: Int) async {
        let startTime = Date()
        isRecalculating = true
        
        // Yield to allow UI to update before starting heavy work
        await Task.yield()
        
        let thumbnailService = ThumbnailService()
        do {
            _ = try await storageService.regenerateVideoThumbnails(
                thumbnailService: thumbnailService,
                maxSize: CGFloat(newSize)
            )
            previousPreviewSize = newSize
        } catch {
            print("Failed to regenerate thumbnails: \(error)")
        }
        
        // Ensure "Recalculating Previews..." shows for at least 1 second
        let elapsed = Date().timeIntervalSince(startTime)
        if elapsed < 1.0 {
            let remainingNanoseconds = UInt64((1.0 - elapsed) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: remainingNanoseconds)
        }
        
        isRecalculating = false
    }
}

struct KeyboardShortcutsPreferencesView: View {
    @EnvironmentObject var preferencesService: PreferencesService
    @State private var showingEnableSheet = false

    var body: some View {
        Form {
            Section {
                Toggle("Enable Global Shortcuts", isOn: Binding(
                    get: { preferencesService.globalShortcutsEnabled },
                    set: { newValue in
                        if newValue && !preferencesService.globalShortcutsEnabled {
                            // Show confirmation sheet when enabling
                            showingEnableSheet = true
                        } else if !newValue {
                            // Defer state changes to avoid "Publishing changes from within view updates"
                            DispatchQueue.main.async {
                                preferencesService.globalShortcutsEnabled = false
                                NotificationCenter.default.post(name: NSNotification.Name("GlobalShortcutsEnabledChanged"), object: nil)
                            }
                        }
                    }
                ))
                
                if preferencesService.globalShortcutsEnabled {
                    LabeledContent("History Shortcut") {
                        ShortcutRecorderView(shortcut: $preferencesService.historyShortcutData)
                            .frame(width: 150)
                    }

                    // Only show snippets shortcut when not in integrated mode
                    if preferencesService.snippetsMenuMode != .integrated {
                        LabeledContent("Snippets Shortcut") {
                            ShortcutRecorderView(shortcut: $preferencesService.snippetsShortcutData)
                                .frame(width: 150)
                        }
                    }
                    
                    Label("Shortcuts active", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                } else {
                    Text("Enable to use \(KeyboardShortcut.defaultHistory.displayString) and \(KeyboardShortcut.defaultSnippets.displayString) from any app")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Global Shortcuts")
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(isPresented: $showingEnableSheet) {
            AccessibilityPermissionView(
                isPresented: $showingEnableSheet,
                onPermissionGranted: {
                    // Defer state changes to avoid "Publishing changes from within view updates"
                    DispatchQueue.main.async {
                        preferencesService.globalShortcutsEnabled = true
                        NotificationCenter.default.post(name: NSNotification.Name("GlobalShortcutsEnabledChanged"), object: nil)
                    }
                },
                onCancel: {
                    // Don't enable shortcuts if cancelled
                }
            )
        }
    }
}

struct StoragePreferencesView: View {
    @EnvironmentObject var preferencesService: PreferencesService
    @EnvironmentObject var storageService: StorageService
    
    @State private var showWipeSnippetsConfirmation = false
    @State private var showWipeAllDataConfirmation = false
    @State private var snippetCount: Int = 0
    @State private var snippetsStorageSize: Int64 = 0
    @State private var historyItemCount: Int = 0
    @State private var historyStorageSize: Int64 = 0
    
    var body: some View {
        Form {
            Section {
                Stepper(value: $preferencesService.maxHistoryItems, in: 5...100, step: 5) {
                    HStack {
                        Text("Max History Items")
                        Spacer()
                        Text("\(historyItemCount) used of \(preferencesService.maxHistoryItems)")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }

                Stepper(value: $preferencesService.maxStorageMB, in: 100...51200, step: 100) {
                    HStack {
                        Text("Max Storage")
                        Spacer()
                        Text("\(formatBytesValue(historyStorageSize)) used of \(formatMBValue(preferencesService.maxStorageMB))")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Stepper(value: $preferencesService.maxItemSizeMB, in: 100...2048, step: 100) {
                        HStack {
                            Text("Item Size Limit")
                            Spacer()
                            Text(formatMBValue(preferencesService.maxItemSizeMB))
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                    }
                    HStack(alignment: .center, spacing: 4) {
                        Image(systemName: "link")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        Text("Items exceeding this limit are saved as references to the original files/folders. If the originals are deleted they will disappear from the menu.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("History Storage")
            }

            Section {
                LabeledContent("Snippets Count") {
                    Text("\(snippetCount) snippets")
                        .foregroundColor(.secondary)
                }
                
                LabeledContent("Storage Used") {
                    Text(ByteCountFormatter.string(fromByteCount: snippetsStorageSize, countStyle: .file))
                        .foregroundColor(.secondary)
                }
                
                Button(role: .destructive) {
                    showWipeSnippetsConfirmation = true
                } label: {
                    Text("Wipe Snippets Database")
                }
                .disabled(snippetCount == 0)
                
                Text("Snippet storage is unlimited. Saving many large items may use significant disk space.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Snippets Storage")
            }
            
            Section {
                Button(role: .destructive) {
                    showWipeAllDataConfirmation = true
                } label: {
                    Label("Wipe All Data and Settings", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                }
                
                Text("This will permanently delete all clipboard history, snippets, media files, and reset the database. This action cannot be undone.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Danger Zone")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            refreshHistoryStats()
            refreshSnippetsStats()
        }
        .onReceive(storageService.objectWillChange) { _ in
            // Refresh stats when storage changes (e.g., after cleanup)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                refreshHistoryStats()
                refreshSnippetsStats()
            }
        }
        .alert("Delete All Snippets?", isPresented: $showWipeSnippetsConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(snippetCount) Snippets", role: .destructive) {
                wipeSnippets()
            }
        } message: {
            Text("This will permanently delete all \(snippetCount) snippets and their associated files. This action cannot be undone.")
        }
        .alert("Wipe All Data and Settings?", isPresented: $showWipeAllDataConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Wipe Everything", role: .destructive) {
                wipeAllData()
            }
        } message: {
            Text("This will permanently delete ALL data including \(historyItemCount) history items, \(snippetCount) snippets, all media files, and reset the database. This action cannot be undone.")
        }
    }
    
    /// Format MB value for display (shows GB if >= 1024 MB)
    private func formatMBValue(_ mb: Int) -> String {
        if mb >= 1024 {
            return String(format: "%.1f GB", Double(mb) / 1024.0)
        } else {
            return "\(mb) MB"
        }
    }
    
    /// Format bytes value for display (shows MB or GB as appropriate)
    private func formatBytesValue(_ bytes: Int64) -> String {
        let mb = Double(bytes) / (1024.0 * 1024.0)
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024.0)
        } else {
            return String(format: "%.0f MB", mb)
        }
    }
    
    private func refreshHistoryStats() {
        if let items = try? storageService.fetchClipboardItems(limit: Int.max) {
            historyItemCount = items.count
        }
        historyStorageSize = storageService.calculateClipboardItemsStorageSize()
    }
    
    private func refreshSnippetsStats() {
        snippetCount = storageService.getSnippetCount()
        snippetsStorageSize = storageService.calculateSnippetsStorageSize()
    }
    
    private func wipeSnippets() {
        do {
            try storageService.deleteAllSnippets()
            refreshSnippetsStats()
        } catch {
            print("Failed to wipe snippets: \(error)")
        }
    }
    
    private func wipeAllData() {
        do {
            try storageService.wipeAllData()
            refreshHistoryStats()
            refreshSnippetsStats()
        } catch {
            print("Failed to wipe all data: \(error)")
        }
    }
}

#Preview {
    PreferencesView()
        .environmentObject(PreferencesService())
        .environmentObject(StorageService())
}
