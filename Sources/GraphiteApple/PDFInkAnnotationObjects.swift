import Foundation
import CoreGraphics
import PDFKit
import zlib
import GraphiteCore

/// Graphite's ink annotations written as PDF objects by Graphite itself, into a `PDFObjectSpool`, instead of through
/// PDFKit's annotation writer, whose cost grows with the square of a page's annotations (BUG-IMPORT-03).
///
/// Each stroke is the `/Ink` annotation PDFKit writes for `PDFInkAnnotationFactory` (invariants M-10 to M-13): the same
/// keys and values (`/Rect`, `/Border`, `/BS`, `/InkList`, `/C`, `/F`, `/T`, `/M`, `/DA`, Graphite's group, name and,
/// on the group's first annotation, its re-editing record) and an appearance stream that fills the stroke's outline in
/// its colour, as `PDFOutlinedInkAnnotation` draws it, through an sRGB ICC colour space and, for a see-through colour,
/// a graphics state with its opacity. A stroke without an outline strokes its `/InkList` at its border width with
/// round caps. Numbers have seven significant digits, as PDFKit writes them.
///
/// The spool's shared objects (the colour space and one resource dictionary per opacity) are written once per spool.
struct PDFInkAnnotationObjects {
    private var colorSpacePlace: Int?
    private var resourcesPlaceByOpacity: [String: Int] = [:]
    /// The `/T` and `/M` PDFKit gives a new annotation: the user's name and the time of writing.
    private let authorText: Data?
    private let modificationDateText: Data

    init(date: Date = Date()) {
        let template = PDFAnnotation(bounds: .zero, forType: .ink, withProperties: nil)
        authorText = template.userName.flatMap { name in name.isEmpty ? nil : PDFObjectText.textString(name) }
        modificationDateText = PDFObjectText.literalString(PDFObjectText.dateText(date))
    }

    /// Spools the update's added strokes in order and returns the places of their annotations. The group's first
    /// annotation carries the update's re-editing record.
    mutating func spool(_ update: PDFInkUpdate, into spool: inout PDFObjectSpool) throws -> [Int] {
        var annotationPlaces: [Int] = []
        annotationPlaces.reserveCapacity(update.addedStrokes.count)
        for stroke in update.addedStrokes {
            guard let geometry = PDFInkAnnotationFactory.geometry(for: stroke) else { continue }
            let record = annotationPlaces.isEmpty ? update.editableRecord : nil
            let appearancePlace = try spoolAppearance(of: stroke, geometry: geometry, into: &spool)
            annotationPlaces.append(try spool.add(annotationParts(stroke, geometry: geometry, group: update.group, record: record,
                                                                  appearancePlace: appearancePlace)))
        }
        return annotationPlaces
    }

    private func annotationParts(_ stroke: PortableInkStroke, geometry: PDFInkAnnotationFactory.Geometry, group: String,
                                 record: PDFEditableInkRecord?, appearancePlace: Int) -> [PDFObjectSpool.Part] {
        let number = PDFObjectText.number
        var text = "<< /Type /Annot /Subtype /Ink /Rect " + PDFObjectText.rectangle(geometry.bounds)
        text += " /Border [ 0 0 \(number(geometry.borderWidth)) ] /BS << /W \(number(geometry.borderWidth)) >> /F 4 /InkList ["
        for path in geometry.inkList {
            text += " [ " + path.map { point in number(Double(point.x)) + " " + number(Double(point.y)) }.joined(separator: " ") + " ]"
        }
        text += " ] /C [ \(number(stroke.red)) \(number(stroke.green)) \(number(stroke.blue)) ] /DA (/Helvetica 12 Tf 0 g)"
        var head = Data(text.utf8)
        if let authorText { head += Data(" /T ".utf8) + authorText }
        head += Data(" /M ".utf8) + modificationDateText
        head += Data(" /GraphiteInkGroup ".utf8) + PDFObjectText.textString(group)
        if let name = stroke.name { head += Data(" /GraphiteAnnotationName ".utf8) + PDFObjectText.textString(name) }
        if let record {
            head += Data(" /GraphitePencilDrawingV1 ".utf8) + PDFObjectText.literalString(record.drawingData.base64EncodedString())
            head += Data(" /GraphiteInkStrokeNamesV1 ".utf8) + PDFObjectText.textString(PDFInkGroups.encodeStrokeNames(record.strokeNames))
        }
        head += Data(" /AP << /N ".utf8)
        return [.bytes(head), .reference(appearancePlace), .bytes(Data(" >> >>".utf8))]
    }

