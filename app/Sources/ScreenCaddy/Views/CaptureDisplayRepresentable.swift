import AppKit
import SwiftUI

// MARK: - Focus mode display

struct CaptureDisplayRepresentable: NSViewRepresentable {
    @ObservedObject var appState: AppState

    func makeNSView(context: Context) -> CaptureDisplayNSView {
        let view = CaptureDisplayNSView()
        appState.displayLayer = view.displayLayer
        return view
    }

    func updateNSView(_ nsView: CaptureDisplayNSView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CaptureDisplayNSView, context: Context) -> CGSize? {
        return proposal.replacingUnspecifiedDimensions()
    }
}

final class CaptureDisplayNSView: NSView {
    let displayLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        displayLayer.contentsGravity = .resize
        displayLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(displayLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        displayLayer.contentsScale = scale
        if displayLayer.superlayer == nil {
            layer?.addSublayer(displayLayer)
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        displayLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
    }

    override func layout() {
        super.layout()
        // Recalculate the aspect-fit frame if we have content
        if let image = displayLayer.contents,
           CFGetTypeID(image as CFTypeRef) == CGImage.typeID {
            let cgImage = image as! CGImage
            CaptureStreamOutput.updateLayerFrame(displayLayer, contentWidth: cgImage.width, contentHeight: cgImage.height)
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            displayLayer.frame = bounds
            CATransaction.commit()
        }
    }
}

// MARK: - Tile mode cell

struct TileCellRepresentable: NSViewRepresentable {
    let contentLayer: CALayer

    func makeNSView(context: Context) -> TileCellNSView {
        TileCellNSView(contentLayer: contentLayer)
    }

    func updateNSView(_ nsView: TileCellNSView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TileCellNSView, context: Context) -> CGSize? {
        return proposal.replacingUnspecifiedDimensions()
    }
}

final class TileCellNSView: NSView {
    private let contentLayer: CALayer

    init(contentLayer: CALayer) {
        self.contentLayer = contentLayer
        super.init(frame: .zero)
        wantsLayer = true
        contentLayer.contentsGravity = .resize
        contentLayer.removeFromSuperlayer()
        layer?.addSublayer(contentLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        contentLayer.contentsScale = scale
        if contentLayer.superlayer == nil {
            layer?.addSublayer(contentLayer)
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        contentLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
    }

    override func layout() {
        super.layout()
        if let image = contentLayer.contents,
           CFGetTypeID(image as CFTypeRef) == CGImage.typeID {
            let cgImage = image as! CGImage
            CaptureStreamOutput.updateLayerFrame(contentLayer, contentWidth: cgImage.width, contentHeight: cgImage.height)
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            contentLayer.frame = bounds
            CATransaction.commit()
        }
    }
}
