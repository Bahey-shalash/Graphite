import Foundation

/// Something an import simplified or left out on a page: a typed fact, worded by the import report's presenter.
public enum ImportReportEntry: Sendable, Hashable {
    /// Highlighter strokes that Goodnotes multiplies over other ink; Graphite draws them normally, so colours under
    /// them look lighter.
    case highlighterNotMultiplied(strokeCount: Int)
    /// Pencil strokes, whose texture Goodnotes draws and PencilKit's pencil does not reproduce.
    case pencilTextureNotKept(strokeCount: Int)
    /// Tape, which Graphite does not have.
    case tapeLeftOut(strokeCount: Int)
    /// Goodnotes' older varying-width ink, whose center line is not decoded.
    case olderVaryingWidthInkLeftOut(strokeCount: Int)
    /// Shapes (lines, arcs, rectangles, ellipses) drawn as ink strokes along their outline: Graphite has no editable
    /// shapes yet.
    case shapesDrawnAsInk(count: Int)
    /// Dashed strokes, drawn solid: PencilKit has no dashed ink.
    case dashesNotKept(strokeCount: Int)
    /// Elements whose kind a later import step converts (shapes, fills, pictures, text, sticky notes).
    case elementsNotYetConverted(kind: ImportElementKind, count: Int)
    /// Pictures the source draws over some of its ink; Graphite draws a page's pictures under all its ink.
    case picturesMovedUnderInk(count: Int)
    /// Animated pictures (GIFs), kept as their first frame in the PDF.
    case animatedPicturesKeptStill(count: Int)
    /// Pictures whose image file is not in the notebook; they are left out.
    case pictureFilesMissing(count: Int)
    /// Pictures whose file is not an image that can be decoded, such as a damaged one; they are left out.
    case picturesNotDecodable(count: Int)
    /// Recordings whose audio file the notebook does not name; they are left out.
    case recordingFilesMissing(count: Int)
    /// Recordings the notebook has that could not be copied into the vault (a file that is not MPEG-4 audio, a damaged
    /// one, a full disk); they are left out.
    case recordingsNotCopied(count: Int)
    /// Ink and other elements timed against a recording: the recording is kept, the timing is not (owner decision,
    /// 2026-10-20).
    case recordingTimingNotKept(timedElementCount: Int)
    /// Outline entries whose page is not in the imported notebook, such as a deleted page or one left out; they are
    /// left out.
    case outlineEntriesWithoutPage(count: Int)
    /// A paper ruling the import does not describe, drawn as plain paper.
    case paperRulingNotDrawn
    /// The page has no paper record, so its size and background are not known; it is left out.
    case pageWithoutPaper
    /// The paper names a PDF attachment that is not in the notebook; the page is plain white paper.
    case backgroundFileMissing
    /// A Notability note whose page size is not known (a reflowable note, or a paper size not described); its pages
    /// are left out.
    case pageGeometryUnknown
    /// The reader listed something it does not know or skipped on this page.
    case goodnotesReadingIssue(GoodnotesReadingIssue)
    case notabilityReadingIssue(NotabilityReadingIssue)
}

public enum ImportElementKind: Sendable, Hashable {
    case shape, shapeFill, picture, textBox, stickyNote, typedText
    /// A Goodnotes element of a kind the reader does not know.
    case unknownKind
    /// A Goodnotes stroke whose path layout the reader does not know.
    case strokeInUnknownLayout
}
