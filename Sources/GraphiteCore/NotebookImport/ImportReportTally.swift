import Foundation

/// Gathers a page's report while it is planned: counted kinds (strokes of an ink, elements of a kind) become one
/// entry each with their count, and every other entry is kept once, in first-reported order.
struct ImportReportTally {
    enum CountedKind: Hashable {
        case highlighter, pencil, tape, olderVaryingWidthInk, dashes, pictureMovedUnderInk, animatedPicture, pictureFileMissing, shapeAsInk
        case element(ImportElementKind)
    }

    private var counts: [CountedKind: Int] = [:]
    private var countedOrder: [CountedKind] = []
    private var entries: [ImportReportEntry] = []

    mutating func count(_ kind: CountedKind) {
        if counts[kind] == nil { countedOrder.append(kind) }
        counts[kind, default: 0] += 1
    }

    mutating func add(_ entry: ImportReportEntry) {
        if !entries.contains(entry) { entries.append(entry) }
    }

    var report: [ImportReportEntry] {
        entries + countedOrder.map { kind in Self.entry(for: kind, count: counts[kind] ?? 0) }
    }

    private static func entry(for kind: CountedKind, count: Int) -> ImportReportEntry {
        switch kind {
        case .highlighter: .highlighterNotMultiplied(strokeCount: count)
        case .pencil: .pencilTextureNotKept(strokeCount: count)
        case .tape: .tapeLeftOut(strokeCount: count)
        case .olderVaryingWidthInk: .olderVaryingWidthInkLeftOut(strokeCount: count)
        case .dashes: .dashesNotKept(strokeCount: count)
        case .pictureMovedUnderInk: .picturesMovedUnderInk(count: count)
        case .animatedPicture: .animatedPicturesKeptStill(count: count)
        case .pictureFileMissing: .pictureFilesMissing(count: count)
        case .shapeAsInk: .shapesDrawnAsInk(count: count)
        case .element(let elementKind): .elementsNotYetConverted(kind: elementKind, count: count)
        }
    }
}
