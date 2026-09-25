import Foundation
import CoreGraphics
import CryptoKit
import GraphiteCore

/// Vector drawings as ordinary SVG. Stroke data for re-editing lives in a standard
/// `<metadata>` element that every SVG renderer ignores. A digest of everything
/// outside that element detects edits made by other applications.
public enum SVGDrawingFile {
    public static let maximumFileBytes = 128 * 1_048_576
    private static let metadataStart = "<metadata id=\"graphite-drawing\">"
    private static let metadataEnd = "</metadata>"
    private static let payloadStart = "<graphite:drawing xmlns:graphite=\"urn:graphite:drawing:1\" encoding=\"base64-binary-property-list\">"
    private static let payloadEnd = "</graphite:drawing>"

    public static func encode(_ drawing: VectorDrawing, payload: DrawingPayload?) throws -> Data {
        // Written as UTF-8 bytes into one buffer: a large drawing has millions of
        // coordinates, and building the text from per-number Strings and copying it for
        // the digest and the file multiplied peak memory about five times.
        var document: [UInt8] = []
        document.reserveCapacity(estimatedByteCount(of: drawing))
        let width = formatted(drawing.size.width), height = formatted(drawing.size.height)
        document.append(contentsOf: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n".utf8)
        document.append(contentsOf: "<svg xmlns=\"http://www.w3.org/2000/svg\" version=\"1.1\" width=\"\(width)\" height=\"\(height)\" viewBox=\"0 0 \(width) \(height)\">\n".utf8)
        if drawing.background == .white {
            document.append(contentsOf: "<rect x=\"0\" y=\"0\" width=\"\(width)\" height=\"\(height)\" fill=\"#ffffff\"/>\n".utf8)
        }
        document.append(contentsOf: "<g fill-rule=\"nonzero\" stroke=\"none\">\n".utf8)
        for shape in drawing.shapes {
            document.append(contentsOf: "<path fill=\"\(hexColor(shape.color))\"".utf8)
            if shape.color.alpha < 0.999 { document.append(contentsOf: " fill-opacity=\"\(formatted(shape.color.alpha, fractionDigits: 3))\"".utf8) }
            document.append(contentsOf: " d=\"".utf8)
            appendPathData(shape.subpaths, to: &document)
            document.append(contentsOf: "\"/>\n".utf8)
        }
        document.append(contentsOf: "</g>\n".utf8)
        let visibleTail = Data("\n</svg>\n".utf8)
        if let payload {
            let digest = document.withUnsafeBytes { visibleHead in visibleContentDigest(head: visibleHead, tail: visibleTail) }
            let encodedPayload = try payload.replacingVisibleContentDigest(digest).encoded().base64EncodedData()
            document.append(contentsOf: (metadataStart + payloadStart).utf8)
            document.append(contentsOf: encodedPayload)
            document.append(contentsOf: (payloadEnd + metadataEnd).utf8)
        }
        document.append(contentsOf: visibleTail)
        guard document.count <= maximumFileBytes else { throw GraphiteError.oversized("This drawing is too complex for an SVG file.") }
        return Data(document)
    }

    /// About 14 bytes per coordinate pair ("L123.45 678.9"), so the buffer rarely grows.
    private static func estimatedByteCount(of drawing: VectorDrawing) -> Int {
        let pointCount = drawing.shapes.reduce(0) { total, shape in total + shape.subpaths.reduce(0) { shapeTotal, subpath in shapeTotal + subpath.count } }
        return min(maximumFileBytes, 1_024 + drawing.shapes.count * 64 + pointCount * 14)
    }

    public static func readMetadata(_ fileData: Data) -> DrawingMetadataReading {
        guard let metadataRange = fileData.range(of: Data(metadataStart.utf8)) else {
            return DrawingMetadataReading(payload: nil, metadataWasDiscarded: false)
        }
        guard fileData.count <= maximumFileBytes,
              let metadataEndRange = fileData.range(of: Data(metadataEnd.utf8), in: metadataRange.upperBound..<fileData.endIndex),
              fileData.range(of: Data(metadataStart.utf8), in: metadataEndRange.upperBound..<fileData.endIndex) == nil else {
            return DrawingMetadataReading(payload: nil, metadataWasDiscarded: true)
        }
        let metadataContent = fileData[metadataRange.upperBound..<metadataEndRange.lowerBound]
        guard metadataContent.starts(with: Data(payloadStart.utf8)), metadataContent.suffix(payloadEnd.utf8.count) == Data(payloadEnd.utf8) else {
            return DrawingMetadataReading(payload: nil, metadataWasDiscarded: true)
        }
        let encodedPayload = metadataContent.dropFirst(payloadStart.utf8.count).dropLast(payloadEnd.utf8.count)
        // Refused before decoding: the base64 text can be almost as large as the file.
        guard encodedPayload.count <= DrawingMetadataReader.maximumBase64PayloadBytes else {
            return DrawingMetadataReading(payload: nil, metadataWasDiscarded: true)
        }
        let digest = visibleContentDigest(head: fileData[fileData.startIndex..<metadataRange.lowerBound], tail: fileData[metadataEndRange.upperBound..<fileData.endIndex])
        guard let payloadData = Data(base64Encoded: Data(encodedPayload)),
              let payload = DrawingPayload.decodeIfValid(payloadData),
              payload.visibleContentDigest == digest else {
            return DrawingMetadataReading(payload: nil, metadataWasDiscarded: true)
        }
        return DrawingMetadataReading(payload: payload, metadataWasDiscarded: false)
    }

    /// Reads the shapes back from an unmodified Graphite SVG, for previews. Other SVG
    /// files use features this reader intentionally does not implement.
    public static func vectorDrawing(from fileData: Data) throws -> VectorDrawing {
        guard let metadataPayload = readMetadata(fileData).payload else {
            throw GraphiteError.unavailable("Graphite previews only SVG drawings it created. Open this file with the system preview.")
        }
        let reader = GraphiteSVGReader()
        let parser = XMLParser(data: fileData)
        parser.delegate = reader
        guard parser.parse(), reader.readingError == nil else {
            throw reader.readingError ?? GraphiteError.invalidFile("The SVG drawing is not valid XML.")
        }
        return VectorDrawing(size: CGSize(width: metadataPayload.width, height: metadataPayload.height), background: reader.hasWhiteBackground ? .white : .transparent, shapes: reader.shapes)
    }

    private static func visibleContentDigest<Head: DataProtocol, Tail: DataProtocol>(head: Head, tail: Tail) -> Data {
        var hash = SHA256()
        hash.update(data: head)
        hash.update(data: tail)
        return Data(hash.finalize())
    }

    private static func appendPathData(_ subpaths: [[CGPoint]], to document: inout [UInt8]) {
        for subpath in subpaths {
            guard let firstPoint = subpath.first else { continue }
            document.append(UInt8(ascii: "M"))
            appendFormatted(firstPoint.x, to: &document)
            document.append(UInt8(ascii: " "))
            appendFormatted(firstPoint.y, to: &document)
            for point in subpath.dropFirst() {
                document.append(UInt8(ascii: "L"))
                appendFormatted(point.x, to: &document)
                document.append(UInt8(ascii: " "))
                appendFormatted(point.y, to: &document)
            }
            document.append(UInt8(ascii: "Z"))
        }
    }

    private static func hexColor(_ color: VectorInkColor) -> String {
        func component(_ value: Double) -> String { String(format: "%02x", value.isNaN ? 0 : Int((min(max(value, 0), 1) * 255).rounded())) }
        return "#" + component(color.red) + component(color.green) + component(color.blue)
    }

    /// Locale-independent decimal text without trailing zeros.
    static func formatted(_ number: Double, fractionDigits: Int = 2) -> String {
        var text: [UInt8] = []
        appendFormatted(number, fractionDigits: fractionDigits, to: &text)
        return String(decoding: text, as: UTF8.self)
    }

    /// Appends `formatted(number)` without allocating intermediate Strings. Numbers too
    /// large for the fixed-point text are clamped rather than trapping.
    static func appendFormatted(_ number: Double, fractionDigits: Int = 2, to text: inout [UInt8]) {
        var multiplier = 1
        for _ in 0..<fractionDigits { multiplier *= 10 }
        let scaledValue = (number * Double(multiplier)).rounded()
        // Double(Int.max) rounds up to 2^63, so every value strictly inside converts exactly.
        let scaledNumber = scaledValue.isNaN ? 0
            : scaledValue >= Double(Int.max) ? Int.max
            : scaledValue <= -Double(Int.max) ? -Int.max
            : Int(scaledValue)
        if scaledNumber < 0 { text.append(UInt8(ascii: "-")) }
        let magnitude = abs(scaledNumber)
        text.append(contentsOf: String(magnitude / multiplier).utf8)
        var fractionPart = magnitude % multiplier
        guard fractionPart > 0 else { return }
        text.append(UInt8(ascii: "."))
        var digitValue = multiplier / 10
        while fractionPart > 0 && digitValue > 0 {
            text.append(UInt8(ascii: "0") + UInt8(fractionPart / digitValue))
            fractionPart %= digitValue
            digitValue /= 10
        }
    }
}

/// Reads the element subset `SVGDrawingFile.encode` writes: one background rectangle
/// and filled paths made of absolute move, line, and close commands.
private final class GraphiteSVGReader: NSObject, XMLParserDelegate {
    var shapes: [VectorShape] = []
    var hasWhiteBackground = false
    var readingError: Error?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        switch elementName {
        case "rect":
            hasWhiteBackground = attributes["fill"]?.lowercased() == "#ffffff"
        case "path":
            do {
                let color = try Self.color(fill: attributes["fill"], opacity: attributes["fill-opacity"])
                shapes.append(VectorShape(subpaths: try Self.subpaths(fromPathData: attributes["d"] ?? ""), color: color))
            } catch {
                readingError = error
                parser.abortParsing()
            }
        default:
            break
        }
    }

