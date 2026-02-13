import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var preferencesWindow: NSWindow?
    let appState = AppState()

    private var statusItem: NSStatusItem?
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupStatusItem()

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ScreenCaddy"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 800, height: 500)

        window.contentView = NSHostingView(
            rootView: MainWindowView(appState: appState)
        )

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appDidActivate),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )

        appState.setup()
    }

    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let isScreenCaddy = (app.bundleIdentifier == Bundle.main.bundleIdentifier)
        appState.isWindowActive = isScreenCaddy
        if isScreenCaddy {
            appState.showWaveOverlay = false
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            window?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "ScreenCaddy")
        }

        updateStatusMenu()

        cancellable = appState.$isSharingActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusMenu()
            }
    }

    private func updateStatusMenu() {
        let menu = NSMenu()

        let toggleTitle = appState.isSharingActive ? "Stop Capture" : "Start Capture"
        menu.addItem(withTitle: toggleTitle, action: #selector(toggleCapture), keyEquivalent: "")

        if appState.isSharingActive {
            menu.addItem(withTitle: "Toggle Wave Overlay", action: #selector(toggleWave), keyEquivalent: "")
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Show ScreenCaddy", action: #selector(showMainWindow), keyEquivalent: "")

        statusItem?.menu = menu

        // Update icon based on state
        let iconName = appState.isSharingActive ? "rectangle.on.rectangle.fill" : "rectangle.on.rectangle"
        statusItem?.button?.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "ScreenCaddy")
    }

    @objc private func toggleCapture() {
        appState.toggleSharing()
    }

    @objc private func toggleWave() {
        appState.toggleWaveOverlay()
    }

    @objc private func showMainWindow() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        let mainMenu = NSMenu()

        // App menu (ScreenCaddy)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About ScreenCaddy", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide ScreenCaddy", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit ScreenCaddy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Capture menu (with in-app keyboard shortcuts)
        let captureMenuItem = NSMenuItem()
        let captureMenu = NSMenu(title: "Capture")
        let toggleItem = NSMenuItem(title: "Toggle Capture", action: #selector(toggleCapture), keyEquivalent: "s")
        toggleItem.keyEquivalentModifierMask = [.command, .shift]
        captureMenu.addItem(toggleItem)
        let waveItem = NSMenuItem(title: "Toggle Wave Overlay", action: #selector(toggleWave), keyEquivalent: "w")
        waveItem.keyEquivalentModifierMask = [.command, .shift]
        captureMenu.addItem(waveItem)
        captureMenuItem.submenu = captureMenu
        mainMenu.addItem(captureMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "ScreenCaddy",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0",
        ])
    }

    @objc private func showPreferences() {
        if let existing = preferencesWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let prefsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        prefsWindow.title = "Preferences"
        prefsWindow.center()
        prefsWindow.isReleasedWhenClosed = false
        prefsWindow.contentView = NSHostingView(
            rootView: PreferencesView(appState: appState)
        )
        prefsWindow.makeKeyAndOrderFront(nil)
        self.preferencesWindow = prefsWindow
    }
}
