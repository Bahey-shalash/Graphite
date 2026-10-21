#if canImport(UIKit)
import UIKit
import PDFKit
import GraphiteCore
import GraphiteApple

/// The text boxes of one PDF view while it is shown: draws Graphite's boxes over each page's
/// ink (`PDFPageTextBoxesView`), answers taps of the text tool and of a finger on a box, keeps
/// the selected box's frame (`PDFTextBoxSelectionFrame`) and the box being typed in
/// (`PDFTextBoxEditor`) over the page as it scrolls and zooms, and follows the session's
/// `textBoxActivity`, which the bar under the page changes too.
@MainActor
final class PDFTextBoxInteraction {
    private let session: PDFSession
    private weak var pdfView: PDFView?
    /// The overlays of the pages shown, by page.
    private var overlays: [ObjectIdentifier: WeakPageOverlay] = [:]
    private var observers: [NSObjectProtocol] = []
    private var scrollObservation: NSKeyValueObservation?
    private var editor: PDFTextBoxEditor?
    /// True while a text view comes or goes: the document's change it makes is told back to
    /// this object, whose activity is not settled until it returns (`withEditorChanging`).
    private var isChangingEditor = false
    private lazy var selectionFrame = PDFTextBoxSelectionFrame(session: session, pdfView: pdfView) { [weak self] viewPoint in
        self?.beginEditingSelectedBox(caretAt: viewPoint)
    }

    private struct WeakPageOverlay {
        weak var page: PDFPage?
        weak var overlay: PDFPageOverlayView?
    }

    init(session: PDFSession, pdfView: PDFView) {
        self.session = session
        self.pdfView = pdfView
        observe()
        session.applyTextBoxFormat = { [weak self] change in self?.applyFormat(change) }
    }

