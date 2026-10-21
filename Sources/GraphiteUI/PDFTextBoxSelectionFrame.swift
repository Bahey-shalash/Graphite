#if canImport(UIKit)
import UIKit
import PDFKit
import GraphiteCore
import GraphiteApple

/// The frame of the selected text box over a PDF view (`SelectionFrameView`): drag inside to
/// move the box, a corner to make it wider or narrower (its height follows its text), the
/// arrow handle to turn it; a tap inside types in it. Each change is one step of the PDF's
/// history, made when the drag ends.
@MainActor
final class PDFTextBoxSelectionFrame: NSObject {
    private let session: PDFSession
    private weak var pdfView: PDFView?
    private var frameView: SelectionFrameView?
    /// The box the frame's preview and label were made for, made again only when it changes.
    private var shownBox: PDFTextBox?
    private let beginEditing: (CGPoint) -> Void

    init(session: PDFSession, pdfView: PDFView?, beginEditing: @escaping (CGPoint) -> Void) {
        self.session = session
        self.pdfView = pdfView
        self.beginEditing = beginEditing
        super.init()
    }

    func stop() {
        frameView?.removeFromSuperview()
        frameView = nil
        shownBox = nil
    }

    /// The selected box and its page, while both exist and the box is not typed in.
    private var selected: (box: PDFTextBox, page: PDFPage)? {
        guard case .selected(let selection) = session.textBoxActivity, let page = selection.page.page,
              let box = session.textBox(selection) else { return nil }
        return (box, page)
    }

    /// Shows, moves or hides the frame after the selection or the page under it changed.
    func update() {
        guard let pdfView, pdfView.window != nil, let (box, page) = selected else {
            stop()
            return
        }
        let frame = frameView ?? makeFrameView(in: pdfView)
        // Not while a drag moves the frame: the box follows when the drag ends.
        guard !frame.dragRecognizers.contains(where: { recognizer in recognizer.state == .began || recognizer.state == .changed }) else { return }
        let geometry = Self.geometry(of: box, on: page, in: pdfView)
        frame.rotation = geometry.rotation
        frame.unrotatedFrame = geometry.unrotatedFrame
        frame.centerLimits = pdfView.convert(page.bounds(for: .cropBox), from: page)
        guard box != shownBox else { return }
        shownBox = box
        frame.dragPreview = Self.preview(of: box)
        frame.accessibilityLabel = "Selected text box: " + box.plainText.prefix(80)
    }

    /// Where the box is on screen: the rectangle before it is turned, about its middle, and
    /// its angle on screen, which is the box's on a page shown turned by quarter turns.
    static func geometry(of box: PDFTextBox, on page: PDFPage, in pdfView: PDFView) -> (unrotatedFrame: CGRect, rotation: CGFloat) {
        let scale = pdfView.scaleFactor
        let middle = pdfView.convert(box.middle, from: page)
        let size = CGSize(width: CGFloat(box.width) * scale, height: CGFloat(box.height) * scale)
        let quarterTurns = ((page.rotation / 90) % 4 + 4) % 4
        return (CGRect(x: middle.x - size.width / 2, y: middle.y - size.height / 2, width: size.width, height: size.height),
                CGFloat(box.rotationRadians) + CGFloat(quarterTurns) * .pi / 2)
    }

    private func makeFrameView(in pdfView: PDFView) -> SelectionFrameView {
        let frame = SelectionFrameView(frame: .zero)
        frame.allowsRotation = true
        frame.staysInSuperviewSafeArea = true
        frame.frameChangeDidEnd = { [weak self] unrotatedFrame in self?.frameChangeDidEnd(unrotatedFrame) }
        frame.rotationChangeDidEnd = { [weak self] rotation in self?.rotationChangeDidEnd(rotation) }
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        frame.addGestureRecognizer(tap)
        pdfView.addSubview(frame)
        frameView = frame
        if let scrollView = Self.scrollView(in: pdfView) {
            for recognizer in frame.dragRecognizers { scrollView.panGestureRecognizer.require(toFail: recognizer) }
        }
        return frame
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, let pdfView else { return }
        beginEditing(recognizer.location(in: pdfView))
    }

    /// The box moved, or made wider or narrower from a corner: its top-left corner goes where
    /// the frame's is, its width is the frame's, and its height follows its text again.
    private func frameChangeDidEnd(_ unrotatedFrame: CGRect) {
        guard let pdfView, let (box, page) = selected, pdfView.scaleFactor > 0 else { return }
        let screenRotation = Self.geometry(of: box, on: page, in: pdfView).rotation
        let middle = CGPoint(x: unrotatedFrame.midX, y: unrotatedFrame.midY)
        let topLeft = PictureRotation.point(CGPoint(x: unrotatedFrame.minX, y: unrotatedFrame.minY), turnedBy: Double(screenRotation), about: middle)
        let origin = pdfView.convert(topLeft, to: page)
        let width = Double(unrotatedFrame.width / pdfView.scaleFactor)
        let isResize = abs(width - box.width) > 0.5
        do {
            try session.changeSelectedTextBox(actionName: isResize ? "Resize Text Box" : "Move Text Box") { changed in
                changed.origin = origin
                changed.width = max(width, PDFTextBox.minimumWidth)
            }
        } catch {
            session.reportFailedChange(error)
        }
        update()
    }

    private func rotationChangeDidEnd(_ rotation: CGFloat) {
        guard let pdfView, let (box, page) = selected else { return }
        let pageTurn = Self.geometry(of: box, on: page, in: pdfView).rotation - CGFloat(box.rotationRadians)
        do {
            try session.changeSelectedTextBox(actionName: "Rotate Text Box") { changed in changed = changed.rotated(to: Double(rotation - pageTurn)) }
        } catch {
            session.reportFailedChange(error)
        }
        update()
    }

    /// The box as it is drawn, for the frame to carry while it is dragged.
    private static func preview(of box: PDFTextBox) -> UIImage? {
        guard box.width > 0, box.height > 0 else { return nil }
        let layout = PDFTextBoxLayout(box: box)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: box.width, height: box.height), format: format).image { rendererContext in
            let context = rendererContext.cgContext
            // The box's space counts upward; the image's downward.
            context.translateBy(x: 0, y: CGFloat(box.height))
            context.scaleBy(x: 1, y: -1)
            layout.drawInBoxSpace(context)
        }
    }

    private static func scrollView(in view: UIView) -> UIScrollView? {
        for subview in view.subviews {
            if let scrollView = subview as? UIScrollView { return scrollView }
            if let scrollView = scrollView(in: subview) { return scrollView }
        }
        return nil
    }
}
#endif
