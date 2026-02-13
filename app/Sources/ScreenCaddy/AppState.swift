import AppKit
import Combine
import ScreenCaptureKit

struct AppInfo: Identifiable, Hashable {
    let id: String  // unique: "bundleID:windowID" or just "bundleID"
    let bundleID: String
    let name: String
    let windowTitle: String
    let icon: NSImage
    var pid: pid_t
    var windowID: CGWindowID?

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum ViewMode {
    case focus
    case tile
}

struct TileInfo: Identifiable {
    let id: String  // matches AppInfo.id
    let layer: CALayer
}

@MainActor
final class AppState: ObservableObject {
    @Published var runningApps: [AppInfo] = []
    @Published var selectedApps: [AppInfo] = []
    @Published var selectedBundleIDs: Set<String> = []
    @Published var isSharingActive = false
    @Published var currentlySharedID: String?
    @Published var displayLayer: CALayer?
    @Published var viewMode: ViewMode = .focus
    @Published var tileInfos: [TileInfo] = []
    @Published var autoSwitch: Bool = true {
        didSet { UserPreferences.saveAutoSwitch(autoSwitch) }
    }
    @Published var showOverlay: Bool = true {
        didSet {
            UserPreferences.saveShowOverlay(showOverlay)
            if showOverlay {
                // Re-show overlay if currently sharing
                if isSharingActive, currentlySharedID != nil {
                    updateOverlayTracking()
                }
            } else {
                overlayController?.stopTracking()
            }
        }
    }
    @Published var showCursor: Bool = true {
        didSet {
            UserPreferences.saveShowCursor(showCursor)
            captureEngine?.showsCursor = showCursor
            for (_, engine) in tileEngines {
                engine.showsCursor = showCursor
            }
        }
    }
    @Published var hideSidebarWhenInactive: Bool = true {
        didSet { UserPreferences.saveHideSidebar(hideSidebarWhenInactive) }
    }
    @Published var isWindowActive: Bool = true
    @Published var showWaveOverlay = false

    private var runningAppsProvider: RunningAppsProvider?
    private var captureEngine: CaptureEngine?
    private var activeWindowMonitor: ActiveWindowMonitor?
    private var overlayController: BeingSharedOverlay?
    private var tileEngines: [String: CaptureEngine] = [:]
    private var windowFocusTimer: Timer?
    private var lastFrontmostWindowID: Int?
    private var cancellables = Set<AnyCancellable>()

    init() {
        autoSwitch = UserPreferences.loadAutoSwitch()
        showOverlay = UserPreferences.loadShowOverlay()
        showCursor = UserPreferences.loadShowCursor()
        hideSidebarWhenInactive = UserPreferences.loadHideSidebar()
        selectedBundleIDs = UserPreferences.loadSelectedBundleIDs()
        restoreSelectedApps()
    }

    func setup() {
        let provider = RunningAppsProvider()
        self.runningAppsProvider = provider
        provider.$apps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] apps in
                self?.runningApps = apps
                self?.removeTerminatedApps()
            }
            .store(in: &cancellables)

