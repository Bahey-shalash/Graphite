import Foundation
import CoreGraphics

/// The typed text of a PDF's text boxes, for Search: the `/Contents` of every `/FreeText`
/// annotation, read with Core Graphics, which loads only the page and annotation
/// dictionaries asked for, not the pages' content. The pages' own printed text is not read.
public enum PDFFreeTextContents {
    /// Bounds the work for one PDF: pages looked at, annotations per page, and text kept.
    public static let maximumPageCount = 10_000
    public static let maximumAnnotationsPerPage = 2_000
    public static let maximumUTF16Count = 1_048_576

    /// The text of the document's text boxes, one box per line, in page order and in each
    /// page's annotation order; empty when it has none. Stops at the limits; what was read
    /// until then is kept.
    public static func searchableText(of document: CGPDFDocument) -> String {
        var text = ""
        var textUTF16Count = 0
        let pageCount = min(document.numberOfPages, maximumPageCount)
        guard pageCount > 0 else { return "" }
        pageLoop: for pageNumber in 1...pageCount {
            guard let page = document.page(at: pageNumber), let pageDictionary = page.dictionary else { continue }
            for contents in freeTextContents(onPage: pageDictionary) {
                let addedCount = contents.utf16.count + 1
                guard textUTF16Count + addedCount <= maximumUTF16Count else { break pageLoop }
                text += contents + "\n"
                textUTF16Count += addedCount
            }
        }
        return text
    }

    private static func freeTextContents(onPage pageDictionary: CGPDFDictionaryRef) -> [String] {
        var annotations: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(pageDictionary, "Annots", &annotations), let annotations else { return [] }
        let annotationCount = min(CGPDFArrayGetCount(annotations), maximumAnnotationsPerPage)
        return (0..<annotationCount).compactMap { annotationIndex -> String? in
            var annotation: CGPDFDictionaryRef?
            var subtype: UnsafePointer<CChar>?
            var contents: CGPDFStringRef?
            guard CGPDFArrayGetDictionary(annotations, annotationIndex, &annotation), let annotation,
                  CGPDFDictionaryGetName(annotation, "Subtype", &subtype), let subtype, String(cString: subtype) == PDFTextBox.annotationTypeName,
                  CGPDFDictionaryGetString(annotation, "Contents", &contents), let contents,
                  let text = CGPDFStringCopyTextString(contents) as String? else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed.replacingOccurrences(of: "\r", with: "\n")
        }
    }
}
