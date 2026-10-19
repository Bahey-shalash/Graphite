import Foundation

/// The keys of each part of a note that the format description accounts for; any other key is reported as
/// `NotabilityReadingIssue.unknownKey`. They are the reference reader's lists, without its `$cls` (an archived
/// object's `$class` is never one of its keys here).
enum NotabilityKnownKeys {
    static let session: Set<String> = [
        "name", "packagePath", "subject", "tags", "creationDate", "isReadOnly", "sessionFormatVersion",
        "richText", "contentPlaybackEventManager", "NBNoteTakingSessionDocumentPaperLayoutModelKey",
        "NBNoteTakingSessionIsHighlighterBehindTextKey", "NBNoteTakingSessionHandwritingLanguageKey",
        "NBNoteTakingSessionMinorVersionNumberKey", "NBNoteTakingSessionLastUsedFontKey",
        "kNBNoteTakingSessionNoteLinkStoreKey", "NBPaperMinorVersionNumber", "NBPaperMajorVersionNumber",
        "NBNoteTakingSessionAllowHighlighterConversionKey", "NBNoteTakingSessionBundleVersionNumberKey",
    ]
    static let richText: Set<String> = [
        "formatVersion", "formattedStringTextAlignmentKey", "attributedString", "NBAttributedBackingString",
        "Handwriting Overlay", "reflowState", "didBecomeReflowable", "pdfFiles", "mediaObjects",
        "recordingTimestampString", "pageLayoutArray",
    ]
    static let picture: Set<String> = [
        "UUID", "assetsIdKey", "captionFieldText", "captionFontColor", "captionFontColorCrossPlatform",
        "captionFontName", "captionFontSize", "captionIsUnderlined", "cornerMode", "documentContentOrigin",
        "documentOrigin", "figure", "handwritingZIndecesKey", "indexable", "isCaptionEnabled", "isFlippedHorizontal",
        "isFlippedVertical", "locked", "maxDimension", "minDimension", "rotationDegrees", "textWrapMode",
        "unscaledContentSize", "zIndex",
    ]
    static let textAttributes: Set<String> = ["NSStrikethrough", "NSUnderline", "line-spacing", "NSBaselineOffset", "checklist-checked"]
    static let shape: Set<String> = ["appearance", "startPt", "endPt", "controlPoint1", "rect", "uuid", "options"]
    static let pageLayout: Set<String> = [
        "kPageLayoutPDFIsOriginalPageKey", "kPageLayoutPDFPageNumberKey", "kPageLayoutPageIsBookmarkedKey",
        "kPageLayoutPDFFileNameKey", "kPageLayoutDocumentPageNumberKey", "kPageLayoutPDFFileKey",
    ]
    static let ink: Set<String> = [
        "numcurves", "numpoints", "numfractionalwidths", "curvesnumpoints", "curvespoints", "curveswidth",
        "curvescolors", "curvesstyles", "curveUUIDs", "options", "curvesfractionalwidths", "curvesforces",
        "curvesaltitudeangles", "curvesazimuthunitvector", "groupsArrays", "bezierPathsDataDictionary", "shapes",
    ]
}