    /// The appearance: a form the size of the annotation's rectangle, its content in the rectangle's own space.
    private mutating func spoolAppearance(of stroke: PortableInkStroke, geometry: PDFInkAnnotationFactory.Geometry,
                                          into spool: inout PDFObjectSpool) throws -> Int {
        let number = PDFObjectText.number
        let bounds = geometry.bounds
        let opacity = min(max(stroke.alpha.isFinite ? stroke.alpha : 1, 0), 1)
        var content = "q 0 0 \(number(Double(bounds.width))) \(number(Double(bounds.height))) re W n /Cs1 cs /Cs1 CS "
        let color = "\(number(stroke.red)) \(number(stroke.green)) \(number(stroke.blue))"
        content += color + " sc " + color + " SC" + (opacity < 1 ? " /Gs1 gs" : "") + "\n"
        let offset = CGPoint(x: bounds.minX, y: bounds.minY)
        if geometry.outline.isEmpty {
            content += "\(number(geometry.borderWidth)) w 1 J 1 j\n" + Self.pathText(geometry.inkList, offset: offset, closes: false) + "S Q\n"
        } else {
            content += Self.pathText(geometry.outline, offset: offset, closes: true) + "f Q\n"
        }
        let resourcesPlace = try resources(opacity: opacity, into: &spool)
        let stream = try PDFObjectText.deflated(Data(content.utf8))
        let dictionary = "<< /Type /XObject /Subtype /Form /FormType 1 /BBox [ 0 0 \(number(Double(bounds.width))) \(number(Double(bounds.height))) ]"
            + " /Length \(stream.count) /Filter /FlateDecode /Resources "
        return try spool.add([.bytes(Data(dictionary.utf8)), .reference(resourcesPlace),
                              .bytes(Data(" >>\nstream\n".utf8) + stream + Data("\nendstream".utf8))])
    }

    private static func pathText(_ subpaths: [[CGPoint]], offset: CGPoint, closes: Bool) -> String {
        let number = PDFObjectText.number
        var text = ""
        for subpath in subpaths {
            for (pointIndex, point) in subpath.enumerated() {
                text += number(Double(point.x - offset.x)) + " " + number(Double(point.y - offset.y)) + (pointIndex == 0 ? " m\n" : " l\n")
            }
            if closes { text += "h\n" }
        }
        return text
    }

    /// The resources of an appearance of this opacity, spooled once: the sRGB colour space and, below full opacity, a
    /// graphics state that draws at it.
    private mutating func resources(opacity: Double, into spool: inout PDFObjectSpool) throws -> Int {
        let key = PDFObjectText.number(opacity)
        if let place = resourcesPlaceByOpacity[key] { return place }
        let colorSpace = try colorSpace(into: &spool)
        var parts: [PDFObjectSpool.Part] = [.bytes(Data("<< /ProcSet [ /PDF ] /ColorSpace << /Cs1 ".utf8)), .reference(colorSpace)]
        parts.append(.bytes(Data((opacity < 1 ? " >> /ExtGState << /Gs1 << /Type /ExtGState /ca \(key) /CA \(key) >> >> >>" : " >> >>").utf8)))
        let place = try spool.add(parts)
        resourcesPlaceByOpacity[key] = place
        return place
    }

