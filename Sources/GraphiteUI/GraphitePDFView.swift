import SwiftUI
import PDFKit
import GraphiteCore
import GraphiteApple

/// Links to pages and quotes for notes, offered in a PDF's text selection menu.
struct PDFLinkActions {
    /// Copies a link to the page (zero-based).
    let copyLink: (_ pageIndex: Int) -> Void
    /// Copies the selected text as a quote followed by a link to its page.
    let copyQuote: (_ pageIndex: Int, _ text: String) -> Void
    /// Inserts the quote into the note open on the other side, named `noteName`.
    let quoteInNote: ((_ pageIndex: Int, _ text: String) -> Void)?
    let noteName: String?
}

/// How a PDF view accepts annotation input.
struct PDFAnnotationInput: Equatable {
    /// Pencil drawing on pages and text markup from the selection menu.
    var isEnabled: Bool
    /// One finger draws and two fingers scroll, for people without an Apple Pencil.
    var drawsWithFinger: Bool
    /// Shows the system tool picker (pens, colors, eraser, lasso, undo, redo).
    var showsToolPicker: Bool
}

/// Follows what a PDF view shows, on both platforms.
///
/// The session's current page stays on the page in view: page actions, the page field and
/// "Open in PDF View" act on it. Form fields on the pages shown are made read-only in the
/// live document. Graphite records no edit for a typed value, so a save, which replays the
/// recorded edits on the file as it was read, would drop the value without a word.
@MainActor
final class PDFViewPageObserver {
    private let session: PDFSession
    private weak var view: PDFView?
    private var notificationObservers: [NSObjectProtocol] = []

    init(session: PDFSession, view: PDFView) {
        self.session = session
        self.view = view
        notificationObservers = [
            NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateCurrentPage() }
            },
            NotificationCenter.default.addObserver(forName: .PDFViewVisiblePagesChanged, object: view, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.makeFormFieldsReadOnlyOnVisiblePages() }
            },
        ]
        makeFormFieldsReadOnlyOnVisiblePages()
    }

    func stop() {
        for observer in notificationObservers { NotificationCenter.default.removeObserver(observer) }
        notificationObservers.removeAll()
    }

    func updateCurrentPage() {
        guard let page = view?.currentPage else { return }
        let pageIndex = session.document.index(for: page)
        if pageIndex != NSNotFound, session.currentPageIndex != pageIndex { session.currentPageIndex = pageIndex }
    }

    func makeFormFieldsReadOnlyOnVisiblePages() {
        for page in view?.visiblePages ?? [] {
            // PDFKit reports the subtype without the leading slash of `PDFAnnotationSubtype`.
            for annotation in page.annotations where annotation.type == "Widget" && !annotation.isReadOnly {
                annotation.isReadOnly = true
            }
        }
    }
}

#if canImport(UIKit)
import UIKit
import PencilKit

extension PDFLinkActions {
    /// The menu items for text selected on a page.
    @MainActor func menuElements(pageIndex: Int, text: String) -> [UIMenuElement] {
        var elements: [UIMenuElement] = [
            UIAction(title: "Copy Link to Page", image: UIImage(systemName: "link")) { _ in copyLink(pageIndex) },
            UIAction(title: "Copy as Quote", image: UIImage(systemName: "text.quote")) { _ in copyQuote(pageIndex, text) },
        ]
        if let quoteInNote, let noteName {
            elements.append(UIAction(title: "Quote in “\(noteName)”", image: UIImage(systemName: "text.badge.plus")) { _ in quoteInNote(pageIndex, text) })
        }
        return elements
    }
}

struct GraphitePDFView: UIViewRepresentable {
    let session: PDFSession
    var input: PDFAnnotationInput
    /// Smaller gaps between pages, for the viewer embedded in a note.
    var isEmbedded = false
    /// The page shown first, once the view has its size.
    var initialPageIndex: Int?
    /// Called when drawing or selecting text begins, so the PDF's side of the split is focused.
    var beginInteraction: (() -> Void)?
    /// Links and quotes offered for selected text; nil where there is no note to link from.
    var linkActions: PDFLinkActions?

    func makeCoordinator() -> PDFAnnotationCoordinator { PDFAnnotationCoordinator(session: session, isEmbedded: isEmbedded) }

    func makeUIView(context: Context) -> GraphitePDFDisplayView {
        let view = GraphitePDFDisplayView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        view.pageShadowsEnabled = true
        view.backgroundColor = .secondarySystemBackground
        if isEmbedded { view.pageBreakMargins = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6) }
        // PDFKit asks for page overlays only when it creates page views, so the provider
        // must be in place before the document is.
        view.pageOverlayViewProvider = context.coordinator
        view.document = session.document
        view.pendingInitialPage = initialPageIndex.flatMap(session.document.page(at:))
        // The system find bar (⌘F, or the toolbar's Find), which PDFKit fills with its
        // matches. A PDF embedded in a note leaves ⌘F to the note.
        view.isFindInteractionEnabled = !isEmbedded
        context.coordinator.attach(to: view)
        context.coordinator.beginInteraction = beginInteraction
        context.coordinator.linkActions = linkActions
        session.pdfView = view
        return view
    }

    func updateUIView(_ view: GraphitePDFDisplayView, context: Context) {
        context.coordinator.beginInteraction = beginInteraction
        context.coordinator.linkActions = linkActions
        context.coordinator.update(input: input)
    }

    static func dismantleUIView(_ view: GraphitePDFDisplayView, coordinator: PDFAnnotationCoordinator) {
        coordinator.detach()
    }
}

