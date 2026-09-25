import SwiftUI
import PDFKit
import GraphiteApple
#if canImport(UIKit)
import UIKit
typealias PDFThumbnailImage = UIImage
#else
import AppKit
typealias PDFThumbnailImage = NSImage
#endif

/// Renders and caches small page images for the pages sidebar.
///
/// A page's own content, which for a scanned page is a large image to decode, is drawn
/// off the main actor, one row at a time. Its annotations belong to the live document on
/// the main actor, so they are drawn over it there. A page's image is reused until its
/// appearance version changes. Every viewer shares one cache, bounded in bytes by the
/// device's memory, and holds its pages weakly, so a released PDF keeps nothing alive.
@MainActor
final class PDFThumbnailRenderer {
    private final class CachedThumbnail {
        let version: Int
        let image: PDFThumbnailImage
        init(version: Int, image: PDFThumbnailImage) { self.version = version; self.image = image }
    }

    private static let largestCacheByteLimit: UInt64 = 32 * 1_048_576
    /// About 20 MB on a 4 GB iPad; at most 32 MB.
    private static let cacheByteLimit = Int(min(largestCacheByteLimit, ProcessInfo.processInfo.physicalMemory / 200))
    private static let cache: NSCache<PDFThumbnailCacheKey, CachedThumbnail> = {
        let cache = NSCache<PDFThumbnailCacheKey, CachedThumbnail>()
        cache.totalCostLimit = cacheByteLimit
        return cache
    }()

    /// This viewer's entries in the shared cache, removed when it releases its PDF.
    private var cacheKeys: [PDFThumbnailCacheKey.Identity: PDFThumbnailCacheKey] = [:]
    private let contentRenderer = PDFPageContentRenderer()
    private weak var mappedDocument: PDFDocument?
    /// The file `mappedDocument` was read from, mapped into memory (see `PDFPageContentSource`).
    private var mappedFileData: NSData?

    /// Maps the file `document` was read from, while it still exists, so page content is
    /// drawn from a separate copy of it. A PDF session reads its file from a private
    /// snapshot that a save replaces, so a viewer calls this as soon as its PDF is open.
    func prepare(for document: PDFDocument) {
        guard mappedDocument !== document else { return }
        mappedDocument = document
        mappedFileData = nil
        // A separate copy of an encrypted PDF would need its password to open.
        guard !document.isEncrypted, let fileLocation = document.documentURL else { return }
        mappedFileData = try? NSData(contentsOf: fileLocation, options: .alwaysMapped)
    }

    /// Drops this viewer's thumbnails and its mapped file when it releases its PDF.
    func removeThumbnails() {
        for cacheKey in cacheKeys.values { Self.cache.removeObject(forKey: cacheKey) }
        cacheKeys.removeAll()
        mappedDocument = nil
        mappedFileData = nil
        let contentRenderer = contentRenderer
        Task { await contentRenderer.closeSeparateDocument() }
    }

    /// Returns nil when the row asking for it went away before its turn came.
    func thumbnail(for page: PDFPage, version: Int, fitting pointSize: CGSize, scale: CGFloat) async -> PDFThumbnailImage? {
        let outputSize = page.thumbnailSize(fitting: pointSize)
        let cacheKey = cacheKey(for: page, outputSize: outputSize, scale: scale)
        if let cached = Self.cache.object(forKey: cacheKey), cached.version == version { return cached.image }
        if let document = page.document { prepare(for: document) }
        let image: PDFThumbnailImage
        if let content = PDFPageContent(page: page, fitting: pointSize, scale: scale, source: contentSource(for: page)) {
            guard let contentImage = await contentRenderer.render(content) else { return nil }
            if let cached = Self.cache.object(forKey: cacheKey), cached.version == version { return cached.image }
            // The page may have been turned while its content was drawn.
            image = content.matches(page) ? composite(contentImage, annotationsOf: page, content: content) : render(page, fitting: pointSize, scale: scale)
        } else {
            image = render(page, fitting: pointSize, scale: scale)
        }
        let byteCost = Int(image.size.width * scale * image.size.height * scale * 4)
        cacheKeys[cacheKey.identity] = cacheKey
        Self.cache.setObject(CachedThumbnail(version: version, image: image), forKey: cacheKey, cost: byteCost)
        return image
    }

