import Foundation
import CoreGraphics
import PDFKit
import GraphiteCore

/// Writing a text box as a standard `/FreeText` annotation.
///
/// Every reader gets the text in `/Contents`, its looks in `/DA`, `/DS` and `/Q`, its fill in
/// `/C`, its border in `/BS` and, for a box turned by a quarter turn, `/Rotate`; and the box
/// exactly as Graphite draws it in the appearance stream (`PDFTextBoxAnnotation`). The rich
/// text is written under `textBoxRichTextKey`, as PDFKit does not write `/RC`; compaction
/// renames it `/RC` in the saved file (`PDFObjectCompaction`). Graphite's record of the box
/// (`PDFTextBoxRecord`) is under `textBoxRecordKey`. A link in the text is a `/Link`
/// annotation over it, which every reader opens.
extension PDFTextBox {
    /// - Parameter isForWrittenDocument: Whether the annotation's document will be written,
    ///   where it draws its appearance, or is shown, where it draws itself on the page.
    func makeAnnotation(isForWrittenDocument: Bool) throws -> PDFAnnotation {
        guard hasValidGeometry else { throw PDFTextBoxError.cannotBePlaced }
        let annotation: PDFTextBoxAnnotation = isForWrittenDocument ? PDFWrittenTextBoxAnnotation(box: self, drawsAppearance: true)
            : PDFTextBoxAnnotation(box: self, drawsAppearance: false)
        annotation.setPersistentName(name)
        annotation.contents = plainText
        PDFPlatformFont.apply(self, to: annotation)
        let border = PDFBorder()
        border.lineWidth = style.hasBorder ? CGFloat(style.borderWidth) : 0
        annotation.border = border
        annotation.setValue(PDFTextStyleDeclarations.defaultStyleText(of: self), forAnnotationKey: PDFPageManager.defaultStyleKey)
        annotation.setValue(try PDFTextBoxRecord(box: self).encodedText(), forAnnotationKey: PDFPageManager.textBoxRecordKey)
        setKeysPageTreeRewritesDrop(on: annotation)
        annotation.shouldPrint = true
        // A shown document is never written: its boxes are edited by Graphite, not in place by
        // PDFKit, whose own changes would not be saved.
        if !isForWrittenDocument { annotation.isReadOnly = true }
        return annotation
    }

    /// Sets the keys of the application that made the box, `/Rotate`, and the rich text,
    /// which PDFKit keeps but drops when a write rewrites the page tree: in a file saved
    /// before, the rich text is `/RC`, which PDFKit does not read at all.
    func setKeysPageTreeRewritesDrop(on annotation: PDFAnnotation) {
        annotation.setValue(PDFTextBoxRichText.richText(of: self), forAnnotationKey: PDFPageManager.textBoxRichTextKey)
        if let rotateDegrees = Self.rotateDegrees(for: rotationRadians), rotateDegrees != 0 {
            annotation.setValue(NSNumber(value: rotateDegrees), forAnnotationKey: PDFPageManager.rotateKey)
        }
        for (key, value) in preservedEntries.sorted(by: { first, second in first.key < second.key }) {
            if let platformValue = Self.platformValue(of: value) { annotation.setValue(platformValue, forAnnotationKey: PDFAnnotationKey(rawValue: "/" + key)) }
        }
    }

    /// `/Rotate` for an angle that is a quarter turn: degrees counterclockwise, as the
    /// standard counts them; nil for any other angle, which only the appearance shows.
    static func rotateDegrees(for rotationRadians: Double) -> Int? {
        let quarterTurns = -rotationRadians / (.pi / 2)
        guard abs(quarterTurns - quarterTurns.rounded()) < 1e-9 else { return nil }
        return (((Int(quarterTurns.rounded()) % 4) + 4) % 4) * 90
    }

    /// A kept value as PDFKit writes it back: a name as text starting with a slash, which
    /// PDFKit writes as a name. Text that itself starts with a slash would come back as a
    /// name too, so it is not written.
    private static func platformValue(of value: PDFPreservedValue) -> NSObject? {
        switch value {
        case .name(let name): ("/" + name) as NSString
        case .text(let text): text.hasPrefix("/") ? nil : text as NSString
        case .integer(let integer): NSNumber(value: integer)
        case .real(let real): NSNumber(value: real)
        case .boolean(let boolean): NSNumber(value: boolean)
        case .array(let elements): elements.compactMap(platformValue(of:)) as NSArray
        case .dictionary(let entries): NSDictionary(dictionary: entries.compactMapValues(platformValue(of:)))
        }
    }

    // MARK: Links

    /// A `/Link` annotation over each linked stretch of each line, named after the box and
    /// marked as its own (`textBoxLinkOwnerKey`), so moving or removing the box takes them.
    func makeLinkAnnotations(layout: PDFTextBoxLayout) -> [PDFAnnotation] {
        let boxToPage = layout.boxToPage
        return layout.linkAreas().enumerated().map { linkIndex, area in
            let corners = [CGPoint(x: area.rectangle.minX, y: area.rectangle.maxY), CGPoint(x: area.rectangle.maxX, y: area.rectangle.maxY),
                           CGPoint(x: area.rectangle.minX, y: area.rectangle.minY), CGPoint(x: area.rectangle.maxX, y: area.rectangle.minY)]
                .map { corner in corner.applying(boxToPage) }
            let bounds = area.rectangle.applying(boxToPage)
            let link = PDFAnnotation(bounds: bounds, forType: .link, withProperties: nil)
            link.url = area.url
            let border = PDFBorder()
            border.lineWidth = 0
            link.border = border
            // Points relative to the rectangle's corner, in the order the standard reads them.
            link.quadrilateralPoints = corners.map { corner in PDFMarkup.pointValue(CGPoint(x: corner.x - bounds.minX, y: corner.y - bounds.minY)) }
            link.setPersistentName(name + "-link-\(linkIndex + 1)")
            link.setValue(name, forAnnotationKey: PDFPageManager.textBoxLinkOwnerKey)
            return link
        }
    }
}


extension PDFTextBox {
    /// The box's annotation on a page, found again by its name, or, for another
    /// application's box without one, by its rectangle.
    public func reference(onPageAt pageIndex: Int) -> PDFAnnotationReference {
        PDFAnnotationReference(pageIndex: pageIndex, name: name.isEmpty ? nil : name, annotationType: Self.annotationTypeName, bounds: annotationBounds)
    }
}
