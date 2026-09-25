import Foundation
import GraphiteCore

/// A change to a note's characters as `NSTextStorage` reports it once the change is
/// processed: `editedRange` holds the new text, in the text after the change.
struct CharacterEdit: Equatable {
    var editedRange: NSRange
    var changeInLength: Int

    /// The range the edit replaced, in the text before it.
    var replacedRange: NSRange {
        NSRange(location: editedRange.location, length: max(0, editedRange.length - changeInLength))
    }

    /// One edit covering this edit and a later one. Text outside the combined edited range
    /// is the same as the text outside its replaced range before both edits.
    func followed(by laterEdit: CharacterEdit) -> CharacterEdit {
        let movedRange = TextRangeMapping.coveringRange(editedRange, through: laterEdit)
        return CharacterEdit(editedRange: NSUnionRange(movedRange, laterEdit.editedRange), changeInLength: changeInLength + laterEdit.changeInLength)
    }
}

/// Where ranges computed for earlier text lie after an edit.
enum TextRangeMapping {
    /// For ranges whose styling must follow the text, such as rendered blocks and revealed
    /// lines: unchanged before the edit, shifted after it, and widened to cover the new text
    /// when the edit touches them, so restyling the range also restyles what changed.
    static func coveringRange(_ range: NSRange, through edit: CharacterEdit) -> NSRange {
        let replacedRange = edit.replacedRange
        if NSMaxRange(range) <= replacedRange.location { return range }
        if range.location >= NSMaxRange(replacedRange) { return range.shifted(by: edit.changeInLength) }
        let location = min(range.location, edit.editedRange.location)
        let end = max(NSMaxRange(range) + edit.changeInLength, NSMaxRange(edit.editedRange))
        return NSRange(location: location, length: end - location)
    }

    /// For where something asked for earlier should still be inserted, such as a pasted
    /// image that finished saving. Text typed at the same place stays after it, as if the
    /// insertion had been immediate; a selection the edit changed collapses to after the
    /// new text, so a second dropped item lands after the first instead of inside it.
    static func insertionTarget(_ range: NSRange, through edit: CharacterEdit) -> NSRange {
        let replacedRange = edit.replacedRange
        let isTypingAtSameLocation = range.length == 0 && replacedRange.length == 0 && replacedRange.location == range.location
        if NSMaxRange(replacedRange) <= range.location && !isTypingAtSameLocation { return range.shifted(by: edit.changeInLength) }
        if NSMaxRange(range) <= replacedRange.location { return range }
        return NSRange(location: NSMaxRange(edit.editedRange), length: 0)
    }

    /// For a range an edit was computed to replace, such as a completion's query: nil when
    /// the later edit changed text inside it, because replacing it now would overwrite what
    /// was typed there.
    static func replacedRange(_ range: NSRange, through edit: CharacterEdit) -> NSRange? {
        let replacedRange = edit.replacedRange
        if NSMaxRange(range) <= replacedRange.location { return range }
        if NSMaxRange(replacedRange) <= range.location { return range.shifted(by: edit.changeInLength) }
        return nil
    }
}

/// The note's recent character edits, numbered, so a range captured before asynchronous
/// work (saving an attachment, finding a completion's edits) can be moved past the edits
/// made while that work ran.
struct CharacterEditHistory {
    /// Increases with every character edit.
    private(set) var revision = 0
    private var recentEdits: [CharacterEdit] = []
    /// Edits kept for mapping; a range older than this many edits is no longer mapped.
    static let rememberedEditCount = 512

    mutating func record(_ edit: CharacterEdit) {
        revision += 1
        recentEdits.append(edit)
        // Trimmed in batches, so recording stays constant time on average.
        if recentEdits.count > 2 * Self.rememberedEditCount { recentEdits.removeFirst(recentEdits.count - Self.rememberedEditCount) }
    }

