import AppKit
import Combine

@MainActor
final class RunningAppsProvider: ObservableObject {
    @Published var apps: [AppInfo] = []

    private var cancellables = Set<AnyCancellable>()

    init() {
        refreshApps()

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshApps() }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshApps() }
            .store(in: &cancellables)
    }

    private func refreshApps() {
        apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> AppInfo? in
                guard let bundleID = app.bundleIdentifier,
                      let name = app.localizedName else { return nil }
                let icon = app.icon ?? NSImage(
                    systemSymbolName: "app",
                    accessibilityDescription: name
                ) ?? NSImage()
                icon.size = NSSize(width: 32, height: 32)
                return AppInfo(
                    id: bundleID,
                    bundleID: bundleID,
                    name: name,
                    windowTitle: "",
                    icon: icon,
                    pid: app.processIdentifier,
                    windowID: nil
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
