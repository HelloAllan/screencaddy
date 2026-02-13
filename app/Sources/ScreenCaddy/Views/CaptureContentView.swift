import SwiftUI
import CoreText

// MARK: - Chalkboard empty state

private let chalkFontName: String = {
    guard let resourcePath = Bundle.main.resourcePath else { return "" }
    let fontPath = resourcePath + "/Chalkboard-Regular.ttf"
    guard let fontData = NSData(contentsOfFile: fontPath),
          let provider = CGDataProvider(data: fontData),
          let font = CGFont(provider) else { return "" }
    CTFontManagerRegisterGraphicsFont(font, nil)
    return font.postScriptName as String? ?? ""
}()

private struct ChalkText: View {
    let text: String
    let size: CGFloat

    var body: some View {
        Text(text)
            .font(chalkFont)
            .foregroundColor(.white.opacity(0.55))
            .shadow(color: .white.opacity(0.15), radius: 3)
            .multilineTextAlignment(.leading)
    }

    private var chalkFont: Font {
        if !chalkFontName.isEmpty {
            return .custom(chalkFontName, size: size)
        }
        return .system(size: size, weight: .bold, design: .rounded).italic()
    }
}

private func chalkArrowImage(_ name: String) -> NSImage? {
    guard let resourcePath = Bundle.main.resourcePath else { return nil }
    return NSImage(contentsOfFile: resourcePath + "/\(name)")
}

struct CaptureContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ZStack {
            // Always render so displayLayer exists for focus capture
            CaptureDisplayRepresentable(appState: appState)
                .opacity(shouldShowFocusCapture ? 1 : 0)

            if appState.viewMode == .tile && appState.isSharingActive && !appState.tileInfos.isEmpty {
                tileView
            } else if !appState.isSharingActive || appState.currentlySharedID == nil {
                emptyState
            }

            if appState.showWaveOverlay {
                waveOverlay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var shouldShowFocusCapture: Bool {
        appState.viewMode == .focus
            && appState.isSharingActive
            && appState.currentlySharedID != nil
    }

    private var tileView: some View {
        let activeID = appState.currentlySharedID
        let activeTile = appState.tileInfos.first { $0.id == activeID }
        let otherTiles = appState.tileInfos.filter { $0.id != activeID }

        return VStack(spacing: 2) {
            if let tile = activeTile {
                TileCellRepresentable(contentLayer: tile.layer)
                    .id(tile.id)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if !otherTiles.isEmpty {
                HStack(spacing: 2) {
                    ForEach(otherTiles) { tile in
                        TileCellRepresentable(contentLayer: tile.layer)
                            .id(tile.id)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                            .onTapGesture {
                                appState.switchToApp(id: tile.id)
                            }
                    }
                }
                .frame(height: 140)
            }
        }
        .padding(4)
    }

    private var waveOverlay: some View {
        GeometryReader { geo in
            let emojiSize = min(geo.size.width, geo.size.height) * 0.8

            ZStack {
                Color.black.opacity(0.75)

                VStack(spacing: 16) {
                    Image(systemName: "hand.wave.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: emojiSize)
                        .foregroundStyle(.yellow)
                        .modifier(WaveModifier())
                    Text("ScreenCaddy")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                    Text("Pick this window to share")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private var emptyState: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Chalkboard background
                if let bgImage = NSImage(contentsOfFile: Bundle.main.resourcePath! + "/BackgroundChalk.png") {
                    Image(nsImage: bgImage)
                        .resizable(resizingMode: .tile)
                        .frame(width: w, height: h)
                        .clipped()
                } else {
                    Color(nsColor: NSColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1))
                }

                // === "Your selected apps will show here" (upper-left) ===
                ChalkText(text: "Your shared apps\nwill show here", size: 19)
                    .position(x: 180, y: h * 0.22 + 15)

                if let arrow1 = chalkArrowImage("Arrow1.png") {
                    Image(nsImage: arrow1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 140)
                        .opacity(0.55)
                        .position(x: 80, y: h * 0.22 + 45)
                }

                // === "Add app here" (bottom-left) ===
                ChalkText(text: "Add app here", size: 19)
                    .position(x: 145, y: h - 95)

                if let arrow2 = chalkArrowImage("Arrow2.png") {
                    Image(nsImage: arrow2)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 70)
                        .scaleEffect(x: -1, y: -1)
                        .rotationEffect(.degrees(90))
                        .opacity(0.55)
                        .position(x: 55, y: h - 50)
                }

                // === Center message ===
                VStack(spacing: 8) {
                    ChalkText(text: "Not currently sharing", size: 28)
                    ChalkText(text: "\u{2318}\u{21E7}W to highlight for easy selecting", size: 16)
                }
                .position(x: w / 2, y: h / 2)
            }
            .allowsHitTesting(false)
        }
    }
}

private struct WaveModifier: ViewModifier {
    @State private var rocking = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(rocking ? 15 : -15))
            .animation(
                .easeInOut(duration: 0.3).repeatForever(autoreverses: true),
                value: rocking
            )
            .onAppear { rocking = true }
    }
}