    /// Each pixel size has its own entry, so a small drag preview never stands in for a row.
    private func cacheKey(for page: PDFPage, outputSize: CGSize, scale: CGFloat) -> PDFThumbnailCacheKey {
        let identity = PDFThumbnailCacheKey.Identity(page: ObjectIdentifier(page),
                                                     pixelWidth: Int((outputSize.width * scale).rounded()),
                                                     pixelHeight: Int((outputSize.height * scale).rounded()))
        if let cacheKey = cacheKeys[identity], cacheKey.page === page { return cacheKey }
        return PDFThumbnailCacheKey(page: page, identity: identity)
    }

    /// Only a page of the mapped file itself, wherever it has moved, is drawn from the copy;
    /// pages inserted from other PDFs are drawn from the live document.
    private func contentSource(for page: PDFPage) -> PDFPageContentSource? {
        guard let document = page.document, document === mappedDocument, let mappedFileData,
              let documentReference = document.documentRef, let corePage = page.pageRef,
              corePage.document === documentReference else { return nil }
        return PDFPageContentSource(fileData: mappedFileData, pageNumber: corePage.pageNumber, filePageCount: documentReference.numberOfPages)
    }

    /// Draws the page's annotations over its content, as PDFKit's own thumbnails show them.
    /// Ink under a live Pencil canvas is hidden in the document; it is drawn here too.
    private func composite(_ contentImage: CGImage, annotationsOf page: PDFPage, content: PDFPageContent) -> PDFThumbnailImage {
        let annotations = page.annotations.filter { annotation in
            annotation.type != "Popup" && (annotation.shouldDisplay || annotation.value(forAnnotationKey: PDFPageManager.groupKey) != nil)
        }
        guard !annotations.isEmpty, let context = makeThumbnailBitmapContext(width: contentImage.width, height: contentImage.height) else {
            return Self.image(contentImage, pointSize: content.outputSize, scale: content.scale)
        }
        context.draw(contentImage, in: CGRect(x: 0, y: 0, width: contentImage.width, height: contentImage.height))
        // A bitmap context already has the PDF's upward y axis.
        context.scaleBy(x: content.pixelsPerPagePoint, y: content.pixelsPerPagePoint)
        for annotation in annotations { annotation.draw(with: .cropBox, in: context) }
        guard let compositeImage = context.makeImage() else { return Self.image(contentImage, pointSize: content.outputSize, scale: content.scale) }
        return Self.image(compositeImage, pointSize: content.outputSize, scale: content.scale)
    }

    private static func image(_ cgImage: CGImage, pointSize: CGSize, scale: CGFloat) -> PDFThumbnailImage {
        #if canImport(UIKit)
        UIImage(cgImage: cgImage, scale: scale, orientation: .up)
        #else
        NSImage(cgImage: cgImage, size: pointSize)
        #endif
    }

    /// Draws the whole page on the main actor, for a page without a Core Graphics page or
    /// one turned while its content was drawn. PDFKit's page and annotation drawing both
    /// apply the page rotation themselves, in a context with the PDF's upward y axis.
    private func render(_ page: PDFPage, fitting pointSize: CGSize, scale: CGFloat) -> PDFThumbnailImage {
        let outputSize = page.thumbnailSize(fitting: pointSize)
        let cropBox = page.bounds(for: .cropBox)
        let displayedWidth = (page.rotation / 90) % 2 != 0 ? cropBox.height : cropBox.width
        let pixelWidth = max(1, Int((outputSize.width * scale).rounded()))
        let pixelHeight = max(1, Int((outputSize.height * scale).rounded()))
        guard displayedWidth > 0, let context = makeThumbnailBitmapContext(width: pixelWidth, height: pixelHeight) else {
            return page.thumbnail(of: outputSize, for: .cropBox)
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        let pixelsPerPagePoint = CGFloat(pixelWidth) / displayedWidth
        context.scaleBy(x: pixelsPerPagePoint, y: pixelsPerPagePoint)
        page.draw(with: .cropBox, to: context)
        // Ink under a live Pencil canvas is hidden in the document; draw it here explicitly.
        for annotation in page.annotations where !annotation.shouldDisplay && annotation.value(forAnnotationKey: PDFPageManager.groupKey) != nil {
            annotation.draw(with: .cropBox, in: context)
        }
        guard let pageImage = context.makeImage() else { return page.thumbnail(of: outputSize, for: .cropBox) }
        return Self.image(pageImage, pointSize: outputSize, scale: scale)
    }
}

private func makeThumbnailBitmapContext(width: Int, height: Int) -> CGContext? {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
}

/// A thumbnail's cache key: the page and the pixel size it was drawn at. It holds the page
/// weakly, so the cache never keeps a released PDF's pages alive, and a key whose page is
/// gone matches no other key, so a new page at the same address never gets its image.
private final class PDFThumbnailCacheKey: NSObject {
    struct Identity: Hashable {
        let page: ObjectIdentifier
        let pixelWidth: Int
        let pixelHeight: Int
    }