    /// The edits made after `earlierRevision`, oldest first; nil when some are forgotten.
    private func edits(since earlierRevision: Int) -> ArraySlice<CharacterEdit>? {
        let editCount = revision - earlierRevision
        guard editCount >= 0, editCount <= recentEdits.count else { return nil }
        return recentEdits.suffix(editCount)
    }

    /// Where an insertion requested at `earlierRevision` goes now; nil when it cannot be told.
    func insertionTarget(_ range: NSRange, requestedAt earlierRevision: Int) -> NSRange? {
        edits(since: earlierRevision)?.reduce(range) { movedRange, edit in TextRangeMapping.insertionTarget(movedRange, through: edit) }
    }

    /// Where a range to replace, computed at `earlierRevision`, is now; nil when later edits
    /// changed text inside it or when it cannot be told.
    func replacedRange(_ range: NSRange, computedAt earlierRevision: Int) -> NSRange? {
        guard let laterEdits = edits(since: earlierRevision) else { return nil }
        var movedRange = range
        for edit in laterEdits {
            guard let nextRange = TextRangeMapping.replacedRange(movedRange, through: edit) else { return nil }
            movedRange = nextRange
        }
        return movedRange
    }
}

/// Where pasted or dropped content should go: the range chosen when it arrived, and the
/// text revision of that moment.
struct InsertionRequest: Equatable {
    let range: NSRange
    let revision: Int
}

/// Pastes and drops whose content is still loading or saving, oldest first. The pane
/// prepares each insertion for the range it was given; the insertion goes where its
/// request points now, and the other items of the same paste or drop follow it in order.
struct PendingInsertionRequests {
    struct PendingRequest {
        /// The range and revision the paste or drop asked for; the prepared insertion
        /// carries this range.
        let requested: InsertionRequest
        /// Where the item goes, measured at the revision it holds.
        fileprivate(set) var target: InsertionRequest

        /// Where the item goes in the text now; nil when it cannot be told.
        func currentTarget(in history: CharacterEditHistory) -> NSRange? {
            history.insertionTarget(target.range, requestedAt: target.revision)
        }
    }

    private var requests: [PendingRequest] = []
    /// A save that failed never inserts; its request is dropped with the oldest ones.
    static let maximumCount = 32

    var count: Int { requests.count }

    mutating func remember(_ request: InsertionRequest) {
        requests.append(PendingRequest(requested: request, target: request))
        if requests.count > Self.maximumCount { requests.removeFirst() }
    }

    /// Takes out the oldest request an insertion prepared for `preparedRange` answers.
    /// The pane can move a range past the note's changes itself before it inserts
    /// (`WorkspaceModel.insertionRange`); given `history`, a request whose place now is
    /// `preparedRange` answers too, so it does not wait on to capture a later insertion.
    mutating func take(preparedFor preparedRange: NSRange, in history: CharacterEditHistory? = nil) -> PendingRequest? {
        let requestIndex = requests.firstIndex { pendingRequest in pendingRequest.requested.range == preparedRange }
            ?? history.flatMap { history in requests.firstIndex { pendingRequest in pendingRequest.currentTarget(in: history) == preparedRange } }
        guard let requestIndex else { return nil }
        return requests.remove(at: requestIndex)
    }

    /// Places the items still waiting from the same paste or drop as `insertedRequest`
    /// right after its inserted text, which ends at `insertedEnd` at `revision`. Without
    /// this, an item dropped at a point would go before the one inserted there first.
    mutating func placeRemainingItems(of insertedRequest: PendingRequest, after insertedEnd: Int, at revision: Int) {
        for requestIndex in requests.indices where requests[requestIndex].requested == insertedRequest.requested {
            requests[requestIndex].target = InsertionRequest(range: NSRange(location: insertedEnd, length: 0), revision: revision)
        }
    }
}

