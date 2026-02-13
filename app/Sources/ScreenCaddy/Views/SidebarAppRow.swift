import SwiftUI

struct SidebarAppRow: View {
    let app: AppInfo
    let isActive: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 40, height: 40)
                .cornerRadius(8)

            Circle()
                .fill(isActive ? Color.green : Color.clear)
                .frame(width: 5, height: 5)
        }
        .frame(width: 52, height: 52)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .help(app.windowTitle.isEmpty ? app.name : "\(app.name) — \(app.windowTitle)")
        .contextMenu {
            Button("Remove") { onRemove() }
        }
    }
}
