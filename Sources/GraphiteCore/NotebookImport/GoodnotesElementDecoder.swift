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

    var knownFieldNumbers: Set<Int> {
        switch self {
        case .stroke: [1, 2, 3, 4, 5, 6, 7, 9, 10, 14, 15, 20, 21]
        case .picture, .shapeFill: [1, 2, 3, 4, 5, 6, 7, 14, 15, 18]
        case .rtfTextBox: [1, 2, 3, 4, 5, 6, 7, 9, 10, 14, 15, 18, 19, 20, 21, 27]
        case .rtfTextElement: [1, 2, 3, 13, 15, 25, 26, 27, 28]
        case .stickyNote: [1, 2, 3, 7, 20, 21, 30, 31, 32, 33, 40, 41]
        case .textBox: [1, 2, 3, 7, 9, 20, 21, 22, 30, 31, 32, 33]
        }
    }

    var positionFieldNumber: Int {
        switch self {
        case .stroke, .stickyNote, .textBox: 7
        case .picture, .rtfTextBox: 5
        case .shapeFill: 3
        case .rtfTextElement: 13
        }
    }
}

/// Decodes one element body of a page's layer into its value, reporting fields it does not know.
struct GoodnotesElementDecoder {
    private static let knownShapeFieldNumbers: Set<Int> = [1, 2, 3, 4, 5, 15]
    /// A text attribute size of -404 means "not set, use the default".
    private static let unsetTextAttributeSize = -404.0

    let limits: NotebookImportLimits
    let attachments: [String: GoodnotesAttachment]

    /// Nil when the element is a stroke whose path layout is not known (reported).
    func content(of kind: GoodnotesElementKind, fields: GoodnotesRecordFields,
                 issues: inout GoodnotesIssueList) throws(GoodnotesReadingError) -> GoodnotesElementContent? {
        for fieldNumber in fields.fieldNumbers.subtracting(kind.knownFieldNumbers).sorted() {
            issues.report(.elementFieldNotKnown(elementKind: kind.rawValue, fieldNumber: fieldNumber))
        }
        switch kind {
        case .stroke: return try stroke(fields, issues: &issues).map(GoodnotesElementContent.stroke)
        case .picture: return .picture(try picture(fields))
        case .shapeFill: return .shapeFill(try shapeFill(fields, issues: &issues))
        case .textBox: return .textBox(try textBox(fields))
        case .stickyNote: return .stickyNote(try stickyNote(fields))
        case .rtfTextBox:
            return .rtfTextBox(GoodnotesRTFTextBox(frame: try fields.rectangle(2), textFrame: try fields.rectangle(3), rtf: try fields.string(6)))
        case .rtfTextElement: return .rtfTextElement(rtf: try fields.string(3))
        }
    }

    private func stroke(_ fields: GoodnotesRecordFields, issues: inout GoodnotesIssueList) throws(GoodnotesReadingError) -> GoodnotesStroke? {
        let pathBytes = try fields.compressedPayload(2, limits: limits)
        let image: TplImage
        do throws(TplImageError) { image = try TplImage(pathBytes) } catch { throw .tplImage(error) }
        let shape = try fields.hasNonEmptyBytes(9) ? try self.shape(try fields.fields(9), issues: &issues) : nil
        guard let path = try GoodnotesStrokePathDecoder.path(of: image, issues: &issues) else { return nil }
        return GoodnotesStroke(ink: Self.ink(try fields.varint(3) ?? 0), color: try fields.color(4), isHighlighter: try fields.varint(5) == 1,
                               isTape: try fields.hasNonEmptyBytes(20), groupIdentifier: try fields.nonEmptyString(10),
                               offset: try fields.vector(6), shape: shape, path: path)
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
        let width = fields.contains(15) ? try fields.float(15) : nil
        let geometry: GoodnotesShape.Geometry? // set from the first geometry field present
        if fields.contains(1) {
            var points: [CGPoint] = []
            for point in try fields.fields(1).repeatedFields(1) { points.append(CGPoint(x: try point.float(1), y: try point.float(2))) }
            geometry = .polyline(points)
        } else if fields.contains(2) {
            let arc = try fields.fields(2)
            geometry = .arcThroughThreePoints(try arc.point(1), try arc.point(2), try arc.point(3))
        } else if fields.contains(3) {
            let rectangle = try fields.fields(3)
            geometry = .rectangle(centre: try rectangle.point(1), size: try rectangle.size(2), angleRadians: try rectangle.float(3))
        } else if fields.contains(4) {
            let ellipse = try fields.fields(4)
            geometry = .ellipse(centre: try ellipse.point(1), radii: try ellipse.size(2), angleRadians: try ellipse.float(3))
        } else {
            geometry = nil
        }
        return GoodnotesShape(geometry: geometry, width: width)
    }

