import Foundation
import CoreGraphics
import PDFKit
import GraphiteCore

/// An annotation's dictionary as its page's file holds it, read with Core Graphics: the
/// entries PDFKit does not give back, the rich text `/RC` among them, and the names of every
/// entry, so another application's keys are kept when Graphite writes its text box again.
///
/// Only an annotation read from a file has one; an annotation made since has its values.
struct PDFAnnotationFileEntries {
    /// Entries Graphite writes itself, or that refer to other objects of the file and
    /// cannot be copied as values, or that would draw the box otherwise than its appearance.
    static let entriesNotPreserved: Set<String> = [
        "Type", "Subtype", "Rect", "Contents", "NM", "M", "T", "F", "P", "AP", "AS", "DA", "DS", "RC", "Q", "BS", "Border", "C", "IC", "CA",
        "Rotate", "RD", "Popup", "Parent", "IRT", "StructParent", "OC", "AAPL:AKExtras",
        PDFPageManager.annotationNameKey.rawValue, PDFPageManager.textBoxRecordKey.rawValue, PDFPageManager.textBoxRichTextKey.rawValue,
        PDFPageManager.textBoxLinkOwnerKey.rawValue,
    ]

    let richText: String?
    let preservedEntries: [String: PDFPreservedValue]

    /// The dictionary of the annotation on its page's file: the one with its `/NM` name, or,
    /// for an unnamed one, the only annotation of its subtype with its rectangle.
    init?(of annotation: PDFAnnotation) {
        guard let page = annotation.page, let pageDictionary = page.pageRef?.dictionary else { return nil }
        let reading: (richText: String?, entries: [String: PDFPreservedValue])? = withExtendedLifetime(page) {
            guard let dictionary = Self.fileDictionary(of: annotation, in: pageDictionary) else { return nil }
            return (Self.text("RC", in: dictionary), Self.preservedEntries(of: dictionary))
        }
        guard let reading else { return nil }
        richText = reading.richText
        preservedEntries = reading.entries
    }

    private static func fileDictionary(of annotation: PDFAnnotation, in pageDictionary: CGPDFDictionaryRef) -> CGPDFDictionaryRef? {
        var annotations: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(pageDictionary, "Annots", &annotations), let annotations else { return nil }
        let name = annotation.persistentName
        let subtype = annotation.type ?? ""
        let bounds = annotation.bounds
        var candidates: [CGPDFDictionaryRef] = []
        for annotationIndex in 0..<min(CGPDFArrayGetCount(annotations), PDFFreeTextContents.maximumAnnotationsPerPage) {
            var dictionary: CGPDFDictionaryRef?
            guard CGPDFArrayGetDictionary(annotations, annotationIndex, &dictionary), let dictionary else { continue }
            if let name {
                if text("NM", in: dictionary) == name || text(PDFPageManager.annotationNameKey.rawValue, in: dictionary) == name { return dictionary }
                continue
            }
            var subtypeName: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtypeName), let subtypeName, String(cString: subtypeName) == subtype,
                  let rectangle = rectangle(in: dictionary), abs(rectangle.minX - bounds.minX) < 0.5, abs(rectangle.minY - bounds.minY) < 0.5,
                  abs(rectangle.width - bounds.width) < 0.5, abs(rectangle.height - bounds.height) < 0.5 else { continue }
            candidates.append(dictionary)
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    private static func rectangle(in dictionary: CGPDFDictionaryRef) -> CGRect? {
        var array: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dictionary, "Rect", &array), let array, CGPDFArrayGetCount(array) == 4 else { return nil }
        var numbers = [CGPDFReal](repeating: 0, count: 4)
        for numberIndex in 0..<4 { guard CGPDFArrayGetNumber(array, numberIndex, &numbers[numberIndex]) else { return nil } }
        return CGRect(x: min(numbers[0], numbers[2]), y: min(numbers[1], numbers[3]), width: abs(numbers[2] - numbers[0]), height: abs(numbers[3] - numbers[1]))
    }

    /// A text value, written as a string or, as `/RC` may be, a stream.
    static func text(_ key: String, in dictionary: CGPDFDictionaryRef) -> String? {
        var string: CGPDFStringRef?
        if CGPDFDictionaryGetString(dictionary, key, &string), let string { return CGPDFStringCopyTextString(string) as String? }
        var stream: CGPDFStreamRef?
        guard CGPDFDictionaryGetStream(dictionary, key, &stream), let stream else { return nil }
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(stream, &format) as Data?, format == .raw,
              data.count <= PDFTextBoxRichText.maximumUTF16Count * 2 else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    // MARK: Entries kept

    private static func preservedEntries(of dictionary: CGPDFDictionaryRef) -> [String: PDFPreservedValue] {
        var entries: [String: PDFPreservedValue] = [:]
        CGPDFDictionaryApplyBlock(dictionary, { key, object, _ in
            let name = String(cString: key)
            guard !entriesNotPreserved.contains(name), !name.hasPrefix("Graphite") else { return true }
            if let value = preservedValue(of: object, nesting: 0) { entries[name] = value }
            return entries.count < PDFPreservedValue.maximumEntryCount
        }, nil)
        return entries
    }

    private static func preservedValue(of object: CGPDFObjectRef, nesting: Int) -> PDFPreservedValue? {
        guard nesting < PDFPreservedValue.maximumNesting else { return nil }
        switch CGPDFObjectGetType(object) {
        case .name:
            var name: UnsafePointer<CChar>?
            return CGPDFObjectGetValue(object, .name, &name) ? name.map { name in .name(String(cString: name)) } : nil
        case .string:
            var string: CGPDFStringRef?
            guard CGPDFObjectGetValue(object, .string, &string), let string, let text = CGPDFStringCopyTextString(string) as String?,
                  text.utf16.count <= PDFPreservedValue.maximumTextUTF16Count else { return nil }
            return .text(text)
        case .integer:
            var integer: CGPDFInteger = 0
            return CGPDFObjectGetValue(object, .integer, &integer) ? .integer(Int(integer)) : nil
        case .real:
            var real: CGPDFReal = 0
            return CGPDFObjectGetValue(object, .real, &real) ? .real(Double(real)) : nil
        case .boolean:
            var boolean: CGPDFBoolean = 0
            return CGPDFObjectGetValue(object, .boolean, &boolean) ? .boolean(boolean != 0) : nil
        case .array:
            var array: CGPDFArrayRef?
            guard CGPDFObjectGetValue(object, .array, &array), let array else { return nil }
            return .array((0..<min(CGPDFArrayGetCount(array), PDFPreservedValue.maximumEntryCount)).compactMap { elementIndex in
                var element: CGPDFObjectRef?
                guard CGPDFArrayGetObject(array, elementIndex, &element), let element else { return nil }
                return preservedValue(of: element, nesting: nesting + 1)
            })
        case .dictionary:
            var dictionary: CGPDFDictionaryRef?
            guard CGPDFObjectGetValue(object, .dictionary, &dictionary), let dictionary else { return nil }
            var entries: [String: PDFPreservedValue] = [:]
            CGPDFDictionaryApplyBlock(dictionary, { key, element, _ in
                if let value = preservedValue(of: element, nesting: nesting + 1) { entries[String(cString: key)] = value }
                return entries.count < PDFPreservedValue.maximumEntryCount
            }, nil)
            return .dictionary(entries)
        case .null, .stream: return nil
        @unknown default: return nil
        }
    }
}