/// A block insertion, such as an embed, prepared for one place and made at another
/// because the note changed while its content loaded or saved.
enum MovedBlockInsertion {
    /// The text and range for putting `preparedText`'s block at `movedRange` of `source`,
    /// with the line breaks that place needs. As when it was prepared, the frontmatter is
    /// never split.
    static func insertion(of preparedText: String, movedTo movedRange: NSRange, in source: NSString) -> (text: String, range: NSRange) {
        let location = max(min(movedRange.location, source.length), FrontmatterLocator.length(in: source))
        let endLocation = max(min(NSMaxRange(movedRange), source.length), location)
        let range = NSRange(location: location, length: endLocation - location)
        let block = preparedText.trimmingCharacters(in: .newlines)
        return (MarkdownBlockInsertion.text(inserting: block, into: source, replacing: range), range)
    }
}

/// Identifies a rendered block across edits elsewhere in the note: its kind, its source,
/// and which occurrence of that source it is. The hash is computed once, because layout
/// passes and scrolling look keys up for every block, and a block's source can be long.
struct LivePreviewBlockKey: Hashable {
    private let identity: String
    private let precomputedHash: Int

    private init(identity: String) {
        self.identity = identity
        precomputedHash = identity.hashValue
    }

    static func == (leftKey: LivePreviewBlockKey, rightKey: LivePreviewBlockKey) -> Bool {
        leftKey.precomputedHash == rightKey.precomputedHash && leftKey.identity == rightKey.identity
    }

    func hash(into hasher: inout Hasher) { hasher.combine(precomputedHash) }

    /// Keys for blocks in note order.
    static func keys(for blocks: [LivePreviewBlock]) -> [LivePreviewBlockKey] {
        var occurrences: [String: Int] = [:]
        return blocks.map { block in
            let baseIdentity = kindName(of: block.kind) + "|" + block.markdown
            let occurrence = occurrences[baseIdentity, default: 0]
            occurrences[baseIdentity] = occurrence + 1
            return LivePreviewBlockKey(identity: baseIdentity + "|" + String(occurrence))
        }
    }

    /// A name per kind. An embed's and a base's details are in the block's source already.
    private static func kindName(of kind: LivePreviewBlock.Kind) -> String {
        switch kind {
        case .frontmatter: "frontmatter"
        case .table: "table"
        case .mathBlock: "math"
        case .embed: "embed"
        case .baseDefinition: "base"
        case .horizontalRule: "rule"
        case .callout: "callout"
        }
    }
}

/// A rendered block where it is now. `block.range` is where the scanner found it: edits
/// that cannot change the note's blocks move `range` instead of scanning the note again.
struct LivePreviewBlockEntry {
    let block: LivePreviewBlock
    var range: NSRange
    let key: LivePreviewBlockKey
}

/// What Live Preview must restyle once an edit is settled.
enum LivePreviewRestylePlan: Equatable {
    /// The edit may change how every later line is styled, such as an opened code fence.
    case everything
    /// Line ranges to restyle, each extended to the rendered blocks it touches.
    case ranges([NSRange])
}

/// Live Preview's knowledge of the text it styled, kept in step with every character edit
/// whichever path made it: typing, undo and redo, find and replace, insertions by Graphite,
/// or a new text. UIKit reports selection changes against the new text before it reports
/// the text change itself, so everything here says whether it still describes older text.
@MainActor
final class LivePreviewTextState {
    /// The text the blocks were found in, as an immutable snapshot.
    private(set) var source: NSString = ""
    private(set) var blockEntries: [LivePreviewBlockEntry] = []
    /// Set from a character edit until the blocks are found again for the new text.
    private(set) var cachesDescribeOldText = false
    private(set) var history = CharacterEditHistory()
    /// Edits the styling has not caught up with, from the last restyle on.
    private var unstyledEdit: UnstyledEdit?
    /// Edits since the blocks were last found, and the text they were found in.
    private var editSinceBlockScan: (edit: CharacterEdit, sourceBeforeEdit: NSString)?
    /// Whether `blockEntries` came from a scan, so they can be moved instead of found again.
    private var hasFoundBlocks = false

    /// Whether an edit is waiting to be restyled.
    var hasUnstyledEdit: Bool { unstyledEdit != nil }

