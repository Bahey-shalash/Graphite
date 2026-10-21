import Foundation

/// Everything of a Notability note but its curves, which `NotabilityNoteReader` decodes one at a time.
public struct NotabilityNote: Sendable, Equatable {
    public let name: String?
    /// `sessionFormatVersion`: 9 in every note read so far.
    public let sessionFormatVersion: Int64?
    /// The Notability version that saved the note, such as `14.3` or `16.13`.
    public let applicationVersion: String?
    public let paper: NotabilityPaper
    public let reflowState: NotabilityReflowState
    public let pageGeometry: NotabilityPageGeometry
    public let shapes: [NotabilityShape]
    /// The pictures in the note's order; `zIndex` gives their drawing order.
    public let pictures: [NotabilityPicture]
    public let typedText: NotabilityTypedText
    public let importedPDFPages: [NotabilityImportedPDFPage]
    /// Sorted by their key in the library, as text.
    public let recordings: [NotabilityRecording]
    public let playbackEvents: [NotabilityPlaybackEvent]
}

/// What one export page of a note shows.
public struct NotabilityPage: Sendable, Equatable {
    /// From 1.
    public let pageNumber: Int
    /// Where the page starts in document units: (pageNumber − 1) × the page height.
    public let topInUnits: Double
    /// In drawing order.
    public let curves: [NotabilityCurve]
    public let shapes: [NotabilityShape]
    public let pictures: [NotabilityPicture]
}
