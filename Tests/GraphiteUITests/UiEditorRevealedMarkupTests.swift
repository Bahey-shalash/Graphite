import XCTest
import AppKit
@testable import GraphiteCore
@testable import GraphiteUI

/// Which markup Live Preview shows as written around the selection, one element at a time
/// as in Obsidian, and how little a moving cursor restyles. The styler is the one the iPad
/// editor uses, with drawn replacements on.
///
/// In the notes below `¦` is the cursor and `«…»` a selection; neither is part of the text.
@MainActor
final class UiEditorRevealedMarkupTests: XCTestCase {
    private let styler = MarkdownTextStyler(configuration: EditorConfiguration(mode: .livePreview), accentColor: .systemBlue, drawsConcealedReplacements: true)

    // MARK: Helpers

    /// The text without its cursor or selection marks, and the selection they describe.
    private func parse(_ markedNote: String) -> (text: String, selection: NSRange) {
        var text = markedNote as NSString
        let cursor = text.range(of: "¦")
        if cursor.location != NSNotFound {
            return (text.replacingCharacters(in: cursor, with: ""), NSRange(location: cursor.location, length: 0))
        }
        let selectionStart = text.range(of: "«").location
        text = text.replacingCharacters(in: NSRange(location: selectionStart, length: 1), with: "") as NSString
        let selectionEnd = text.range(of: "»").location
        return (text.replacingCharacters(in: NSRange(location: selectionEnd, length: 1), with: ""), NSRange(location: selectionStart, length: selectionEnd - selectionStart))
    }

    private func styledStorage(_ text: String, revealedMarkup: RevealedMarkup?, styler: MarkdownTextStyler? = nil) -> NSTextStorage {
        let textStorage = NSTextStorage(string: text)
        (styler ?? self.styler).applyStyles(to: textStorage, editedRange: NSRange(location: 0, length: 0), restyleEverything: true,
                                            revealedMarkup: revealedMarkup, concealedBlocks: [])
        return textStorage
    }

    /// Whether the characters of `range` are drawn as written: not shrunk to nothing, not
    /// clear, and not standing in for a drawn bullet, checkbox, bar, separator or formula.
    private func isShownAsWritten(_ range: NSRange, in textStorage: NSTextStorage) -> Bool {
        var isShown = true
        textStorage.enumerateAttributes(in: range) { attributes, _, _ in
            if let font = attributes[.font] as? NSFont, font.pointSize < 1 { isShown = false }
            if let color = attributes[.foregroundColor] as? NSColor, color.alphaComponent == 0 { isShown = false }
            if attributes[ConcealedReplacement.attributeKey] != nil { isShown = false }
        }
        return isShown
    }

    private static let markupStyles: Set<MarkdownStyle> = [.concealableMarker, .subpathSeparator, .listMarker, .taskMarker, .math]

    /// The markup shown as written in a styled text: markers, list and task markers,
    /// quote markers and formulas, in the scanner's order.
    private func shownMarkup(in textStorage: NSTextStorage) -> [String] {
        let source = NSString(string: textStorage.string)
        return MarkdownStyleScanner.spans(in: source, range: NSRange(location: 0, length: source.length))
            .filter { span in Self.markupStyles.contains(span.style) || (span.style == .syntaxMarker && source.substring(with: span.range).hasPrefix(">")) }
            .filter { span in isShownAsWritten(span.range, in: textStorage) }
            .map { span in source.substring(with: span.range) }
    }

    /// The markup shown as written when the note is styled for its marked selection.
    private func shownMarkup(_ markedNote: String) -> [String] {
        let (text, selection) = parse(markedNote)
        return shownMarkup(in: styledStorage(text, revealedMarkup: RevealedMarkup(selection: selection, in: text as NSString)))
    }

    /// Attribute runs as comparable values; a formula's layout object is new on every
    /// pass, so only its LaTeX is compared.
    private func attributeRuns(of textStorage: NSTextStorage) -> [String] {
        var runs: [String] = []
        textStorage.enumerateAttributes(in: NSRange(location: 0, length: textStorage.length)) { attributes, range, _ in
            let comparable = attributes.mapValues { value in (value as? InlineMathLayout).map { layout in "math(\(layout.latex))" as NSString } ?? value }
            runs.append("\(range): \(comparable as NSDictionary)")
        }
        return runs
    }

    // MARK: One element at a time

    func testOnlyTheElementUnderTheCursorShowsItsMarkup() {
        XCTAssertEqual(shownMarkup("plain **bo¦ld** and ==mark== and *italic*"), ["**", "**"])
        XCTAssertEqual(shownMarkup("plain **bold** and ==ma¦rk== and *italic*"), ["==", "=="])
        XCTAssertEqual(shownMarkup("plain **bold** and ==mark== and *ita¦lic*"), ["*", "*"])
        XCTAssertEqual(shownMarkup("pl¦ain **bold** and ==mark== and *italic*"), [])
        XCTAssertEqual(shownMarkup("some ~~ol¦d~~ and `code`"), ["~~", "~~"])
        XCTAssertEqual(shownMarkup("some ~~old~~ and `co¦de`"), ["`", "`"])
    }

