import SwiftUI

struct MainWindowView: View {
    @ObservedObject var appState: AppState

    private var showSidebar: Bool {
        !appState.hideSidebarWhenInactive || appState.isWindowActive
    }

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                SidebarView(appState: appState)
                Divider()
            }
            CaptureContentView(appState: appState)
        }
    }
}
