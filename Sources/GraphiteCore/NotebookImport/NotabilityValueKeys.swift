import Foundation

// The keys of the parts of `Session.plist` and `Recordings/library.plist` that are read without being checked for
// keys the reader does not know.

/// The session's paper layout model.
enum NotabilityPaperLayoutModelKey: String, NotabilityKey {
    case paperAttributes = "documentPaperAttributes"
}

/// The paper attributes of the paper layout model.
enum NotabilityPaperAttributeKey: String, NotabilityKey {
    case identifier = "paperIdentifier"
    case size = "paperSize"
    case orientation = "paperOrientation"
    case sizingBehaviour = "paperSizingBehavior"
    case lineStyle = "lineStyle2"
}

/// The reflow state of `richText`.
enum NotabilityReflowStateKey: String, NotabilityKey {
    case pageWidth = "pageWidthInDocumentCoordsKey"
    case nativeLayoutDevice = "nativeLayoutDeviceStringKey"
}

/// `richText.Handwriting Overlay`.
enum NotabilityHandwritingOverlayKey: String, NotabilityKey {
    case spatialHash = "SpatialHash"
}

/// The `contentPlaybackEventManager`; its packed arrays are `NotabilityPackedArray`.
enum NotabilityEventManagerKey: String, NotabilityKey {
    case eventCount = "NBCPTimeManagerSOANumEventsKey"
}

/// `richText.attributedString`.
enum NotabilityAttributedStringKey: String, NotabilityKey {
    case text = "stringKey"
    case runs = "subRangesKey"
}

/// One run of the typed text.
enum NotabilityTextRunKey: String, NotabilityKey {
    case otherAttributes = "subRangeOtherAttributesKey"
    case font = "subRangeFontKey"
    case range = "subRangeRangeKey"
    case color = "subRangeColorCrossPlatformKey"
}

/// A text run's font.
enum NotabilityTextFontKey: String, NotabilityKey {
    case name = "NSFontNameAttribute"
    case size = "NSFontSizeAttribute"
}

/// A picture's figure.
enum NotabilityFigureKey: String, NotabilityKey {
    case cropRectangle = "FigureCropRectKey"
    case backgroundObject = "FigureBackgroundObjectKey"
}

/// A figure's background object.
enum NotabilityFigureBackgroundKey: String, NotabilityKey {
    case imageSnapshot = "kImageObjectSnapshotKey"
}

/// A picture's image snapshot.
enum NotabilityImageSnapshotKey: String, NotabilityKey {
    case relativePath
}

/// The embedded property list of the ink's `shapes`: three arrays of one length.
enum NotabilityShapeListKey: String, NotabilityKey {
    case shapes
    case kinds
    case indices
}

/// A shape's appearance.
enum NotabilityShapeAppearanceKey: String, NotabilityKey {
    case strokeColor
    case strokeWidth
    case dashStyle
}

/// A shape's stroke colour.
enum NotabilityShapeColorKey: String, NotabilityKey {
    case rgba
}

/// A shape's dash style.
enum NotabilityShapeDashStyleKey: String, NotabilityKey {
    case pattern
}

/// The root of `Recordings/library.plist`.
enum NotabilityRecordingsLibraryKey: String, NotabilityKey {
    case recordings
}

/// One recording of the library.
enum NotabilityRecordingKey: String, NotabilityKey {
    case identifier
    case filePath = "filepath"
    case duration
    case name
}