    /// Records a character edit reported by the text storage. `revealedRange` is the range
    /// the current styling shows as source. Returns true for the first edit since the
    /// caches last described the text.
    @discardableResult
    func recordCharacterEdit(_ edit: CharacterEdit, revealedRange: NSRange?) -> Bool {
        history.record(edit)
        if var pendingEdit = unstyledEdit {
            pendingEdit.record(edit)
            unstyledEdit = pendingEdit
        } else {
            unstyledEdit = UnstyledEdit(edit: edit, sourceBeforeEdit: source, revealedRange: revealedRange,
                                        blockRanges: blockEntries.map(\.range))
        }
        if let previousEdit = editSinceBlockScan {
            editSinceBlockScan = (previousEdit.edit.followed(by: edit), previousEdit.sourceBeforeEdit)
        } else {
            editSinceBlockScan = (edit, source)
        }
        let isFirstEdit = !cachesDescribeOldText
        cachesDescribeOldText = true
        return isFirstEdit
    }

    /// Takes in the current text. Blocks move with an edit that cannot change them, and
    /// are found again otherwise. `findsBlocks` is false outside Live Preview;
    /// `forcesBlockScan` is for a change in which blocks are rendered.
    func update(source newSource: NSString, findsBlocks: Bool, forcesBlockScan: Bool = false, isRendered: (LivePreviewBlock) -> Bool) {
        defer {
            source = newSource
            cachesDescribeOldText = false
            editSinceBlockScan = nil
            hasFoundBlocks = findsBlocks
        }
        guard findsBlocks else {
            blockEntries = []
            return
        }
        if hasFoundBlocks, !forcesBlockScan, let editSinceBlockScan,
           let movedEntries = LivePreviewBlockShifting.entries(blockEntries, across: editSinceBlockScan.edit,
                                                               sourceBeforeEdit: editSinceBlockScan.sourceBeforeEdit, source: newSource) {
            blockEntries = movedEntries
            return
        }
        let blocks = LivePreviewBlockScanner.blocks(in: newSource).filter(isRendered)
        blockEntries = zip(blocks, LivePreviewBlockKey.keys(for: blocks)).map { block, key in
            LivePreviewBlockEntry(block: block, range: block.range, key: key)
        }
    }

    /// Consumes the waiting edit and says what to restyle for it, given the lines revealed now.
    func takeRestylePlan(revealedRange: NSRange?) -> LivePreviewRestylePlan? {
        guard let pendingEdit = unstyledEdit, !cachesDescribeOldText else { return nil }
        unstyledEdit = nil
        return pendingEdit.restylePlan(source: source, revealedRange: revealedRange, blockRanges: blockEntries.map(\.range))
    }

    /// Forgets the waiting edit after the whole note was restyled.
    func discardUnstyledEdit() {
        unstyledEdit = nil
    }
}

/// Character edits the styling has not caught up with yet, and what the styled text
/// looked like before them.
struct UnstyledEdit {
    private(set) var combinedEdit: CharacterEdit
    /// The text the current styling was made for.
    let sourceBeforeEdit: NSString
    /// The lines whose markup showed, moved through the edits.
    private(set) var revealedRangeBeforeEdit: NSRange?
    /// The rendered blocks' ranges before the edits, moved through them.
    private(set) var blockRangesBeforeEdit: [NSRange]

    init(edit: CharacterEdit, sourceBeforeEdit: NSString, revealedRange: NSRange?, blockRanges: [NSRange]) {
        combinedEdit = edit
        self.sourceBeforeEdit = sourceBeforeEdit
        revealedRangeBeforeEdit = revealedRange.map { range in TextRangeMapping.coveringRange(range, through: edit) }
        blockRangesBeforeEdit = blockRanges.map { range in TextRangeMapping.coveringRange(range, through: edit) }
    }

    mutating func record(_ edit: CharacterEdit) {
        combinedEdit = combinedEdit.followed(by: edit)
        revealedRangeBeforeEdit = revealedRangeBeforeEdit.map { range in TextRangeMapping.coveringRange(range, through: edit) }
        blockRangesBeforeEdit = blockRangesBeforeEdit.map { range in TextRangeMapping.coveringRange(range, through: edit) }
    }

