import Foundation
import CoreGraphics

/// Graphite's own record of a text box, kept in its annotation beside the standard keys:
/// the box's corner, width and angle, and every run with its link. The standard keys give
/// the text and its looks to every reader, but not an angle other than a quarter turn nor
/// links, and PDFKit cannot read back the rich text it does not write itself.
///
/// The record is optional (`OBJECTIVE.md`): a box without one, or whose record no longer
/// matches its `/Contents` because another application changed the text, is read from
/// the standard keys.
public struct PDFTextBoxRecord: Sendable, Equatable, Codable {
    public static let currentVersion = 1
    /// Bounds the record read from a file.
    public static let maximumEncodedBytes = 4 * 1_048_576

    public let version: Int
    /// The plain text as written in `/Contents`, to tell whether another application changed it.
    public let contents: String
    public let originX: Double
    public let originY: Double
    public let width: Double
    public let height: Double
    public let rotationRadians: Double
    /// The annotation's rectangle as written, to tell whether another application moved it.
    public let rectangle: [Double]
    public let style: PDFTextBoxStyle
    public let runs: [PDFTextRun]

    public init(box: PDFTextBox) {
        version = Self.currentVersion
        contents = box.plainText
        originX = Double(box.origin.x)
        originY = Double(box.origin.y)
        width = box.width
        height = box.height
        rotationRadians = box.rotationRadians
        let bounds = box.annotationBounds
        rectangle = [Double(bounds.minX), Double(bounds.minY), Double(bounds.width), Double(bounds.height)]
        style = box.style
        runs = box.runs
    }

    /// The record as JSON text, with its keys sorted so the same box is written the same.
    public func encodedText() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    /// A record read from a file, or nil when it is not one this build reads: too large, not
    /// JSON of this form, another version, or with values outside a box's limits.
    public static func decoded(from text: String) -> PDFTextBoxRecord? {
        guard text.utf8.count <= maximumEncodedBytes,
              let record = try? JSONDecoder().decode(PDFTextBoxRecord.self, from: Data(text.utf8)), // Unreadable: the standard keys are read.
              record.version == currentVersion, record.rectangle.count == 4,
              ([record.originX, record.originY, record.width, record.height, record.rotationRadians] + record.rectangle).allSatisfy(\.isFinite),
              record.width > 0, record.height >= 0, record.runs.count <= PDFTextBox.maximumRunCount,
              record.contents.utf16.count <= PDFTextBox.maximumTextUTF16Count else { return nil }
        return record
    }

    /// The rectangle the record was written with.
    public var writtenRectangle: CGRect { CGRect(x: rectangle[0], y: rectangle[1], width: rectangle[2], height: rectangle[3]) }

    /// The box the record describes, named and placed as it was written. Values a file can
    /// hold outside a box's limits are brought inside, as a new box would have them.
    public func box(named name: String, preservedEntries: [String: PDFPreservedValue]) -> PDFTextBox {
        let validatedRuns = runs.map { run in
            let attributes = run.attributes
            return PDFTextRun(text: run.text, attributes: PDFTextAttributes(fontFamily: attributes.fontFamily, fontSize: attributes.fontSize,
                                                                            color: attributes.color, isBold: attributes.isBold, isItalic: attributes.isItalic,
                                                                            isUnderlined: attributes.isUnderlined, link: attributes.link))
        }
        let validatedStyle = PDFTextBoxStyle(alignment: style.alignment, lineSpacing: style.lineSpacing, fillColor: style.fillColor,
                                             borderColor: style.borderColor, borderWidth: style.borderWidth, padding: style.padding)
        return PDFTextBox(name: name, runs: validatedRuns, origin: CGPoint(x: originX, y: originY), width: width, height: height,
                          rotationRadians: rotationRadians, style: validatedStyle, preservedEntries: preservedEntries)
    }
}
