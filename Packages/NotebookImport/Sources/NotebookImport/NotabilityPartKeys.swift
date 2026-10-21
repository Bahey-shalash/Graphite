import Foundation

// The keys of the parts of `Session.plist` that are checked for keys the reader does not know. Some cases are keys the
// format description accounts for and the reader does not read.

/// The `NoteTakingSession` root.
enum NotabilitySessionKey: String, NotabilityKey {
    case name
    case packagePath
    case subject
    case tags
    case creationDate
    case isReadOnly
    case sessionFormatVersion
    case richText
    case contentPlaybackEventManager
    case paperLayoutModel = "NBNoteTakingSessionDocumentPaperLayoutModelKey"
    case isHighlighterBehindText = "NBNoteTakingSessionIsHighlighterBehindTextKey"
    case handwritingLanguage = "NBNoteTakingSessionHandwritingLanguageKey"
    case minorVersionNumber = "NBNoteTakingSessionMinorVersionNumberKey"
    case lastUsedFont = "NBNoteTakingSessionLastUsedFontKey"
    case noteLinkStore = "kNBNoteTakingSessionNoteLinkStoreKey"
    case paperMinorVersionNumber = "NBPaperMinorVersionNumber"
    case paperMajorVersionNumber = "NBPaperMajorVersionNumber"
    case allowsHighlighterConversion = "NBNoteTakingSessionAllowHighlighterConversionKey"
    case applicationVersion = "NBNoteTakingSessionBundleVersionNumberKey"
}

/// `richText`, the `FormattedString` of the page content.
enum NotabilityRichTextKey: String, NotabilityKey {
    case formatVersion
    case textAlignment = "formattedStringTextAlignmentKey"
    case attributedString
    case attributedBackingString = "NBAttributedBackingString"
    case handwritingOverlay = "Handwriting Overlay"
    case reflowState
    case didBecomeReflowable
    case pdfFiles
    case mediaObjects
    case recordingTimestampString
    case pageLayoutArray
}

/// The `InkedSpatialHash` that holds the curves: its counts, its packed arrays (`NotabilityPackedArray`, whose keys the
/// known set adds) and four more values.
enum NotabilityInkKey: String, NotabilityKey {
    case curveCount = "numcurves"
    case pointCount = "numpoints"
    case knotCount = "numfractionalwidths"
    case options
    case groups = "groupsArrays"
    case bezierPathsData = "bezierPathsDataDictionary"
    /// An embedded property list of the recognised shapes.
    case shapes
}

/// A picture, an `ImageMediaObject` of `richText.mediaObjects`.
enum NotabilityPictureKey: String, NotabilityKey {
    case identifier = "UUID"
    case assetsIdentifier = "assetsIdKey"
    case captionText = "captionFieldText"
    case captionFontColor
    case captionFontColorCrossPlatform
    case captionFontName
    case captionFontSize
    case isCaptionUnderlined = "captionIsUnderlined"
    case cornerMode
    case documentContentOrigin
    case documentOrigin
    case figure
    case handwritingZIndices = "handwritingZIndecesKey"
    case isIndexable = "indexable"
    case isCaptionEnabled
    case isFlippedHorizontal
    case isFlippedVertical
    case isLocked = "locked"
    case maximumDimension = "maxDimension"
    case minimumDimension = "minDimension"
    case rotationDegrees
    case textWrapMode
    case unscaledContentSize
    case zIndex
}

/// A text run's `subRangeOtherAttributesKey`.
enum NotabilityTextAttributeKey: String, NotabilityKey {
    case strikethrough = "NSStrikethrough"
    case underline = "NSUnderline"
    case lineSpacing = "line-spacing"
    case baselineOffset = "NSBaselineOffset"
    case isChecklistChecked = "checklist-checked"
}

/// A recognised shape of the ink's `shapes` list.
enum NotabilityShapeKey: String, NotabilityKey {
    case appearance
    case startPoint = "startPt"
    case endPoint = "endPt"
    case controlPoint = "controlPoint1"
    case rectangle = "rect"
    case identifier = "uuid"
    case options
}

/// An entry of `richText.pageLayoutArray`.
enum NotabilityPageLayoutKey: String, NotabilityKey {
    case pdfIsOriginalPage = "kPageLayoutPDFIsOriginalPageKey"
    case pdfPageNumber = "kPageLayoutPDFPageNumberKey"
    case isBookmarked = "kPageLayoutPageIsBookmarkedKey"
    case pdfFileName = "kPageLayoutPDFFileNameKey"
    case documentPageNumber = "kPageLayoutDocumentPageNumberKey"
    case pdfFile = "kPageLayoutPDFFileKey"
}