    func testLinksShowTheirWholeSourceOnlyUnderTheCursor() {
        XCTAssertEqual(shownMarkup("See [[No¦te]] and [[Other|alias]]"), ["[[", "]]"])
        XCTAssertEqual(shownMarkup("See [[Note]] and [[Other|ali¦as]]"), ["[[Other|", "]]"])
        XCTAssertEqual(shownMarkup("See [[Note#Head¦ing]] and [[Other]]"), ["[[", "#", "]]"])
        XCTAssertEqual(shownMarkup("See [[#Head¦ing]] and [[Other]]"), ["[[#", "]]"])
        XCTAssertEqual(shownMarkup("A [si¦te](https://a.b) and [[Other]]"), ["[", "](https://a.b)"])
        XCTAssertEqual(shownMarkup("An ![[Figu¦re.png|200]] and [[Other]]"), ["![[", "]]"])
        XCTAssertEqual(shownMarkup("A¦ [site](https://a.b) and [[Note#Heading]]"), [])
    }

    func testFormulasFootnotesAndTagsFollowTheCursor() {
        XCTAssertEqual(shownMarkup("Energy $E = m¦c^2$ and $x^2$"), ["$E = mc^2$"])
        XCTAssertEqual(shownMarkup("Ener¦gy $E = mc^2$ and $x^2$"), [])
        XCTAssertEqual(shownMarkup("A note[^fo¦urier] and ^[inline]"), ["[^", "]"])
        XCTAssertEqual(shownMarkup("A note[^fourier] and ^[inl¦ine]"), ["^[", "]"])
        // A tag has no markup to hide: its `#` is part of how it reads, as in Obsidian.
        let (text, selection) = parse("A #ta¦g and **bold**")
        let textStorage = styledStorage(text, revealedMarkup: RevealedMarkup(selection: selection, in: text as NSString))
        XCTAssertTrue(isShownAsWritten((text as NSString).range(of: "#tag"), in: textStorage))
        XCTAssertEqual(shownMarkup(in: textStorage), [])
        let styledElsewhere = styledStorage(text, revealedMarkup: RevealedMarkup(selection: NSRange(location: text.utf16.count, length: 0), in: text as NSString))
        XCTAssertTrue(isShownAsWritten((text as NSString).range(of: "#tag"), in: styledElsewhere))
    }

