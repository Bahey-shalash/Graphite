#if canImport(UIKit)
import UIKit
import PDFKit
import GraphiteCore
import GraphiteApple

/// The view a text box is typed in: the system's text view, so the keyboard, Scribble with
/// Apple Pencil, dictation, the selection menu and ⌘B, ⌘I and ⌘U work as in any text field.
/// It keeps typing's own undo history while it is shown; the PDF's history takes the box as
/// one step when typing ends (`PDFTextBoxEditStep`).
final class PDFTextBoxEditingView: UITextView {
    private let typingUndoManager = UndoManager()
    override var undoManager: UndoManager? { typingUndoManager }
}

/// Types in one text box over a PDF view. The text view shows the box at the view's zoom,
/// turned as the box is, its top-left corner on the box's: every size is the box's times the
/// zoom, so it reads as sharply as the page, and the box grows downward as lines are added.
/// The document takes the typed box when typing ends, and before the PDF is saved.
@MainActor
final class PDFTextBoxEditor: NSObject, UITextViewDelegate {
    private let session: PDFSession
    private weak var pdfView: PDFView?
    let step: PDFTextBoxEditStep
    /// The box as typed so far.
    private(set) var box: PDFTextBox
    let textView = PDFTextBoxEditingView(frame: .zero, textContainer: nil)
    /// The zoom the text view's sizes are at.
    private var scale: CGFloat = 1
    /// The looks new text takes where the box has none yet.
    private var typingLooks: PDFTextAttributes
    /// Told when the box changes size or looks, for the bar's format popover.
    private let boxDidChange: () -> Void

    init(session: PDFSession, pdfView: PDFView, box: PDFTextBox, step: PDFTextBoxEditStep, typingLooks: PDFTextAttributes,
         boxDidChange: @escaping () -> Void) {
        self.session = session
        self.pdfView = pdfView
        self.box = box
        self.step = step
        self.typingLooks = box.runs.last?.attributes ?? typingLooks
        self.boxDidChange = boxDidChange
        super.init()
        configureTextView()
    }

    private func configureTextView() {
        textView.delegate = self
        textView.isScrollEnabled = false
        textView.backgroundColor = box.style.fillColor.map { fill in UIColor(cgColor: PDFTextBoxLayout.cgColor(fill)) } ?? .clear
        textView.textContainer.lineFragmentPadding = 0
        // The page is white paper in every appearance.
        textView.overrideUserInterfaceStyle = .light
        textView.layer.anchorPoint = .zero
        textView.layer.borderColor = UIColor.tintColor.cgColor
        textView.layer.borderWidth = 1
        textView.autocorrectionType = .default
        textView.accessibilityLabel = "Text box"
    }

    // MARK: Showing

    /// Shows the text view over the box, with the caret at a point of the PDF view, or at
    /// the end of the text.
    func begin(caretAt viewPoint: CGPoint?) {
        guard let pdfView else { return }
        pdfView.addSubview(textView)
        scale = max(pdfView.scaleFactor, 0.01)
        showText()
        place()
        textView.becomeFirstResponder()
        if let viewPoint, let position = textView.closestPosition(to: textView.convert(viewPoint, from: pdfView)) {
            textView.selectedTextRange = textView.textRange(from: position, to: position)
        } else {
            textView.selectedRange = NSRange(location: textView.attributedText.length, length: 0)
        }
        session.registerPendingInkRecordWriter(for: self) { [weak self] in self?.commit() }
    }

    private func showText() {
        let selection = textView.selectedRange
        textView.attributedText = PDFTextBoxTextConversion.attributedText(of: box.runs, style: box.style, scale: scale)
        textView.typingAttributes = PDFTextBoxTextConversion.textAttributes(of: typingLooks, style: box.style, scale: scale)
        let padding = CGFloat(box.style.padding) * scale
        textView.textContainerInset = UIEdgeInsets(top: padding, left: padding, bottom: padding, right: padding)
        if NSMaxRange(selection) <= textView.attributedText.length { textView.selectedRange = selection }
    }

    /// Places the text view over the box as the PDF view shows it now; at another zoom its
    /// text is set again at that zoom.
    func place() {
        guard let pdfView, let page = step.page.page, page.document === session.document else { return }
        let zoom = max(pdfView.scaleFactor, 0.01)
        if abs(zoom - scale) > 0.001 {
            scale = zoom
            showText()
        }
        let quarterTurns = ((page.rotation / 90) % 4 + 4) % 4
        textView.bounds = CGRect(x: 0, y: 0, width: CGFloat(box.width) * scale, height: CGFloat(box.height) * scale)
        textView.layer.position = pdfView.convert(box.origin, from: page)
        textView.transform = CGAffineTransform(rotationAngle: CGFloat(box.rotationRadians) + CGFloat(quarterTurns) * .pi / 2)
    }

    // MARK: Typing

    func textViewDidChange(_ textView: UITextView) {
        box.runs = PDFTextBoxTextConversion.runs(of: textView.attributedText, scale: scale, typingDefaults: typingLooks)
        let fittedHeight = PDFTextBoxLayout(box: box).fittedHeight
        if abs(fittedHeight - box.height) > 0.01 {
            box.height = fittedHeight
            place()
        }
        boxDidChange()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        boxDidChange()
    }

    /// The looks the format popover shows: of the text at the caret or the start of the
    /// selection, or the typing looks.
    var currentLooks: PDFTextAttributes {
        let location = textView.selectedRange.location
        guard textView.attributedText.length > 0 else { return typingLooks }
        let index = min(max(location == 0 ? 0 : location - 1, 0), textView.attributedText.length - 1)
        return PDFTextBoxTextConversion.runs(of: textView.attributedText.attributedSubstring(from: NSRange(location: index, length: 1)),
                                             scale: scale, typingDefaults: typingLooks).first?.attributes ?? typingLooks
    }

    /// Changes the looks of the selected text, or, with none selected, of the text typed next;
    /// a change of the box (alignment, fill, border) changes the whole box.
    func apply(_ change: PDFTextBoxFormatChange) {
        let selection = textView.selectedRange
        let changedStyle = change.applied(to: box.style, textColor: currentLooks.color)
        if changedStyle != box.style {
            box.style = changedStyle
            textView.backgroundColor = box.style.fillColor.map { fill in UIColor(cgColor: PDFTextBoxLayout.cgColor(fill)) } ?? .clear
            showText()
        } else if selection.length > 0 {
            let selected = textView.attributedText.attributedSubstring(from: selection)
            let changedRuns = PDFTextBoxTextConversion.runs(of: selected, scale: scale, typingDefaults: typingLooks).map { run in
                PDFTextRun(text: run.text, attributes: change.applied(to: run.attributes))
            }
            let changedText = PDFTextBoxTextConversion.attributedText(of: changedRuns, style: box.style, scale: scale)
            textView.textStorage.replaceCharacters(in: selection, with: changedText)
            textView.selectedRange = selection
        }
        typingLooks = change.applied(to: currentLooks)
        textView.typingAttributes = PDFTextBoxTextConversion.textAttributes(of: typingLooks, style: box.style, scale: scale)
        textViewDidChange(textView)
    }

    // MARK: Ending

    /// Gives the document the box as typed, as the one step of this typing.
    func commit() {
        do { try session.commitTextBox(box, in: step) }
        catch { session.reportFailedChange(error) }
    }

    /// Commits the box and takes the text view away.
    func end() {
        commit()
        session.unregisterPendingInkRecordWriter(for: self)
        textView.delegate = nil
        if textView.isFirstResponder { textView.resignFirstResponder() }
        textView.removeFromSuperview()
    }
}
#endif
