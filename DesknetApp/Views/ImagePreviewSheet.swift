import AppKit
import Combine
import SwiftUI

/// Image opened from a body card. Identifiable so a card can present it with `.sheet(item:)`.
struct ImagePreviewItem: Identifiable {
    let id = UUID()
    let title: String
    let data: Data
    /// nil for SVG, which is drawn by WebKit.
    let image: NSImage?
}

/// Large image view: trackpad pinch to zoom, two-finger drag to pan, double-tap to smart zoom.
/// Toolbar buttons and Preview.app shortcuts (⌘+, ⌘-, ⌘0 actual size, ⌘9 fit) cover mouse users.
/// Bitmaps use an NSScrollView; SVG uses a sandboxed WKWebView (see `SVGWebView`).
struct ImagePreviewSheet: View {
    let item: ImagePreviewItem
    let onCopy: (CopyPayload) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var zoom = ImageZoomController()
    @State private var svgZoom = SVGZoomController()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let image = item.image {
                ZoomableImageView(image: image, controller: zoom)
            } else {
                SVGWebView(data: item.data, interactive: true, controller: svgZoom)
            }
        }
        .frame(minWidth: 480, idealWidth: 820, minHeight: 360, idealHeight: 620)
        .background(DesknetPalette.windowBackground)
    }

    private var subtitle: String {
        if let image = item.image {
            return "\(Int(image.size.width)) × \(Int(image.size.height)) px"
        }
        return "SVG · \(ByteCountFormatter.string(fromByteCount: Int64(item.data.count), countStyle: .file))"
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            if item.image != nil {
                bitmapZoomControls
                CopyButton(payload: .image(item.data), label: "Copy Image", onCopy: onCopy)
            } else {
                svgZoomControls
                CopyButton(payload: .svg(item.data), label: "Copy SVG", onCopy: onCopy)
            }
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .buttonStyle(.borderless)
        .padding(12)
    }

    @ViewBuilder
    private var bitmapZoomControls: some View {
        Button(action: zoom.zoomOut) { Image(systemName: "minus.magnifyingglass") }
            .keyboardShortcut("-", modifiers: .command)
            .help("Zoom Out (⌘-)")
        Text("\(Int((zoom.magnification * 100).rounded()))%")
            .font(.system(size: 12).monospacedDigit())
            .frame(minWidth: 44)
            .accessibilityLabel("Zoom \(Int((zoom.magnification * 100).rounded())) percent")
        Button(action: zoom.zoomIn) { Image(systemName: "plus.magnifyingglass") }
            .keyboardShortcut("=", modifiers: .command)
            .help("Zoom In (⌘+)")
        Button("Fit", action: zoom.fit)
            .keyboardShortcut("9", modifiers: .command)
            .help("Zoom to Fit (⌘9)")
        Button("100%", action: zoom.actualSize)
            .keyboardShortcut("0", modifiers: .command)
            .help("Actual Size (⌘0)")
    }

    /// SVG has no fixed pixel size, so "Fit" is the base and there is no 100%.
    @ViewBuilder
    private var svgZoomControls: some View {
        Button(action: svgZoom.zoomOut) { Image(systemName: "minus.magnifyingglass") }
            .keyboardShortcut("-", modifiers: .command)
            .help("Zoom Out (⌘-)")
        Button(action: svgZoom.zoomIn) { Image(systemName: "plus.magnifyingglass") }
            .keyboardShortcut("=", modifiers: .command)
            .help("Zoom In (⌘+)")
        Button("Fit", action: svgZoom.fit)
            .keyboardShortcut("9", modifiers: .command)
            .help("Zoom to Fit (⌘9)")
    }
}

/// Drives the scroll view's magnification from SwiftUI buttons and reports it back for the % label.
@MainActor
final class ImageZoomController: ObservableObject {
    static let minZoom: CGFloat = 0.05
    static let maxZoom: CGFloat = 16
    private static let step: CGFloat = 1.25

    @Published private(set) var magnification: CGFloat = 1
    fileprivate weak var scrollView: NSScrollView?

    func zoomIn() { zoom(to: (scrollView?.magnification ?? 1) * Self.step) }
    func zoomOut() { zoom(to: (scrollView?.magnification ?? 1) / Self.step) }
    func actualSize() { zoom(to: 1) }

    /// Whole image in view. Never upscales: small images open at 100%.
    func fit() {
        guard let scrollView, let document = scrollView.documentView,
            document.frame.width > 0, document.frame.height > 0
        else { return }
        let available = scrollView.contentSize
        let scale = min(available.width / document.frame.width, available.height / document.frame.height)
        zoom(to: min(1, scale), centeredAt: NSPoint(x: document.frame.midX, y: document.frame.midY))
    }

    /// Keeps the point at the center of the view in place, like Preview.app.
    private func zoom(to value: CGFloat, centeredAt point: NSPoint? = nil) {
        guard let scrollView else { return }
        let bounds = scrollView.contentView.bounds
        let center = point ?? NSPoint(x: bounds.midX, y: bounds.midY)
        scrollView.setMagnification(min(max(value, Self.minZoom), Self.maxZoom), centeredAt: center)
        sync()
    }

    fileprivate func sync() {
        magnification = scrollView?.magnification ?? 1
    }
}

private struct ZoomableImageView: NSViewRepresentable {
    let image: NSImage
    let controller: ImageZoomController

    final class Coordinator {
        var observer: NSObjectProtocol?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = FittingScrollView()
        scrollView.contentView = CenteringClipView()
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        // Enables pinch and double-tap smart zoom on the trackpad.
        scrollView.allowsMagnification = true
        scrollView.minMagnification = ImageZoomController.minZoom
        scrollView.maxMagnification = ImageZoomController.maxZoom

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: image.size))
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        imageView.setAccessibilityLabel("Image preview")
        scrollView.documentView = imageView

        controller.scrollView = scrollView
        // Sizes are zero until the sheet lays out, so fit on the first real layout.
        scrollView.onFirstLayout = { [weak controller] in controller?.fit() }
        // Pinch changes magnification without going through the controller.
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveMagnifyNotification, object: scrollView, queue: .main
        ) { [weak controller] _ in
            Task { @MainActor in controller?.sync() }
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        if let observer = coordinator.observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

/// Calls `onFirstLayout` once, when the view first has a real size.
private final class FittingScrollView: NSScrollView {
    var onFirstLayout: (() -> Void)?

    override func layout() {
        super.layout()
        guard let onFirstLayout, contentSize.width > 0, contentSize.height > 0 else { return }
        self.onFirstLayout = nil
        onFirstLayout()
    }
}

/// Keeps an image smaller than the view centered instead of pinned to the bottom-left corner.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView else { return rect }
        if rect.width > document.frame.width {
            rect.origin.x = (document.frame.width - rect.width) / 2
        }
        if rect.height > document.frame.height {
            rect.origin.y = (document.frame.height - rect.height) / 2
        }
        return rect
    }
}
