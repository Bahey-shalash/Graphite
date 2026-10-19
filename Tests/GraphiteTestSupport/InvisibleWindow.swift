#if os(macOS)
import AppKit

public extension NSWindow {
    /// Puts the window on screen for AppKit, so its views are in a visible window, without a
    /// person seeing it: fully transparent and taking no mouse events. A test that shows a window
    /// with `orderFront` flashes it on the developer's screen (at the bottom left, for a window
    /// at the origin) for as long as the test runs; views draw into a bitmap the same way.
    func showInvisibly() {
        alphaValue = 0
        ignoresMouseEvents = true
        hasShadow = false
        collectionBehavior = [.transient, .ignoresCycle]
        orderFront(nil)
    }
}
#endif
