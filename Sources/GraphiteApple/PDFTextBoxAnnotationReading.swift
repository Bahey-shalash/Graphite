import Foundation
import CoreGraphics
import PDFKit
import GraphiteCore

/// Reading a text box from a `/FreeText` annotation.
///
/// A box Graphite wrote is read from its record (`PDFTextBoxRecord`), as long as its
/// `/Contents` is still the text the record holds. Any other box, one made by Preview or
/// Acrobat, or one whose text another application changed, is read from the standard keys:
/// the rich text `/RC` where the file has it, the default style `/DS` and appearance `/DA`,
/// the alignment `/Q`, `/Rotate`, the fill `/C` and the border `/BS`. Anything that cannot be
/// read gives way to the next: bad rich text is the plain `/Contents`, an unusable record is
/// the standard keys. Nothing here traps on file data.
extension PDFTextBox {
    /// The box an annotation is, or nil for an annotation of another subtype. A box with no
    /// text, as another application can leave one, is a box with no runs.
    public init?(annotation: PDFAnnotation) {
        guard annotation.type == Self.annotationTypeName else { return nil }
        let box = (annotation as? PDFTextBoxAnnotation)?.readTextBox() ?? Self.reading(of: annotation)
        guard let box else { return nil }
        self = box
    }

    /// Reads the annotation afresh; `PDFTextBoxAnnotation` keeps what this returns.
    static func reading(of annotation: PDFAnnotation) -> PDFTextBox? {
        guard annotation.type == annotationTypeName else { return nil }
        let fileEntries = PDFAnnotationFileEntries(of: annotation)
        if var recorded = recordedBox(in: annotation) {
            recorded.preservedEntries = fileEntries?.preservedEntries ?? [:]
            return recorded
        }
        return standardBox(in: annotation, fileEntries: fileEntries)
    }

    /// Whether an annotation holds a record of Graphite's text box, without reading it.
    static func hasRecord(_ annotation: PDFAnnotation) -> Bool {
        annotation.type == annotationTypeName && annotation.value(forAnnotationKey: PDFPageManager.textBoxRecordKey) != nil
    }

    /// The box Graphite's record describes, placed where the annotation now is; nil when
    /// the annotation has no usable record or its text is no longer the record's.
    static func recordedBox(in annotation: PDFAnnotation) -> PDFTextBox? {
        if let made = (annotation as? PDFTextBoxAnnotation)?.madeTextBox { return made }
        guard annotation.type == annotationTypeName, let name = annotation.persistentName,
              let recordText = annotation.value(forAnnotationKey: PDFPageManager.textBoxRecordKey) as? String,
              let record = PDFTextBoxRecord.decoded(from: recordText),
              normalizedLineBreaks(annotation.contents ?? "") == normalizedLineBreaks(record.contents) else { return nil }
        let box = record.box(named: name, preservedEntries: [:])
        return placed(box, writtenIn: record.writtenRectangle, nowIn: annotation.bounds)
    }

    /// A box another application moved or resized: moved with its rectangle, and, when
    /// upright, given the rectangle's size, which is all a reader without the record changes.
    private static func placed(_ box: PDFTextBox, writtenIn writtenRectangle: CGRect, nowIn currentRectangle: CGRect) -> PDFTextBox {
        guard !currentRectangle.isNearlyEqual(to: writtenRectangle) else { return box }
        if box.rotationRadians == 0 {
            var resized = box
            resized.origin = CGPoint(x: currentRectangle.minX, y: currentRectangle.maxY)
            resized.width = max(Double(currentRectangle.width), minimumWidth)
            resized.height = Double(currentRectangle.height)
            return resized
        }
        return box.movingMiddle(to: CGPoint(x: currentRectangle.midX, y: currentRectangle.midY))
    }

    private static func normalizedLineBreaks(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    // MARK: The standard keys

    /// The padding PDFKit and Preview draw a `/FreeText`'s text with.
    static let standardPadding: Double = 2

    private static func standardBox(in annotation: PDFAnnotation, fileEntries: PDFAnnotationFileEntries?) -> PDFTextBox? {
        let contents = normalizedLineBreaks(annotation.contents ?? "")
        let defaultStyle = PDFTextStyleDeclarations.properties(of: annotation.value(forAnnotationKey: PDFPageManager.defaultStyleKey) as? String ?? "")
        let defaults = defaultStyle.applied(to: PDFPlatformFont.attributes(of: annotation))
        let richReading = fileEntries?.richText.flatMap { richText in PDFTextBoxRichText.reading(richText, defaults: defaults) }
        // Rich text that says something else than `/Contents` was not updated with it.
        let runs = richReading.flatMap { reading in normalizedLineBreaks(reading.runs.map(\.text).joined()) == contents ? reading.runs : nil }
            ?? [PDFTextRun(text: contents, attributes: defaults)]
        let rotation = quarterTurnRotation(of: annotation)
        let placement = placement(in: annotation.bounds, rotationRadians: rotation)
        let style = PDFTextBoxStyle(alignment: richReading?.alignment ?? defaultStyle.alignment ?? PDFPlatformFont.alignment(of: annotation),
                                    fillColor: PDFPlatformFont.fillColor(of: annotation), borderColor: .black,
                                    borderWidth: Double(annotation.border?.lineWidth ?? 0), padding: standardPadding)
        return PDFTextBox(name: annotation.persistentName ?? "", runs: runs, origin: placement.origin, width: placement.width,
                          height: placement.height, rotationRadians: rotation, style: style, preservedEntries: fileEntries?.preservedEntries ?? [:])
    }

    /// `/Rotate`, the quarter turns counterclockwise the text is turned by on its page, as
    /// the clockwise angle Graphite keeps.
    private static func quarterTurnRotation(of annotation: PDFAnnotation) -> Double {
        guard let degrees = (annotation.value(forAnnotationKey: PDFPageManager.rotateKey) as? NSNumber)?.intValue else { return 0 }
        let quarterTurns = (((degrees / 90) % 4) + 4) % 4
        return PictureRotation.normalized(-Double(quarterTurns) * .pi / 2)
    }

    /// The corner a box turned by quarter turns starts at in its rectangle, and its width and
    /// height along and across the text.
    static func placement(in rectangle: CGRect, rotationRadians: Double) -> (origin: CGPoint, width: Double, height: Double) {
        let quarterTurns = Int((-rotationRadians / (.pi / 2)).rounded())
        switch ((quarterTurns % 4) + 4) % 4 {
        case 1: return (CGPoint(x: rectangle.minX, y: rectangle.minY), Double(rectangle.height), Double(rectangle.width))
        case 2: return (CGPoint(x: rectangle.maxX, y: rectangle.minY), Double(rectangle.width), Double(rectangle.height))
        case 3: return (CGPoint(x: rectangle.maxX, y: rectangle.maxY), Double(rectangle.height), Double(rectangle.width))
        default: return (CGPoint(x: rectangle.minX, y: rectangle.maxY), Double(rectangle.width), Double(rectangle.height))
        }
    }
}
