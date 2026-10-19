#if os(macOS)
import AppKit

/// A window whose backing scale is `backingScale`, whatever display it is on. A virtual
/// Mac (CI) has a display at one pixel to the point and a developer's Mac at two, and AppKit
/// and SwiftUI align lines and views to whole device pixels, so a layout measured in points
/// differs by up to a point between the two. A test that measures layout hosts its view in
/// this window to measure the same layout everywhere.
public final class PinnedBackingScaleWindow: NSWindow {
    private let pinnedBackingScale: CGFloat

    public init(contentRect: NSRect, styleMask: NSWindow.StyleMask = [.borderless], backingScale: CGFloat = 2) {
        pinnedBackingScale = backingScale
        super.init(contentRect: contentRect, styleMask: styleMask, backing: .buffered, defer: true)
    }

    public override var backingScaleFactor: CGFloat { pinnedBackingScale }
}
#endif
