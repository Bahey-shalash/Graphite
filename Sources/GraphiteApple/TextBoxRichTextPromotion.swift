import Foundation
import GraphiteCore

/// Puts right in a file PDFKit wrote what it writes wrongly or not at all for a `/FreeText`.
///
/// - PDFKit neither reads nor writes `/RC`, so Graphite's text box keeps its rich text under
///   `PDFPageManager.textBoxRichTextKey`; that key's name is replaced by `/RC`. A stale
///   `/RC` the box still had is left out, and so is Apple's markup copy of the annotation
///   (`/AAPL:AKExtras`), from which Apple's markup tools would rebuild the box with PDFKit's
///   default font instead of reading its keys.
/// - In a document read from a file, PDFKit writes `/DA` as a name (its text starts with a
///   slash, which PDFKit takes for a name), where the standard has a string; readers then
///   ignore the default appearance. It is written as the string it spells.
///
/// Every other byte of the annotation's dictionary is copied as it is.
enum TextBoxRichTextPromotion {
    private static let richTextKey = PDFPageManager.textBoxRichTextKey.rawValue
    private static let standardRichTextKey = "RC"
    private static let markupDataKey = "AAPL:AKExtras"
    private static let defaultAppearanceKey = "DA"

    /// Whether the dictionary is a `/FreeText` this repair changes.
    static func needsRepair(_ dictionary: PDFSyntaxDictionary) -> Bool {
        guard case .name(PDFTextBox.annotationTypeName)? = dictionary.entries["Subtype"] else { return false }
        return holdsRichText(dictionary) || hasDefaultAppearanceName(dictionary)
    }

    static func holdsRichText(_ dictionary: PDFSyntaxDictionary) -> Bool {
        guard case .string? = dictionary.entries[richTextKey] else { return false }
        return true
    }

    private static func hasDefaultAppearanceName(_ dictionary: PDFSyntaxDictionary) -> Bool {
        guard case .name? = dictionary.entries[defaultAppearanceKey] else { return false }
        return true
    }

    /// The annotations' new bytes, by object number, and how many had their rich text named `/RC`.
    static func find(in candidates: Set<Int>, objects: (Int) -> (generation: Int, range: Range<Int>)?,
                     bytes: UnsafeRawBufferPointer) -> (replacements: [Int: Data], richTextsNamed: Int) {
        var replacements: [Int: Data] = [:]
        var richTextsNamed = 0
        for number in candidates {
            guard let object = objects(number) else { continue }
            var scanner = PDFSyntaxScanner(bytes: bytes)
            scanner.position = object.range.lowerBound
            guard scanner.readUnsignedInteger() == number, scanner.readUnsignedInteger() == object.generation, scanner.readKeyword() == "obj",
                  case .dictionary(let annotation)? = scanner.readValue(), scanner.streamDataStart(before: object.range.upperBound) == nil,
                  needsRepair(annotation) else { continue }
            let richTextCuts = richTextCuts(in: annotation, object: object.range, bytes: bytes)
            let cuts = (richTextCuts + defaultAppearanceCuts(in: annotation, object: object.range))
                .sorted { first, second in first.range.lowerBound < second.range.lowerBound }
            guard !cuts.isEmpty, zip(cuts, cuts.dropFirst()).allSatisfy({ earlier, later in earlier.range.upperBound <= later.range.lowerBound }) else { continue }
            if !richTextCuts.isEmpty { richTextsNamed += 1 }
            var objectBytes = Data()
            var copiedUpTo = object.range.lowerBound
            for cut in cuts {
                objectBytes.append(Data(UnsafeRawBufferPointer(rebasing: bytes[copiedUpTo..<cut.range.lowerBound])))
                objectBytes.append(cut.insertion)
                copiedUpTo = cut.range.upperBound
            }
            objectBytes.append(Data(UnsafeRawBufferPointer(rebasing: bytes[copiedUpTo..<object.range.upperBound])))
            replacements[number] = objectBytes
        }
        return (replacements, richTextsNamed)
    }

    private struct Cut {
        let range: Range<Int>
        let insertion: Data
    }

    /// The rich text's key renamed `/RC`, a stale `/RC` and Apple's markup copy left out.
    private static func richTextCuts(in annotation: PDFSyntaxDictionary, object: Range<Int>, bytes: UnsafeRawBufferPointer) -> [Cut] {
        let keyToken = Array(("/" + richTextKey).utf8)
        guard holdsRichText(annotation), let keyStart = annotation.entryRanges[richTextKey]?.lowerBound, keyStart + keyToken.count <= object.upperBound,
              (0..<keyToken.count).allSatisfy({ offset in bytes[keyStart + offset] == keyToken[offset] }) else { return [] }
        let removed = [standardRichTextKey, markupDataKey].compactMap { key in annotation.entryRanges[key] }
            .filter { range in object.contains(range.lowerBound) && range.upperBound <= object.upperBound }
        return removed.map { range in Cut(range: range, insertion: Data()) }
            + [Cut(range: keyStart..<(keyStart + keyToken.count), insertion: Data(("/" + standardRichTextKey).utf8))]
    }

    /// `/DA` written as a name, written as the string it spells.
    private static func defaultAppearanceCuts(in annotation: PDFSyntaxDictionary, object: Range<Int>) -> [Cut] {
        guard case .name(let spelled)? = annotation.entries[defaultAppearanceKey], let valueRange = annotation.sourceRanges[defaultAppearanceKey],
              object.contains(valueRange.lowerBound), valueRange.upperBound <= object.upperBound else { return [] }
        let escaped = ("/" + decodedNameEscapes(spelled)).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
        return [Cut(range: valueRange, insertion: Data(("(" + escaped + ")").utf8))]
    }

    /// The name's `#xx` escapes decoded again: PDFKit escapes the `#` of its own escapes, so
    /// a name read once still spells `Helvetica#2014#20Tf`.
    private static func decodedNameEscapes(_ name: String) -> String {
        var decoded: [UInt8] = []
        let bytes = Array(name.utf8)
        var index = 0
        while index < bytes.count {
            if bytes[index] == UInt8(ascii: "#"), index + 2 < bytes.count, let value = UInt8(String(decoding: bytes[(index + 1)...(index + 2)], as: UTF8.self), radix: 16) {
                decoded.append(value)
                index += 3
            } else {
                decoded.append(bytes[index])
                index += 1
            }
        }
        return String(decoding: decoded, as: UTF8.self)
    }
}