/// PDFView that routes touches on a page to its Pencil canvas while annotating.
final class GraphitePDFDisplayView: PDFView {
    weak var annotationCoordinator: PDFAnnotationCoordinator?
    /// PDFKit scrolls to a page reliably only after the first layout.
    var pendingInitialPage: PDFPage?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // The tool picker needs a first responder in a window.
        annotationCoordinator?.windowDidChange()
    }

    /// The place on screen when the width began to change: the page at the top of the
    /// view and how far down that page the top edge was. Autoscaling changes the zoom when
    /// the width changes (the sidebar, the split divider) but keeps the scroll offset,
    /// which then lands on another page; this place is shown again after the change.
    private var placeBeforeResize: (page: PDFPage, fractionFromTop: CGFloat)?
    /// Ends a resize once the width has stopped changing for a moment.
    private var resizeEndWorkItem: DispatchWorkItem?

    override var frame: CGRect {
        willSet { rememberPlaceBeforeResizing(to: newValue.size) }
    }

    override var bounds: CGRect {
        willSet { rememberPlaceBeforeResizing(to: newValue.size) }
    }

    private func rememberPlaceBeforeResizing(to newSize: CGSize) {
        // UIKit sets the frame while the view is still being created, before PDFKit is
        // ready to be asked anything; a view that is not on screen has no place to keep.
        guard window != nil, pendingInitialPage == nil, bounds.width > 0,
              abs(newSize.width - bounds.width) > 0.5, document != nil else { return }
        // The place is read once, when a resize begins, and kept until it ends: read again
        // at every step of a divider drag, small errors would add up.
        if placeBeforeResize == nil { placeBeforeResize = currentPlace() }
        resizeEndWorkItem?.cancel()
        // PDFKit may finish rescaling after the last layout, so the place is shown once
        // more when the width has settled.
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let placeBeforeResize = self.placeBeforeResize else { return }
            self.placeBeforeResize = nil
            self.show(placeBeforeResize)
        }
        resizeEndWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    private func currentPlace() -> (page: PDFPage, fractionFromTop: CGFloat)? {
        let topPoint = CGPoint(x: bounds.midX, y: bounds.minY + 1)
        guard let page = page(for: topPoint, nearest: true) else { return nil }
        let pageBounds = page.bounds(for: displayBox)
        guard pageBounds.height > 0 else { return nil }
        // Page space runs upward from the bottom of the page.
        let pagePoint = convert(topPoint, to: page)
        return (page, min(max((pageBounds.maxY - pagePoint.y) / pageBounds.height, -0.2), 1))
    }

    /// Scrolls so the top edge is the same way down the same page as before.
    private func show(_ place: (page: PDFPage, fractionFromTop: CGFloat)) {
        guard let scrollView = documentView?.enclosingScrollView else { return }
        let pageRect = convert(place.page.bounds(for: displayBox), from: place.page)
        let offsetChange = pageRect.minY + place.fractionFromTop * pageRect.height - (bounds.minY + 1)
        let minimumOffset = -scrollView.adjustedContentInset.top
        let maximumOffset = max(minimumOffset, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
        let offset = min(max(scrollView.contentOffset.y + offsetChange, minimumOffset), maximumOffset)
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: offset), animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let pendingInitialPage, bounds.width > 0, bounds.height > 0 {
            self.pendingInitialPage = nil
            placeBeforeResize = nil
            go(to: pendingInitialPage)
        } else if let placeBeforeResize {
            show(placeBeforeResize)
        }
    }

    /// The system's menu for text selected with PDFKit's own selection (when not
    /// annotating) gets the links and quotes too.
    override func buildMenu(with builder: any UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .context, let linkActions = annotationCoordinator?.linkActions, let document,
              let selection = currentSelection, let text = selection.string, !text.isEmpty,
              let page = selection.pages.first else { return }
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound else { return }
        builder.insertSibling(UIMenu(title: "", identifier: UIMenu.Identifier("com.graphite.study.pdf-links"), options: .displayInline,
                                     children: linkActions.menuElements(pageIndex: pageIndex, text: text)), afterMenu: .standardEdit)
    }

    /// UIKit cannot tell a Pencil from a finger during hit-testing (the event carries no
    /// touches yet), so while annotating every touch on a page goes to its canvas. The
    /// canvas draws only the input its drawing policy allows; the other touches still
    /// reach the scrolling, zooming, and text selection gestures of this view.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let canvas = annotationCoordinator?.canvas(at: point, in: self) {
            // The drawing gesture lives on a subview of the canvas.
            return canvas.hitTest(canvas.convert(point, from: self), with: event) ?? canvas
        }
        return super.hitTest(point, with: event)
    }
}

