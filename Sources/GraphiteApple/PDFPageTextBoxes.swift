import Foundation
import PDFKit
import GraphiteCore

/// Text boxes on PDF pages, as edits (`PDFEdit.addTextBox`, `.replaceTextBox`,
/// `.removeTextBox`) applied the same way to the shown document and to the one saving writes.
///
/// A page's annotations are in this order: other applications' annotations, then Graphite's
/// pictures, its ink, and its text boxes, each box followed by the links over its text. The
/// boxes are over the ink in every reader, as they are on screen. A box another application
/// made stays where it is among the page's annotations until Graphite writes it again.
extension PDFPageManager {
    static func addTextBox(_ textBox: PDFTextBox, to page: PDFPage, isForWrittenDocument: Bool) throws {
        try add(textBox, to: page, isForWrittenDocument: isForWrittenDocument)
    }

    static func replaceTextBox(_ reference: PDFAnnotationReference, with textBox: PDFTextBox, in document: PDFDocument, isForWrittenDocument: Bool) throws {
        let (page, annotation) = try textBoxAnnotation(reference, in: document)
        var replacement = textBox
        // The box keeps the keys of the application that made it, whatever the edit says.
        replacement.preservedEntries = PDFTextBox(annotation: annotation)?.preservedEntries ?? textBox.preservedEntries
        removeTextBox(annotation, from: page)
        try add(replacement, to: page, isForWrittenDocument: isForWrittenDocument)
    }

    static func removeTextBox(_ reference: PDFAnnotationReference, from document: PDFDocument) throws {
        let (page, annotation) = try textBoxAnnotation(reference, in: document)
        removeTextBox(annotation, from: page)
    }

    /// The text boxes on a page, the lowest first: Graphite's and other applications'.
    public static func textBoxes(on page: PDFPage) -> [PDFTextBox] {
        page.annotations.compactMap(PDFTextBox.init(annotation:))
    }

    private static func add(_ textBox: PDFTextBox, to page: PDFPage, isForWrittenDocument: Bool) throws {
        let annotation = try textBox.makeAnnotation(isForWrittenDocument: isForWrittenDocument)
        // Added after everything: the page's text boxes are its last annotations.
        page.addAnnotation(annotation)
        let layout = PDFTextBoxLayout(box: textBox)
        for link in textBox.makeLinkAnnotations(layout: layout) { page.addAnnotation(link) }
    }

    private static func textBoxAnnotation(_ reference: PDFAnnotationReference, in document: PDFDocument) throws -> (PDFPage, PDFAnnotation) {
        guard reference.pageIndex >= 0, reference.pageIndex < document.pageCount, let page = document.page(at: reference.pageIndex) else {
            throw PDFTextBoxError.pageMissing
        }
        let annotations = page.annotations
        guard let annotation = annotations.first(where: reference.matches) ?? annotations.first(where: reference.matchesAfterNameWasLost),
              annotation.type == PDFTextBox.annotationTypeName else { throw PDFTextBoxError.boxMissing }
        return (page, annotation)
    }

    /// Removes the box and the links that belong to it. A popup another application gave the
    /// box goes with it, as it would be left without a parent.
    private static func removeTextBox(_ annotation: PDFAnnotation, from page: PDFPage) {
        if let name = annotation.persistentName {
            for link in page.annotations where link.value(forAnnotationKey: textBoxLinkOwnerKey) as? String == name { page.removeAnnotation(link) }
        }
        if let popup = annotation.popup, popup.page === page { page.removeAnnotation(popup) }
        page.removeAnnotation(annotation)
    }

    // MARK: Order

    /// Whether the annotation is one of Graphite's text boxes or a link over one's text.
    static func isTextBoxOnTop(_ annotation: PDFAnnotation) -> Bool {
        PDFTextBox.hasRecord(annotation) || annotation.value(forAnnotationKey: textBoxLinkOwnerKey) != nil
    }

    /// Puts Graphite's text boxes and their links after everything else on the page, in the
    /// order they had, after pictures or ink were put back under them.
    static func moveTextBoxesToTop(of page: PDFPage) {
        let onTop = page.annotations.filter(isTextBoxOnTop)
        for annotation in onTop { page.removeAnnotation(annotation) }
        for annotation in onTop { page.addAnnotation(annotation) }
    }

    /// Takes off the page the text boxes at the end of its annotations, to be added again
    /// after new ink. Only the end is read, so a stroke costs the same on a full page (FR-104).
    static func takeTextBoxesOffTop(of page: PDFPage) -> [PDFAnnotation] {
        let annotations = page.annotations
        var firstOnTop = annotations.endIndex
        while firstOnTop > annotations.startIndex, isTextBoxOnTop(annotations[firstOnTop - 1]) { firstOnTop -= 1 }
        let onTop = Array(annotations[firstOnTop...])
        for annotation in onTop { page.removeAnnotation(annotation) }
        return onTop
    }

    // MARK: Page tree rewrites

    /// When a write also rewrites the page tree, PDFKit drops keys it does not read; a text
    /// box Graphite wrote gets its kept keys and its `/Rotate` again
    /// (`preserveGraphiteKeysThroughPageTreeRewrite`).
    static func preserveTextBoxEntriesThroughPageTreeRewrite(of annotation: PDFAnnotation) {
        guard PDFTextBox.hasRecord(annotation), let box = PDFTextBox(annotation: annotation) else { return }
        box.setKeysPageTreeRewritesDrop(on: annotation)
    }
}
