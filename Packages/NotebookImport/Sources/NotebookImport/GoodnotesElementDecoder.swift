import CoreGraphics
import Foundation

/// The kinds of element body in a page's layer, with the fields each is known to have and the field that holds its
/// drawing position.
enum GoodnotesElementKind: Int {
    case picture = 1
    case stroke = 7
    case rtfTextBox = 8
    case shapeFill = 9
    case rtfTextElement = 12
    case stickyNote = 20
    case textBox = 21

    private static let knownStrokeFieldNumbers = GoodnotesStrokeField.knownFieldNumbers
    private static let knownPictureFieldNumbers = GoodnotesPictureField.knownFieldNumbers
    private static let knownShapeFillFieldNumbers = GoodnotesShapeFillField.knownFieldNumbers
    private static let knownRTFTextBoxFieldNumbers = GoodnotesRTFTextBoxField.knownFieldNumbers
    private static let knownRTFTextElementFieldNumbers = GoodnotesRTFTextElementField.knownFieldNumbers
    private static let knownStickyNoteFieldNumbers = GoodnotesStickyNoteField.knownFieldNumbers
    private static let knownTextBoxFieldNumbers = GoodnotesTextBoxField.knownFieldNumbers

    /// The fields of the kind's layout (its `GoodnotesFieldNumber` enum); any other field is reported.
    var knownFieldNumbers: Set<Int> {
        switch self {
        case .stroke: Self.knownStrokeFieldNumbers
        case .picture: Self.knownPictureFieldNumbers
        case .shapeFill: Self.knownShapeFillFieldNumbers
        case .rtfTextBox: Self.knownRTFTextBoxFieldNumbers
        case .rtfTextElement: Self.knownRTFTextElementFieldNumbers
        case .stickyNote: Self.knownStickyNoteFieldNumbers
        case .textBox: Self.knownTextBoxFieldNumbers
        }
    }

    var positionFieldNumber: Int {
        switch self {
        case .stroke: GoodnotesStrokeField.drawingPosition.rawValue
        case .picture: GoodnotesPictureField.drawingPosition.rawValue
        case .shapeFill: GoodnotesShapeFillField.drawingPosition.rawValue
        case .rtfTextBox: GoodnotesRTFTextBoxField.drawingPosition.rawValue
        case .rtfTextElement: GoodnotesRTFTextElementField.drawingPosition.rawValue
        case .stickyNote: GoodnotesStickyNoteField.drawingPosition.rawValue
        case .textBox: GoodnotesTextBoxField.drawingPosition.rawValue
        }
    }
}

/// Decodes one element body of a page's layer into its value, reporting fields it does not know.
struct GoodnotesElementDecoder {
    private static let knownShapeFieldNumbers = GoodnotesShapeField.knownFieldNumbers
    /// A text attribute size of -404 means "not set, use the default".
    private static let unsetTextAttributeSize = -404.0

    let limits: NotebookImportLimits
    let attachments: [String: GoodnotesAttachment]

    func content(of kind: GoodnotesElementKind, fields: GoodnotesRecordFields,
                 issues: inout GoodnotesIssueList) throws(GoodnotesReadingError) -> GoodnotesElementContent {
        for fieldNumber in fields.fieldNumbers.subtracting(kind.knownFieldNumbers).sorted() {
            issues.report(.elementFieldNotKnown(elementKind: kind.rawValue, fieldNumber: fieldNumber))
        }
        switch kind {
        case .stroke: return .stroke(try stroke(fields, issues: &issues))
        case .picture: return .picture(try picture(fields, issues: &issues))
        case .shapeFill: return .shapeFill(try shapeFill(fields, issues: &issues))
        case .textBox: return .textBox(try textBox(fields))
        case .stickyNote: return .stickyNote(try stickyNote(fields))
        case .rtfTextBox:
            return .rtfTextBox(GoodnotesRTFTextBox(frame: try fields.rectangle(GoodnotesRTFTextBoxField.frame),
                                                   textFrame: try fields.rectangle(GoodnotesRTFTextBoxField.textFrame),
                                                   rtf: try fields.string(GoodnotesRTFTextBoxField.rtf)))
        case .rtfTextElement: return .rtfTextElement(rtf: try fields.string(GoodnotesRTFTextElementField.rtf))
        }
    }

    private func stroke(_ fields: GoodnotesRecordFields, issues: inout GoodnotesIssueList) throws(GoodnotesReadingError) -> GoodnotesStroke {
        let pathBytes = try fields.compressedPayload(GoodnotesStrokeField.path, limits: limits)
        let image: TplImage
        do throws(TplImageError) { image = try TplImage(pathBytes) } catch { throw .tplImage(error) }
        let shape = try fields.hasNonEmptyBytes(GoodnotesStrokeField.shape)
            ? try self.shape(try fields.fields(GoodnotesStrokeField.shape), issues: &issues) : nil
        let path = try GoodnotesStrokePathDecoder.path(of: image, issues: &issues)
        return GoodnotesStroke(ink: Self.ink(try fields.varint(GoodnotesStrokeField.ink) ?? 0), color: try fields.color(GoodnotesStrokeField.color),
                               isHighlighter: try fields.varint(GoodnotesStrokeField.isHighlighter) == 1,
                               isTape: try fields.hasNonEmptyBytes(GoodnotesStrokeField.tape),
                               groupIdentifier: try fields.nonEmptyString(GoodnotesStrokeField.groupIdentifier),
                               offset: try fields.vector(GoodnotesStrokeField.offset), shape: shape, path: path)
    }