    /// What to restyle in `source`, the text after the edits. The edited lines, the lines
    /// revealed before and now, and every block before or after the edit that touches
    /// them: a block can grow over the edited line (a callout taking in a new `>` line) or
    /// stop covering lines it concealed.
    func restylePlan(source: NSString, revealedRange: NSRange?, blockRanges: [NSRange]) -> LivePreviewRestylePlan {
        let replacedRange = combinedEdit.replacedRange
        guard sourceBeforeEdit.length + combinedEdit.changeInLength == source.length,
              NSMaxRange(combinedEdit.editedRange) <= source.length, NSMaxRange(replacedRange) <= sourceBeforeEdit.length else { return .everything }
        let replacedLines = sourceBeforeEdit.lineRange(for: replacedRange)
        let editedLines = source.lineRange(for: combinedEdit.editedRange)
        if Self.containsLineAffectingFollowingLines(sourceBeforeEdit, in: replacedLines) || Self.containsLineAffectingFollowingLines(source, in: editedLines) {
            return .everything
        }
        let candidateBlocks = blockRangesBeforeEdit + blockRanges
        // `---` right after a blank line is a rule, and after text it underlines a heading,
        // so the block right after the edited lines can appear or disappear too.
        var editedRange = editedLines
        for blockRange in candidateBlocks where blockRange.location == NSMaxRange(editedLines) {
            editedRange = NSUnionRange(editedRange, blockRange)
        }
        var ranges = [Self.extended(editedRange, toBlocks: candidateBlocks)]
        // The styler also shows markup that starts right after the revealed lines, so when
        // the edit moved them, as an undo far from the cursor does, the line after each
        // starts or stops showing too.
        let didMoveRevealedLines = revealedRangeBeforeEdit != revealedRange
        for revealed in [revealedRangeBeforeEdit, revealedRange].compactMap({ range in range }) {
            let restyledRange = didMoveRevealedLines ? RevealedLinesChange.includingFollowingLine(revealed, in: source) : revealed
            let extendedRange = Self.extended(restyledRange, toBlocks: candidateBlocks)
            if !ranges.contains(where: { range in NSIntersectionRange(range, extendedRange) == extendedRange }) { ranges.append(extendedRange) }
        }
        let documentRange = NSRange(location: 0, length: source.length)
        return .ranges(ranges.map { range in NSIntersectionRange(range, documentRange) })
    }

    /// `range` grown to every block it touches, and to the blocks those touch in turn.
    private static func extended(_ range: NSRange, toBlocks blockRanges: [NSRange]) -> NSRange {
        var extendedRange = range
        var didGrow = true
        while didGrow {
            didGrow = false
            for blockRange in blockRanges where touches(blockRange, extendedRange) && NSUnionRange(blockRange, extendedRange) != extendedRange {
                extendedRange = NSUnionRange(extendedRange, blockRange)
                didGrow = true
            }
        }
        return extendedRange
    }

    private static func touches(_ firstRange: NSRange, _ secondRange: NSRange) -> Bool {
        NSIntersectionRange(firstRange, secondRange).length > 0 || NSLocationInRange(firstRange.location, secondRange) || NSLocationInRange(secondRange.location, firstRange)
    }

    /// Whether a line in `lineRange` opens or closes code, math, or frontmatter, which
    /// changes how every later line is styled. A math block closes at a line ending in
    /// `$$`, and frontmatter also closes at `...`; the style scanner's own check only
    /// looks at how a line starts.
    static func containsLineAffectingFollowingLines(_ text: NSString, in lineRange: NSRange) -> Bool {
        var lineStart = lineRange.location
        while lineStart < NSMaxRange(lineRange) {
            let currentLine = text.lineRange(for: NSRange(location: lineStart, length: 0))
            let line = text.substring(with: currentLine)
            if MarkdownStyleScanner.lineAffectsFollowingLines(line) || line.contains("$$") || line.trimmingCharacters(in: .whitespacesAndNewlines) == "..." {
                return true
            }
            lineStart = NSMaxRange(currentLine)
        }
        return false
    }
}