        let monitor = ActiveWindowMonitor()
        self.activeWindowMonitor = monitor
        monitor.onAppActivated = { [weak self] bundleID in
            self?.handleAppActivated(bundleID: bundleID)
        }
    }

    func toggleWaveOverlay() {
        showWaveOverlay.toggle()
    }

    private func removeTerminatedApps() {
        let runningBundleIDs = Set(runningApps.map { $0.bundleID })
        let staleIDs = selectedApps
            .filter { !runningBundleIDs.contains($0.bundleID) }
            .map { $0.id }

        for id in staleIDs {
            removeApp(id: id)
        }
    }

    // MARK: - App Management

    func addApp(bundleID: String, windowID: CGWindowID? = nil, windowTitle: String = "") {
        let uniqueID: String
        if let wid = windowID {
            uniqueID = "\(bundleID):\(wid)"
        } else {
            uniqueID = bundleID
        }

        guard !selectedApps.contains(where: { $0.id == uniqueID }) else { return }

        // If adding a specific window, remove any generic (restored) entry for this bundle
        if windowID != nil {
            if let genericIndex = selectedApps.firstIndex(where: {
                $0.bundleID == bundleID && $0.windowID == nil
            }) {
                let genericID = selectedApps[genericIndex].id
                removeTileCapture(for: genericID)
                if currentlySharedID == genericID {
                    currentlySharedID = nil
                }
                selectedApps.remove(at: genericIndex)
            }
        }

        let name: String
        let icon: NSImage
        var pid: pid_t = 0

        if let runningApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleID
        }) {
            name = runningApp.localizedName ?? bundleID
            icon = runningApp.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: name) ?? NSImage()
            pid = runningApp.processIdentifier
        } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let displayName = FileManager.default.displayName(atPath: appURL.path)
            name = displayName.hasSuffix(".app") ? String(displayName.dropLast(4)) : displayName
            icon = NSWorkspace.shared.icon(forFile: appURL.path)
        } else {
            return
        }

        icon.size = NSSize(width: 40, height: 40)
        let appInfo = AppInfo(
            id: uniqueID,
            bundleID: bundleID,
            name: name,
            windowTitle: windowTitle,
            icon: icon,
            pid: pid,
            windowID: windowID
        )
        selectedApps.append(appInfo)
        selectedBundleIDs.insert(bundleID)
        UserPreferences.saveSelectedBundleIDs(selectedBundleIDs)

        if viewMode == .tile && isSharingActive {
            Task { await addTileCapture(for: appInfo) }
        }
    }

    func removeApp(id: String) {
        guard let app = selectedApps.first(where: { $0.id == id }) else { return }
        let bundleID = app.bundleID
        selectedApps.removeAll { $0.id == id }

        // Only remove from selectedBundleIDs if no other entries share this bundleID
        if !selectedApps.contains(where: { $0.bundleID == bundleID }) {
            selectedBundleIDs.remove(bundleID)
            UserPreferences.saveSelectedBundleIDs(selectedBundleIDs)
        }

        removeTileCapture(for: id)

        if currentlySharedID == id {
            // Stop the current capture engine — its source window may be gone,
            // leaving the SCStream in a broken state that can't switch targets.
            captureEngine?.stopCapture()
            captureEngine = nil
            currentlySharedID = nil
            displayLayer?.contents = nil

            if let nextApp = selectedApps.first {
                switchToApp(id: nextApp.id)
            } else {
                stopSharing()
            }
        }
    }

    func switchToApp(id: String) {
        if viewMode == .tile && isSharingActive {
            currentlySharedID = id
            updateOverlayTracking()
            return
        }
        Task {
            if !isSharingActive {
                await startSharingWith(id: id)
            } else {
                await switchCapture(to: id)
            }
        }
    }

    // MARK: - View Mode

    func switchViewMode(_ mode: ViewMode) {
        guard mode != viewMode else { return }
        viewMode = mode

        guard isSharingActive else { return }

        Task {
            if mode == .tile {
                captureEngine?.stopCapture()
                captureEngine = nil
                await startTileCaptures()
            } else {
                stopTileCaptures()
                let engine = makeCaptureEngine()
                self.captureEngine = engine
                if let id = currentlySharedID,
                   let app = selectedApps.first(where: { $0.id == id }),
                   let layer = displayLayer {
                    do {
                        try await engine.switchToApp(bundleID: app.bundleID, windowID: app.windowID, displayLayer: layer)
                        updateOverlayTracking()
                    } catch {
                        print("Failed to restart focus capture: \(error)")
                    }
                }
            }
        }
    }

    // MARK: - Sharing

    func toggleSharing() {
        if isSharingActive {
            stopSharing()
        } else {
            startSharing()
        }
    }

    func startSharing() {
        guard !selectedApps.isEmpty else { return }

        Task {
            let hasPermission = await Permissions.checkScreenCapturePermission()
            guard hasPermission else {
                Permissions.showPermissionAlert()
                return
            }

            let overlay = BeingSharedOverlay()
            self.overlayController = overlay
            self.isSharingActive = true
            self.activeWindowMonitor?.startMonitoring()
            self.startWindowFocusTimer()

            if viewMode == .tile {
                await startTileCaptures()
                if let first = selectedApps.first {
                    currentlySharedID = first.id
                    updateOverlayTracking()
                }
            } else {
                let engine = makeCaptureEngine()
                self.captureEngine = engine

                if let frontApp = NSWorkspace.shared.frontmostApplication,
                   let bundleID = frontApp.bundleIdentifier,
                   let match = selectedApps.first(where: { $0.bundleID == bundleID }) {
                    await switchCapture(to: match.id)
                } else if let firstApp = selectedApps.first {
                    await switchCapture(to: firstApp.id)
                }
            }
        }
    }

    private func startSharingWith(id: String) async {
        let hasPermission = await Permissions.checkScreenCapturePermission()
        guard hasPermission else {
            Permissions.showPermissionAlert()
            return
        }

        let overlay = BeingSharedOverlay()
        self.overlayController = overlay
        self.isSharingActive = true
        self.activeWindowMonitor?.startMonitoring()
        self.startWindowFocusTimer()

        if viewMode == .tile {
            await startTileCaptures()
            currentlySharedID = id
            updateOverlayTracking()
        } else {
            let engine = makeCaptureEngine()
            self.captureEngine = engine
            await switchCapture(to: id)
        }
    }

    func stopSharing() {
        captureEngine?.stopCapture()
        captureEngine = nil

        stopTileCaptures()

        overlayController?.stopTracking()
        overlayController = nil

        activeWindowMonitor?.stopMonitoring()
        stopWindowFocusTimer()

        currentlySharedID = nil
        isSharingActive = false
    }

    // MARK: - Tile Captures

    private func startTileCaptures() async {
        stopTileCaptures()

        for app in selectedApps {
            await addTileCapture(for: app)
        }
    }

    private func addTileCapture(for app: AppInfo) async {
        let layer = CALayer()
        layer.contentsGravity = .resizeAspect
        layer.backgroundColor = NSColor.black.cgColor

        let engine = makeCaptureEngine()
        tileEngines[app.id] = engine

        do {
            try await engine.switchToApp(bundleID: app.bundleID, windowID: app.windowID, displayLayer: layer)
            tileInfos.append(TileInfo(id: app.id, layer: layer))
        } catch {
            print("Failed to start tile capture for \(app.bundleID): \(error)")
            tileEngines.removeValue(forKey: app.id)
        }
    }

    private func removeTileCapture(for id: String) {
        tileEngines[id]?.stopCapture()
        tileEngines.removeValue(forKey: id)
        tileInfos.removeAll { $0.id == id }
    }

    private func stopTileCaptures() {
        for (_, engine) in tileEngines {
            engine.stopCapture()
        }
        tileEngines.removeAll()
        tileInfos.removeAll()
    }

    // MARK: - Private

    private func handleAppActivated(bundleID: String) {
        guard isSharingActive, autoSwitch else { return }

        // Find entries matching this bundleID
        let matchingEntries = selectedApps.filter { $0.bundleID == bundleID }
        guard !matchingEntries.isEmpty else { return }

        Task {
            // If we have multiple windows of this app, detect which is frontmost
            if matchingEntries.count > 1 {
                if let target = await frontmostEntry(among: matchingEntries) {
                    if target.id != currentlySharedID {
                        if viewMode == .tile {
                            currentlySharedID = target.id
                            updateOverlayTracking()
                        } else {
                            await switchCapture(to: target.id)
                        }
                    }
                    return
                }
            }

            // If current entry already matches this bundleID, keep it
            if let currentID = currentlySharedID,
               let current = selectedApps.first(where: { $0.id == currentID }),
               current.bundleID == bundleID {
                return
            }

            // Switch to the first matching entry
            let target = matchingEntries[0]

            if viewMode == .tile {
                currentlySharedID = target.id
                updateOverlayTracking()
            } else {
                await switchCapture(to: target.id)
            }
        }
    }

    /// Find which shared entry matches the frontmost window of the app
    private func frontmostEntry(among entries: [AppInfo]) async -> AppInfo? {
        guard let bundleID = entries.first?.bundleID,
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == bundleID
              }) else { return nil }

        let pid = app.processIdentifier

        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            true, onScreenWindowsOnly: true
        ) else { return nil }

        // SCShareableContent returns windows in z-order (front to back)
        let frontWindow = content.windows.first { window in
            guard let ownerPID = window.owningApplication?.processID,
                  ownerPID == pid,
                  window.frame.width >= 100,
                  window.frame.height >= 100
            else { return false }
            return true
        }

        guard let frontWindow else { return nil }
        return entries.first { $0.windowID == frontWindow.windowID }
    }

    private func switchCapture(to id: String) async {
        guard let layer = displayLayer,
              let app = selectedApps.first(where: { $0.id == id }) else { return }

        // Create engine if needed (e.g. after removing a terminated app)
        if captureEngine == nil {
            captureEngine = makeCaptureEngine()
        }

        do {
            try await captureEngine!.switchToApp(bundleID: app.bundleID, windowID: app.windowID, displayLayer: layer)
            currentlySharedID = id
            updateOverlayTracking()
        } catch {
            print("Failed to switch capture to \(app.bundleID): \(error)")
            // Stream may be broken — tear it down so the next attempt starts fresh
            captureEngine?.stopCapture()
            captureEngine = nil
            currentlySharedID = nil
        }
    }

    private func makeCaptureEngine() -> CaptureEngine {
        let engine = CaptureEngine()
        engine.showsCursor = showCursor
        return engine
    }

    private func updateOverlayTracking() {
        guard showOverlay else { return }
        guard let id = currentlySharedID,
              let app = selectedApps.first(where: { $0.id == id }) else { return }

        let resolvedWindowID: CGWindowID?
        if viewMode == .tile {
            resolvedWindowID = tileEngines[id]?.trackedWindowID ?? app.windowID
        } else {
            resolvedWindowID = captureEngine?.trackedWindowID ?? app.windowID
        }

        overlayController?.startTracking(bundleID: app.bundleID, windowID: resolvedWindowID)
    }

    // MARK: - Window Focus Polling

    private func startWindowFocusTimer() {
        stopWindowFocusTimer()
        windowFocusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkWindowFocusChange()
            }
        }
    }

    private func stopWindowFocusTimer() {
        windowFocusTimer?.invalidate()
        windowFocusTimer = nil
        lastFrontmostWindowID = nil
    }

    private var isCheckingFocus = false

    private func checkWindowFocusChange() {
        guard isSharingActive, autoSwitch, !isCheckingFocus else { return }
        guard let currentID = currentlySharedID,
              let currentApp = selectedApps.first(where: { $0.id == currentID }) else { return }

        // Only check when the current shared app is the active application
        guard let runningApp = NSWorkspace.shared.frontmostApplication,
              let frontBundleID = runningApp.bundleIdentifier,
              frontBundleID == currentApp.bundleID else { return }

        // Only relevant if we have multiple windows of this app
        let sameAppEntries = selectedApps.filter { $0.bundleID == currentApp.bundleID }
        guard sameAppEntries.count > 1 else { return }

        let pid = runningApp.processIdentifier

        isCheckingFocus = true
        Task {
            defer { isCheckingFocus = false }

            guard let content = try? await SCShareableContent.excludingDesktopWindows(
                true, onScreenWindowsOnly: true
            ) else { return }

            // Find the frontmost real window for this app (SCShareableContent returns z-ordered)
            let frontWindow = content.windows.first { window in
                guard let ownerPID = window.owningApplication?.processID,
                      ownerPID == pid,
                      window.frame.width >= 100,
                      window.frame.height >= 100
                else { return false }
                return true
            }

            guard let frontWindow else { return }
            let frontID = Int(frontWindow.windowID)

            // Only act if the frontmost window changed
            guard frontID != lastFrontmostWindowID else { return }
            lastFrontmostWindowID = frontID

            guard let target = sameAppEntries.first(where: { $0.windowID == frontWindow.windowID }),
                  target.id != currentlySharedID else { return }

            if viewMode == .tile {
                currentlySharedID = target.id
                updateOverlayTracking()
            } else {
                await switchCapture(to: target.id)
            }
        }
    }

    private func restoreSelectedApps() {
        var validBundleIDs = Set<String>()

        for bundleID in selectedBundleIDs {
            // Only restore apps that are currently running
            guard let runningApp = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == bundleID
            }) else {
                continue
            }

            let name = runningApp.localizedName ?? bundleID
            let icon = runningApp.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: name) ?? NSImage()
            let pid = runningApp.processIdentifier

            icon.size = NSSize(width: 40, height: 40)
            selectedApps.append(AppInfo(
                id: bundleID,
                bundleID: bundleID,
                name: name,
                windowTitle: "",
                icon: icon,
                pid: pid,
                windowID: nil
            ))
            validBundleIDs.insert(bundleID)
        }

        // Update saved preferences to remove stale entries
        if validBundleIDs != selectedBundleIDs {
            selectedBundleIDs = validBundleIDs
            UserPreferences.saveSelectedBundleIDs(selectedBundleIDs)
        }
    }
}
