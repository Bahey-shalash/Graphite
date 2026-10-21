import Foundation
import CoreGraphics
import Observation
import UniformTypeIdentifiers
import GraphiteApple

/// Why a chosen file cannot become a paper template.
enum MyTemplateDraftError: Error, Equatable {
    case unreadable
    case tooLarge
    /// Neither a PDF nor a picture.
    case unsupported
    case locked
}

/// A PDF or a picture the person chose to make paper of, while they pick its page and name it.
/// The file is read once; its pages are drawn small as they come on screen.
@MainActor @Observable
final class MyTemplateDraft: Identifiable {
    enum Kind: Equatable {
        case pdf(pageCount: Int)
        case picture
    }

    /// The most a chosen file may weigh: it is read into memory (mapped where the system allows).
    nonisolated static let maximumSourceBytes = 256 * 1_048_576
    /// A page's small picture, longer side in pixels.
    nonisolated static let pagePreviewPixels = 220
    /// Small pictures kept at once while the pages are scrolled.
    static let maximumPagePreviewCount = 24

    let id = UUID()
    let kind: Kind
    /// The chosen file's name without its extension; "Picture" for a photo that has none.
    let sourceName: String
    private(set) var selectedPageIndex = 0
    private(set) var name: String
    private(set) var pagePreviews: [Int: CGImage] = [:]

    @ObservationIgnored private let sourceData: Data
    @ObservationIgnored private var hasEditedName = false
    @ObservationIgnored private var drawnPageOrder: [Int] = []

    private init(kind: Kind, sourceName: String, sourceData: Data) {
        self.kind = kind
        self.sourceName = sourceName
        self.sourceData = sourceData
        name = Self.defaultName(sourceName: sourceName, kind: kind, pageIndex: 0)
    }

    var pageCount: Int {
        switch kind {
        case .pdf(let pageCount): pageCount
        case .picture: 1
        }
    }

    /// The name offered: the file's, with the page's number when the PDF has several.
    private static func defaultName(sourceName: String, kind: Kind, pageIndex: Int) -> String {
        guard case .pdf(let pageCount) = kind, pageCount > 1 else { return sourceName }
        return "\(sourceName) page \(pageIndex + 1)"
    }

    func selectPage(_ pageIndex: Int) {
        guard pageIndex >= 0, pageIndex < pageCount, pageIndex != selectedPageIndex else { return }
        selectedPageIndex = pageIndex
        if !hasEditedName { name = Self.defaultName(sourceName: sourceName, kind: kind, pageIndex: pageIndex) }
    }

    func rename(to newName: String) {
        hasEditedName = true
        name = newName
    }

    // MARK: Reading

    /// Reads a chosen file (with its security scope, off the main actor) and decides what it is.
    static func read(from location: URL) async throws -> MyTemplateDraft {
        let sourceData: Data = try await Task.detached(priority: .userInitiated) {
            let hasAccess = location.startAccessingSecurityScopedResource()
            defer { if hasAccess { location.stopAccessingSecurityScopedResource() } }
            let fileSize = (try? location.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? nil // An unknown size is not read.
            guard let fileSize else { throw MyTemplateDraftError.unreadable }
            guard fileSize <= maximumSourceBytes else { throw MyTemplateDraftError.tooLarge }
            let data = try? Data(contentsOf: location, options: .mappedIfSafe) // Any failure reads as unreadable.
            guard let data else { throw MyTemplateDraftError.unreadable }
            return data
        }.value
        return try await make(from: sourceData, sourceName: location.deletingPathExtension().lastPathComponent)
    }

    /// A draft of a picture's data, such as a photo from the photo library.
    static func make(from sourceData: Data, sourceName: String) async throws -> MyTemplateDraft {
        let kind: Kind = try await Task.detached(priority: .userInitiated) {
            if sourceData.prefix(5) == Data("%PDF-".utf8) {
                do {
                    return Kind.pdf(pageCount: try MyPaperTemplateBuilder.pageCount(ofPDF: sourceData))
                } catch MyPaperTemplateError.locked {
                    throw MyTemplateDraftError.locked
                } catch {
                    throw MyTemplateDraftError.unsupported
                }
            }
            guard MyPaperTemplateBuilder.previewImage(ofPicture: sourceData, longerSidePixels: 1) != nil else { throw MyTemplateDraftError.unsupported }
            return Kind.picture
        }.value
        return MyTemplateDraft(kind: kind, sourceName: sourceName.isEmpty ? "Picture" : sourceName, sourceData: sourceData)
    }

    // MARK: Drawing and making

    /// Draws a page's small picture once, when its tile comes on screen.
    func drawPagePreview(of pageIndex: Int) async {
        guard pagePreviews[pageIndex] == nil else { return }
        let sourceData = sourceData, kind = kind
        let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            switch kind {
            case .pdf: MyPaperTemplateBuilder.previewImage(ofPDF: sourceData, pageIndex: pageIndex, longerSidePixels: Self.pagePreviewPixels)
            case .picture: MyPaperTemplateBuilder.previewImage(ofPicture: sourceData, longerSidePixels: Self.pagePreviewPixels)
            }
        }.value
        guard let image, pagePreviews[pageIndex] == nil else { return }
        pagePreviews[pageIndex] = image
        drawnPageOrder.append(pageIndex)
        while drawnPageOrder.count > Self.maximumPagePreviewCount { pagePreviews[drawnPageOrder.removeFirst()] = nil }
    }

    /// The one-page PDF of the chosen page or picture; nil when it cannot be made.
    var templateData: Data? {
        get async {
            let sourceData = sourceData, kind = kind, pageIndex = selectedPageIndex
            return await Task.detached(priority: .userInitiated) { () -> Data? in
                switch kind {
                case .pdf: try? MyPaperTemplateBuilder.templateData(fromPDF: sourceData, pageIndex: pageIndex) // Not made: nothing is kept.
                case .picture: try? MyPaperTemplateBuilder.templateData(fromPicture: sourceData) // Not made: nothing is kept.
                }
            }.value
        }
    }
}