    /// `[ /ICCBased <sRGB profile> ]`, as Core Graphics writes the colour space of an sRGB colour.
    private mutating func colorSpace(into spool: inout PDFObjectSpool) throws -> Int {
        if let colorSpacePlace { return colorSpacePlace }
        let profile = (CGColorSpace(name: CGColorSpace.sRGB)?.copyICCData() as Data?) ?? Data()
        let compressed = try PDFObjectText.deflated(profile)
        let profilePlace = try spool.add([.bytes(Data("<< /N 3 /Alternate /DeviceRGB /Length \(compressed.count) /Filter /FlateDecode >>\nstream\n".utf8)
                                                + compressed + Data("\nendstream".utf8))])
        let place = try spool.add([.bytes(Data("[ /ICCBased ".utf8)), .reference(profilePlace), .bytes(Data(" ]".utf8))])
        colorSpacePlace = place
        return place
    }
}

/// PDF syntax for values Graphite writes itself (ISO 32000-1, section 7.3).
enum PDFObjectText {
    enum DeflateError: Error { case failed }

    /// A real number with up to seven significant digits and no exponent, as PDFKit and Core Graphics write them; zero
    /// for a value that is not finite.
    static func number(_ value: Double) -> String {
        guard value.isFinite, abs(value) >= 1e-9 else { return "0" }
        let integerDigits = max(1, Int(floor(log10(abs(value)))) + 1)
        let decimals = min(max(0, 7 - integerDigits), 9)
        var text = String(format: "%.\(decimals)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text == "-0" ? "0" : text
    }

    static func rectangle(_ rectangle: CGRect) -> String {
        "[ " + [rectangle.minX, rectangle.minY, rectangle.maxX, rectangle.maxY].map { value in number(Double(value)) }.joined(separator: " ") + " ]"
    }

    /// A text string: a literal string for printable ASCII, else UTF-16 with its byte order mark, in hexadecimal.
    static func textString(_ text: String) -> Data {
        guard text.unicodeScalars.allSatisfy({ scalar in scalar.value >= 0x20 && scalar.value < 0x7F }) else {
            let units = [UInt16(0xFEFF)] + Array(text.utf16)
            return Data(("<" + units.map { unit in String(format: "%04X", unit) }.joined() + ">").utf8)
        }
        return literalString(text)
    }

    /// `(…)` with the backslash and parentheses escaped; for ASCII text.
    static func literalString(_ text: String) -> Data {
        var escaped = "("
        escaped.reserveCapacity(text.utf8.count + 2)
        for character in text {
            if character == "\\" || character == "(" || character == ")" { escaped.append("\\") }
            escaped.append(character)
        }
        return Data((escaped + ")").utf8)
    }

    /// `D:YYYYMMDDHHmmSSZ00'00'`, in UTC, as PDFKit writes an annotation's `/M`.
    static func dateText(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "D:%04d%02d%02d%02d%02d%02dZ00'00'", parts.year ?? 2000, parts.month ?? 1, parts.day ?? 1, parts.hour ?? 0,
                      parts.minute ?? 0, parts.second ?? 0)
    }

    /// The bytes compressed in the zlib format `/FlateDecode` reads.
    static func deflated(_ bytes: Data) throws -> Data {
        var destinationLength = compressBound(uLong(bytes.count))
        var destination = Data(count: Int(destinationLength))
        let status = destination.withUnsafeMutableBytes { target in
            bytes.withUnsafeBytes { source in
                compress2(target.bindMemory(to: Bytef.self).baseAddress, &destinationLength, source.bindMemory(to: Bytef.self).baseAddress,
                          uLong(bytes.count), Z_DEFAULT_COMPRESSION)
            }
        }
        guard status == Z_OK else { throw DeflateError.failed }
        destination.count = Int(destinationLength)
        return destination
    }
}
