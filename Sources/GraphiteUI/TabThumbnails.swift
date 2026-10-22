import SwiftUI
import GraphiteCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Thumbnails of the tabs as they were last seen, for the tab overview's cards, as Safari
/// keeps a picture of each page. A side's document area is captured for its active tab when
/// the overview opens, and once a tab has been on screen for a moment (`TabOverviewModel`);
/// never while switching tabs, which it would slow down. They are small, their longer side
/// at most `longestSidePixels`, and few: the `maximumThumbnailCount` most recently captured,
/// and none after a memory warning.
@MainActor
final class TabThumbnails {
    static let maximumThumbnailCount = 24
    nonisolated static let longestSidePixels: CGFloat = 640

    private var thumbnails: [UUID: CGImage] = [:]
    /// The tabs with a thumbnail, least recently captured first.
    private var captureOrder: [UUID] = []
    /// Each side's document areas, by tab group. SwiftUI can make a side's new area before
    /// it lets go of the old one, so a side can have two for a moment.
    private var documentAreas: [UUID: [WeakDocumentArea]] = [:]
    #if canImport(UIKit)
    /// Lets go of every thumbnail on a memory warning; ended with the store.
    private var memoryWarningTask: Task<Void, Never>?
    #endif

    init() {
        #if canImport(UIKit)
        memoryWarningTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIApplication.didReceiveMemoryWarningNotification) {
                self?.removeAllThumbnails()
            }
        }
        #endif
    }

    isolated deinit {
        #if canImport(UIKit)
        memoryWarningTask?.cancel()
        #endif
    }

    func thumbnail(of tabID: UUID) -> CGImage? { thumbnails[tabID] }

    var thumbnailCount: Int { thumbnails.count }

    func store(_ thumbnail: CGImage, for tabID: UUID) {
        thumbnails[tabID] = thumbnail
        captureOrder.removeAll { capturedTabID in capturedTabID == tabID }
        captureOrder.append(tabID)
        while captureOrder.count > Self.maximumThumbnailCount {
            thumbnails[captureOrder.removeFirst()] = nil
        }
    }

    /// Lets go of the thumbnails of tabs that were closed.
    func keepOnly(_ openTabIDs: Set<UUID>) {
        captureOrder.removeAll { capturedTabID in !openTabIDs.contains(capturedTabID) }
        thumbnails = thumbnails.filter { tabID, _ in openTabIDs.contains(tabID) }
    }

    func removeAllThumbnails() {
        thumbnails.removeAll()
        captureOrder.removeAll()
    }

    // MARK: Capturing

    func register(_ area: DocumentAreaView, forGroup groupID: UUID) {
        var areas = documentAreas[groupID, default: []].filter { registered in registered.view != nil }
        if !areas.contains(where: { registered in registered.view === area }) { areas.append(WeakDocumentArea(view: area)) }
        documentAreas[groupID] = areas
    }

    func unregister(_ area: DocumentAreaView, forGroup groupID: UUID) {
        let areas = documentAreas[groupID, default: []].filter { registered in registered.view != nil && registered.view !== area }
        documentAreas[groupID] = areas.isEmpty ? nil : areas
    }

    /// The side's document area on screen, the newest when there are two.
    private func documentArea(ofGroup groupID: UUID) -> DocumentAreaView? {
        documentAreas[groupID]?.last { registered in registered.view?.window != nil }?.view
    }

    /// The shape of a side's document area, its width over its height, while it is on screen.
    func aspectRatio(ofGroup groupID: UUID) -> CGFloat? {
        guard let area = documentArea(ofGroup: groupID), area.bounds.height >= 1 else { return nil }
        return area.bounds.width / area.bounds.height
    }

    /// Captures the active tab of every side on screen, as the overview opens. A stacked
    /// side shows several tabs at once, so none of them is captured.
    func captureShownTabs(in layout: TabLayout) {
        for group in layout.groups where !group.isStacked {
            captureActiveTab(ofGroup: group.id, tabID: group.activeTabID)
        }
    }

    /// Captures what a side's document area shows, for the tab it shows.
    @discardableResult
    func captureActiveTab(ofGroup groupID: UUID, tabID: UUID) -> Bool {
        guard let area = documentArea(ofGroup: groupID), let thumbnail = Self.thumbnail(of: area) else { return false }
        store(thumbnail, for: tabID)
        return true
    }

    /// What is on screen over the view's frame, at the scale that makes its longer side
    /// `longestSidePixels` at most.
    static func thumbnail(of area: DocumentAreaView) -> CGImage? {
        #if canImport(UIKit)
        guard let window = area.window, !area.isHidden else { return nil }
        // The window's content alone: UIKit puts a context menu, and the dimming behind it,
        // over the content in the window itself, and they are not part of the page.
        let content: UIView = window.rootViewController?.view ?? window
        let frame = area.convert(area.bounds, to: content)
        guard frame.width >= 1, frame.height >= 1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(area.traitCollection.displayScale, longestSidePixels / max(frame.width, frame.height))
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: frame.size, format: format)
        // What the screen shows: afterScreenUpdates false takes the frame already drawn,
        // without laying the window out again.
        let image = renderer.image { _ in
            content.drawHierarchy(in: CGRect(origin: CGPoint(x: -frame.minX, y: -frame.minY), size: content.bounds.size), afterScreenUpdates: false)
        }
        return image.cgImage
        #else
        guard let window = area.window, let contentView = window.contentView, let layer = contentView.layer,
              !area.isHiddenOrHasHiddenAncestor else { return nil }
        let frame = area.convert(area.bounds, to: contentView)
        guard frame.width >= 1, frame.height >= 1 else { return nil }
        let scale = min(window.backingScaleFactor, longestSidePixels / max(frame.width, frame.height))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int((frame.width * scale).rounded()), height: Int((frame.height * scale).rounded()),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        // The layers as they are drawn, which costs about half as much as drawing the views
        // again with `cacheDisplay`. A material or Liquid Glass does not render this way. The
        // content view is flipped, so the thumbnail is too, with the area's top left at its origin.
        context.scaleBy(x: scale, y: scale)
        if contentView.isFlipped {
            context.translateBy(x: 0, y: frame.height)
            context.scaleBy(x: 1, y: -1)
        }
        context.translateBy(x: -frame.minX, y: -frame.minY)
        layer.render(in: context)
        return context.makeImage()
        #endif
    }
}

