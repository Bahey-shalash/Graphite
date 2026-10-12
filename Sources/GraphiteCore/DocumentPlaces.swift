import Foundation

/// Where a note was shown: the character at the top of the view, in UTF-16 units of the
/// note's text, and the cursor.
public struct NotePlace: Codable, Equatable, Sendable {
    public var topLocation: Int
    public var selectionLocation: Int
    public var selectionLength: Int

    public init(topLocation: Int, selectionLocation: Int, selectionLength: Int) {
        self.topLocation = topLocation
        self.selectionLocation = selectionLocation
        self.selectionLength = selectionLength
    }

    /// The top of the note with the cursor at its start: nothing to come back to.
    public var isStart: Bool { topLocation <= 0 && selectionLocation <= 0 && selectionLength <= 0 }
}

/// Where a PDF was shown: the page at the top of the view, and how far down that page the
/// top edge was, as a fraction of the page's height, which does not depend on the zoom.
public struct PDFPagePlace: Codable, Equatable, Sendable {
    public var pageIndex: Int
    public var fractionFromTop: Double

    public init(pageIndex: Int, fractionFromTop: Double) {
        self.pageIndex = pageIndex
        self.fractionFromTop = fractionFromTop
    }

    /// The top of the first page: nothing to come back to.
    public var isStart: Bool { pageIndex <= 0 && fractionFromTop <= 0 }
}

public enum DocumentPlace: Codable, Equatable, Sendable {
    case note(NotePlace)
    case pdf(PDFPagePlace)

    var isStart: Bool {
        switch self {
        case .note(let place): place.isStart
        case .pdf(let place): place.isStart
        }
    }
}

/// The places the documents of one vault were left at, so each opens where it was left,
/// also after Graphite quits or iOS closes it in the background. Kept on the device, as
/// folds are, never in the vault. The most recently left `maximumDocumentCount` are kept.
public struct DocumentPlaceMemory: Codable, Equatable, Sendable {
    public static let maximumDocumentCount = 400

    private struct RememberedPlace: Codable, Equatable, Sendable {
        var place: DocumentPlace
        var leftAt: Date
    }

    private var placesByPath: [String: RememberedPlace] = [:]

    public init() {}

    public var documentCount: Int { placesByPath.count }

    public func place(of path: VaultPath) -> DocumentPlace? {
        placesByPath[path.rawValue]?.place
    }

    /// Remembers where a document was left; the start of a document is forgotten, as it is
    /// where the document opens anyway. The places left longest ago make way beyond the bound.
    public mutating func remember(_ place: DocumentPlace, of path: VaultPath, at time: Date) {
        guard !place.isStart else {
            placesByPath[path.rawValue] = nil
            return
        }
        placesByPath[path.rawValue] = RememberedPlace(place: place, leftAt: time)
        let excessCount = placesByPath.count - Self.maximumDocumentCount
        guard excessCount > 0 else { return }
        let oldestPaths = placesByPath.sorted { leftEntry, rightEntry in leftEntry.value.leftAt < rightEntry.value.leftAt }
            .prefix(excessCount).map(\.key)
        for oldestPath in oldestPaths { placesByPath[oldestPath] = nil }
    }

    /// Keeps places with their documents when a file or folder is renamed or moved.
    public mutating func followMove(from oldPath: VaultPath, to newPath: VaultPath) {
        for (rawPath, rememberedPlace) in placesByPath {
            guard let path = try? VaultPath(rawPath), path.isInside(oldPath),
                  let movedPath = try? path.replacingPrefix(oldPath, with: newPath) else { continue }
            placesByPath[rawPath] = nil
            placesByPath[movedPath.rawValue] = rememberedPlace
        }
    }

    public mutating func forget(inside removedPath: VaultPath) {
        for rawPath in placesByPath.keys where (try? VaultPath(rawPath))?.isInside(removedPath) == true {
            placesByPath[rawPath] = nil
        }
    }
}
