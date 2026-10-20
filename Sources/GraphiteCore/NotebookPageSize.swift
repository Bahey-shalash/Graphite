import Foundation

/// The paper sizes a new notebook can take, as Goodnotes offers them. Sizes are portrait,
/// in PDF points (1/72 inch); `PageOrientation` turns them.
public enum NotebookPageSize: String, CaseIterable, Codable, Sendable, Identifiable {
    case a3, a4, a5, a6, a7, letter, tabloid

    public var id: String { rawValue }

    private static let pointsPerMillimeter = 72 / 25.4

    public var portraitPointSize: CGSize {
        switch self {
        case .a3: Self.isoSize(widthMillimeters: 297, heightMillimeters: 420)
        case .a4: Self.isoSize(widthMillimeters: 210, heightMillimeters: 297)
        case .a5: Self.isoSize(widthMillimeters: 148, heightMillimeters: 210)
        case .a6: Self.isoSize(widthMillimeters: 105, heightMillimeters: 148)
        case .a7: Self.isoSize(widthMillimeters: 74, heightMillimeters: 105)
        case .letter: CGSize(width: 612, height: 792)
        case .tabloid: CGSize(width: 792, height: 1224)
        }
    }

    /// An ISO 216 size, rounded to a hundredth of a point as PDF writers store it.
    private static func isoSize(widthMillimeters: Double, heightMillimeters: Double) -> CGSize {
        func points(_ millimeters: Double) -> Double { (millimeters * pointsPerMillimeter * 100).rounded() / 100 }
        return CGSize(width: points(widthMillimeters), height: points(heightMillimeters))
    }

    public func pointSize(in orientation: PageOrientation) -> CGSize {
        orientation.applied(to: portraitPointSize)
    }
}

/// Whether a page stands upright or lies on its side.
public enum PageOrientation: String, CaseIterable, Codable, Sendable, Identifiable {
    case portrait, landscape

    public var id: String { rawValue }

    /// The size turned to this orientation: the longer side vertical in portrait,
    /// horizontal in landscape. A square page is the same in both.
    public func applied(to size: CGSize) -> CGSize {
        let shorterSide = min(size.width, size.height), longerSide = max(size.width, size.height)
        switch self {
        case .portrait: return CGSize(width: shorterSide, height: longerSide)
        case .landscape: return CGSize(width: longerSide, height: shorterSide)
        }
    }

    /// The orientation a page of this size has; a square page counts as portrait.
    public init(of size: CGSize) {
        self = size.width > size.height ? .landscape : .portrait
    }
}
