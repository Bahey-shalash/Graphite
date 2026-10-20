import Foundation
import CoreGraphics
import GraphiteCore

/// Pictures of paper for choosing it. Each is the first page of the PDF a notebook with
/// that paper would get, drawn small, so a picture cannot differ from the notebook made.
/// Core Graphics only, so it runs off the main thread.
public enum PaperPreviewRenderer {
    /// The largest picture side drawn, in pixels; a picture larger than this costs memory
    /// without showing more paper.
    public static let maximumSidePixels = 1024

    /// The first page of the paper, fitted into a square of `longerSidePixels`.
    public static func image(of paper: PaperSpecification, longerSidePixels: Int) throws -> CGImage {
        let pageData = try PDFTemplateGenerator.documentData(paper: paper, pageCount: 1)
        guard let provider = CGDataProvider(data: pageData as CFData), let document = CGPDFDocument(provider),
              let page = document.page(at: 1) else {
            throw PaperPreviewError.pageNotDrawn
        }
        let pageBox = page.getBoxRect(.mediaBox)
        let longerSidePixels = min(max(longerSidePixels, 1), maximumSidePixels)
        let scale = Double(longerSidePixels) / max(pageBox.width, pageBox.height)
        let pixelWidth = max(Int((pageBox.width * scale).rounded()), 1), pixelHeight = max(Int((pageBox.height * scale).rounded()), 1)
        guard let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw PaperPreviewError.pageNotDrawn
        }
        context.interpolationQuality = .high
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -pageBox.minX, y: -pageBox.minY)
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { throw PaperPreviewError.pageNotDrawn }
        return image
    }
}

/// Why a picture of paper could not be made.
public enum PaperPreviewError: Error, Equatable {
    /// Core Graphics could not read back or draw the paper's page.
    case pageNotDrawn
}
