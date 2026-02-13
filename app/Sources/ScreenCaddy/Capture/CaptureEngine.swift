import AppKit
import ScreenCaptureKit
import VideoToolbox

@MainActor
final class CaptureEngine: NSObject {
    private var stream: SCStream?
    private var streamOutput: CaptureStreamOutput?
    private var sizeCheckTimer: Timer?
    private(set) var trackedWindowID: CGWindowID?
    private var trackedSize: CGSize = .zero
    var showsCursor: Bool = true {
        didSet {
            guard showsCursor != oldValue, let stream = stream else { return }
            let scale = Int(NSScreen.main?.backingScaleFactor ?? 2)
            let config = SCStreamConfiguration()
            config.width = Int(trackedSize.width) * scale
            config.height = Int(trackedSize.height) * scale
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            config.showsCursor = showsCursor
            config.pixelFormat = kCVPixelFormatType_32BGRA
            Task {
                try? await stream.updateConfiguration(config)
            }
        }
    }

    func switchToApp(bundleID: String, windowID: CGWindowID? = nil, displayLayer: CALayer) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )

        // If a specific windowID was requested, try to find it first
        var targetWindow: SCWindow?
        if let windowID = windowID {
            targetWindow = content.windows.first {
                $0.windowID == windowID && $0.isOnScreen
            }
        }

        // Fall back to largest visible window for this bundle ID
        if targetWindow == nil {
            let appWindows = content.windows.filter { window in
                window.owningApplication?.bundleIdentifier == bundleID
                    && window.isOnScreen
                    && window.frame.width > 0
                    && window.frame.height > 0
            }

            targetWindow = appWindows.max(by: {
                ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height)
            })
        }

        guard let targetWindow else {
            throw CaptureError.noWindowFound
        }

        let filter = SCContentFilter(desktopIndependentWindow: targetWindow)

        let scale = Int(NSScreen.main?.backingScaleFactor ?? 2)
        let config = SCStreamConfiguration()
        config.width = Int(targetWindow.frame.width) * scale
        config.height = Int(targetWindow.frame.height) * scale
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = showsCursor
        config.pixelFormat = kCVPixelFormatType_32BGRA

        trackedWindowID = targetWindow.windowID
        trackedSize = CGSize(width: targetWindow.frame.width, height: targetWindow.frame.height)

        if let existingStream = stream {
            // Update filter without restarting stream
            try await existingStream.updateContentFilter(filter)
            try await existingStream.updateConfiguration(config)
        } else {
            // Create new stream
            let output = CaptureStreamOutput(displayLayer: displayLayer)
            self.streamOutput = output

            let newStream = SCStream(filter: filter, configuration: config, delegate: nil)
            try newStream.addStreamOutput(output, type: .screen, sampleHandlerQueue: .global())
            try await newStream.startCapture()
            self.stream = newStream
        }

        startSizeTracking()
    }

    func stopCapture() {
        sizeCheckTimer?.invalidate()
        sizeCheckTimer = nil
        guard let stream = stream else { return }
        Task {
            try? await stream.stopCapture()
        }
        self.stream = nil
        self.streamOutput = nil
        self.trackedWindowID = nil
    }

    // MARK: - Window size tracking

    private func startSizeTracking() {
        sizeCheckTimer?.invalidate()
        sizeCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkWindowSize()
            }
        }
    }

    private var isCheckingSize = false

    private func checkWindowSize() {
        guard stream != nil, let windowID = trackedWindowID, !isCheckingSize else { return }

        isCheckingSize = true
        Task {
            defer { isCheckingSize = false }

            guard let content = try? await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            ),
            let window = content.windows.first(where: { $0.windowID == windowID })
            else { return }

            let newSize = CGSize(width: window.frame.width, height: window.frame.height)
            guard abs(newSize.width - trackedSize.width) > 1 || abs(newSize.height - trackedSize.height) > 1 else { return }

            trackedSize = newSize
            let scale = Int(NSScreen.main?.backingScaleFactor ?? 2)
            let config = SCStreamConfiguration()
            config.width = Int(newSize.width) * scale
            config.height = Int(newSize.height) * scale
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            config.showsCursor = showsCursor
            config.pixelFormat = kCVPixelFormatType_32BGRA

            try? await stream?.updateConfiguration(config)
        }
    }
}

final class CaptureStreamOutput: NSObject, SCStreamOutput {
    private weak var displayLayer: CALayer?
    private var lastContentWidth: Int = 0
    private var lastContentHeight: Int = 0

    init(displayLayer: CALayer) {
        self.displayLayer = displayLayer
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard let imageBuffer = sampleBuffer.imageBuffer else { return }

        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(imageBuffer, options: nil, imageOut: &cgImage)
        guard let image = cgImage else { return }

        let imgW = image.width
        let imgH = image.height

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let layer = self.displayLayer else { return }
            layer.contents = image

            // Recalculate frame only when content dimensions change
            if imgW != self.lastContentWidth || imgH != self.lastContentHeight {
                self.lastContentWidth = imgW
                self.lastContentHeight = imgH
                Self.updateLayerFrame(layer, contentWidth: imgW, contentHeight: imgH)
            }
        }
    }

    /// Calculate an aspect-fit frame for the layer within its superlayer's bounds,
    /// bypassing contentsGravity entirely.
    static func updateLayerFrame(_ layer: CALayer, contentWidth: Int, contentHeight: Int) {
        guard let parentBounds = layer.superlayer?.bounds,
              parentBounds.width > 0, parentBounds.height > 0,
              contentWidth > 0, contentHeight > 0 else { return }

        let contentAspect = CGFloat(contentWidth) / CGFloat(contentHeight)
        let parentAspect = parentBounds.width / parentBounds.height

        let targetSize: CGSize
        if contentAspect > parentAspect {
            targetSize = CGSize(width: parentBounds.width, height: parentBounds.width / contentAspect)
        } else {
            targetSize = CGSize(width: parentBounds.height * contentAspect, height: parentBounds.height)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = CGRect(
            x: (parentBounds.width - targetSize.width) / 2,
            y: (parentBounds.height - targetSize.height) / 2,
            width: targetSize.width,
            height: targetSize.height
        )
        CATransaction.commit()
    }
}

enum CaptureError: LocalizedError {
    case noWindowFound

    var errorDescription: String? {
        switch self {
        case .noWindowFound:
            return "No visible window found for this application."
        }
    }
}