private extension UIView {
    /// The nearest scroll view above this view, such as the one PDFKit scrolls pages in.
    var enclosingScrollView: UIScrollView? {
        var ancestor = superview
        while let view = ancestor {
            if let scrollView = view as? UIScrollView { return scrollView }
            ancestor = view.superview
        }
        return nil
    }
}

/// Invisible first responder that keeps the tool picker on screen while pages, and with
/// them their canvases, scroll in and out of view.
final class PDFToolPickerHostView: UIView {
    override var canBecomeFirstResponder: Bool { true }
}

/// A PencilKit canvas over one PDF page, in the page overlay's coordinates.
final class PDFPageCanvasView: PKCanvasView {
    weak var page: PDFPage?
    var inkTracker: PDFPageInkTracker
    /// The page's stored ink is decoded into the canvas the first time it is shown for
    /// annotating; pages only viewed never pay for it.
    var hasRestoredStoredInk = false
    /// True while the stored drawing is decoded in the background. The canvas is empty
    /// and takes no input meanwhile, and the page's ink annotations stay visible.
    var isRestoringStoredInk = false

    init(page: PDFPage, inkTracker: PDFPageInkTracker) {
        self.page = page
        self.inkTracker = inkTracker
        super.init(frame: CGRect(origin: .zero, size: page.bounds(for: .cropBox).size))
    }

    required init?(coder: NSCoder) { nil }
}

