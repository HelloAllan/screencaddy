import SwiftUI

struct PreferencesView: View {
    @ObservedObject var appState: AppState

    private let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"

    var body: some View {
        Form {
            Section("Streaming") {
                Toggle("Show streaming overlay on captured window", isOn: $appState.showOverlay)
                Toggle("Auto-switch capture when changing apps", isOn: $appState.autoSwitch)
                Toggle("Show cursor in capture", isOn: $appState.showCursor)
                Toggle("Hide sidebar when window is inactive", isOn: $appState.hideSidebarWhenInactive)
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(appVersion)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Website")
                    Spacer()
                    Link("screencaddy.app", destination: URL(string: "https://screencaddy.app")!)
                }

                HStack {
                    Text("Contact")
                    Spacer()
                    Link("hello@screencaddy.app", destination: URL(string: "mailto:hello@screencaddy.app")!)
                }
            }
        }
        .formStyle(.grouped)
    }
}