/// Moves rendered blocks past an edit that cannot change them, so typing an ordinary
/// paragraph does not scan the whole note for blocks again.
enum LivePreviewBlockShifting {
    /// First characters, after indentation, of lines that can start, end, or join a block:
    /// fences, `$$`, quotes and callouts, table rows and delimiter rows, embeds, rules, and
    /// frontmatter's `---` and `...`.
    private static let blockSyntaxStarts = CharacterSet(charactersIn: "`~$>|!-*_:.")

    /// The entries moved past `edit`, or nil when the note must be scanned again. That is
    /// when the edit adds or removes a line break, when the edited line is inside a block,
    /// when the line starts or started with block syntax, or when it is or was blank
    /// (a blank line before `---` makes it a rule).
    static func entries(_ entries: [LivePreviewBlockEntry], across edit: CharacterEdit, sourceBeforeEdit: NSString, source: NSString) -> [LivePreviewBlockEntry]? {
        let replacedRange = edit.replacedRange
        guard sourceBeforeEdit.length + edit.changeInLength == source.length,
              NSMaxRange(replacedRange) <= sourceBeforeEdit.length, NSMaxRange(edit.editedRange) <= source.length,
              !containsLineBreak(sourceBeforeEdit, in: replacedRange), !containsLineBreak(source, in: edit.editedRange) else { return nil }
        let lineBeforeEdit = sourceBeforeEdit.lineRange(for: replacedRange)
        guard !entries.contains(where: { entry in NSIntersectionRange(entry.range, lineBeforeEdit).length > 0 }),
              isOrdinaryLine(sourceBeforeEdit, lineRange: lineBeforeEdit),
              isOrdinaryLine(source, lineRange: source.lineRange(for: edit.editedRange)) else { return nil }
        return entries.map { entry in
            guard entry.range.location >= NSMaxRange(lineBeforeEdit) else { return entry }
            var movedEntry = entry
            movedEntry.range = entry.range.shifted(by: edit.changeInLength)
            return movedEntry
        }
    }

    private static func containsLineBreak(_ text: NSString, in range: NSRange) -> Bool {
        text.rangeOfCharacter(from: .newlines, options: [], range: range).location != NSNotFound
    }

    /// A line that is not blank and does not start with block syntax.
    private static func isOrdinaryLine(_ text: NSString, lineRange: NSRange) -> Bool {
        let firstCharacter = text.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted, options: [], range: lineRange)
        guard firstCharacter.location != NSNotFound else { return false }
        return text.rangeOfCharacter(from: blockSyntaxStarts, options: .anchored, range: NSRange(location: firstCharacter.location, length: NSMaxRange(lineRange) - firstCharacter.location)).location == NSNotFound
    }
}

/// What to restyle when the lines whose markup shows move with the cursor.
enum RevealedLinesChange {
    /// The pieces of `source` whose markup starts or stops showing when the revealed lines
    /// move from `previousRange` to `newRange`. Lines revealed both times, and the lines
    /// between two far-apart ranges, keep their styling, so a far jump restyles two lines
    /// rather than everything between them. The styler also shows markup that starts right
    /// after the revealed lines, so the line after each changed end is included.
    static func restyledRanges(from previousRange: NSRange?, to newRange: NSRange?, in source: NSString) -> [NSRange] {
        var pieces: [NSRange] = []
        if let previousRange, let newRange, NSIntersectionRange(previousRange, newRange).length > 0 {
            // A selection that grows or shrinks changes only its ends.
            let starts = [previousRange.location, newRange.location]
            if let firstStart = starts.min(), let lastStart = starts.max(), firstStart != lastStart {
                pieces.append(NSRange(location: firstStart, length: lastStart - firstStart))
            }
            let ends = [NSMaxRange(previousRange), NSMaxRange(newRange)]
            if let firstEnd = ends.min(), let lastEnd = ends.max(), firstEnd != lastEnd {
                pieces.append(includingFollowingLine(NSRange(location: firstEnd, length: lastEnd - firstEnd), in: source))
            }
        } else {
            pieces = [previousRange, newRange].compactMap { range in range }.map { range in includingFollowingLine(range, in: source) }
        }
        return merged(pieces)
    }

