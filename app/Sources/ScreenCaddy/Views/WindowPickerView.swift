import SwiftUI
import ScreenCaptureKit

struct WindowPickerItem: Identifiable {
    let id: CGWindowID
    let bundleID: String
    let appName: String
    let windowTitle: String
    let icon: NSImage
    let thumbnail: NSImage
}

struct WindowPickerView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var windows: [WindowPickerItem] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Window")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if isLoading {
                Spacer()
                ProgressView("Scanning windows...")
                Spacer()
            } else if windows.isEmpty {
                Spacer()
                Text("No windows found.")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 220), spacing: 16)
                    ], spacing: 16) {
                        ForEach(windows) { item in
                            WindowPickerCell(item: item) {
                                appState.addApp(
                                    bundleID: item.bundleID,
                                    windowID: item.id,
                                    windowTitle: item.windowTitle
                                )
                                appState.switchToApp(id: "\(item.bundleID):\(item.id)")
                                dismiss()
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 640, height: 500)
        .task {
            await loadWindows()
        }
    }

    private func loadWindows() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                true, onScreenWindowsOnly: true
            )

            let alreadyAddedWindowIDs = Set(
                appState.selectedApps.compactMap { $0.windowID }
            )

            // Bundle IDs of regular (Dock) apps — excludes menu bar agents, system UI, etc.
            let regularAppBundleIDs = Set(
                NSWorkspace.shared.runningApplications
                    .filter { $0.activationPolicy == .regular }
                    .compactMap { $0.bundleIdentifier }
            )

            let systemBundleIDs: Set<String> = [
                "com.apple.controlcenter",
                "com.apple.dock",
                "com.apple.notificationcenterui",
                "com.apple.WindowManager",
                "com.apple.Spotlight",
            ]

            var items: [WindowPickerItem] = []

            let minDimension: CGFloat = 100
            let sortedWindows = content.windows
                .filter { $0.isOnScreen && $0.frame.width >= minDimension && $0.frame.height >= minDimension }
                .sorted { ($0.frame.width * $0.frame.height) > ($1.frame.width * $1.frame.height) }

            for window in sortedWindows {
                guard let bundleID = window.owningApplication?.bundleIdentifier else { continue }
                if bundleID == Bundle.main.bundleIdentifier { continue }
                if alreadyAddedWindowIDs.contains(window.windowID) { continue }
                if !regularAppBundleIDs.contains(bundleID) { continue }
                if systemBundleIDs.contains(bundleID) { continue }

                let appName = window.owningApplication?.applicationName ?? bundleID
                let title = window.title ?? ""

                let icon: NSImage
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    icon = NSWorkspace.shared.icon(forFile: url.path)
                } else {
                    icon = NSImage(systemSymbolName: "app", accessibilityDescription: appName) ?? NSImage()
                }
                icon.size = NSSize(width: 20, height: 20)

                let thumbnail = await captureWindowThumbnail(window: window)

                items.append(WindowPickerItem(
                    id: window.windowID,
                    bundleID: bundleID,
                    appName: appName,
                    windowTitle: title,
                    icon: icon,
                    thumbnail: thumbnail
                ))
            }

            windows = items.sorted {
                $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
            }
        } catch {
            print("Failed to enumerate windows: \(error)")
        }

        isLoading = false
    }

    private func captureWindowThumbnail(window: SCWindow) async -> NSImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width)
        config.height = Int(window.frame.height)
        config.showsCursor = false

        if let cgImage = try? await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        ) {
            return NSImage(cgImage: cgImage, size: NSSize(width: window.frame.width, height: window.frame.height))
        }
        return NSImage()
    }
}

struct WindowPickerCell: View {
    let item: WindowPickerItem
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 0) {
                // Window thumbnail
                Image(nsImage: item.thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 140)
                    .background(Color.black)
                    .clipped()

                // App info bar
                HStack(spacing: 6) {
                    Image(nsImage: item.icon)
                        .resizable()
                        .frame(width: 20, height: 20)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.appName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if !item.windowTitle.isEmpty {
                            Text(item.windowTitle)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.05))
            }
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
