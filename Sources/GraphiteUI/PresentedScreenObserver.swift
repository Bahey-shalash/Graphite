#if canImport(UIKit)
import UIKit

extension UIView {
    /// Whether a screen presented in this view's window covers the view: a sheet, a popover,
    /// an alert, a file picker or a full-screen cover presented over the screen the view is
    /// on. A view inside the screen presented last is not covered.
    var isCoveredByPresentedScreen: Bool {
        guard let rootViewController = window?.rootViewController else { return false }
        var topController = rootViewController
        while let presentedController = topController.presentedViewController { topController = presentedController }
        guard topController !== rootViewController else { return false }
        guard let presentedView = topController.viewIfLoaded else { return true }
        return !isDescendant(of: presentedView)
    }
}

/// Follows whether a screen presented over a view covers it, and says when that changes.
///
/// Apple's floating Pencil palette is drawn above every screen of the app, so a sheet, a file
/// picker or an alert presented over a document being written on showed the palette on top of
/// it. The palette's owner hides it while its document is covered. UIKit tells the views under
/// a presentation nothing when it begins or ends, so while observing, the view is checked each
/// time the main run loop is about to wait: after every event, timer and animation completion
/// that can present or dismiss a screen, and never while the app is idle. The check walks the
/// window's presented screens and the view's ancestors.
@MainActor
final class PresentedScreenObserver {
    private weak var view: UIView?
    private let coverDidChange: () -> Void
    private var runLoopObserver: CFRunLoopObserver?
    private var wasCovered = false

    /// - Parameter coverDidChange: Called when a screen comes over the view, or the last
    ///   screen over it goes, while observing.
    init(view: UIView, coverDidChange: @escaping () -> Void) {
        self.view = view
        self.coverDidChange = coverDidChange
    }

    isolated deinit {
        stopObserving()
    }

    /// Whether a screen presented over the view covers it now.
    var isViewCovered: Bool { view?.isCoveredByPresentedScreen ?? false }

    /// Whether changes are reported. Owners observe only while the view needs it, as while a
    /// PDF is being written on.
    var isObserving: Bool {
        get { runLoopObserver != nil }
        set { if newValue { startObserving() } else { stopObserving() } }
    }

    private func startObserving() {
        guard runLoopObserver == nil else { return }
        wasCovered = isViewCovered
        // Last of the run loop's observers, so a screen another observer presents or
        // dismisses in the same pass is seen in it.
        guard let observer = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, CFRunLoopActivity.beforeWaiting.rawValue,
                                                                true, CFIndex.max, { [weak self] _, _ in
            MainActor.assumeIsolated { self?.checkCover() }
        }) else { return }
        // Common modes: a screen can come or go while a scroll view tracks a touch.
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        runLoopObserver = observer
    }

    private func stopObserving() {
        guard let runLoopObserver else { return }
        CFRunLoopObserverInvalidate(runLoopObserver)
        self.runLoopObserver = nil
    }

    private func checkCover() {
        let isCovered = isViewCovered
        guard isCovered != wasCovered else { return }
        wasCovered = isCovered
        // The run loop is about to sleep. The owner changes its views on the next turn of
        // the main queue, which wakes it, so they are drawn without waiting for an event.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isObserving else { return }
            self.coverDidChange()
        }
    }
}
#endif