    private static func color(fill: String?, opacity: String?) throws -> VectorInkColor {
        guard let fill, fill.hasPrefix("#"), fill.count == 7, let colorValue = Int(fill.dropFirst(), radix: 16) else {
            throw GraphiteError.invalidFile("Unsupported SVG fill color.")
        }
        return VectorInkColor(red: Double((colorValue >> 16) & 0xff) / 255, green: Double((colorValue >> 8) & 0xff) / 255, blue: Double(colorValue & 0xff) / 255, alpha: opacity.flatMap(Double.init) ?? 1)
    }

    private static func subpaths(fromPathData pathText: String) throws -> [[CGPoint]] {
        var subpaths: [[CGPoint]] = []
        var currentSubpath: [CGPoint] = []
        var pendingNumbers: [Double] = []
        var currentCommand: Character?
        var numberText = ""
        func flushNumber() throws {
            guard !numberText.isEmpty else { return }
            guard let number = Double(numberText) else { throw GraphiteError.invalidFile("Invalid SVG path number.") }
            pendingNumbers.append(number)
            numberText = ""
            if pendingNumbers.count == 2 {
                currentSubpath.append(CGPoint(x: pendingNumbers[0], y: pendingNumbers[1]))
                pendingNumbers.removeAll(keepingCapacity: true)
            }
        }
        for character in pathText {
            switch character {
            case "M", "L", "Z":
                try flushNumber()
                if character == "M" && !currentSubpath.isEmpty { subpaths.append(currentSubpath); currentSubpath = [] }
                if character == "Z" { if !currentSubpath.isEmpty { subpaths.append(currentSubpath) }; currentSubpath = [] }
                currentCommand = character
            case "0"..."9", ".", "-":
                if character == "-" && !numberText.isEmpty { try flushNumber() }
                numberText.append(character)
            case " ", ",", "\n", "\t":
                try flushNumber()
            default:
                throw GraphiteError.invalidFile("Unsupported SVG path command.")
            }
        }
        try flushNumber()
        guard currentCommand != nil else { return [] }
        if !currentSubpath.isEmpty { subpaths.append(currentSubpath) }
        return subpaths
    }
}
