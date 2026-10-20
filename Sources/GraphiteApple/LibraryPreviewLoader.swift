import Foundation
import CoreGraphics
import ImageIO
import PDFKit
import GraphiteCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// What a library tile shows for a file.
public enum LibraryTilePreview: Sendable {
    /// A PDF's first page with its ink, an image, or a drawing.
    case picture(CGImage)
    /// A note's first lines as reading view shows them, and its first picture.
    case note(NotePreviewSummary, picture: CGImage?)
    /// A file in the cloud that is not on this device; it is not downloaded for a preview.
    case notDownloaded
    /// Nothing to draw, such as a canvas or an unreadable file: the tile shows its kind.
    case kindIcon
}

/// Makes library tile previews from vault files. Reads only what a tile needs: a PDF's first
/// page, an image scaled down by ImageIO, a note's first `NotePreviewSummary.maximumPrefixBytes`.
/// Every read is coordinated with the file's provider; none runs on the main actor.
public struct LibraryPreviewLoader: Sendable {
    /// Finds the vault file a note's picture embed names, from the note's path.
    public typealias PictureResolver = @Sendable (_ target: String, _ notePath: VaultPath) async -> VaultPath?

    public let root: URL
    private let resolvePicture: PictureResolver

    public init(root: URL, resolvePicture: @escaping PictureResolver) {
        self.root = root
        self.resolvePicture = resolvePicture
    }

    public func preview(of path: VaultPath, longerSidePixels: Int) async -> LibraryTilePreview {
        guard let location = try? path.url(in: root) else { return .kindIcon } // A path outside the vault has nothing to draw.
        if !Self.isOnThisDevice(location) { return .notDownloaded }
        // A tile scrolled away before its turn draws nothing; its result is not used.
        if Task.isCancelled { return .kindIcon }
        switch DocumentKind(path: path) {
        case .pdf: return Self.firstPage(of: location, longerSidePixels: longerSidePixels).map(LibraryTilePreview.picture) ?? .kindIcon
        case .image: return Self.picture(at: location, longerSidePixels: longerSidePixels).map(LibraryTilePreview.picture) ?? .kindIcon
        case .markdown: return await notePreview(of: path, at: location, longerSidePixels: longerSidePixels)
        case .base, .canvas, .media, .other: return .kindIcon
        }
    }

    private func notePreview(of path: VaultPath, at location: URL, longerSidePixels: Int) async -> LibraryTilePreview {
        guard let prefix = Self.coordinatedPrefix(of: location, maximumBytes: NotePreviewSummary.maximumPrefixBytes) else { return .kindIcon }
        let text = String(decoding: prefix.data, as: UTF8.self)
        let summary = NotePreviewSummary.summary(ofPrefix: text, isWholeFile: prefix.isWholeFile)
        var picture: CGImage?
        if let target = summary.firstPictureTarget, !Task.isCancelled, let picturePath = await resolvePicture(target, path),
           let pictureLocation = try? picturePath.url(in: root), Self.isOnThisDevice(pictureLocation), !Task.isCancelled { // No picture: text only.
            picture = Self.picture(at: pictureLocation, longerSidePixels: longerSidePixels / 2)
        }
        return .note(summary, picture: picture)
    }

    /// A file iCloud or another provider has not downloaded is read only when opened.
    static func isOnThisDevice(_ location: URL) -> Bool {
        guard let values = try? location.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]), // Unknown is local.
              values.isUbiquitousItem == true else { return true }
        return values.ubiquitousItemDownloadingStatus == .current
    }

    /// The first page with its annotations, as PDFKit draws it for any reader.
    static func firstPage(of location: URL, longerSidePixels: Int) -> CGImage? {
        coordinatedRead(of: location) { readableLocation in
            guard let document = PDFDocument(url: readableLocation), !document.isLocked, let page = document.page(at: 0) else { return nil }
            let bounds = page.bounds(for: .cropBox)
            guard bounds.width > 0, bounds.height > 0 else { return nil }
            let scale = CGFloat(longerSidePixels) / max(bounds.width, bounds.height)
            let thumbnail = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .cropBox)
            #if canImport(UIKit)
            return thumbnail.cgImage
            #else
            return thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil)
            #endif
        } ?? nil
    }

    /// An image scaled down while it is decoded, never decoded at full size.
    static func picture(at location: URL, longerSidePixels: Int) -> CGImage? {
        coordinatedRead(of: location) { readableLocation in
            guard let source = CGImageSourceCreateWithURL(readableLocation as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                            kCGImageSourceThumbnailMaxPixelSize: max(longerSidePixels, 1), kCGImageSourceShouldCacheImmediately: true]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        } ?? nil
    }

    /// The first bytes of a file, and whether they are all of it.
    static func coordinatedPrefix(of location: URL, maximumBytes: Int) -> (data: Data, isWholeFile: Bool)? {
        coordinatedRead(of: location) { readableLocation in
            guard let handle = try? FileHandle(forReadingFrom: readableLocation) else { return nil } // Unreadable: the tile shows the kind.
            defer { try? handle.close() } // Closing a read-only handle loses nothing.
            // One byte more than shown tells whether the file goes on.
            guard let data = try? handle.read(upToCount: maximumBytes + 1) else { return (Data(), true) } // Unreadable reads as empty text.
            return (data.prefix(maximumBytes), data.count <= maximumBytes)
        } ?? nil
    }

    /// Runs `read` with the file provider's agreement; nil when it is refused.
    private static func coordinatedRead<Value>(of location: URL, _ read: (URL) -> Value) -> Value? {
        var coordinationError: NSError?
        var value: Value?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: location, options: [.withoutChanges], error: &coordinationError) { readableLocation in
            value = read(readableLocation)
        }
        return coordinationError == nil ? value : nil
    }
}
