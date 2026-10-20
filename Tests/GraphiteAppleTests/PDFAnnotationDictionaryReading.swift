import XCTest
import CoreGraphics

/// Reads annotation dictionaries straight from a PDF's bytes with CoreGraphics, an
/// independent parser, so a test sees the keys and values as another reader does and not
/// as PDFKit presents them.
enum PDFAnnotationDictionaryReading {
    /// Calls `body` with the annotation dictionaries of page `pageNumber` (counted from 1),
    /// in the order the page lists them. The dictionaries belong to a document that stays
    /// alive for the duration of `body`.
    static func withAnnotationDictionaries(in fileData: Data, pageNumber: Int = 1, body: ([CGPDFDictionaryRef]) throws -> Void) throws {
        let provider = try XCTUnwrap(CGDataProvider(data: fileData as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))
        let page = try XCTUnwrap(document.page(at: pageNumber))
        var annotations: CGPDFArrayRef?
        var dictionaries: [CGPDFDictionaryRef] = []
        if let pageDictionary = page.dictionary, CGPDFDictionaryGetArray(pageDictionary, "Annots", &annotations), let annotations {
            for annotationIndex in 0..<CGPDFArrayGetCount(annotations) {
                var annotationDictionary: CGPDFDictionaryRef?
                if CGPDFArrayGetDictionary(annotations, annotationIndex, &annotationDictionary), let annotationDictionary {
                    dictionaries.append(annotationDictionary)
                }
            }
        }
        try withExtendedLifetime(document) { try body(dictionaries) }
    }

    /// The bytes of a string value read as text, such as `/NM (name)`.
    static func string(_ key: String, in dictionary: CGPDFDictionaryRef) -> String? {
        var value: CGPDFStringRef?
        guard CGPDFDictionaryGetString(dictionary, key, &value), let value, let bytes = CGPDFStringGetBytePtr(value) else { return nil }
        return String(decoding: UnsafeBufferPointer(start: bytes, count: CGPDFStringGetLength(value)), as: UTF8.self)
    }

    /// A name value without its slash, such as `/Subtype /Ink`.
    static func name(_ key: String, in dictionary: CGPDFDictionaryRef) -> String? {
        var value: UnsafePointer<Int8>?
        guard CGPDFDictionaryGetName(dictionary, key, &value), let value else { return nil }
        return String(cString: value)
    }

    /// A number value, whether the file writes it as an integer or a real.
    static func number(_ key: String, in dictionary: CGPDFDictionaryRef) -> Double? {
        var real: CGPDFReal = 0
        if CGPDFDictionaryGetNumber(dictionary, key, &real) { return Double(real) }
        return nil
    }

    static func integer(_ key: String, in dictionary: CGPDFDictionaryRef) -> Int? {
        var value: CGPDFInteger = 0
        return CGPDFDictionaryGetInteger(dictionary, key, &value) ? Int(value) : nil
    }

    static func hasKey(_ key: String, in dictionary: CGPDFDictionaryRef) -> Bool {
        var object: CGPDFObjectRef?
        return CGPDFDictionaryGetObject(dictionary, key, &object)
    }

    /// The numbers of an array value, such as `/QuadPoints [..]`.
    static func numbers(_ key: String, in dictionary: CGPDFDictionaryRef) -> [Double]? {
        var array: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dictionary, key, &array), let array else { return nil }
        return numbers(in: array)
    }

    /// The paths of an array of arrays of numbers, such as `/InkList`.
    static func numberArrays(_ key: String, in dictionary: CGPDFDictionaryRef) -> [[Double]]? {
        var outerArray: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dictionary, key, &outerArray), let outerArray else { return nil }
        return (0..<CGPDFArrayGetCount(outerArray)).map { index in
            var innerArray: CGPDFArrayRef?
            return CGPDFArrayGetArray(outerArray, index, &innerArray) && innerArray != nil ? numbers(in: innerArray!) : []
        }
    }

    private static func numbers(in array: CGPDFArrayRef) -> [Double] {
        (0..<CGPDFArrayGetCount(array)).compactMap { index in
            var real: CGPDFReal = 0
            return CGPDFArrayGetNumber(array, index, &real) ? Double(real) : nil
        }
    }

    /// The decoded content of the annotation's normal appearance stream (`/AP /N`).
    static func normalAppearanceContent(of dictionary: CGPDFDictionaryRef) -> String? {
        var appearance: CGPDFDictionaryRef?
        var normalAppearance: CGPDFStreamRef?
        guard CGPDFDictionaryGetDictionary(dictionary, "AP", &appearance), let appearance,
              CGPDFDictionaryGetStream(appearance, "N", &normalAppearance), let normalAppearance else { return nil }
        var format = CGPDFDataFormat.raw
        guard let content = CGPDFStreamCopyData(normalAppearance, &format) else { return nil }
        return String(decoding: content as Data, as: UTF8.self)
    }
}
