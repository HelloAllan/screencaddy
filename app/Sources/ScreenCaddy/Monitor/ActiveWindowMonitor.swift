import AppKit

@MainActor
final class ActiveWindowMonitor {
    var onAppActivated: ((String) -> Void)?

    private var observer: NSObjectProtocol?
    private let debouncer = Debouncer(delay: 0.3)

    func startMonitoring() {
        stopMonitoring()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier,
                  bundleID != Bundle.main.bundleIdentifier else { return }
            MainActor.assumeIsolated {
                self?.debouncer.debounce {
                    self?.onAppActivated?(bundleID)
                }
            }
        }
    }

    func stopMonitoring() {
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
        debouncer.cancel()
    }
}
