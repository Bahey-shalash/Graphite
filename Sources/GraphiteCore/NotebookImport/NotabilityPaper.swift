import Foundation

/// The paper of a Notability note (`GLModel.PaperAttributes`), each string decoded once. A string this reader does
/// not know is kept as it is; an absent one is nil.
public struct NotabilityPaper: Sendable, Equatable {
    public let identifier: NotabilityPaperIdentifier?
    public let size: NotabilityPaperSize?
    public let orientation: NotabilityPaperOrientation?
    public let sizingBehaviour: NotabilityPaperSizingBehaviour?
    public let lineStyle: NotabilityPaperLineStyle?

    public init(identifier: NotabilityPaperIdentifier?, size: NotabilityPaperSize?, orientation: NotabilityPaperOrientation?,
                sizingBehaviour: NotabilityPaperSizingBehaviour?, lineStyle: NotabilityPaperLineStyle?) {
        self.identifier = identifier
        self.size = size
        self.orientation = orientation
        self.sizingBehaviour = sizingBehaviour
        self.lineStyle = lineStyle
    }
}

/// `paperIdentifier`: which paper Notability draws.
public enum NotabilityPaperIdentifier: Sendable, Hashable {
    /// `Legacy:13`, white in every export seen.
    case legacyWhite
    /// `Legacy:15`, black in every export seen.
    case legacyBlack
    case unknown(String)

    public init(rawIdentifier: String) {
        switch rawIdentifier {
        case "Legacy:13": self = .legacyWhite
        case "Legacy:15": self = .legacyBlack
        default: self = .unknown(rawIdentifier)
        }
    }
}

/// `paperSize`: the export's page size.
public enum NotabilityPaperSize: Sendable, Hashable {
    case letter
    case a4
    case unknown(String)

    public init(rawSize: String) {
        switch rawSize {
        case "letter": self = .letter
        case "a4": self = .a4
        default: self = .unknown(rawSize)
        }
    }
}

public enum NotabilityPaperOrientation: Sendable, Hashable {
    case portrait
    case landscape
    case unknown(String)

    public init(rawOrientation: String) {
        switch rawOrientation {
        case "portrait": self = .portrait
        case "landscape": self = .landscape
        default: self = .unknown(rawOrientation)
        }
    }
}

/// `paperSizingBehavior`: how wide a page is in document units.
public enum NotabilityPaperSizingBehaviour: Sendable, Hashable {
    /// `lockedWidth:<width>:<device>`: the page is `width` units wide, as on the device the note was made on.
    case lockedWidth(width: Double, device: String)
    /// `deviceBasedWidth`: the width of the device that opens the note; the note stores none.
    case deviceBasedWidth
    /// `staticWidth`: a note made from an imported PDF.
    case staticWidth
    case unknown(String)

    private static let lockedWidthPrefix = "lockedWidth:"

    /// `lockedWidth:` must be followed by digits and dots, a colon and the device, as the reference reader requires.
    public init(rawBehaviour: String) {
        switch rawBehaviour {
        case "deviceBasedWidth": self = .deviceBasedWidth
        case "staticWidth": self = .staticWidth
        default: self = Self.lockedWidth(rawBehaviour) ?? .unknown(rawBehaviour)
        }
    }

    private static func lockedWidth(_ rawBehaviour: String) -> NotabilityPaperSizingBehaviour? {
        guard rawBehaviour.hasPrefix(lockedWidthPrefix) else { return nil }
        let parameters = rawBehaviour.dropFirst(lockedWidthPrefix.count)
        guard let separator = parameters.firstIndex(of: ":") else { return nil }
        let widthText = parameters[..<separator]
        let device = String(parameters[parameters.index(after: separator)...])
        guard !widthText.isEmpty, widthText.allSatisfy({ character in character == "." || ("0"..."9").contains(character) }),
              !device.contains("\n"), let width = Double(widthText) else { return nil }
        return .lockedWidth(width: width, device: device)
    }
}

/// `lineStyle2`: the rules drawn on the paper. The parameters after the style's name are kept as written: what
/// they mean is not known beyond the samples (`Lines:false:false:0.5`, `Grid:false:true:0.5`).
public enum NotabilityPaperLineStyle: Sendable, Hashable {
    case noLines
    case lines(parameters: [String])
    case grid(parameters: [String])
    case unknown(String)

    public init(rawStyle: String) {
        let parts = rawStyle.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        let parameters = Array(parts.dropFirst())
        switch parts.first ?? "" {
        case "No Lines" where parameters.isEmpty: self = .noLines
        case "Lines": self = .lines(parameters: parameters)
        case "Grid": self = .grid(parameters: parameters)
        default: self = .unknown(rawStyle)
        }
    }
}

/// `richText.reflowState`: whether the page width is locked to the device the note was made on.
public enum NotabilityReflowState: Sendable, Hashable {
    /// `NBReflowStateLocked`, with `pageWidthInDocumentCoordsKey` and the device (`iPad`, `Mac`, `A4`) when stored.
    case locked(pageWidth: Double?, device: String?)
    /// `NBReflowStateReflowable`: the text reflows to the device that opens the note.
    case reflowable
    case unknown(className: String)
}