    static func includingFollowingLine(_ range: NSRange, in source: NSString) -> NSRange {
        let end = NSMaxRange(range)
        guard end < source.length else { return range }
        return NSUnionRange(range, source.lineRange(for: NSRange(location: end, length: 0)))
    }

    /// The ranges in text order, with overlapping or adjacent ones joined.
    private static func merged(_ ranges: [NSRange]) -> [NSRange] {
        var mergedRanges: [NSRange] = []
        for range in ranges.sorted(by: { leftRange, rightRange in leftRange.location < rightRange.location }) {
            if let last = mergedRanges.last, range.location <= NSMaxRange(last) {
                mergedRanges[mergedRanges.count - 1] = NSUnionRange(last, range)
            } else {
                mergedRanges.append(range)
            }
        }
        return mergedRanges
    }
}

/// Finds a rendered block by position in blocks kept in note order.
enum LivePreviewBlockLookup {
    /// The index of the element whose range contains `location`, in `sortedElements`, which
    /// are in order and do not overlap, as the block scanner finds blocks. A binary search,
    /// because layout passes ask this for every line on screen.
    static func index<Element>(ofElementContaining location: Int, in sortedElements: [Element], range: (Element) -> NSRange) -> Int? {
        var lowerBound = 0
        var upperBound = sortedElements.count
        // The first element that starts after `location`.
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if range(sortedElements[middle]).location <= location { lowerBound = middle + 1 } else { upperBound = middle }
        }
        guard lowerBound > 0, NSLocationInRange(location, range(sortedElements[lowerBound - 1])) else { return nil }
        return lowerBound - 1
    }
}

/// Which rendered block the cursor is in, so its source shows instead of its view.
enum LivePreviewBlockActivity {
    /// Whether `selection` is in the block at `blockRange` of `source`. A cursor right after
    /// a block counts as inside it when the block does not end with a line break, as at
    /// the end of the note. Any line break counts, `\r\n` included.
    static func isActive(blockRange: NSRange, selection: NSRange, in source: NSString) -> Bool {
        let blockEnd = NSMaxRange(blockRange)
        guard blockEnd <= source.length else { return false }
        let selectionEnd = NSMaxRange(selection)
        if selection.location >= blockRange.location && selection.location < blockEnd { return true }
        if selectionEnd > blockRange.location && selectionEnd < blockEnd { return true }
        guard selection.location == blockEnd else { return false }
        let endsWithLineBreak = blockEnd > 0 && Unicode.Scalar(source.character(at: blockEnd - 1)).map { scalar in CharacterSet.newlines.contains(scalar) } == true
        return !endsWithLineBreak
    }
}

/// What a tap in Live Preview acts on. Checkboxes and links count only where the styler
/// draws them, so a tap on text that merely looks like one, such as a task in a code
/// sample, places the cursor instead of changing the note or leaving it.
enum LivePreviewTapTargets {
    private static let drawnCheckboxTexts: Set<String> = ["[ ]", "[x]", "[X]"]

    /// The `[ ]` or `[x]` of a drawn checkbox at `characterIndex`, quoted tasks included.
    static func taskCheckboxRange(at characterIndex: Int, in source: NSString) -> NSRange? {
        guard characterIndex <= source.length else { return nil }
        let lineRange = source.lineRange(for: NSRange(location: characterIndex, length: 0))
        // A quick look first: the style scan starts from the top of the note.
        let line = source.substring(with: lineRange)
        guard drawnCheckboxTexts.contains(where: { checkboxText in line.contains(checkboxText) }) else { return nil }
        let marker = MarkdownStyleScanner.spans(in: source, range: lineRange).first { span in
            span.style == .taskMarker && drawnCheckboxTexts.contains(source.substring(with: span.range))
        }
        guard let marker, characterIndex >= marker.range.location, characterIndex <= NSMaxRange(marker.range) else { return nil }
        return marker.range
    }