    func testColorMarkupShowsOnlyWhileTheSelectionTouchesTheColoredText() {
        let note = "Plain ~={#ff0000}red text=~ then ~={#00ff00}green=~ end"
        let source = note as NSString
        let redMarkers = [source.range(of: "~={#ff0000}"), source.range(of: "=~")]
        let greenMarkers = [source.range(of: "~={#00ff00}"), source.range(of: "=~", options: .backwards)]
        func shownMarkers(cursorAt location: Int) -> (red: Bool, green: Bool) {
            let textStorage = styledStorage(note, revealedMarkup: RevealedMarkup(selection: NSRange(location: location, length: 0), in: source))
            return (redMarkers.allSatisfy { marker in isShownAsWritten(marker, in: textStorage) }, greenMarkers.allSatisfy { marker in isShownAsWritten(marker, in: textStorage) })
        }
        XCTAssertTrue(shownMarkers(cursorAt: 2) == (false, false))
        XCTAssertTrue(shownMarkers(cursorAt: source.range(of: "red").location + 1) == (true, false))
        XCTAssertTrue(shownMarkers(cursorAt: source.range(of: "green").location + 1) == (false, true))
        XCTAssertTrue(shownMarkers(cursorAt: source.range(of: "then").location + 1) == (false, false))
        // Either edge of the colored element counts.
        XCTAssertTrue(shownMarkers(cursorAt: source.range(of: "~={#ff0000}").location) == (true, false))
        XCTAssertTrue(shownMarkers(cursorAt: NSMaxRange(source.range(of: "=~"))) == (true, false))
        // The text keeps its color either way.
        let textStorage = styledStorage(note, revealedMarkup: RevealedMarkup(selection: NSRange(location: 0, length: 0), in: source))
        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: source.range(of: "red").location, effectiveRange: nil) as? NSColor, NSColor(graphiteHex: "#ff0000"))
    }

    /// A color can run over several lines of a paragraph; the cursor anywhere in it shows
    /// both markers, wherever they are.
    func testColorOverSeveralLinesShowsBothMarkersFromAnyOfItsLines() {
        let note = "First ~={#ff0000}red starts\nmiddle line\nred ends=~ here\n\nnext paragraph"
        let source = note as NSString
        let markers = [source.range(of: "~={#ff0000}"), source.range(of: "=~")]
        let middle = RevealedMarkup(selection: NSRange(location: source.range(of: "middle").location + 2, length: 0), in: source)
        let textStorage = styledStorage(note, revealedMarkup: middle)
        XCTAssertTrue(markers.allSatisfy { marker in isShownAsWritten(marker, in: textStorage) })
        let away = RevealedMarkup(selection: NSRange(location: source.range(of: "next").location, length: 0), in: source)
        let restyledRanges = styler.applyRevealedMarkupChange(to: textStorage, from: middle, to: away, concealedBlocks: [])
        XCTAssertEqual(restyledRanges, markers)
        XCTAssertFalse(markers.contains { marker in isShownAsWritten(marker, in: textStorage) })
        XCTAssertEqual(attributeRuns(of: textStorage), attributeRuns(of: styledStorage(note, revealedMarkup: away)))
    }

    // MARK: Edges

    /// A cursor at either edge of an element is inside it, as in Obsidian, so typing at
    /// the end of bold text keeps its closing `**` in view.
    func testCursorAtEitherEdgeOfAnElementCountsAsInsideIt() {
        XCTAssertEqual(shownMarkup("plain ¦**bold** after"), ["**", "**"])
        XCTAssertEqual(shownMarkup("plain **bold**¦ after"), ["**", "**"])
        XCTAssertEqual(shownMarkup("plain **¦bold** after"), ["**", "**"])
        XCTAssertEqual(shownMarkup("plain **bold¦** after"), ["**", "**"])
        XCTAssertEqual(shownMarkup("plain¦ **bold** after"), [])
        XCTAssertEqual(shownMarkup("plain **bold** ¦after"), [])
        XCTAssertEqual(shownMarkup("see ¦[[Note|alias]] x"), ["[[Note|", "]]"])
        XCTAssertEqual(shownMarkup("see [[Note|alias]]¦ x"), ["[[Note|", "]]"])
        XCTAssertEqual(shownMarkup("see [[Note|alias]] ¦x"), [])
        XCTAssertEqual(shownMarkup("is ¦$x^2$ so"), ["$x^2$"])
        XCTAssertEqual(shownMarkup("is $x^2$¦ so"), ["$x^2$"])
        XCTAssertEqual(shownMarkup("is $x^2$ ¦so"), [])
    }

    func testElementsAtTheStartAndEndOfALine() {
        XCTAssertEqual(shownMarkup("¦**first** words\nnext **line**"), ["**", "**"])
        XCTAssertEqual(shownMarkup("**first** words¦\nnext **line**"), [])
        XCTAssertEqual(shownMarkup("words **last**¦\n**next** line"), ["**", "**"])
        XCTAssertEqual(shownMarkup("words **last**\n¦**next** line"), ["**", "**"])
        // The end of one line and the start of the next are different places: each shows
        // its own element only.
        let (text, selection) = parse("words **last**¦\n[[next]] line")
        let textStorage = styledStorage(text, revealedMarkup: RevealedMarkup(selection: selection, in: text as NSString))
        XCTAssertFalse(isShownAsWritten((text as NSString).range(of: "[["), in: textStorage))
        XCTAssertEqual(shownMarkup("words **last**\n¦[[next]] line"), ["[[", "]]"])
        XCTAssertEqual(shownMarkup("only **bold**¦"), ["**", "**"])
        XCTAssertEqual(shownMarkup("¦[[Note]]"), ["[[", "]]"])
    }

    func testAdjacentElementsBothShowWhenTheCursorIsBetweenThem() {
        XCTAssertEqual(shownMarkup("**bold**¦[[Note]] after"), ["[[", "]]", "**", "**"])
        XCTAssertEqual(shownMarkup("**bo¦ld**[[Note]] after"), ["**", "**"])
        XCTAssertEqual(shownMarkup("**bold**[[No¦te]] after"), ["[[", "]]"])
        XCTAssertEqual(shownMarkup("`code`¦==mark=="), ["`", "`", "==", "=="])
    }

    // MARK: Nesting

    func testNestedElementsShowWithTheElementsAroundThem() {
        XCTAssertEqual(shownMarkup("**bo¦ld with _italic_ and [[link]]**"), ["**", "**"])
        XCTAssertEqual(shownMarkup("**bold with _ita¦lic_ and [[link]]**"), ["**", "**", "_", "_"])
        XCTAssertEqual(shownMarkup("**bold with _italic_ and [[li¦nk]]**"), ["[[", "]]", "**", "**"])
        // Right after the link, before the closing `**`: the link's edge, inside the bold.
        XCTAssertEqual(shownMarkup("**bold with _italic_ and [[link]]¦**"), ["[[", "]]", "**", "**"])
        // After the closing `**`: the bold's edge only.
        XCTAssertEqual(shownMarkup("**bold with _italic_ and [[link]]**¦"), ["**", "**"])
        XCTAssertEqual(shownMarkup("x ¦ **bold with _italic_ and [[link]]**"), [])
        XCTAssertEqual(shownMarkup("==mark with $x¦^2$ inside== and **bold**"), ["$x^2$", "==", "=="])
    }

    // MARK: Headings, lists, tasks and quotes

    func testHeadingMarksShowOnTheCursorsLineAndItsElementsOnlyUnderTheCursor() {
        XCTAssertEqual(shownMarkup("# A **bold** head¦ing\nplain"), ["# "])
        XCTAssertEqual(shownMarkup("# A **bo¦ld** heading\nplain"), ["# ", "**", "**"])
        XCTAssertEqual(shownMarkup("¦# A **bold** heading\nplain"), ["# "])
        XCTAssertEqual(shownMarkup("# A **bold** heading\npla¦in"), [])
    }

    func testListTaskAndQuoteMarkersShowOnTheCursorsLineAsBefore() {
        XCTAssertEqual(shownMarkup("- item with **bo¦ld**\n- other [[Note]]"), ["-", "**", "**"])
        XCTAssertEqual(shownMarkup("- it¦em with **bold**\n- other [[Note]]"), ["-"])
        XCTAssertEqual(shownMarkup("- [ ] ta¦sk with ==mark==\n- [x] done"), ["-", "[ ]"])
        XCTAssertEqual(shownMarkup("- [ ] task with ==ma¦rk==\n- [x] done"), ["-", "[ ]", "==", "=="])
        XCTAssertEqual(shownMarkup("> quo¦te with *italic*\n> more"), ["> "])
        XCTAssertEqual(shownMarkup("> quote with *ita¦lic*\n> more"), ["> ", "*", "*"])
        XCTAssertEqual(shownMarkup("1. fir¦st `code`\n2. second"), ["1.", "2."], "An ordered marker has no drawn stand-in, so it always reads as written.")
        XCTAssertEqual(shownMarkup("A block of text ^block¦-id\nnext"), ["^block-id"])
        XCTAssertEqual(shownMarkup("A bl¦ock of text ^block-id\nnext"), ["^block-id"], "A block's id belongs to its line.")
        XCTAssertEqual(shownMarkup("A block of text ^block-id\nne¦xt"), [])
    }

    // MARK: Selections

    func testSelectionShowsEachElementItTouchesAndNoOther() {
        XCTAssertEqual(shownMarkup("**one** «and ==two== and» [[three]] `four`"), ["==", "=="])
        XCTAssertEqual(shownMarkup("**one**« and ==two== and »[[three]] `four`"), ["[[", "]]", "**", "**", "==", "=="])
        XCTAssertEqual(shownMarkup("**o«ne** and ==tw»o== and [[three]] `four`"), ["**", "**", "==", "=="])
        XCTAssertEqual(shownMarkup("«**one** and ==two== and [[three]] `four`»"), ["`", "`", "[[", "]]", "**", "**", "==", "=="])
    }

    /// A selection over several lines shows the elements it touches on each line, not
    /// everything on those lines; the lines' own markers show as before.
    func testSelectionOverSeveralLinesShowsOnlyTheElementsItTouches() {
        let markedNote = "# Title with **bold** and «==mark==\n- item with [[link]]\nlast `co»de` and *italic*\nuntouched **line**"
        XCTAssertEqual(shownMarkup(markedNote), ["# ", "==", "==", "-", "[[", "]]", "`", "`"])
    }

    // MARK: Emoji and right-to-left text

    func testElementsInEmojiAndRightToLeftTextUseTheirUTF16Ranges() {
        XCTAssertEqual(shownMarkup("👍🏽 **غا¦مق 🎉** و [[ملاحظة|اسم]] ثم ==مميز=="), ["**", "**"])
        XCTAssertEqual(shownMarkup("👍🏽 **غامق 🎉** و [[ملاحظة|اس¦م]] ثم ==مميز=="), ["[[ملاحظة|", "]]"])
        XCTAssertEqual(shownMarkup("👍🏽 **غامق 🎉** و [[ملاحظة|اسم]] ثم ==مميز==¦"), ["==", "=="])
        XCTAssertEqual(shownMarkup("👍🏽¦ **غامق 🎉** و [[ملاحظة|اسم]] ثم ==مميز=="), [])
        // The cursor right after the emoji that ends the bold text, four UTF-16 units in.
        XCTAssertEqual(shownMarkup("👨‍👩‍👧 **🎉¦** then `👍🏽`"), ["**", "**"])
        XCTAssertEqual(shownMarkup("👨‍👩‍👧 **🎉** then `👍🏽`¦"), ["`", "`"])
        XCTAssertEqual(shownMarkup("👨‍👩‍👧¦ **🎉** then `👍🏽`"), [])
    }

    // MARK: Reading, and Source mode

    func testNothingShowsWhileOnlyReadingAndEverythingShowsInSourceMode() {
        let note = "# Title\n- item **bold** [[Note|alias]] $x$\n"
        XCTAssertEqual(shownMarkup(in: styledStorage(note, revealedMarkup: nil)), [])
        let sourceStyler = MarkdownTextStyler(configuration: EditorConfiguration(mode: .source), accentColor: .systemBlue, drawsConcealedReplacements: true)
        XCTAssertEqual(shownMarkup(in: styledStorage(note, revealedMarkup: nil, styler: sourceStyler)), ["# ", "-", "$x$", "[[Note|", "]]", "**", "**"])
        let sourceStorage = styledStorage(note, revealedMarkup: nil, styler: sourceStyler)
        XCTAssertEqual(sourceStyler.applyRevealedMarkupChange(to: sourceStorage, from: nil, to: RevealedMarkup(selection: NSRange(location: 3, length: 0), in: note as NSString),
                                                             concealedBlocks: []), [], "Source mode has nothing to reveal.")
    }

    // MARK: Moving the cursor restyles only what changes

    private static let variedNote = """
    # Heading with **bold** and [[Link#Part|alias]]

    Plain text with *italic*, ==mark==, `code`, $x^2$ and a [site](https://a.b).
    **bold with _italic_ and [[link]]** then [[Note#Heading]] end[^1]
    - item with ~~old~~ text ^item-id
    - [x] done task with **bold** and $y$
    - [ ] open task ^[inline note]
    > quote with ==mark== inside
    Title line **bold**
    ===
    ~={#ff0000}red **bold** starts
    and ends=~ after ~={#00ff00}green=~ 👍🏽 **غامق**
    ```
    code **not bold** [[not a link]]
    ```
    $$
    a^2 **not bold**
    $$
    last line **bold**
    """

    /// Styling for one selection and then moving to another gives exactly the attributes
    /// that styling the whole note for the second selection gives.
    func testMovingTheSelectionMatchesStylingTheWholeNoteAgain() {
        let note = Self.variedNote
        let source = note as NSString
        var selections: [NSRange?] = [nil]
        for location in stride(from: 0, through: source.length, by: 5) {
            selections.append(NSRange(location: location, length: 0))
            if location % 3 == 0, location + 23 <= source.length { selections.append(NSRange(location: location, length: 23)) }
        }
        selections.append(NSRange(location: 0, length: source.length))
        selections.append(NSRange(location: 40, length: 210))
        let checkpoints = MarkdownBlockContextCheckpoints()
        var expectedRunsBySelection: [NSRange?: [String]] = [:]
        func markup(_ selection: NSRange?) -> RevealedMarkup? { selection.map { selection in RevealedMarkup(selection: selection, in: source) } }
        for selection in selections { expectedRunsBySelection[selection] = attributeRuns(of: styledStorage(note, revealedMarkup: markup(selection))) }
        for (pairIndex, previousSelection) in selections.enumerated() {
            let textStorage = styledStorage(note, revealedMarkup: markup(previousSelection))
            var currentSelection = previousSelection
            // A chain of moves from each starting selection, so every selection is reached
            // from several others.
            for step in [1, 7, 3, 11, 2] {
                let newSelection = selections[(pairIndex + step * (pairIndex + 1)) % selections.count]
                styler.applyRevealedMarkupChange(to: textStorage, from: markup(currentSelection), to: markup(newSelection), concealedBlocks: [],
                                                 blockContextCheckpoints: pairIndex % 2 == 0 ? checkpoints : nil)
                XCTAssertEqual(attributeRuns(of: textStorage), expectedRunsBySelection[newSelection],
                               "from \(String(describing: currentSelection)) to \(String(describing: newSelection))")
                currentSelection = newSelection
            }
        }
    }

    /// Markup inside a rendered block or a folded section stays hidden as a unit.
    func testMarkupInRenderedBlocksAndFoldsIsLeftAlone() {
        let note = "Intro **bold**\n| **a** | b |\n| - | - |\n| 1 | 2 |\n# Folded\nhidden **bold** line\n# Next **bold**\n"
        let source = note as NSString
        let tableRange = NSRange(location: source.range(of: "| **a**").location, length: source.range(of: "# Folded").location - source.range(of: "| **a**").location)
        let block = ConcealedBlock(range: tableRange, reservedHeight: 40)
        let foldedHeader = source.lineRange(for: NSRange(location: source.range(of: "# Folded").location, length: 0))
        let nextHeading = source.range(of: "# Next").location
        let fold = FoldableRegion(kind: .heading(level: 1), headerRange: NSRange(location: foldedHeader.location, length: foldedHeader.length - 1),
                                  hiddenRange: NSRange(location: NSMaxRange(foldedHeader) - 1, length: nextHeading - NSMaxRange(foldedHeader) + 1), endLocation: nextHeading, key: "folded")
        func styled(_ revealedMarkup: RevealedMarkup?) -> NSTextStorage {
            let textStorage = NSTextStorage(string: note)
            styler.applyStyles(to: textStorage, editedRange: NSRange(location: 0, length: 0), restyleEverything: true, revealedMarkup: revealedMarkup,
                               concealedBlocks: [block], foldedRegions: [fold])
            return textStorage
        }
        let textStorage = styled(nil)
        // A selection over the whole note touches every element, the hidden ones included.
        let everything = RevealedMarkup(selection: NSRange(location: 0, length: source.length), in: source)
        let restyledRanges = styler.applyRevealedMarkupChange(to: textStorage, from: nil, to: everything, concealedBlocks: [block], foldedRegions: [fold])
        XCTAssertFalse(restyledRanges.contains { restyledRange in NSIntersectionRange(restyledRange, tableRange).length > 0 || NSIntersectionRange(restyledRange, fold.hiddenRange).length > 0 })
        XCTAssertFalse(restyledRanges.isEmpty)
        XCTAssertEqual(attributeRuns(of: textStorage), attributeRuns(of: styled(everything)))
        XCTAssertFalse(isShownAsWritten(source.range(of: "**a**"), in: textStorage))
        XCTAssertFalse(isShownAsWritten(source.range(of: "hidden **bold**"), in: textStorage))
        XCTAssertTrue(isShownAsWritten(source.range(of: "**", range: NSRange(location: nextHeading, length: source.length - nextHeading)), in: textStorage))
    }

    /// In a long note, a cursor moving from one bold word to another, far away, changes
    /// the attributes of those two words' markers and of nothing else: not their lines,
    /// not the lines between, not the note.
    func testMovingTheCursorInALongNoteRestylesOnlyTheMarkersOfTheElementsInvolved() {
        let lineCount = 4_000
        let note = (0..<lineCount).map { index in "Paragraph \(index) with **bold \(index)** text, a [[Note \(index)|link]], ==mark== and $x_{\(index)}$ in a longer line of words." }
            .joined(separator: "\n")
        let source = note as NSString
        let textStorage = RecordingTextStorage()
        textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: note)
        func cursor(inBoldOfLine index: Int) -> RevealedMarkup {
            RevealedMarkup(selection: NSRange(location: source.range(of: "**bold \(index)**").location + 4, length: 0), in: source)
        }
        let firstMarkup = cursor(inBoldOfLine: 12)
        styler.applyStyles(to: textStorage, editedRange: NSRange(location: 0, length: 0), restyleEverything: true, revealedMarkup: firstMarkup, concealedBlocks: [])
        let checkpoints = MarkdownBlockContextCheckpoints()

        // A far jump.
        let farMarkup = cursor(inBoldOfLine: 3_500)
        textStorage.startRecording()
        let restyledRanges = styler.applyRevealedMarkupChange(to: textStorage, from: firstMarkup, to: farMarkup, concealedBlocks: [], blockContextCheckpoints: checkpoints)
        let involvedElements = [source.range(of: "**bold 12**"), source.range(of: "**bold 3500**")]
        let markers = involvedElements.flatMap { element in [NSRange(location: element.location, length: 2), NSRange(location: NSMaxRange(element) - 2, length: 2)] }
        XCTAssertEqual(restyledRanges, markers)
        XCTAssertEqual(textStorage.changedAttributeRanges, markers, "Attributes changed outside the markers that start or stop showing.")
        XCTAssertEqual(textStorage.changedAttributeRanges.reduce(0) { unitCount, range in unitCount + range.length }, 8)
        XCTAssertTrue(isShownAsWritten(markers[2], in: textStorage) && !isShownAsWritten(markers[0], in: textStorage))

        // Within one line: from the bold word to plain text, then into the link.
        let lineStart = source.range(of: "Paragraph 3500 ").location
        let plainMarkup = RevealedMarkup(selection: NSRange(location: lineStart + 3, length: 0), in: source)
        textStorage.startRecording()
        styler.applyRevealedMarkupChange(to: textStorage, from: farMarkup, to: plainMarkup, concealedBlocks: [], blockContextCheckpoints: checkpoints)
        XCTAssertEqual(textStorage.changedAttributeRanges, [markers[2], markers[3]])
        let link = source.range(of: "[[Note 3500|link]]")
        let linkMarkup = RevealedMarkup(selection: NSRange(location: NSMaxRange(link) - 3, length: 0), in: source)
        textStorage.startRecording()
        styler.applyRevealedMarkupChange(to: textStorage, from: plainMarkup, to: linkMarkup, concealedBlocks: [], blockContextCheckpoints: checkpoints)
        XCTAssertEqual(textStorage.changedAttributeRanges, [NSRange(location: link.location, length: 12), NSRange(location: NSMaxRange(link) - 2, length: 2)])

        // Moving inside plain text, or inside the element already showing, restyles nothing.
        textStorage.startRecording()
        styler.applyRevealedMarkupChange(to: textStorage, from: linkMarkup, to: RevealedMarkup(selection: NSRange(location: NSMaxRange(link) - 2, length: 0), in: source),
                                         concealedBlocks: [], blockContextCheckpoints: checkpoints)
        styler.applyRevealedMarkupChange(to: textStorage, from: plainMarkup, to: RevealedMarkup(selection: NSRange(location: lineStart + 5, length: 0), in: source),
                                         concealedBlocks: [], blockContextCheckpoints: checkpoints)
        XCTAssertEqual(textStorage.changedAttributeRanges, [])

        // The whole note still reads as a note styled for the last selection.
        let finalMarkup = RevealedMarkup(selection: NSRange(location: NSMaxRange(link) - 2, length: 0), in: source)
        XCTAssertEqual(attributeRuns(of: textStorage), attributeRuns(of: styledStorage(note, revealedMarkup: finalMarkup)))
    }

    /// The time one cursor move takes near the end of a note of about a million characters
    /// with no blank line in it, where the colors around a line would be looked for in the
    /// whole note. The bound is loose: it fails if a move scans the note, or scans its own
    /// line again at every step, rather than looking at what it remembers of the line.
    func testMovingTheCursorNearTheEndOfAVeryLongNoteIsFast() {
        let lineCount = 10_000
        let note = (0..<lineCount).map { index in "Paragraph \(index) with **bold \(index)** text, a [[Note \(index)|link]], ==mark== and $x_{\(index)}$ in a longer line of words." }
            .joined(separator: "\n")
        let source = note as NSString
        XCTAssertGreaterThan(source.length, 900_000)
        let textStorage = NSTextStorage(string: note)
        styler.applyStyles(to: textStorage, editedRange: NSRange(location: 0, length: 0), restyleEverything: true, revealedMarkup: nil, concealedBlocks: [])
        let checkpoints = MarkdownBlockContextCheckpoints()
        let lineStart = source.range(of: "Paragraph 9900 ").location
        let lineLength = source.lineRange(for: NSRange(location: lineStart, length: 0)).length
        // The first move leaves checkpoints behind, as the first restyle in the editor does.
        var currentMarkup = RevealedMarkup(selection: NSRange(location: lineStart, length: 0), in: source)
        styler.applyRevealedMarkupChange(to: textStorage, from: nil, to: currentMarkup, concealedBlocks: [], blockContextCheckpoints: checkpoints)
        let moveCount = 400
        var restyledUnitCount = 0
        let start = ProcessInfo.processInfo.systemUptime
        for move in 1...moveCount {
            // Along the line and onto the next, as the arrow keys go.
            let newMarkup = RevealedMarkup(selection: NSRange(location: lineStart + (move * 3) % (2 * lineLength), length: 0), in: source)
            let restyledRanges = styler.applyRevealedMarkupChange(to: textStorage, from: currentMarkup, to: newMarkup, concealedBlocks: [], blockContextCheckpoints: checkpoints)
            restyledUnitCount += restyledRanges.reduce(0) { unitCount, range in unitCount + range.length }
            currentMarkup = newMarkup
        }
        let millisecondsPerMove = (ProcessInfo.processInfo.systemUptime - start) * 1_000 / Double(moveCount)
        print("Live Preview cursor move in a \(source.length)-unit note: \(String(format: "%.3f", millisecondsPerMove)) ms each, \(restyledUnitCount) units restyled in \(moveCount) moves")
        XCTAssertLessThan(millisecondsPerMove, 2, "A cursor move costs more than looking at its own lines.")
        // No move restyles more than the markup of the elements on the two lines it can touch.
        XCTAssertLessThan(restyledUnitCount, moveCount * 40)
        XCTAssertTrue(isShownAsWritten(NSRange(location: lineStart, length: 9), in: textStorage))
    }

    /// Notes without colors skip looking for them; a color typed into such a note, or made
    /// by a deletion that joins its marker's characters, is still found.
    func testColorTypedIntoANoteWithoutColorsIsStyled() {
        let note = "First line\nSecond ~=X{#ff0000}red=~ line\nThird line\n"
        let textStorage = NSTextStorage(string: note)
        let checkpoints = MarkdownBlockContextCheckpoints()
        func restyleEverything() {
            styler.applyStyles(to: textStorage, editedRange: NSRange(location: 0, length: 0), restyleEverything: true, revealedMarkup: nil, concealedBlocks: [],
                               blockContextCheckpoints: checkpoints)
        }
        func restyleLine(containing text: String) {
            let location = textStorage.mutableString.range(of: text).location
            styler.applyStyles(to: textStorage, editedRange: NSRange(location: location, length: 0), restyleEverything: false, revealedMarkup: nil, concealedBlocks: [],
                               blockContextCheckpoints: checkpoints)
        }
        func color(of text: String) -> NSColor? {
            textStorage.attribute(.foregroundColor, at: textStorage.mutableString.range(of: text).location, effectiveRange: nil) as? NSColor
        }
        restyleEverything()
        XCTAssertEqual(color(of: "red"), MarkdownTextStyler.primaryTextColor)
        // Deleting the `X` joins `~=` and `{` into a marker.
        textStorage.replaceCharacters(in: textStorage.mutableString.range(of: "X"), with: "")
        restyleLine(containing: "Second")
        XCTAssertEqual(color(of: "red"), NSColor(graphiteHex: "#ff0000"))
        // Typing a whole marker.
        textStorage.replaceCharacters(in: NSRange(location: textStorage.mutableString.range(of: "Third").location, length: 0), with: "~={#00ff00}green=~ ")
        restyleLine(containing: "Third")
        XCTAssertEqual(color(of: "green"), NSColor(graphiteHex: "#00ff00"))
        XCTAssertFalse(isShownAsWritten(textStorage.mutableString.range(of: "~={#00ff00}"), in: textStorage))
        XCTAssertEqual(attributeRuns(of: textStorage), attributeRuns(of: styledStorage(textStorage.string, revealedMarkup: nil)))
    }

    // MARK: Rendered blocks the cursor enters or leaves

    func testOnlyBlocksTheCursorEntersOrLeavesChangeActivity() {
        let source = "Intro\n\n| a |\n| - |\n\nBetween\n\n| b |\n| - |\n\nEnd\n\n| c |\n| - |" as NSString
        let blockRanges = LivePreviewBlockScanner.blocks(in: source).map(\.range)
        XCTAssertEqual(blockRanges.count, 3)
        func changing(from previousLocation: Int?, to newLocation: Int?) -> [Int] {
            LivePreviewBlockActivity.indicesOfBlocksChangingActivity(from: previousLocation.map { location in NSRange(location: location, length: 0) },
                                                                     to: newLocation.map { location in NSRange(location: location, length: 0) }, blockRanges: blockRanges, in: source)
        }
        let intro = 2
        let firstTable = blockRanges[0].location + 3
        let secondTable = blockRanges[1].location + 3
        XCTAssertEqual(changing(from: intro, to: firstTable), [0])
        XCTAssertEqual(changing(from: firstTable, to: firstTable + 4), [], "Moving inside a block keeps it active.")
        XCTAssertEqual(changing(from: firstTable, to: secondTable), [0, 1])
        XCTAssertEqual(changing(from: secondTable, to: nil), [1], "Ending editing leaves the block.")
        XCTAssertEqual(changing(from: nil, to: intro), [])
        XCTAssertEqual(changing(from: intro, to: source.range(of: "Between").location), [])
        // A cursor right after a block that ends the note is inside it.
        XCTAssertEqual(changing(from: intro, to: source.length), [2])
        // A selection that grows past a block's end leaves it: the block is inside the
        // selection, which no longer has an end in it.
        let selectionIntoBlock = NSRange(location: intro, length: firstTable - intro)
        let selectionPastBlock = NSRange(location: intro, length: source.range(of: "Between").location + 2 - intro)
        XCTAssertEqual(LivePreviewBlockActivity.indicesOfBlocksChangingActivity(from: selectionIntoBlock, to: selectionPastBlock, blockRanges: blockRanges, in: source), [0])
        // The answer matches asking every block.
        for previousLocation in stride(from: 0, through: source.length, by: 2) {
            for newLocation in stride(from: 1, through: source.length, by: 3) {
                let expected = blockRanges.indices.filter { index in
                    LivePreviewBlockActivity.isActive(blockRange: blockRanges[index], selection: NSRange(location: previousLocation, length: 0), in: source)
                        != LivePreviewBlockActivity.isActive(blockRange: blockRanges[index], selection: NSRange(location: newLocation, length: 0), in: source)
                }
                XCTAssertEqual(changing(from: previousLocation, to: newLocation), expected, "from \(previousLocation) to \(newLocation)")
            }
        }
    }

    // MARK: Taps

    /// A tap on a link follows it unless the link's markup is showing, in which case the
    /// link is being edited and the tap places the cursor.
    func testTapsReachALinkOnlyWhileItsMarkupIsHidden() {
        let source = "See [[Here]] and **bold [[Inside]]** plus [[There]]\n[[Next]] line" as NSString
        func isInsideLinkShowingItsMarkup(_ text: String, cursorIn cursorText: String) -> Bool {
            let revealedMarkup = RevealedMarkup(selection: NSRange(location: source.range(of: cursorText).location + 1, length: 0), in: source)
            return LivePreviewTapTargets.isInsideLinkShowingItsMarkup(source.range(of: text).location + 1, in: source, revealedMarkup: revealedMarkup)
        }
        XCTAssertTrue(isInsideLinkShowingItsMarkup("Here", cursorIn: "Here"))
        XCTAssertFalse(isInsideLinkShowingItsMarkup("There", cursorIn: "Here"), "Another link on the cursor's line is still a link.")
        XCTAssertFalse(isInsideLinkShowingItsMarkup("Next", cursorIn: "Here"))
        XCTAssertFalse(isInsideLinkShowingItsMarkup("Inside", cursorIn: "bold"), "A link in bold text that shows its `**` is still a link.")
        XCTAssertTrue(isInsideLinkShowingItsMarkup("Inside", cursorIn: "Inside"))
        XCTAssertFalse(isInsideLinkShowingItsMarkup("bold", cursorIn: "bold"), "Bold text is not a link.")
        XCTAssertFalse(isInsideLinkShowingItsMarkup("Here", cursorIn: "See"))
        let cursorAtTheEnd = RevealedMarkup(selection: NSRange(location: source.length, length: 0), in: source)
        XCTAssertFalse(LivePreviewTapTargets.isInsideLinkShowingItsMarkup(source.length, in: source, revealedMarkup: cursorAtTheEnd))
    }

    // MARK: The revealed markup itself

    func testRevealedMarkupClampsItsSelectionAndKnowsItsLines() {
        let source = "one **two**\nthree\n" as NSString
        let cursor = RevealedMarkup(selection: NSRange(location: 4, length: 0), in: source)
        XCTAssertEqual(cursor.lineRange, NSRange(location: 0, length: 12))
        XCTAssertEqual(cursor.shownLineRange, cursor.lineRange)
        XCTAssertTrue(cursor.showsInlineElement(at: NSRange(location: 4, length: 7)))
        XCTAssertFalse(cursor.showsInlineElement(at: NSRange(location: 5, length: 6)))
        XCTAssertTrue(cursor.showsLineMarker(at: 0))
        XCTAssertFalse(cursor.showsLineMarker(at: 12), "The next line starts where the cursor's line ends.")
        // A selection through a line break ends where the next line starts, and touches an
        // element starting there, though that line's own markers stay hidden.
        let throughLineBreak = RevealedMarkup(selection: NSRange(location: 4, length: 8), in: source)
        XCTAssertEqual(throughLineBreak.lineRange, NSRange(location: 0, length: 12))
        XCTAssertEqual(throughLineBreak.shownLineRange, NSRange(location: 0, length: 18))
        XCTAssertTrue(throughLineBreak.showsInlineElement(at: NSRange(location: 12, length: 3)))
        XCTAssertFalse(throughLineBreak.showsLineMarker(at: 12))
        let pastTheEnd = RevealedMarkup(selection: NSRange(location: 40, length: 9), in: source)
        XCTAssertEqual(pastTheEnd.selection, NSRange(location: source.length, length: 0))
    }
}

/// A text storage that records which ranges had their attributes set, so a test can tell
/// exactly how much of a note a restyle touched.
private final class RecordingTextStorage: NSTextStorage {
    private let backingStore = NSMutableAttributedString()
    /// The text as a value: reading the backing store's own string copies it on every call.
    private var text = ""
    private var isRecording = false
    private var recordedRanges: [NSRange] = []

    func startRecording() {
        recordedRanges = []
        isRecording = true
    }

    /// The recorded ranges in text order, with overlapping or adjacent ones joined.
    var changedAttributeRanges: [NSRange] { RevealedMarkupChange.merged(recordedRanges) }

    override var string: String { text }

    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backingStore.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with string: String) {
        beginEditing()
        backingStore.replaceCharacters(in: range, with: string)
        text = backingStore.string
        edited(.editedCharacters, range: range, changeInLength: (string as NSString).length - range.length)
        endEditing()
    }

    override func setAttributes(_ attributes: [NSAttributedString.Key: Any]?, range: NSRange) {
        if isRecording { recordedRanges.append(range) }
        beginEditing()
        backingStore.setAttributes(attributes, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }
}