    private static func ink(_ code: UInt64) -> GoodnotesStroke.Ink {
        switch code {
        case 0: .ballPenOrHighlighter
        case 1: .fountainPenBrushPenOrTape
        case 4: .olderVaryingWidth
        case 5: .pencil
        default: .unknown(code)
        }
    }

    /// The first geometry field present, in field order: polyline, arc, rectangle, ellipse.
    private func shape(_ fields: GoodnotesRecordFields, issues: inout GoodnotesIssueList) throws(GoodnotesReadingError) -> GoodnotesShape {
        for fieldNumber in fields.fieldNumbers.subtracting(Self.knownShapeFieldNumbers).sorted() { issues.report(.shapeFieldNotKnown(fieldNumber)) }
        let width = fields.contains(GoodnotesShapeField.width) ? try fields.float(GoodnotesShapeField.width) : nil
        return GoodnotesShape(geometry: try geometry(of: fields), width: width)
    }

    /// The first geometry field present, in field order; nil when there is none.
    private func geometry(of fields: GoodnotesRecordFields) throws(GoodnotesReadingError) -> GoodnotesShape.Geometry? {
        if fields.contains(GoodnotesShapeField.polyline) {
            var points: [CGPoint] = []
            for point in try fields.fields(GoodnotesShapeField.polyline).repeatedFields(GoodnotesPolylineField.point) {
                points.append(try point.pointValue())
            }
            return .polyline(points)
        } else if fields.contains(GoodnotesShapeField.arcThroughThreePoints) {
            let arc = try fields.fields(GoodnotesShapeField.arcThroughThreePoints)
            return .arcThroughThreePoints(try arc.point(GoodnotesArcField.start), try arc.point(GoodnotesArcField.middle),
                                          try arc.point(GoodnotesArcField.end))
        } else if fields.contains(GoodnotesShapeField.rectangle) {
            let rectangle = try fields.fields(GoodnotesShapeField.rectangle)
            return .rectangle(center: try rectangle.point(GoodnotesShapeRectangleField.center), size: try rectangle.size(GoodnotesShapeRectangleField.size),
                              angleRadians: try rectangle.float(GoodnotesShapeRectangleField.angleRadians))
        } else if fields.contains(GoodnotesShapeField.ellipse) {
            let ellipse = try fields.fields(GoodnotesShapeField.ellipse)
            return .ellipse(center: try ellipse.point(GoodnotesShapeEllipseField.center), radii: try ellipse.size(GoodnotesShapeEllipseField.radii),
                            angleRadians: try ellipse.float(GoodnotesShapeEllipseField.angleRadians))
        } else {
            return nil
        }
    }

    private func picture(_ fields: GoodnotesRecordFields, issues: inout GoodnotesIssueList) throws(GoodnotesReadingError) -> GoodnotesPicture {
        let placement = try fields.fields(GoodnotesPictureField.placement)
        let kindCode = try fields.varint(GoodnotesPictureField.kind)
        let kind: GoodnotesPicture.Kind? = switch kindCode {
        case nil: nil
        case 2?: .jpeg2000Sticker
        case 5?: .animatedGIF
        case let code?: .unknown(code)
        }
        let attachmentIdentifier = try fields.string(GoodnotesPictureField.attachment)
        var attachment: GoodnotesAttachment?
        if !attachmentIdentifier.isEmpty {
            attachment = attachments[attachmentIdentifier]
            if attachment == nil { issues.report(.attachmentNotInLog(attachmentIdentifier: attachmentIdentifier)) }
        }
        return GoodnotesPicture(attachment: attachment, boundingBox: try fields.rectangle(GoodnotesPictureField.boundingBox),
                                center: try placement.point(GoodnotesPicturePlacementField.center),
                                size: try placement.size(GoodnotesPicturePlacementField.sizeBeforeTurning),
                                rotationRadians: try placement.float(GoodnotesPicturePlacementField.rotationRadians), kind: kind)
    }

