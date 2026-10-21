#if canImport(UIKit)
import SwiftUI
import UIKit
import VisionKit

/// The system's document scanner: the camera finds the page, straightens and crops it, and
/// the person can scan several pages before saving. It is offered only where the device can
/// scan (`isSupported`: false in the simulator and on a Mac), so no control appears that
/// cannot work. Cancelling reports nothing.
struct DocumentScanner: UIViewControllerRepresentable {
    enum Outcome {
        case scanned([CGImage])
        /// The scanner failed, or a page's picture could not be read; the person is told to scan again.
        case failed
    }

    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    let finish: (Outcome) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    // VisionKit calls its delegate on the main thread; the protocol does not say so.
    @MainActor
    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        init(parent: DocumentScanner) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pageImages = (0..<scan.pageCount).compactMap { pageIndex in DocumentScanner.pageImage(from: scan.imageOfPage(at: pageIndex)) }
            parent.dismiss()
            guard scan.pageCount > 0 else { return }
            // A page that cannot be read must not silently drop out of the document.
            parent.finish(pageImages.count == scan.pageCount ? .scanned(pageImages) : .failed)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: any Error) {
            parent.dismiss()
            parent.finish(.failed)
        }
    }

    /// The page's pixels with the picture's orientation applied, so the PDF page is upright.
    static func pageImage(from image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let pixels = image.cgImage { return pixels }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in image.draw(at: .zero) }.cgImage
    }
}
#endif