    private func observe() {
        let center = NotificationCenter.default
        // Every page shown is drawn again after a change of a box, a few pages at most.
        session.registerTextBoxChangeObserver(for: self) { [weak self] in self?.textBoxesDidChange() }
        for name in [Notification.Name.PDFViewScaleChanged, .PDFViewVisiblePagesChanged] {
            observers.append(center.addObserver(forName: name, object: pdfView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.placeOverPages() } // Delivered on the main queue, as asked.
            })
        }
        // Undo and redo take the box back to a former state; typing ends first, and goes
        // into the history as its own step, so the undo is of what was there before.
        observers.append(center.addObserver(forName: .NSUndoManagerWillUndoChange, object: session.undoManager, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.endEditing() } // Delivered on the main queue, as asked.
        })
        observers.append(center.addObserver(forName: .NSUndoManagerWillRedoChange, object: session.undoManager, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.endEditing() } // Delivered on the main queue, as asked.
        })
    }

    func stop() {
        endEditing()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        session.unregisterTextBoxChangeObserver(for: self)
        scrollObservation = nil
        selectionFrame.stop()
        session.applyTextBoxFormat = nil
        for entry in overlays.values { if let page = entry.page { setBoxAnnotationsHidden(false, on: page) } }
        overlays = [:]
    }

    var isEditing: Bool { editor != nil }

    // MARK: Pages

    func pageDidAppear(_ page: PDFPage, in overlay: PDFPageOverlayView) {
        overlays[ObjectIdentifier(page)] = WeakPageOverlay(page: page, overlay: overlay)
        followScrolling()
        refresh(page)
    }

    func pageDidDisappear(_ page: PDFPage) {
        overlays[ObjectIdentifier(page)] = nil
        // Thumbnails and other views show the boxes' annotations while no overlay draws them.
        setBoxAnnotationsHidden(false, on: page)
    }

    private func textBoxesDidChange() {
        for entry in overlays.values { if let page = entry.page { refresh(page) } }
        syncWithActivity()
    }

    /// Draws the page's boxes over its ink, and hides their annotations so they are not drawn twice.
    private func refresh(_ page: PDFPage) {
        guard let overlay = overlays[ObjectIdentifier(page)]?.overlay else { return }
        let boxes = page.annotations.filter(PDFPageTextBoxesView.drawsAnnotation).compactMap(PDFTextBox.init(annotation:))
        let editedName = editor.flatMap { editor in editor.step.page.page === page ? editor.box.name : nil }
        overlay.textBoxesView.show(boxes, cropBox: page.bounds(for: .cropBox), hiding: editedName)
        setBoxAnnotationsHidden(true, on: page)
    }

    private func setBoxAnnotationsHidden(_ isHidden: Bool, on page: PDFPage) {
        for annotation in page.annotations where PDFPageTextBoxesView.drawsAnnotation(annotation) {
            if annotation.shouldDisplay == isHidden { annotation.shouldDisplay = !isHidden }
        }
    }

    /// The frame and the text view follow the page as the PDF view scrolls.
    private func followScrolling() {
        guard scrollObservation == nil, let scrollView = pdfView?.documentView?.enclosingScrollViewForTextBoxes else { return }
        scrollObservation = scrollView.observe(\.contentOffset) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.placeOverPages() } // The scroll view's offset changes on the main thread.
        }
    }

    private func placeOverPages() {
        editor?.place()
        selectionFrame.update()
    }

    // MARK: Taps

    /// A finger tap while the PDF is written on: ends typing, or selects the box under it, or,
    /// on the box already selected, types in it. False when the tap is not the boxes'.
    func handleTap(at viewPoint: CGPoint) -> Bool {
        if editor != nil {
            endEditing()
            session.textBoxActivity = .idle
            syncWithActivity()
            return true
        }
        guard let (page, box) = textBox(at: viewPoint) else {
            if session.textBoxActivity != .idle {
                session.textBoxActivity = .idle
                syncWithActivity()
            }
            return false
        }
        let selection = PDFTextBoxSelection(boxName: box.name, page: session.historyPage(for: page))
        if session.textBoxActivity == .selected(selection) {
            beginEditing(box, on: page, caretAt: viewPoint)
        } else {
            session.textBoxActivity = .selected(selection)
            syncWithActivity()
        }
        return true
    }

    /// Whether a finger tap at the point is the boxes': on a box, or while one is selected or typed in.
    func takesTap(at viewPoint: CGPoint) -> Bool {
        editor != nil || session.textBoxActivity != .idle || textBox(at: viewPoint) != nil
    }

    /// A tap of the text tool: types in the box under it, or ends typing, or starts a new box there.
    func handleTextToolTap(atWindowPoint windowPoint: CGPoint) {
        guard let pdfView else { return }
        let viewPoint = pdfView.convert(windowPoint, from: nil)
        if let (page, box) = textBox(at: viewPoint) {
            if editor?.box.name == box.name { return }
            endEditing()
            beginEditing(box, on: page, caretAt: viewPoint)
            return
        }
        if editor != nil {
            endEditing()
            session.textBoxActivity = .idle
            return
        }
        guard let page = pdfView.page(for: viewPoint, nearest: false), session.document.index(for: page) != NSNotFound else { return }
        let defaults = PDFTextBoxDefaults.stored(in: .standard)
        let newBox = session.newTextBox(at: pdfView.convert(viewPoint, to: page), on: page, style: defaults)
        beginEditing(newBox, isNew: true, on: page, caretAt: nil, typingLooks: defaults.attributes)
    }

    /// The topmost box at a point of the PDF view, with its page.
    private func textBox(at viewPoint: CGPoint) -> (PDFPage, PDFTextBox)? {
        guard let pdfView, let page = pdfView.page(for: viewPoint, nearest: false),
              let box = session.textBox(at: pdfView.convert(viewPoint, to: page), on: page) else { return nil }
        return (page, box)
    }

    // MARK: Typing

    private func beginEditingSelectedBox(caretAt viewPoint: CGPoint?) {
        guard let selection = session.textBoxActivity.selection, let page = selection.page.page, let box = session.textBox(selection) else { return }
        beginEditing(box, on: page, caretAt: viewPoint)
    }

    private func beginEditing(_ box: PDFTextBox, isNew: Bool = false, on page: PDFPage, caretAt viewPoint: CGPoint?,
                              typingLooks: PDFTextAttributes = PDFTextBoxDefaults.original.attributes) {
        guard let pdfView else { return }
        finishTyping()
        let historyPage = session.historyPage(for: page)
        // A box another application made, without a name, gets one as Graphite writes it.
        let named = box.name.isEmpty ? box.renamed(UUID().uuidString) : box
        let step = PDFTextBoxEditStep(before: isNew ? nil : box, page: historyPage)
        let editor = PDFTextBoxEditor(session: session, pdfView: pdfView, box: named, step: step, typingLooks: typingLooks) { [weak self] in
            self?.editedBoxDidChange()
        }
        self.editor = editor
        withEditorChanging {
            session.textBoxActivity = .editing(PDFTextBoxSelection(boxName: named.name, page: historyPage))
            refresh(page)
            editor.begin(caretAt: viewPoint)
        }
        editedBoxDidChange()
    }

    private func editedBoxDidChange() {
        guard let editor else { return }
        showFormat(PDFTextBoxDefaults(attributes: editor.currentLooks, boxStyle: editor.box.style))
    }

    /// Ends typing: the document takes the box, and the box is drawn over the ink again.
    func endEditing() {
        guard editor != nil else { return }
        finishTyping()
        if session.textBoxActivity.isEditing { session.textBoxActivity = .idle }
    }

    /// Commits the box typed in and takes its text view away, leaving the activity as it is.
    private func finishTyping() {
        guard let editor else { return }
        self.editor = nil
        withEditorChanging { editor.end() }
        if let page = editor.step.page.page { refresh(page) }
    }

    /// Runs a change of the text view that commits the box, so the session's notice of that
    /// commit does not start or end typing while the change is half done.
    private func withEditorChanging(_ change: () -> Void) {
        let wasChanging = isChangingEditor
        isChangingEditor = true
        defer { isChangingEditor = wasChanging }
        change()
    }

    private func applyFormat(_ change: PDFTextBoxFormatChange) {
        if let editor {
            editor.apply(change)
            PDFTextBoxDefaults(attributes: editor.currentLooks, boxStyle: editor.box.style).store(in: .standard)
            return
        }
        do {
            try session.changeSelectedTextBox(actionName: "Format Text") { box in box = change.applied(to: box) }
            if let selection = session.textBoxActivity.selection, let box = session.textBox(selection) {
                PDFTextBoxDefaults(box: box).store(in: .standard)
            }
        } catch {
            session.reportFailedChange(error)
        }
        syncWithActivity()
    }

    // MARK: The session's activity

    /// Gives the bar's format popover the format, only when it changes: each change of an
    /// observed value updates the views, which call `syncWithActivity` again.
    private func showFormat(_ format: PDFTextBoxDefaults?) {
        if session.textBoxFormat != format { session.textBoxFormat = format }
    }

    /// Shows what the session's `textBoxActivity` says: the frame of the selected box, the
    /// text view of the box typed in, or neither. Called after SwiftUI updates the view.
    func syncWithActivity() {
        guard !isChangingEditor else { return }
        switch session.textBoxActivity {
        case .idle:
            endEditing()
            showFormat(nil)
        case .selected(let selection):
            endEditing()
            if let box = session.textBox(selection) { showFormat(PDFTextBoxDefaults(box: box)) } else { session.textBoxActivity = .idle }
        case .editing(let selection):
            if editor == nil || editor?.box.name != selection.boxName { beginEditingSelectedBox(caretAt: nil) }
        }
        selectionFrame.update()
    }
}

private extension UIView {
    /// The nearest scroll view above this view, such as the one PDFKit scrolls pages in.
    var enclosingScrollViewForTextBoxes: UIScrollView? {
        var ancestor = superview
        while let view = ancestor {
            if let scrollView = view as? UIScrollView { return scrollView }
            ancestor = view.superview
        }
        return nil
    }
}
#endif