    private func shapeFill(_ fields: GoodnotesRecordFields, issues: inout GoodnotesIssueList) throws(GoodnotesReadingError) -> GoodnotesShapeFill {
        var outlineStrokeIdentifiers: [String] = []
        let outlineFieldNumber = GoodnotesShapeFillField.outlineStrokeIdentifier.rawValue
        for value in fields.message.values(outlineFieldNumber) {
            do throws(ProtocolBufferError) {
                outlineStrokeIdentifiers.append(try ProtocolBufferMessage.string(from: ProtocolBufferMessage.bytes(of: value, fieldNumber: outlineFieldNumber),
                                                                                 fieldNumber: outlineFieldNumber))
            } catch {
                throw .protocolBuffer(error)
            }
        }
        return GoodnotesShapeFill(color: try fields.color(GoodnotesShapeFillField.color),
                                  shape: fields.contains(GoodnotesShapeFillField.geometry)
                                      ? try shape(try fields.fields(GoodnotesShapeFillField.geometry), issues: &issues) : nil,
                                  outlineStrokeIdentifiers: outlineStrokeIdentifiers, offset: try fields.vector(GoodnotesShapeFillField.offset))
    }

    private func textBox(_ fields: GoodnotesRecordFields) throws(GoodnotesReadingError) -> GoodnotesTextBox {
        let placement = try fields.fields(GoodnotesTextBoxField.placement)
        let layout = try fields.fields(GoodnotesTextBoxField.layoutAndText)
        var insets: [Double]?
        if layout.contains(GoodnotesTextLayoutField.insets) {
            let insetFields = try layout.fields(GoodnotesTextLayoutField.insets)
            insets = [try insetFields.float(GoodnotesInsetField.first), try insetFields.float(GoodnotesInsetField.second),
                      try insetFields.float(GoodnotesInsetField.third), try insetFields.float(GoodnotesInsetField.fourth)]
        }
        return GoodnotesTextBox(origin: try placement.point(GoodnotesTextBoxPlacementField.origin),
                                rotationRadians: try placement.float(GoodnotesTextBoxPlacementField.rotationRadians),
                                scale: placement.contains(GoodnotesTextBoxPlacementField.scale) ? try placement.float(GoodnotesTextBoxPlacementField.scale) : 1,
                                size: layout.contains(GoodnotesTextLayoutField.size) ? try layout.size(GoodnotesTextLayoutField.size) : nil,
                                insets: insets, richText: try richText(layout))
    }

    private func stickyNote(_ fields: GoodnotesRecordFields) throws(GoodnotesReadingError) -> GoodnotesStickyNote {
        GoodnotesStickyNote(origin: try fields.fields(GoodnotesStickyNoteField.placement).point(GoodnotesStickyNotePlacementField.origin),
                            size: try fields.fields(GoodnotesStickyNoteField.dimensions).size(GoodnotesStickyNoteDimensionsField.size),
                            paperColor: try fields.color(GoodnotesStickyNoteField.paperColor),
                            richText: try richText(try fields.fields(GoodnotesStickyNoteField.richTextLayout)),
                            authorName: try fields.string(GoodnotesStickyNoteField.authorName))
    }

    /// A text layout (`GoodnotesTextLayoutField`): the content holds the rich text (LZ4), which decompresses to
    /// `{1: {1: text, 2: attributes…}}`, and the defaults hold the default attributes.
    private func richText(_ container: GoodnotesRecordFields) throws(GoodnotesReadingError) -> GoodnotesRichText {
        let content = try container.fields(GoodnotesTextLayoutField.content)
        let defaults = try container.fields(GoodnotesTextLayoutField.defaults)
        var body = GoodnotesRecordFields.empty
        if content.contains(GoodnotesTextContentField.compressedRichText) {
            let decoded = try content.compressedPayload(GoodnotesTextContentField.compressedRichText, limits: limits)
            body = try GoodnotesRecordFields(parsing: decoded[...]).fields(GoodnotesRichTextFileField.body)
        }
        var runs: [GoodnotesRichText.Attributes] = []
        for run in try body.repeatedFields(GoodnotesRichTextBodyField.attributes) { runs.append(try attributes(run)) }
        return GoodnotesRichText(text: try body.string(GoodnotesRichTextBodyField.text), runs: runs,
                                 defaultAttributes: defaults.contains(GoodnotesTextDefaultsField.attributes)
                                     ? try attributes(try defaults.fields(GoodnotesTextDefaultsField.attributes)) : nil)
    }

    /// Colour, link, font name and size in units (`GoodnotesTextAttributeField`).
    private func attributes(_ fields: GoodnotesRecordFields) throws(GoodnotesReadingError) -> GoodnotesRichText.Attributes {
        var size: Double?
        if fields.contains(GoodnotesTextAttributeField.sizeInUnits) {
            let storedSize = try fields.float(GoodnotesTextAttributeField.sizeInUnits)
            size = storedSize == Self.unsetTextAttributeSize ? nil : storedSize
        }
        return GoodnotesRichText.Attributes(
            color: fields.contains(GoodnotesTextAttributeField.color) ? try fields.color(GoodnotesTextAttributeField.color) : nil,
            link: try fields.nonEmptyString(GoodnotesTextAttributeField.link), fontName: try fields.nonEmptyString(GoodnotesTextAttributeField.fontName),
            sizeInUnits: size)
    }
}