    /// Whether `characterIndex`, or the character before it, is in code, math, or
    /// frontmatter, where links are text. The character before counts for a cursor
    /// right after a link.
    static func isInsideCode(_ characterIndex: Int, in source: NSString) -> Bool {
        guard source.length > 0 else { return false }
        let location = min(characterIndex, source.length)
        let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
        let codeStyles: Set<MarkdownStyle> = [.inlineCode, .codeBlock, .math, .frontmatter]
        let checkedLocations = [location, location - 1].filter { checkedLocation in checkedLocation >= lineRange.location }
        return MarkdownStyleScanner.spans(in: source, range: lineRange).contains { span in
            codeStyles.contains(span.style) && checkedLocations.contains { checkedLocation in NSLocationInRange(checkedLocation, span.range) }
        }
    }
}

/// Finds headings the way the outline lists them.
enum HeadingLocator {
    /// Where the line of the `occurrence`th heading (from zero) with `anchor` starts. The
    /// outline lists body headings outside code, so frontmatter and code are skipped: a
    /// YAML comment such as `# Summary` is not a heading.
    static func lineLocation(ofHeadingWithAnchor anchor: String, occurrence: Int = 0, in source: NSString) -> Int? {
        var lineStart = FrontmatterLocator.length(in: source)
        var fenceTracker = CodeFenceTracker()
        var remainingOccurrences = occurrence
        while lineStart < source.length {
            let lineRange = source.lineRange(for: NSRange(location: lineStart, length: 0))
            let line = source.substring(with: lineRange)
            let isCodeLine = fenceTracker.isCodeLine(line.trimmingCharacters(in: .whitespacesAndNewlines))
            if !isCodeLine, let heading = NotePreviewDocument.outline(of: line).first, heading.anchor == anchor {
                if remainingOccurrences == 0 { return lineRange.location }
                remainingOccurrences -= 1
            }
            lineStart = NSMaxRange(lineRange)
        }
        return nil
    }
}

/// The smallest change that turns one text into another, for replacing a text in place
/// so the editor's undo history and cursor survive.
enum TextDifference {
    /// The range of `oldText` to replace and the range of `newText` that replaces it, or
    /// nil when the texts are equal. Both ends fall between whole characters, so an emoji
    /// or a `\r\n` is never split.
    static func changedRanges(from oldText: NSString, to newText: NSString) -> (replacedRange: NSRange, replacementRange: NSRange)? {
        guard !oldText.isEqual(newText) else { return nil }
        let sharedLength = min(oldText.length, newText.length)
        var prefixLength = 0
        while prefixLength < sharedLength && oldText.character(at: prefixLength) == newText.character(at: prefixLength) { prefixLength += 1 }
        while prefixLength > 0 && (!isCharacterBoundary(prefixLength, in: oldText) || !isCharacterBoundary(prefixLength, in: newText)) { prefixLength -= 1 }
        var suffixLength = 0
        while suffixLength < sharedLength - prefixLength
                && oldText.character(at: oldText.length - suffixLength - 1) == newText.character(at: newText.length - suffixLength - 1) { suffixLength += 1 }
        while suffixLength > 0 && (!isCharacterBoundary(oldText.length - suffixLength, in: oldText) || !isCharacterBoundary(newText.length - suffixLength, in: newText)) { suffixLength -= 1 }
        return (NSRange(location: prefixLength, length: oldText.length - suffixLength - prefixLength),
                NSRange(location: prefixLength, length: newText.length - suffixLength - prefixLength))
    }

    private static func isCharacterBoundary(_ location: Int, in text: NSString) -> Bool {
        guard location > 0 && location < text.length else { return true }
        return text.rangeOfComposedCharacterSequence(at: location).location == location
    }
}
