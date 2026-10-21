import Foundation
import CoreGraphics
import PDFKit
import GraphiteCore

/// A text box as a `/FreeText` annotation that draws its own text with Core Text
/// (`PDFTextBoxLayout`): its appearance in a document that is written, so every reader
/// shows exactly Graphite's text, and itself on a page that is shown, sharp at any zoom.
///
/// PDFKit calls the same method for both, with different coordinates; see
/// `PDFPictureAnnotation`, which is made the same way. Each annotation is made for one of
/// them. PDFKit also makes the `/FreeText` annotations it reads from a file one of these
/// (`PDFAnnotationDrawingDelegate`, `PDFWrittenDocumentDelegate`): one that holds
/// Graphite's record of a box reads it at its first drawing and from then on draws the box
/// itself; any other is drawn by PDFKit from the appearance its application wrote.
class PDFTextBoxAnnotation: PDFAnnotation {
    // Optional references only, set before the annotation is shared; see
    // `PDFOutlinedInkAnnotation` for why.
    private var madeLayout: PDFTextBoxLayout?
    private var madeDrawsAppearance = false
    /// For an annotation PDFKit read from a file: what was read at the first drawing. Set
    /// once, under `fileReadingLock`, since PDFKit draws pages on several threads.
    private var layoutReadFromFile: PDFTextBoxReadFromFile?
    private static let fileReadingLock = NSLock()

    /// Whether an annotation PDFKit read from a file draws an appearance for the file
    /// being written rather than itself on a shown page.
    class var drawsAppearanceWhenReadFromFile: Bool { false }

    init(box: PDFTextBox, drawsAppearance: Bool) {
        madeLayout = PDFTextBoxLayout(box: box)
        madeDrawsAppearance = drawsAppearance
        super.init(bounds: box.annotationBounds, forType: .freeText, withProperties: nil)
    }

    override init(bounds: CGRect, forType annotationType: PDFAnnotationSubtype, withProperties properties: [AnyHashable: Any]?) {
        super.init(bounds: bounds, forType: annotationType, withProperties: properties)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// The box Graphite made this annotation for; nil for one PDFKit read from a file.
    var madeTextBox: PDFTextBox? { madeLayout?.box }

    /// For an annotation read from a file: the box read from it, kept, since the session
    /// looks for the boxes of a page at every tap. Set once, under `fileReadingLock`.
    private var boxReadFromFile: PDFTextBoxReading?

    /// The box an annotation read from a file is, read once (`PDFTextBox.reading(of:)`).
    func readTextBox() -> PDFTextBox? {
        if let madeTextBox { return madeTextBox }
        Self.fileReadingLock.lock()
        let earlierReading = boxReadFromFile
        Self.fileReadingLock.unlock()
        if let earlierReading { return earlierReading.box }
        let reading = PDFTextBoxReading(box: PDFTextBox.reading(of: self))
        Self.fileReadingLock.lock()
        defer { Self.fileReadingLock.unlock() }
        if boxReadFromFile == nil { boxReadFromFile = reading }
        return boxReadFromFile?.box
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let (layout, drawsAppearance) = currentLayout() else {
            super.draw(with: box, in: context)
            return
        }
        context.saveGState()
        if drawsAppearance {
            if let mediaBoxOrigin = page?.bounds(for: .mediaBox).origin { context.translateBy(x: -mediaBoxOrigin.x, y: -mediaBoxOrigin.y) }
        } else {
            page?.transform(context, for: box)
        }
        layout.draw(inPageContext: context)
        context.restoreGState()
    }

    private func currentLayout() -> (PDFTextBoxLayout, Bool)? {
        if let madeLayout { return (madeLayout, madeDrawsAppearance) }
        return readLayoutFromFile().map { layout in (layout, Self.drawsAppearanceWhenReadFromFile) }
    }

    /// The box an annotation read from a file holds, read once; nil when it holds no
    /// record of Graphite's, and PDFKit then draws its saved appearance.
    private func readLayoutFromFile() -> PDFTextBoxLayout? {
        Self.fileReadingLock.lock()
        let earlierReading = layoutReadFromFile
        Self.fileReadingLock.unlock()
        if let earlierReading { return earlierReading.layout }
        // Read outside the lock, so pages drawn at the same time do not wait for each
        // other; two threads may both read it the first time, harmlessly.
        let layout = PDFTextBox.recordedBox(in: self).map(PDFTextBoxLayout.init(box:))
        Self.fileReadingLock.lock()
        defer { Self.fileReadingLock.unlock() }
        if layoutReadFromFile == nil { layoutReadFromFile = PDFTextBoxReadFromFile(layout: layout) }
        return layoutReadFromFile?.layout
    }
}

/// A text box read from the file of a document that will be written: when PDFKit draws its
/// appearance again (a change of the page tree rewrites every annotation), it is Graphite's
/// drawing of the box, not PDFKit's plain one.
final class PDFWrittenTextBoxAnnotation: PDFTextBoxAnnotation {
    override class var drawsAppearanceWhenReadFromFile: Bool { true }
}

/// The result of reading a text box's drawing from a file, kept so it is read once.
final class PDFTextBoxReadFromFile: Sendable {
    let layout: PDFTextBoxLayout?

    init(layout: PDFTextBoxLayout?) { self.layout = layout }
}

/// The box read from an annotation of a file, nil for a `/FreeText` with no text at all.
final class PDFTextBoxReading: Sendable {
    let box: PDFTextBox?

    init(box: PDFTextBox?) { self.box = box }
}

extension CGRect {
    /// Whether two rectangles are the same but for the last digits a file changes.
    func isNearlyEqual(to other: CGRect, tolerance: CGFloat = 0.01) -> Bool {
        abs(minX - other.minX) < tolerance && abs(minY - other.minY) < tolerance
            && abs(width - other.width) < tolerance && abs(height - other.height) < tolerance
    }
}