/// Owns the Pencil canvases of one PDF view and turns their drawings and text selections
/// into edits of the session.
///
/// PDFKit calls the overlay provider on the main thread; its Objective-C protocol has no
/// actor annotations, so the preconcurrency conformance checks isolation at run time.
@MainActor
final class PDFAnnotationCoordinator: NSObject, @preconcurrency PDFPageOverlayViewProvider, PKCanvasViewDelegate,
                                      UIGestureRecognizerDelegate, @preconcurrency UIEditMenuInteractionDelegate {
    /// Canvases of pages that scrolled away are kept for a while, with their undo history.
    private static let retainedHiddenCanvasCount = 6
    private static let textSelectionPressDuration: TimeInterval = 0.35
    private static let selectionMenuIdentifier = "GraphiteTextSelection" as NSString
    private static let markupMenuIdentifier = "GraphiteMarkup" as NSString

    let session: PDFSession
    /// An embed sits inside the note's own scroll view, which annotating restricts too.
    let isEmbedded: Bool
    var beginInteraction: (() -> Void)?
    var linkActions: PDFLinkActions?
    private weak var pdfView: GraphitePDFDisplayView?
    private let toolPicker = PKToolPicker()
    private let toolPickerHost = PDFToolPickerHostView()
    private var canvasesByPage: [ObjectIdentifier: PDFPageCanvasView] = [:]
    private var displayedPages: Set<ObjectIdentifier> = []
    private var hiddenCanvasOrder: [ObjectIdentifier] = []
    private var input = PDFAnnotationInput(isEnabled: false, drawsWithFinger: false, showsToolPicker: false)
    private var markupTapRecognizer: UITapGestureRecognizer?
    private var textSelectionRecognizer: UILongPressGestureRecognizer?
    private var editMenuInteraction: UIEditMenuInteraction?
    private var tappedMarkup: (annotation: PDFAnnotation, page: PDFPage)?
    private var selectionAnchor: (page: PDFPage, point: CGPoint)?
    private var pageObserver: PDFViewPageObserver?
    private var observedScrollRecognizers: Set<ObjectIdentifier> = []
    /// The scroll views around this embed that it restricts while annotating.
    private var restrictedEnclosingScrollViews: [ObjectIdentifier] = []
    private var hasAppliedInput = false

    /// A scroll view around annotating embeds, with the gesture settings it had before.
    private struct EnclosingScrollRestriction {
        weak var scrollView: UIScrollView?
        let panTouchTypes: [NSNumber]
        let minimumPanTouchCount: Int
        let pinchTouchTypes: [NSNumber]?
        var restrictingCoordinators: Set<ObjectIdentifier>
    }

    /// Shared by every coordinator: two annotating embeds in one note restrict the same
    /// scroll view, and its own settings come back only when the last of them stops.
    private static var enclosingScrollRestrictions: [ObjectIdentifier: EnclosingScrollRestriction] = [:]

    init(session: PDFSession, isEmbedded: Bool) {
        self.session = session
        self.isEmbedded = isEmbedded
        super.init()
    }

    func attach(to view: GraphitePDFDisplayView) {
        pdfView = view
        view.annotationCoordinator = self
        view.addSubview(toolPickerHost)
        toolPicker.colorUserInterfaceStyle = .light
        // The picker's own finger-drawing switch only affects canvases that follow the
        // system policy; Graphite's Draw with Finger setting controls these canvases.
        toolPicker.showsDrawingPolicyControls = false
        let fingerAndPointer = [UITouch.TouchType.direct, .indirectPointer].map { touchType in NSNumber(value: touchType.rawValue) }

        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapRecognizer.delegate = self
        tapRecognizer.allowedTouchTypes = fingerAndPointer
        view.addGestureRecognizer(tapRecognizer)
        markupTapRecognizer = tapRecognizer

        let selectionRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleTextSelection(_:)))
        selectionRecognizer.minimumPressDuration = Self.textSelectionPressDuration
        selectionRecognizer.delegate = self
        selectionRecognizer.allowedTouchTypes = fingerAndPointer
        view.addGestureRecognizer(selectionRecognizer)
        textSelectionRecognizer = selectionRecognizer

        let menuInteraction = UIEditMenuInteraction(delegate: self)
        view.addInteraction(menuInteraction)
        editMenuInteraction = menuInteraction
        pageObserver = PDFViewPageObserver(session: session, view: view)
        session.registerPendingInkRecordWriter(for: self) { [weak self] in self?.writeDeferredInkRecords() }
    }

    func detach() {
        toolPicker.setVisible(false, forFirstResponder: toolPickerHost)
        toolPickerHost.resignFirstResponder()
        for canvas in canvasesByPage.values { release(canvas) }
        canvasesByPage.removeAll()
        session.unregisterPendingInkRecordWriter(for: self)
        // The window's undo history outlives this view; its markup steps must not reach
        // a session that is closing.
        pdfView?.undoManager?.removeAllActions(withTarget: session)
        restoreEnclosingScrollViews()
        pageObserver?.stop()
    }

    func update(input newInput: PDFAnnotationInput) {
        guard let pdfView else { return }
        defer { updateToolPickerVisibility() }
        // SwiftUI calls this on every update of the pane; the view tree is walked only
        // when the input actually changes.
        guard newInput != input || !hasAppliedInput else { return }
        hasAppliedInput = true
        let wasEnabled = input.isEnabled
        input = newInput
        if wasEnabled && !newInput.isEnabled { pdfView.clearSelection() }
        for canvas in canvasesByPage.values { configure(canvas) }
        configureScrollGestures(of: pdfView)
        configureEnclosingScrollViews(of: pdfView)
        // With finger drawing, a long press belongs to the pen, as in Goodnotes.
        textSelectionRecognizer?.isEnabled = newInput.isEnabled && !newInput.drawsWithFinger
    }

    func windowDidChange() {
        // SwiftUI settles focus after inserting the view; claim first responder after it.
        Task { @MainActor [weak self] in self?.updateToolPickerVisibility() }
    }

    // MARK: Touch routing

    func canvas(at point: CGPoint, in view: PDFView) -> PDFPageCanvasView? {
        guard input.isEnabled else { return nil }
        for identifier in displayedPages {
            guard let canvas = canvasesByPage[identifier], canvas.window != nil, !canvas.isHidden, !canvas.isRestoringStoredInk else { continue }
            if canvas.bounds.contains(canvas.convert(point, from: view)) { return canvas }
        }
        return nil
    }

    /// While annotating, the Pencil never scrolls or zooms; with finger drawing, one
    /// finger draws and scrolling takes two, as in Goodnotes.
    private func configureScrollGestures(of view: UIView) {
        let withoutPencil = [UITouch.TouchType.direct, .indirect, .indirectPointer].map { touchType in NSNumber(value: touchType.rawValue) }
        let allTouchTypes = withoutPencil + [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        for scrollView in scrollViews(in: view) {
            scrollView.panGestureRecognizer.allowedTouchTypes = input.isEnabled ? withoutPencil : allTouchTypes
            scrollView.panGestureRecognizer.minimumNumberOfTouches = input.isEnabled && input.drawsWithFinger ? 2 : 1
            scrollView.pinchGestureRecognizer?.allowedTouchTypes = input.isEnabled ? withoutPencil : allTouchTypes
            for recognizer in [scrollView.panGestureRecognizer, scrollView.pinchGestureRecognizer].compactMap({ recognizer in recognizer })
            where !observedScrollRecognizers.contains(ObjectIdentifier(recognizer)) {
                recognizer.addTarget(self, action: #selector(scrollGestureChanged(_:)))
                observedScrollRecognizers.insert(ObjectIdentifier(recognizer))
            }
        }
    }

    /// With finger drawing, the first finger of a two-finger scroll or pinch has already
    /// started a stroke (or erasing) on the canvas. Cancelling the canvas input when the
    /// scroll begins discards that partial stroke, as Goodnotes does.
    @objc private func scrollGestureChanged(_ recognizer: UIGestureRecognizer) {
        guard recognizer.state == .began, input.isEnabled, input.drawsWithFinger else { return }
        for canvas in canvasesByPage.values where canvas.drawingGestureRecognizer.state != .possible {
            canvas.drawingGestureRecognizer.isEnabled = false
            canvas.drawingGestureRecognizer.isEnabled = true
        }
    }

    /// The note around an embed scrolls by the same rule while annotating: otherwise its pan
    /// takes Pencil and one-finger strokes on the pages, scrolling the note or cutting the
    /// stroke short. The note's own settings come back when annotating ends.
    private func configureEnclosingScrollViews(of view: UIView) {
        guard isEmbedded, input.isEnabled else {
            restoreEnclosingScrollViews()
            return
        }
        if restrictedEnclosingScrollViews.isEmpty {
            for scrollView in enclosingScrollViews(of: view) {
                let identifier = ObjectIdentifier(scrollView)
                var restriction = Self.enclosingScrollRestrictions[identifier].flatMap { restriction in restriction.scrollView === scrollView ? restriction : nil }
                    ?? EnclosingScrollRestriction(scrollView: scrollView,
                                                  panTouchTypes: scrollView.panGestureRecognizer.allowedTouchTypes,
                                                  minimumPanTouchCount: scrollView.panGestureRecognizer.minimumNumberOfTouches,
                                                  pinchTouchTypes: scrollView.pinchGestureRecognizer?.allowedTouchTypes,
                                                  restrictingCoordinators: [])
                restriction.restrictingCoordinators.insert(ObjectIdentifier(self))
                Self.enclosingScrollRestrictions[identifier] = restriction
                restrictedEnclosingScrollViews.append(identifier)
            }
        }
        let pencil = NSNumber(value: UITouch.TouchType.pencil.rawValue)
        for identifier in restrictedEnclosingScrollViews {
            guard let restriction = Self.enclosingScrollRestrictions[identifier], let scrollView = restriction.scrollView else { continue }
            scrollView.panGestureRecognizer.allowedTouchTypes = restriction.panTouchTypes.filter { touchType in touchType != pencil }
            scrollView.panGestureRecognizer.minimumNumberOfTouches = input.drawsWithFinger ? max(2, restriction.minimumPanTouchCount) : restriction.minimumPanTouchCount
            if let pinchTouchTypes = restriction.pinchTouchTypes {
                scrollView.pinchGestureRecognizer?.allowedTouchTypes = pinchTouchTypes.filter { touchType in touchType != pencil }
            }
            scrollView.panGestureRecognizer.addTarget(self, action: #selector(scrollGestureChanged(_:)))
        }
    }

    private func restoreEnclosingScrollViews() {
        for identifier in restrictedEnclosingScrollViews {
            guard var restriction = Self.enclosingScrollRestrictions[identifier] else { continue }
            restriction.scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(scrollGestureChanged(_:)))
            restriction.restrictingCoordinators.remove(ObjectIdentifier(self))
            guard restriction.restrictingCoordinators.isEmpty else {
                Self.enclosingScrollRestrictions[identifier] = restriction
                continue
            }
            Self.enclosingScrollRestrictions[identifier] = nil
            guard let scrollView = restriction.scrollView else { continue }
            scrollView.panGestureRecognizer.allowedTouchTypes = restriction.panTouchTypes
            scrollView.panGestureRecognizer.minimumNumberOfTouches = restriction.minimumPanTouchCount
            if let pinchTouchTypes = restriction.pinchTouchTypes { scrollView.pinchGestureRecognizer?.allowedTouchTypes = pinchTouchTypes }
        }
        restrictedEnclosingScrollViews.removeAll()
    }

    private func enclosingScrollViews(of view: UIView) -> [UIScrollView] {
        var scrollViews: [UIScrollView] = []
        var ancestor = view.superview
        while let ancestorView = ancestor {
            if let scrollView = ancestorView as? UIScrollView { scrollViews.append(scrollView) }
            ancestor = ancestorView.superview
        }
        return scrollViews
    }

    /// PDFView's own scroll views, not the canvases (which are scroll views too).
    private func scrollViews(in view: UIView) -> [UIScrollView] {
        guard !(view is PKCanvasView) else { return [] }
        let nested = view.subviews.flatMap { subview in scrollViews(in: subview) }
        guard let scrollView = view as? UIScrollView else { return nested }
        return [scrollView] + nested
    }

    // MARK: Page overlays

    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        let identifier = ObjectIdentifier(page)
        if let existing = canvasesByPage[identifier], existing.page === page { return existing }
        let canvas = makeCanvas(for: page)
        canvasesByPage[identifier] = canvas
        return canvas
    }

    func pdfView(_ pdfView: PDFView, willDisplayOverlayView overlayView: UIView, for page: PDFPage) {
        guard let canvas = overlayView as? PDFPageCanvasView else { return }
        let identifier = ObjectIdentifier(page)
        displayedPages.insert(identifier)
        hiddenCanvasOrder.removeAll { hiddenIdentifier in hiddenIdentifier == identifier }
        configure(canvas)
    }

    func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
        guard let canvas = overlayView as? PDFPageCanvasView else { return }
        let identifier = ObjectIdentifier(page)
        displayedPages.remove(identifier)
        // Thumbnails and other views show the saved ink while no canvas covers the page.
        setInkAnnotationsHidden(false, on: page, group: canvas.inkTracker.group)
        hiddenCanvasOrder.append(identifier)
        while hiddenCanvasOrder.count > Self.retainedHiddenCanvasCount {
            let evictedIdentifier = hiddenCanvasOrder.removeFirst()
            if let evictedCanvas = canvasesByPage.removeValue(forKey: evictedIdentifier) { release(evictedCanvas) }
        }
    }

    private func makeCanvas(for page: PDFPage) -> PDFPageCanvasView {
        let canvas = PDFPageCanvasView(page: page, inkTracker: PDFPageInkTracker(group: PDFInkGroups.newGroup(on: page)))
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // Pages are white paper; dark-mode ink adaptation would make black ink invisible.
        canvas.overrideUserInterfaceStyle = .light
        canvas.isScrollEnabled = false
        canvas.minimumZoomScale = 1
        canvas.maximumZoomScale = 1
        canvas.contentInsetAdjustmentBehavior = .never
        toolPicker.addObserver(canvas)
        // Observers hear only later changes; start with the tool already selected.
        if #available(iOS 26.0, *), let selectedTool = toolPicker.selectedToolItem.tool {
            canvas.tool = selectedTool
        } else {
            (canvas as PKToolPickerObserver).toolPickerSelectedToolItemDidChange?(toolPicker)
        }
        configure(canvas)
        // PencilKit's own finger long press (its Select All and Insert Space menu) waits
        // until the press is known not to select PDF text.
        if let textSelectionRecognizer {
            for recognizer in longPressRecognizers(in: canvas) { recognizer.require(toFail: textSelectionRecognizer) }
        }
        // A finger tap on a highlight (with finger drawing) opens its menu instead of also
        // leaving a dot. The tap takes only touches on markup or with text selected, so
        // other strokes do not wait for it.
        if let markupTapRecognizer { canvas.drawingGestureRecognizer.require(toFail: markupTapRecognizer) }
        return canvas
    }

    /// Decoding a stored drawing takes tens of milliseconds for a full page, so it runs in
    /// the background; reading the group from the page's annotations stays here, on the
    /// main actor that owns the document.
    private func restoreStoredInkIfNeeded(on canvas: PDFPageCanvasView) {
        guard !canvas.hasRestoredStoredInk, let page = canvas.page else { return }
        canvas.hasRestoredStoredInk = true
        guard let editableGroup = PDFInkGroups.editableGroup(on: page) else {
            canvas.delegate = self
            return
        }
        canvas.isRestoringStoredInk = true
        Task { [weak self, weak canvas] in
            let decodedDrawing = await Task.detached(priority: .userInitiated) {
                try? PKDrawing(data: editableGroup.record.drawingData)
            }.value
            guard let self, let canvas, canvas.page === page, self.canvasesByPage[ObjectIdentifier(page)] === canvas else { return }
            canvas.isRestoringStoredInk = false
            if let decodedDrawing, let restored = PDFPageInkTracker.restoring(editableGroup, decodedDrawing: decodedDrawing) {
                canvas.inkTracker = restored.tracker
                // Set before the delegate, so loading the stored drawing is not recorded as an edit.
                canvas.drawing = restored.drawing
            }
            canvas.delegate = self
            self.configure(canvas)
        }
    }

    private func longPressRecognizers(in view: UIView) -> [UILongPressGestureRecognizer] {
        (view.gestureRecognizers ?? []).compactMap { recognizer in recognizer as? UILongPressGestureRecognizer }
            + view.subviews.flatMap { subview in longPressRecognizers(in: subview) }
    }

    /// A canvas shows the page's ink while annotating; otherwise the ink annotations do.
    private func configure(_ canvas: PDFPageCanvasView) {
        if input.isEnabled { restoreStoredInkIfNeeded(on: canvas) }
        canvas.drawingPolicy = input.drawsWithFinger ? .anyInput : .pencilOnly
        canvas.isHidden = !input.isEnabled
        canvas.isUserInteractionEnabled = input.isEnabled && !canvas.isRestoringStoredInk
        if let page = canvas.page {
            let isDisplayed = displayedPages.contains(ObjectIdentifier(page))
            setInkAnnotationsHidden(input.isEnabled && isDisplayed && !canvas.isRestoringStoredInk, on: page, group: canvas.inkTracker.group)
        }
    }

    private func release(_ canvas: PDFPageCanvasView) {
        writeDeferredInkRecord(of: canvas)
        // Undo steps that would change a canvas that no longer exists are dropped. The
        // canvas may already be out of the window, so ask the PDF view for the manager.
        pdfView?.undoManager?.removeAllActions(withTarget: canvas)
        toolPicker.removeObserver(canvas)
        canvas.delegate = nil
        if let page = canvas.page { setInkAnnotationsHidden(false, on: page, group: canvas.inkTracker.group) }
    }

    /// While a canvas covers a page, it shows the ink; the ink annotations are hidden so
    /// translucent strokes are not drawn twice.
    private func setInkAnnotationsHidden(_ isHidden: Bool, on page: PDFPage, group: String) {
        for annotation in page.annotations where annotation.value(forAnnotationKey: PDFPageManager.groupKey) as? String == group {
            if annotation.shouldDisplay == isHidden { annotation.shouldDisplay = !isHidden }
        }
    }

    // MARK: Drawing

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard let canvas = canvasView as? PDFPageCanvasView, let page = canvas.page, canvas.bounds.width > 0, canvas.bounds.height > 0 else { return }
        let pageIndex = session.document.index(for: page)
        guard pageIndex != NSNotFound else { return }
        do {
            let coordinates = try PageCoordinates(cropBox: page.bounds(for: .cropBox), overlaySize: canvas.bounds.size)
            // Archiving the whole drawing at every pen-up grows with the page's strokes;
            // the session asks for the record before it is needed (see `writeDeferredInkRecords`).
            let update = canvas.inkTracker.update(for: canvas.drawing, pageIndex: pageIndex, coordinates: coordinates, defersEditableRecord: true)
            try session.apply(.updateInk(update))
            if displayedPages.contains(ObjectIdentifier(page)) { setInkAnnotationsHidden(true, on: page, group: canvas.inkTracker.group) }
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }

    /// Writes the re-editing records that drawing deferred, for every canvas.
    func writeDeferredInkRecords() {
        for canvas in canvasesByPage.values { writeDeferredInkRecord(of: canvas) }
    }

    private func writeDeferredInkRecord(of canvas: PDFPageCanvasView) {
        guard canvas.inkTracker.hasDeferredEditableRecord, let page = canvas.page else { return }
        let pageIndex = session.document.index(for: page)
        // A deleted page's ink went with it.
        guard pageIndex != NSNotFound,
              let update = canvas.inkTracker.deferredEditableRecordUpdate(for: canvas.drawing, pageIndex: pageIndex) else { return }
        do {
            try session.apply(.updateInk(update))
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        beginInteraction?()
        pdfView?.clearSelection()
        // A text field or the selection menu may have taken first responder.
        if input.showsToolPicker, !toolPickerHost.isFirstResponder { toolPickerHost.becomeFirstResponder() }
    }

    private func updateToolPickerVisibility() {
        let showsPicker = input.isEnabled && input.showsToolPicker && pdfView?.window != nil
        toolPicker.setVisible(showsPicker, forFirstResponder: toolPickerHost)
        if showsPicker {
            if !toolPickerHost.isFirstResponder { toolPickerHost.becomeFirstResponder() }
        } else if toolPickerHost.isFirstResponder {
            toolPickerHost.resignFirstResponder()
        }
    }

    // MARK: Text selection

    /// While annotating, touches on a page belong to its canvas, so PDFKit's own text
    /// selection never sees them. A finger press selects the word under it; dragging
    /// extends the selection, and lifting shows Copy and the markup actions.
    @objc private func handleTextSelection(_ recognizer: UILongPressGestureRecognizer) {
        guard let pdfView else { return }
        let viewPoint = recognizer.location(in: pdfView)
        switch recognizer.state {
        case .began:
            beginInteraction?()
            editMenuInteraction?.dismissMenu()
            guard let page = pdfView.page(for: viewPoint, nearest: true) else { return }
            let pagePoint = pdfView.convert(viewPoint, to: page)
            selectionAnchor = (page, pagePoint)
            pdfView.currentSelection = page.selectionForWord(at: pagePoint)
        case .changed:
            guard let selectionAnchor, let page = pdfView.page(for: viewPoint, nearest: true) else { return }
            let pagePoint = pdfView.convert(viewPoint, to: page)
            let rangeSelection = session.document.selection(from: selectionAnchor.page, at: selectionAnchor.point, to: page, at: pagePoint)
            if let anchorWord = selectionAnchor.page.selectionForWord(at: selectionAnchor.point) { rangeSelection?.add(anchorWord) }
            if let rangeSelection, !(rangeSelection.string ?? "").isEmpty { pdfView.currentSelection = rangeSelection }
        case .ended:
            selectionAnchor = nil
            presentSelectionMenu()
        default:
            selectionAnchor = nil
        }
    }

    private func presentSelectionMenu() {
        guard let pdfView, let selection = pdfView.currentSelection, !(selection.string ?? "").isEmpty,
              let firstPage = selection.pages.first else { return }
        let selectionBounds = pdfView.convert(selection.bounds(for: firstPage), from: firstPage)
        let configuration = UIEditMenuConfiguration(identifier: Self.selectionMenuIdentifier, sourcePoint: CGPoint(x: selectionBounds.midX, y: selectionBounds.minY))
        editMenuInteraction?.presentEditMenu(with: configuration)
    }

    private func selectionMenu() -> UIMenu? {
        guard let selection = pdfView?.currentSelection, let selectedText = selection.string, !selectedText.isEmpty else { return nil }
        let copy = UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in UIPasteboard.general.string = selectedText }
        let highlightActions = PDFMarkupColor.highlightColors.map { color in
            UIAction(title: color.title, image: Self.swatch(for: color)) { [weak self] _ in self?.addMarkup(.highlight, color: color) }
        }
        let highlight = UIMenu(title: PDFMarkupKind.highlight.title, image: UIImage(systemName: "highlighter"), children: highlightActions)
        let underline = UIAction(title: PDFMarkupKind.underline.title, image: UIImage(systemName: "underline")) { [weak self] _ in self?.addMarkup(.underline, color: .red) }
        let strikeOut = UIAction(title: PDFMarkupKind.strikeOut.title, image: UIImage(systemName: "strikethrough")) { [weak self] _ in self?.addMarkup(.strikeOut, color: .red) }
        var children: [UIMenuElement] = [copy, highlight, underline, strikeOut]
        if let linkActions, let page = selection.pages.first, session.document.index(for: page) != NSNotFound {
            children.append(UIMenu(options: .displayInline, children: linkActions.menuElements(pageIndex: session.document.index(for: page), text: selectedText)))
        }
        return UIMenu(children: children)
    }

    private func addMarkup(_ kind: PDFMarkupKind, color: PDFMarkupColor) {
        guard let selection = pdfView?.currentSelection else { return }
        do {
            try session.addMarkup(kind, color: color, for: selection)
            pdfView?.clearSelection()
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }

    private static func swatch(for color: PDFMarkupColor) -> UIImage? {
        UIImage(systemName: "circle.fill")?.withTintColor(color.platformColor, renderingMode: .alwaysOriginal)
    }

    // MARK: Existing markup

    /// A tap on a highlight, underline or strikethrough offers to recolor or remove it;
    /// any other tap clears the text selection.
    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let pdfView else { return }
        let viewPoint = recognizer.location(in: pdfView)
        guard let markup = markup(at: viewPoint) else {
            pdfView.clearSelection()
            return
        }
        tappedMarkup = markup
        editMenuInteraction?.presentEditMenu(with: UIEditMenuConfiguration(identifier: Self.markupMenuIdentifier, sourcePoint: viewPoint))
    }

    private func markup(at viewPoint: CGPoint) -> (annotation: PDFAnnotation, page: PDFPage)? {
        guard input.isEnabled, let pdfView, let page = pdfView.page(for: viewPoint, nearest: false) else { return nil }
        return page.markupAnnotation(at: pdfView.convert(viewPoint, to: page)).map { annotation in (annotation, page) }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pdfView else { return false }
        if gestureRecognizer === markupTapRecognizer {
            return input.isEnabled && (markup(at: gestureRecognizer.location(in: pdfView)) != nil || pdfView.currentSelection != nil)
        }
        if gestureRecognizer === textSelectionRecognizer {
            let viewPoint = gestureRecognizer.location(in: pdfView)
            guard let page = pdfView.page(for: viewPoint, nearest: false) else { return false }
            return !(page.selectionForWord(at: pdfView.convert(viewPoint, to: page))?.string ?? "").isEmpty
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === markupTapRecognizer, let pdfView else { return true }
        return input.isEnabled && (markup(at: touch.location(in: pdfView)) != nil || pdfView.currentSelection != nil)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Taps never block scrolling; a selection drag must not scroll the page.
        gestureRecognizer === markupTapRecognizer
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        if configuration.identifier as? NSString == Self.selectionMenuIdentifier { return selectionMenu() }
        guard let (annotation, page) = tappedMarkup, let kind = PDFMarkupKind(annotationType: annotation.type) else { return nil }
        let colors = kind == .highlight ? PDFMarkupColor.highlightColors : [PDFMarkupColor.red] + PDFMarkupColor.highlightColors
        let colorActions = colors.map { color in
            UIAction(title: color.title, image: Self.swatch(for: color)) { [weak self] _ in
                guard let self else { return }
                do { try self.session.recolorMarkup(annotation, on: page, to: color) } catch { self.session.errorMessage = error.localizedDescription }
            }
        }
        let remove = UIAction(title: "Remove \(kind.title)", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            guard let self else { return }
            do { try self.session.removeMarkup(annotation, on: page) } catch { self.session.errorMessage = error.localizedDescription }
        }
        return UIMenu(children: [UIMenu(title: "Color", image: UIImage(systemName: "paintpalette"), children: colorActions), remove])
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, willDismissMenuFor configuration: UIEditMenuConfiguration, animator: any UIEditMenuInteractionAnimating) {
        // Showing the menu can take first responder from the tool picker's host.
        animator.addCompletion { [weak self] in self?.updateToolPickerVisibility() }
    }
}
#else
import AppKit

struct GraphitePDFView: NSViewRepresentable {
    let session: PDFSession
    var input: PDFAnnotationInput
    var isEmbedded = false
    var initialPageIndex: Int?
    /// The Mac viewer has no Pencil canvases; accepted so both platforms share one call.
    var beginInteraction: (() -> Void)?
    var linkActions: PDFLinkActions?

    final class Coordinator {
        var pageObserver: PDFViewPageObserver?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = session.document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        if let initialPage = initialPageIndex.flatMap(session.document.page(at:)) { view.go(to: initialPage) }
        context.coordinator.pageObserver = PDFViewPageObserver(session: session, view: view)
        session.pdfView = view
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {}

    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) {
        coordinator.pageObserver?.stop()
    }
}
#endif
