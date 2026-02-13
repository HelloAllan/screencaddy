import SwiftUI

struct SidebarView: View {
    @ObservedObject var appState: AppState
    @State private var showingWindowPicker = false

    var body: some View {
        VStack(spacing: 0) {
            if appState.selectedApps.isEmpty {
                Spacer()
                Image(systemName: "display")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary.opacity(0.5))
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(appState.selectedApps) { app in
                            SidebarAppRow(
                                app: app,
                                isActive: appState.currentlySharedID == app.id,
                                onSelect: { appState.switchToApp(id: app.id) },
                                onRemove: { appState.removeApp(id: app.id) }
                            )
                        }
                    }
                    .padding(.top, 8)
                }
            }

            Divider()

            VStack(spacing: 4) {
                Button {
                    showingWindowPicker = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 36, height: 36)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Add Window")

                if appState.selectedApps.count > 1 {
                    Button {
                        appState.switchViewMode(appState.viewMode == .focus ? .tile : .focus)
                    } label: {
                        Image(systemName: appState.viewMode == .focus ? "square.grid.2x2" : "rectangle.center.inset.filled")
                            .font(.system(size: 13))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .help(appState.viewMode == .focus ? "Tile View" : "Focus View")
                }

                if appState.isSharingActive {
                    Button {
                        appState.stopSharing()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .help("Stop Sharing")
                }

}
            .padding(.vertical, 6)
        }
        .frame(width: 64)
        .sheet(isPresented: $showingWindowPicker) {
            WindowPickerView(appState: appState)
        }
    }
}
