import Foundation
import PDFKit
import GraphiteCore

/// The delegate of every PDF document Graphite shows (`PDFPageManager.prepareForDisplay`):
/// PDFKit makes the stamps it reads from the file `PDFPictureAnnotation`s and the
/// `/FreeText` annotations `PDFTextBoxAnnotation`s, so Graphite's pictures and text boxes
/// are drawn as smoothly after the PDF is opened again as while it is edited. The file is
/// not changed: an annotation read this way keeps its saved appearance and keys, and a
/// document Graphite writes never has this delegate.
public final class PDFAnnotationDrawingDelegate: NSObject, PDFDocumentDelegate, @unchecked Sendable {
    // Unchecked: it has no state, so it can be shared by documents on any thread.
    public static let shared = PDFAnnotationDrawingDelegate()

    override private init() { super.init() }

    /// PDFKit asks with the subtype without its slash. For any other subtype, the base
    /// class leaves PDFKit to choose as it would without a delegate (seen with PDFKit on
    /// macOS 27 and iOS 27, `PDFPictureTests`).
    public func `class`(forAnnotationType annotationType: String) -> AnyClass {
        switch annotationType {
        case PDFPicture.annotationTypeName: PDFPictureAnnotation.self
        case PDFTextBox.annotationTypeName: PDFTextBoxAnnotation.self
        default: PDFAnnotation.self
        }
    }
}

/// The delegate of every PDF document Graphite writes (`PDFPageManager.prepareForWriting`):
/// PDFKit makes the `/FreeText` annotations it reads from the file
/// `PDFWrittenTextBoxAnnotation`s, so that a write that draws their appearance again (one
/// that rewrites the page tree) draws Graphite's text boxes as Graphite does. Every other
/// annotation, and another application's text box, is drawn by PDFKit as before.
public final class PDFWrittenDocumentDelegate: NSObject, PDFDocumentDelegate, @unchecked Sendable {
    // Unchecked: it has no state, so it can be shared by documents on any thread.
    public static let shared = PDFWrittenDocumentDelegate()

    override private init() { super.init() }

    public func `class`(forAnnotationType annotationType: String) -> AnyClass {
        annotationType == PDFTextBox.annotationTypeName ? PDFWrittenTextBoxAnnotation.self : PDFAnnotation.self
    }
}
