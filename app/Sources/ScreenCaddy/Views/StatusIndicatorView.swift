import SwiftUI

struct StatusIndicatorView: View {
    let isSharing: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isSharing ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(isSharing ? "Sharing" : "Inactive")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
