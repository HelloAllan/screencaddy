import AppKit
import ScreenCaptureKit
import SwiftUI

@MainActor
final class BeingSharedOverlay {
    private var panel: NSPanel?
    private var trackingTimer: Timer?
    private var trackedBundleID: String?
    private var trackedWindowID: CGWindowID?
    private var isUpdating = false

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 28),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.hasShadow = false

        let hostingView = NSHostingView(rootView: BeingSharedOverlayView())
        hostingView.frame = panel.contentView!.bounds
        panel.contentView = hostingView

        self.panel = panel
    }

    func startTracking(bundleID: String, windowID: CGWindowID? = nil) {
        stopTracking()
        trackedBundleID = bundleID
        trackedWindowID = windowID
        updatePosition()
        panel?.orderFront(nil)

        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updatePosition()
            }
        }
    }

    func stopTracking() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        trackedBundleID = nil
        trackedWindowID = nil
        panel?.orderOut(nil)
    }

    func show() {
        panel?.orderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func updatePosition() {
        guard !isUpdating else { return }
        guard let panel = panel, let bundleID = trackedBundleID else { return }

        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleID
        }) else { return }

        // Hide overlay when tracked app is not the frontmost application
        guard app.isActive else {
            panel.orderOut(nil)
            return
        }

        let pid = app.processIdentifier

        isUpdating = true
        Task {
            defer { isUpdating = false }

            guard let content = try? await SCShareableContent.excludingDesktopWindows(
                true, onScreenWindowsOnly: true
            ) else { return }

            let appWindows = content.windows.filter { window in
                guard let ownerPID = window.owningApplication?.processID,
                      ownerPID == pid,
                      window.frame.width > 0,
                      window.frame.height > 0
                else { return false }
                return true
            }

            var targetWindow: SCWindow?

            if let targetWID = trackedWindowID {
                // Check if a different real window is in front (SCShareableContent is z-ordered)
                let realWindows = appWindows.filter {
                    $0.frame.width >= 100 && $0.frame.height >= 100
                }
                if let frontmost = realWindows.first,
                   frontmost.windowID != targetWID {
                    panel.orderOut(nil)
                    return
                }

                targetWindow = appWindows.first { $0.windowID == targetWID }
            }

            // Fall back to largest window if no specific match
            let resolvedWindow = targetWindow ?? appWindows.max(by: {
                ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height)
            })

            guard let resolvedWindow else {
                panel.orderOut(nil)
                return
            }

            let windowFrame = resolvedWindow.frame
            guard let screen = NSScreen.screens.first else { return }
            let screenHeight = screen.frame.height

            let overlayX = windowFrame.origin.x + windowFrame.width - 100 - 8
            let overlayY = screenHeight - windowFrame.origin.y - 28 - 8

            panel.orderFront(nil)
            panel.setFrameOrigin(NSPoint(x: overlayX, y: overlayY))
        }
    }
}
