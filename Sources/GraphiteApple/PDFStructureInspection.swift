import Foundation
import CoreGraphics

/// Document-level PDF entries that a page change would remove.
///
/// PDFKit rewrites the document catalog whenever pages are inserted, deleted, reordered,
/// or the outline changes, and the rewritten catalog keeps only the page tree, outline
/// and XMP metadata. Anything else, such as page numbering labels, viewer settings or the
/// PDF version the catalog declares, disappears from the saved file. The user is told
/// before that happens.
public enum PDFStructureInspection {
    private static let catalogKeysKeptByRewrite: Set<String> = ["Type", "Pages", "Outlines", "Metadata"]
    /// Bounds the form fields read while looking for a signature, since a file can nest
    /// fields without limit (or in a cycle).
    private static let maximumInspectedFormFields = 10_000

    /// Readable names of the entries a page change would remove from this PDF, empty when
    /// nothing would be lost. Reads only the catalog, which CoreGraphics loads lazily.
    public static func entriesLostByPageChanges(in fileLocation: URL) -> [String] {
        guard let document = CGPDFDocument(fileLocation as CFURL), let catalog = document.catalog else { return [] }
        var keys: [String] = []
        CGPDFDictionaryApplyBlock(catalog, { key, _, _ in
            keys.append(String(cString: key))
            return true
        }, nil)
        var descriptions = Set(keys.filter { key in !catalogKeysKeptByRewrite.contains(key) }.map(description(ofCatalogKey:)))
        if hasDigitalSignature(catalog: catalog) { descriptions.insert("digital signatures") }
        return descriptions.sorted()
    }

    /// Whether the PDF is digitally signed. Graphite writes every change as a new file,
    /// not as an incremental update appended to the signed bytes, so any saved change
    /// invalidates the signature.
    public static func hasDigitalSignature(in fileLocation: URL) -> Bool {
        guard let document = CGPDFDocument(fileLocation as CFURL), let catalog = document.catalog else { return false }
        return hasDigitalSignature(catalog: catalog)
    }

    private static func hasDigitalSignature(catalog: CGPDFDictionaryRef) -> Bool {
        // Certification and usage-rights signatures, and long-term validation data.
        var permissions: CGPDFDictionaryRef?, securityStore: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(catalog, "Perms", &permissions) || CGPDFDictionaryGetDictionary(catalog, "DSS", &securityStore) { return true }
        var form: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(catalog, "AcroForm", &form), let form else { return false }
        // Bit 1 of SigFlags is SignaturesExist.
        var signatureFlags: CGPDFInteger = 0
        if CGPDFDictionaryGetInteger(form, "SigFlags", &signatureFlags), signatureFlags & 1 != 0 { return true }
        var fields: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(form, "Fields", &fields), let fields else { return false }
        var pendingFieldArrays = [fields]
        var inspectedFieldCount = 0
        while let fieldArray = pendingFieldArrays.popLast() {
            for fieldIndex in 0..<CGPDFArrayGetCount(fieldArray) {
                inspectedFieldCount += 1
                guard inspectedFieldCount <= maximumInspectedFormFields else { return false }
                var field: CGPDFDictionaryRef?
                guard CGPDFArrayGetDictionary(fieldArray, fieldIndex, &field), let field else { continue }
                var fieldType: UnsafePointer<Int8>?
                var signatureValue: CGPDFObjectRef?
                if CGPDFDictionaryGetName(field, "FT", &fieldType), let fieldType, String(cString: fieldType) == "Sig",
                   CGPDFDictionaryGetObject(field, "V", &signatureValue) {
                    return true
                }
                var childFields: CGPDFArrayRef?
                if CGPDFDictionaryGetArray(field, "Kids", &childFields), let childFields { pendingFieldArrays.append(childFields) }
            }
        }
        return false
    }

    private static func description(ofCatalogKey key: String) -> String {
        switch key {
        case "PageLabels": "page numbering labels"
        case "OpenAction": "the opening page"
        case "PageLayout", "PageMode", "ViewerPreferences": "viewer settings"
        case "AcroForm": "form fields"
        case "Names", "Dests": "named destinations and attachments"
        case "StructTreeRoot", "MarkInfo", "Lang": "accessibility tags"
        case "OCProperties": "layers"
        case "AA", "JavaScript": "scripts"
        case "Version": "the declared PDF version"
        default: "other document settings"
        }
    }
}
