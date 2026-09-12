import SwiftUI
import AppKit

struct OnboardingView: View {
    let preferencesService: PreferencesService
    let onComplete: @MainActor () -> Void
    
    @State private var permissionGranted = false
    @State private var showingError = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)
                
                Text("Welcome to ClipboardMenu")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Your clipboard history, always at hand")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)
            .padding(.bottom, 32)
            
            Divider()
                .padding(.horizontal, 40)
            
            // Permission explanation
            VStack(alignment: .leading, spacing: 20) {
                Text("File Access Permission")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 16) {
                    PermissionReasonRow(
                        icon: "doc.on.doc",
                        title: "Access Copied Files",
                        description: "Preview and paste files you copy from Finder or other apps"
                    )
                    
                    PermissionReasonRow(
                        icon: "folder",
                        title: "Folder Contents",
                        description: "View contents of copied folders in the clipboard history"
                    )
                    
                    PermissionReasonRow(
                        icon: "photo",
                        title: "Generate Previews",
                        description: "Create thumbnails for images and documents you copy"
                    )
                }
                
                // Privacy note
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "lock.shield")
                        .foregroundColor(.green)
                        .font(.title3)
                    
                    Text("Your files stay private. ClipboardMenu only accesses files when you copy them or view your clipboard history. No data is sent anywhere.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            .padding(40)
            
            Spacer()
            
            // Action buttons
            VStack(spacing: 12) {
                if permissionGranted {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Permission Granted")
                            .foregroundColor(.green)
                    }
                    .font(.headline)
                    
                    Button("Get Started") {
                        completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                } else {
                    HStack(spacing: 16) {
                        Button("Skip for Now") {
                            completeOnboarding()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Grant File Access") {
                            requestPermission()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .frame(width: 520, height: 620)
        .alert("Permission Required", isPresented: $showingError) {
            Button("Try Again") {
                requestPermission()
            }
            Button("Skip") {
                completeOnboarding()
            }
        } message: {
            Text("Please select your home folder to grant ClipboardMenu access to your files.")
        }
    }
    
    private func requestPermission() {
        let granted = FilePermissionService.shared.requestHomeDirectoryAccess(preferencesService: preferencesService)
        
        if granted {
            permissionGranted = true
        } else {
            showingError = true
        }
    }
    
    private func completeOnboarding() {
        preferencesService.hasCompletedOnboarding = true
        onComplete()
    }
}

// MARK: - Permission Reason Row

struct PermissionReasonRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(preferencesService: PreferencesService()) {
        print("Onboarding complete")
    }
}
