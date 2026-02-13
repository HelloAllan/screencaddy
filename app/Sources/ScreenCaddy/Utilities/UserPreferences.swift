import Foundation

enum UserPreferences {
    private static let selectedBundleIDsKey = "selectedBundleIDs"
    private static let showOverlayKey = "showStreamingOverlay"
    private static let autoSwitchKey = "autoSwitchCapture"
    private static let showCursorKey = "showCursorInCapture"
    private static let hideSidebarKey = "hideSidebarWhenInactive"

    static func loadSelectedBundleIDs() -> Set<String> {
        let array = UserDefaults.standard.stringArray(forKey: selectedBundleIDsKey) ?? []
        return Set(array)
    }

    static func saveSelectedBundleIDs(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: selectedBundleIDsKey)
    }

    static func loadShowOverlay() -> Bool {
        if UserDefaults.standard.object(forKey: showOverlayKey) == nil {
            return true  // default on
        }
        return UserDefaults.standard.bool(forKey: showOverlayKey)
    }

    static func saveShowOverlay(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: showOverlayKey)
    }

    static func loadAutoSwitch() -> Bool {
        if UserDefaults.standard.object(forKey: autoSwitchKey) == nil {
            return true  // default on
        }
        return UserDefaults.standard.bool(forKey: autoSwitchKey)
    }

    static func saveAutoSwitch(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: autoSwitchKey)
    }

    static func loadShowCursor() -> Bool {
        if UserDefaults.standard.object(forKey: showCursorKey) == nil {
            return true  // default on
        }
        return UserDefaults.standard.bool(forKey: showCursorKey)
    }

    static func saveShowCursor(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: showCursorKey)
    }

    static func loadHideSidebar() -> Bool {
        if UserDefaults.standard.object(forKey: hideSidebarKey) == nil {
            return true  // default on
        }
        return UserDefaults.standard.bool(forKey: hideSidebarKey)
    }

    static func saveHideSidebar(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: hideSidebarKey)
    }
}