    let identity: Identity
    weak var page: PDFPage?

    init(page: PDFPage, identity: Identity) {
        self.page = page
        self.identity = identity
    }

    override var hash: Int { identity.hashValue }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? PDFThumbnailCacheKey else { return false }
        if other === self { return true }
        guard let page, page === other.page else { return false }
        return identity == other.identity
    }
}

/// Where a page's content is drawn from instead of the live document.
///
/// Drawing a page keeps its decoded fonts and images in its Core Graphics document until
/// that document is released. Drawn from the live document, a scroll through the pages
/// would keep them for as long as the PDF is open; drawn from a separate copy of the same
/// file, reopened every few pages, they are released as the scroll goes on.
struct PDFPageContentSource: @unchecked Sendable {
    /// Immutable and mapped from a file that is never rewritten; it survives the file's
    /// removal when a save replaces the snapshot.
    let fileData: NSData
    /// One-based page number in the file.
    let pageNumber: Int
    /// A copy with another page count is not the file the page came from.
    let filePageCount: Int
}

/// What the background renderer needs to draw a page's own content: its immutable Core
/// Graphics page and the geometry read from the live page on the main actor.
///
/// `CGPDFPage` is an immutable Core Foundation object, which Quartz allows to be drawn
/// from any thread; the live `PDFPage` itself never leaves the main actor.
struct PDFPageContent: @unchecked Sendable {
    let corePage: CGPDFPage
    let source: PDFPageContentSource?
    let cropBox: CGRect
    /// Clockwise quarter turns shown, from the live page (edits may have turned it).
    let rotation: Int
    let outputSize: CGSize
    let scale: CGFloat

    @MainActor init?(page: PDFPage, fitting pointSize: CGSize, scale: CGFloat, source: PDFPageContentSource? = nil) {
        guard let corePage = page.pageRef, scale > 0 else { return nil }
        let cropBox = page.bounds(for: .cropBox)
        let outputSize = page.thumbnailSize(fitting: pointSize)
        guard cropBox.width > 0, cropBox.height > 0, outputSize.width > 0, outputSize.height > 0 else { return nil }
        self.corePage = corePage
        self.source = source
        self.cropBox = cropBox
        self.rotation = ((page.rotation % 360) + 360) % 360
        self.outputSize = outputSize
        self.scale = scale
    }

    var displayedWidth: CGFloat { rotation % 180 == 0 ? cropBox.width : cropBox.height }
    var pixelWidth: Int { max(1, Int((outputSize.width * scale).rounded())) }
    var pixelHeight: Int { max(1, Int((outputSize.height * scale).rounded())) }
    var pixelsPerPagePoint: CGFloat { CGFloat(pixelWidth) / displayedWidth }

    @MainActor func matches(_ page: PDFPage) -> Bool {
        page.bounds(for: .cropBox) == cropBox && ((page.rotation % 360) + 360) % 360 == rotation
    }

    /// Maps the crop box, turned clockwise by the page rotation, onto the bitmap, which has
    /// the PDF's upward y axis.
    func contentTransform() -> CGAffineTransform {
        let width = cropBox.width
        let height = cropBox.height
        let turn: CGAffineTransform = switch rotation {
        case 90: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: width)
        case 180: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: width, ty: height)
        case 270: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: height, ty: 0)
        default: .identity
        }
        return CGAffineTransform(translationX: -cropBox.minX, y: -cropBox.minY)
            .concatenating(turn)
            .concatenating(CGAffineTransform(scaleX: pixelsPerPagePoint, y: pixelsPerPagePoint))
    }
}