private struct WeakDocumentArea {
    weak var view: DocumentAreaView?
}

/// The view behind a side's document, whose frame is what `TabThumbnails` captures. It takes
/// no touches or clicks.
#if canImport(UIKit)
final class DocumentAreaView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}
#else
final class DocumentAreaView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
#endif

/// Marks a side's document area for `TabThumbnails`.
@MainActor
struct TabThumbnailArea {
    let groupID: UUID
    let thumbnails: TabThumbnails

    @MainActor
    final class Coordinator {
        var groupID: UUID
        let thumbnails: TabThumbnails
        init(groupID: UUID, thumbnails: TabThumbnails) { self.groupID = groupID; self.thumbnails = thumbnails }
    }

    func makeCoordinator() -> Coordinator { Coordinator(groupID: groupID, thumbnails: thumbnails) }

    private func update(_ area: DocumentAreaView, coordinator: Coordinator) {
        if coordinator.groupID != groupID {
            coordinator.thumbnails.unregister(area, forGroup: coordinator.groupID)
            coordinator.groupID = groupID
        }
        thumbnails.register(area, forGroup: groupID)
    }
}

#if canImport(UIKit)
extension TabThumbnailArea: UIViewRepresentable {
    func makeUIView(context: Context) -> DocumentAreaView {
        let area = DocumentAreaView()
        area.isUserInteractionEnabled = false
        thumbnails.register(area, forGroup: groupID)
        return area
    }

    func updateUIView(_ area: DocumentAreaView, context: Context) { update(area, coordinator: context.coordinator) }

    static func dismantleUIView(_ area: DocumentAreaView, coordinator: Coordinator) {
        coordinator.thumbnails.unregister(area, forGroup: coordinator.groupID)
    }
}
#else
extension TabThumbnailArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DocumentAreaView {
        let area = DocumentAreaView()
        thumbnails.register(area, forGroup: groupID)
        return area
    }

    func updateNSView(_ area: DocumentAreaView, context: Context) { update(area, coordinator: context.coordinator) }

    static func dismantleNSView(_ area: DocumentAreaView, coordinator: Coordinator) {
        coordinator.thumbnails.unregister(area, forGroup: coordinator.groupID)
    }
}
#endif