    private func picture(_ fields: GoodnotesRecordFields) throws(GoodnotesReadingError) -> GoodnotesPicture {
        let placement = try fields.fields(3)
        let kindCode = try fields.varint(6)
        let kind: GoodnotesPicture.Kind? = switch kindCode {
        case nil: nil
        case 2?: .jpeg2000Sticker
        case 5?: .animatedGIF
        case let code?: .unknown(code)
        }
        return GoodnotesPicture(attachment: attachments[try fields.string(4)], boundingBox: try fields.rectangle(2), centre: try placement.point(1),
                                size: try placement.size(2), rotationRadians: try placement.float(3), kind: kind)
    }

    private func shapeFill(_ fields: GoodnotesRecordFields, issues: inout GoodnotesIssueList) throws(GoodnotesReadingError) -> GoodnotesShapeFill {
        var outlineStrokeIdentifiers: [String] = []
        for value in fields.message.values(5) {
            do throws(ProtocolBufferError) {
                outlineStrokeIdentifiers.append(try ProtocolBufferMessage.string(from: ProtocolBufferMessage.bytes(of: value, fieldNumber: 5), fieldNumber: 5))
            } catch {
                throw .protocolBuffer(error)
            }
        }
        return GoodnotesShapeFill(color: try fields.color(7), shape: fields.contains(4) ? try shape(try fields.fields(4), issues: &issues) : nil,
                                  outlineStrokeIdentifiers: outlineStrokeIdentifiers, offset: try fields.vector(6))
    }

    private func textBox(_ fields: GoodnotesRecordFields) throws(GoodnotesReadingError) -> GoodnotesTextBox {
        let placement = try fields.fields(20)
        let layout = try fields.fields(32)
        var insets: [Double]?
        if layout.contains(10) {
            let insetFields = try layout.fields(10)
            insets = [try insetFields.float(1), try insetFields.float(2), try insetFields.float(3), try insetFields.float(4)]
        }
        return GoodnotesTextBox(origin: try placement.point(1), scale: placement.contains(3) ? try placement.float(3) : 1,
                                size: layout.contains(2) ? try layout.size(2) : nil, insets: insets, richText: try richText(layout))
    }

    private func stickyNote(_ fields: GoodnotesRecordFields) throws(GoodnotesReadingError) -> GoodnotesStickyNote {
        GoodnotesStickyNote(origin: try fields.fields(20).point(1), size: try fields.fields(21).size(2), paperColor: try fields.color(30),
                            richText: try richText(try fields.fields(31)), authorName: try fields.string(33))
    }

    /// `{1: {2: rich text (LZ4), 3: hash}, 5: {1: default attributes}}`; the rich text decompresses to
    /// `{1: {1: text, 2: attributes…}}`.
    private func richText(_ container: GoodnotesRecordFields) throws(GoodnotesReadingError) -> GoodnotesRichText {
        let content = try container.fields(1)
        let defaults = try container.fields(5)
        var body = GoodnotesRecordFields.empty
        if content.contains(2) {
            let decoded = try content.compressedPayload(2, limits: limits)
            body = try GoodnotesRecordFields(parsing: decoded[...]).fields(1)
        }
        var runs: [GoodnotesRichText.Attributes] = []
        for run in try body.repeatedFields(2) { runs.append(try attributes(run)) }
        return GoodnotesRichText(text: try body.string(1), runs: runs,
                                 defaultAttributes: defaults.contains(1) ? try attributes(try defaults.fields(1)) : nil)
    }

    /// Colour (3), link (4), font name (30) and size in units (40).
    private func attributes(_ fields: GoodnotesRecordFields) throws(GoodnotesReadingError) -> GoodnotesRichText.Attributes {
        var size: Double?
        if fields.contains(40) {
            let storedSize = try fields.float(40)
            size = storedSize == Self.unsetTextAttributeSize ? nil : storedSize
        }
        return GoodnotesRichText.Attributes(color: fields.contains(3) ? try fields.color(3) : nil, link: try fields.nonEmptyString(4),
                                            fontName: try fields.nonEmptyString(30), sizeInUnits: size)
    }
}