/// Draws page content off the main actor, one page at a time, so the rows of a fast scroll
/// queue up instead of decoding many scanned pages at once.
actor PDFPageContentRenderer {
    /// About 10 to 20 MB of decoded pages at a time for a typical lecture PDF.
    private static let pagesPerSeparateDocument = 64

    private struct SeparateDocument {
        let fileData: NSData
        let filePageCount: Int
        /// Nil when the mapped file is not the one the pages came from.
        let document: CGPDFDocument?
        var drawnPageCount = 0
    }

    private var separateDocument: SeparateDocument?

    /// Returns nil when the asking task was cancelled before its turn.
    func render(_ content: PDFPageContent) -> CGImage? {
        guard !Task.isCancelled, let context = makeThumbnailBitmapContext(width: content.pixelWidth, height: content.pixelHeight) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: content.pixelWidth, height: content.pixelHeight))
        context.interpolationQuality = .high
        context.concatenate(content.contentTransform())
        context.clip(to: content.cropBox)
        context.drawPDFPage(corePage(for: content))
        return context.makeImage()
    }

    func closeSeparateDocument() {
        separateDocument = nil
    }

    private func corePage(for content: PDFPageContent) -> CGPDFPage {
        guard let source = content.source else { return content.corePage }
        if let separateDocument, separateDocument.fileData !== source.fileData || separateDocument.filePageCount != source.filePageCount
            || (separateDocument.document != nil && separateDocument.drawnPageCount >= Self.pagesPerSeparateDocument) {
            self.separateDocument = nil
        }
        if separateDocument == nil {
            let document = CGDataProvider(data: source.fileData as CFData).flatMap { provider in CGPDFDocument(provider) }
            separateDocument = SeparateDocument(fileData: source.fileData, filePageCount: source.filePageCount,
                                                document: document.flatMap { document in document.numberOfPages == source.filePageCount ? document : nil })
        }
        guard let document = separateDocument?.document, let page = document.page(at: source.pageNumber) else { return content.corePage }
        separateDocument?.drawnPageCount += 1
        return page
    }
}

extension PDFPage {
    /// The page's displayed size (after rotation) scaled to fit `bounds`.
    func thumbnailSize(fitting bounds: CGSize) -> CGSize {
        let pageBounds = self.bounds(for: .cropBox)
        let isQuarterTurn = (rotation / 90) % 2 != 0
        let displayedSize = isQuarterTurn ? CGSize(width: pageBounds.height, height: pageBounds.width) : pageBounds.size
        guard displayedSize.width > 0, displayedSize.height > 0 else { return bounds }
        let fittingScale = min(bounds.width / displayedSize.width, bounds.height / displayedSize.height)
        return CGSize(width: (displayedSize.width * fittingScale).rounded(), height: (displayedSize.height * fittingScale).rounded())
    }
}

/// A page in a thumbnail list. Rows are identified by the page object, not its index,
/// so inserting or moving pages never shows one page's image for another.
struct PDFThumbnailListPage: Identifiable {
    let pageIndex: Int
    let page: PDFPage
    var id: ObjectIdentifier { ObjectIdentifier(page) }

    @MainActor static func pages(of document: PDFDocument) -> [PDFThumbnailListPage] {
        (0..<document.pageCount).compactMap { pageIndex in
            document.page(at: pageIndex).map { page in PDFThumbnailListPage(pageIndex: pageIndex, page: page) }
        }
    }
}

private struct PDFThumbnailKey: Hashable {
    let page: ObjectIdentifier
    let version: Int
    let width: CGFloat
    let height: CGFloat
    let scale: CGFloat
}

/// One page image in a thumbnail list, rendered when the row appears. Its frame has the
/// page's proportions within `size`.
struct PDFPageThumbnail: View {
    let page: PDFPage
    let version: Int
    let renderer: PDFThumbnailRenderer
    let size: CGSize
    private static let redrawDelay = Duration.milliseconds(400)
    @Environment(\.displayScale) private var displayScale
    @State private var image: PDFThumbnailImage?

    var body: some View {
        ZStack {
            if let image {
                #if canImport(UIKit)
                Image(uiImage: image).resizable().scaledToFit()
                #else
                Image(nsImage: image).resizable().scaledToFit()
                #endif
            } else {
                Rectangle().fill(.white)
            }
        }
        .frame(width: page.thumbnailSize(fitting: size).width, height: page.thumbnailSize(fitting: size).height)
        .task(id: PDFThumbnailKey(page: ObjectIdentifier(page), version: version, width: size.width, height: size.height, scale: displayScale)) {
            if image != nil {
                // A page already shown is drawn again only once writing on it pauses, not
                // for every stroke's new version.
                do { try await Task.sleep(for: Self.redrawDelay) } catch { return }
            } else {
                // Yield first so a fast scroll cancels rows that are no longer visible.
                await Task.yield()
            }
            guard !Task.isCancelled, let renderedImage = await renderer.thumbnail(for: page, version: version, fitting: size, scale: displayScale) else { return }
            image = renderedImage
        }
    }
}
