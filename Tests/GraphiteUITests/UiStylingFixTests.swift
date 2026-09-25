import XCTest
import AppKit
import SwiftUI
@testable import GraphiteCore
import Textual
@testable import GraphiteUI

@MainActor
final class UiStylingFixTests: XCTestCase {
    private let livePreview = EditorConfiguration(mode: .livePreview)

    // MARK: Crash safety

    /// A rendered block or fold from the editor's previous scan can lie past the end of
    /// the text after an edit. Styling must skip it: attributes past the end raise an
    /// exception that ends the app.
    func testBlocksAndFoldsPastTheEndOfTheTextAreSkipped() {
        let textStorage = NSTextStorage(string: "| a | b |\n| - | - |\n| 1 | 2 |\n")
        let length = textStorage.length
        let insideBlock = ConcealedBlock(range: NSRange(location: 0, length: length), reservedHeight: 40)
        let staleBlock = ConcealedBlock(range: NSRange(location: 10, length: length), reservedHeight: 40)
        let staleFold = FoldableRegion(kind: .heading(level: 1), headerRange: NSRange(location: 0, length: 3),
                                       hiddenRange: NSRange(location: 3, length: length), endLocation: length + 5, key: "stale")
        let styler = MarkdownTextStyler(configuration: livePreview, accentColor: .systemBlue)
        styler.applyStyles(to: textStorage, editedRange: NSRange(location: 0, length: 0), restyleEverything: true,
                           revealedRange: nil, concealedBlocks: [insideBlock, staleBlock], foldedRegions: [staleFold])
        // The block that still fits is concealed.
        let font = textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize ?? 0, 0.01, accuracy: 0.001)
        styler.applyStyles(to: textStorage, editedRange: NSRange(location: length - 2, length: 50), restyleEverything: false,
                           revealedRange: nil, concealedBlocks: [staleBlock], foldedRegions: [staleFold])
        styler.applyStyles(to: textStorage, editedRange: NSRange(location: -4, length: 2), restyleEverything: false,
                           revealedRange: nil, concealedBlocks: [], foldedRegions: [])
    }

    // MARK: Replacements without a drawer

    /// The Mac editor has no layout fragment to draw bullets, checkboxes, quote bars,
    /// subpath separators or formulas, so their markup must stay visible.
    func testMarkupStaysVisibleWhenNothingDrawsItsReplacement() {
        let text = "- item\n- [ ] task\n> quote\n[[Note#Heading]]\n$x^2$ here\n"
        let textStorage = NSTextStorage(string: text)
        let styler = MarkdownTextStyler(configuration: livePreview, accentColor: .systemBlue, drawsConcealedReplacements: false)
        styler.applyStyles(to: textStorage, editedRange: NSRange(location: 0, length: 0), restyleEverything: true, revealedRange: nil, concealedBlocks: [])
        let source = text as NSString
        for marker in ["-", "[ ]", ">", "#", "$x^2$"] {
            let location = source.range(of: marker, options: [], range: NSRange(location: marker == "-" ? 0 : 7, length: source.length - (marker == "-" ? 0 : 7))).location
            XCTAssertNil(textStorage.attribute(ConcealedReplacement.attributeKey, at: location, effectiveRange: nil), marker)
            XCTAssertNotEqual(textStorage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor, NSColor.clear, marker)
            let font = textStorage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
            XCTAssertGreaterThan(font?.pointSize ?? 0, 1, marker)
        }
        // Markup that needs no stand-in is still hidden away from the cursor.
        let bracketFont = textStorage.attribute(.font, at: source.range(of: "[[").location, effectiveRange: nil) as? NSFont
        XCTAssertEqual(bracketFont?.pointSize ?? 0, 0.01, accuracy: 0.001)
    }

    func testReplacementsAreHiddenWhenTheEditorDrawsThem() {
        let text = "- item\n- [ ] task\n> quote\n"
        let textStorage = NSTextStorage(string: text)
        let styler = MarkdownTextStyler(configuration: livePreview, accentColor: .systemBlue, drawsConcealedReplacements: true)
        styler.applyStyles(to: textStorage, editedRange: NSRange(location: 0, length: 0), restyleEverything: true, revealedRange: nil, concealedBlocks: [])
        XCTAssertEqual(textStorage.attribute(ConcealedReplacement.attributeKey, at: 0, effectiveRange: nil) as? String, ConcealedReplacement.bullet.rawValue)
        XCTAssertEqual(textStorage.attribute(ConcealedReplacement.attributeKey, at: 9, effectiveRange: nil) as? String, ConcealedReplacement.uncheckedTask.rawValue)
        XCTAssertEqual(textStorage.attribute(ConcealedReplacement.attributeKey, at: 18, effectiveRange: nil) as? String, ConcealedReplacement.quoteBar.rawValue)
    }

    // MARK: Revealed lines

    /// The revealed range is whole lines, so it ends where the next line starts; the next
    /// line's markup must stay hidden.
    func testMarkupAtTheStartOfTheNextLineStaysHidden() {
        let text = "Intro\n# Heading\n- item\n- two\n"
        let textStorage = NSTextStorage(string: text)
        let styler = MarkdownTextStyler(configuration: livePreview, accentColor: .systemBlue, drawsConcealedReplacements: true)
        let source = text as NSString
        let introLine = source.lineRange(for: NSRange(location: 0, length: 0))
        styler.applyStyles(to: textStorage, editedRange: NSRange(location: 0, length: 0), restyleEverything: true, revealedRange: introLine, concealedBlocks: [])
        let headingMarkerFont = textStorage.attribute(.font, at: introLine.length, effectiveRange: nil) as? NSFont
        XCTAssertEqual(headingMarkerFont?.pointSize ?? 0, 0.01, accuracy: 0.001)

        let headingLine = source.lineRange(for: NSRange(location: introLine.length, length: 0))
        styler.applyStyles(to: textStorage, editedRange: NSRange(location: 0, length: 0), restyleEverything: true, revealedRange: headingLine, concealedBlocks: [])
        XCTAssertEqual(textStorage.attribute(ConcealedReplacement.attributeKey, at: NSMaxRange(headingLine), effectiveRange: nil) as? String, ConcealedReplacement.bullet.rawValue)
        let revealedHeadingFont = textStorage.attribute(.font, at: introLine.length, effectiveRange: nil) as? NSFont
        XCTAssertGreaterThan(revealedHeadingFont?.pointSize ?? 0, 1)
    }

    // MARK: Colors context

    /// A line restyle must color exactly as a whole-note restyle does, including inside
    /// and after fenced code that contains blank lines, and in notes with Windows line
    /// endings or whitespace-only blank lines.
    func testLineRestylesColorLikeWholeNoteRestyles() {
        let notes = [
            "```\nline\n\n~={#ff0000}x=~ in code\n```\n",
            "```swift\nfunc a() {}\n\nfunc b() {}\n```\nSee ~={#ff0000}this=~ note.\n",
            "Intro ~={#00ff00}green\nstill green=~\r\n\r\n```\r\ncode\r\n\r\n~={#ff0000}x=~\r\n```\r\nAfter ~={#0000ff}blue=~ text\r\n",
            "Para one ~={#ff0000}red\n   \nPara two=~ plain\n$$\n\n~={#ff0000}in math=~\n$$\nend ~={#00ff00}x=~\n",
            "---\ntitle: ~={#ff0000}x=~\n---\n\n# Heading ~={#ff0000}red=~\n- item ~={#00ff00}green=~\n"
        ]
        for note in notes {
            for usesCheckpoints in [false, true] {
                assertLineRestylesMatchWholeNoteRestyle(note, usesCheckpoints: usesCheckpoints)
            }
        }
    }

    func testCodeAfterABlankLineInsideAFenceIsNotColored() {
        let note = "```\nline\n\n~={#ff0000}x=~ in code\n```\n"
        let textStorage = NSTextStorage(string: note)
        let styler = MarkdownTextStyler(configuration: livePreview, accentColor: .systemBlue)
        let source = note as NSString
        let markerLine = source.lineRange(for: NSRange(location: source.range(of: "~={").location, length: 0))
        styler.applyStyles(to: textStorage, editedRange: NSRange(location: 0, length: 0), restyleEverything: true, revealedRange: nil, concealedBlocks: [])
        styler.applyStyles(to: textStorage, editedRange: markerLine, restyleEverything: false, revealedRange: nil, concealedBlocks: [])
        let color = textStorage.attribute(.foregroundColor, at: source.range(of: "x=~").location, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, MarkdownTextStyler.primaryTextColor)
        let markerFont = textStorage.attribute(.font, at: markerLine.location, effectiveRange: nil) as? NSFont
        XCTAssertGreaterThan(markerFont?.pointSize ?? 0, 1)
    }

    func testParagraphRunBoundsTreatWhitespaceAndWindowsBlankLinesAsBreaks() {
        let source = "one\r\ntwo\r\n\r\nthree\r\n  \t\r\nfour\nfive\n" as NSString
        let threeLocation = source.range(of: "three").location
        let fourLocation = source.range(of: "four").location
        XCTAssertEqual(MarkdownTextStyler.paragraphRunStart(atLineContaining: threeLocation + 2, in: source), threeLocation)
        XCTAssertEqual(MarkdownTextStyler.paragraphRunEnd(atLineContaining: threeLocation, in: source), source.range(of: "  \t").location)
        XCTAssertEqual(MarkdownTextStyler.paragraphRunStart(atLineContaining: source.range(of: "five").location, in: source), fourLocation)
        XCTAssertEqual(MarkdownTextStyler.paragraphRunEnd(atLineContaining: fourLocation, in: source), source.length)
        XCTAssertEqual(MarkdownTextStyler.paragraphRunStart(atLineContaining: 1, in: source), 0)
    }

    private func assertLineRestylesMatchWholeNoteRestyle(_ note: String, usesCheckpoints: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let source = note as NSString
        let styler = MarkdownTextStyler(configuration: livePreview, accentColor: .systemBlue, drawsConcealedReplacements: true)
        let expected = NSTextStorage(string: note)
        styler.applyStyles(to: expected, editedRange: NSRange(location: 0, length: 0), restyleEverything: true, revealedRange: nil, concealedBlocks: [])
        let checkpoints = MarkdownBlockContextCheckpoints()
        var lineStart = 0
        while lineStart < source.length {
            let lineRange = source.lineRange(for: NSRange(location: lineStart, length: 0))
            let restyled = NSTextStorage(attributedString: expected)
            styler.applyStyles(to: restyled, editedRange: lineRange, restyleEverything: false, revealedRange: nil, concealedBlocks: [],
                               blockContextCheckpoints: usesCheckpoints ? checkpoints : nil)
            XCTAssertEqual(Self.attributeRuns(of: restyled), Self.attributeRuns(of: expected),
                           "line \(source.substring(with: lineRange).debugDescription) of \(note.debugDescription)", file: file, line: line)
            lineStart = NSMaxRange(lineRange)
        }
    }

    /// Attribute runs as comparable values; a formula's layout object is new on every
    /// pass, so only its LaTeX is compared.
    private static func attributeRuns(of textStorage: NSTextStorage) -> [AttributeRun] {
        var runs: [AttributeRun] = []
        textStorage.enumerateAttributes(in: NSRange(location: 0, length: textStorage.length)) { attributes, range, _ in
            let comparable = attributes.mapValues { value in (value as? InlineMathLayout).map { layout in "math(\(layout.latex))" as NSString } ?? value }
            runs.append(AttributeRun(range: range, attributes: comparable as NSDictionary))
        }
        return runs
    }

    private struct AttributeRun: Equatable, CustomStringConvertible {
        let range: NSRange
        let attributes: NSDictionary
        var description: String { "\(range): \(attributes)" }
    }

    // MARK: Block context checkpoints

    func testCheckpointsGiveTheScannersContextAndSpansBeforeAndAfterEdits() {
        let textStorage = NSTextStorage(string: Self.longNote())
        let checkpoints = MarkdownBlockContextCheckpoints()
        assertCheckpointsMatchScanner(checkpoints, textStorage: textStorage)
        let edits: [(location: Int, deletedLength: Int, insertedText: String)] = [
            (textStorage.length / 2, 0, "```\n"),
            (textStorage.length / 3, 5, ""),
            (textStorage.length - 10, 0, "\n$$\n"),
            (0, 0, "---\ntitle: x\n"),
            (textStorage.length / 4, 0, "\r\n"),
            (textStorage.length / 2, 0, "\n")
        ]
        for edit in edits {
            let location = min(edit.location, textStorage.length)
            textStorage.replaceCharacters(in: NSRange(location: location, length: min(edit.deletedLength, textStorage.length - location)), with: edit.insertedText)
            assertCheckpointsMatchScanner(checkpoints, textStorage: textStorage)
        }
        // A lone carriage return that an edit turns into a Windows line break.
        let carriageReturnStorage = NSTextStorage(string: String(repeating: "line\r", count: 1500) + "```\ncode\n")
        let carriageReturnCheckpoints = MarkdownBlockContextCheckpoints()
        assertCheckpointsMatchScanner(carriageReturnCheckpoints, textStorage: carriageReturnStorage)
        carriageReturnStorage.replaceCharacters(in: NSRange(location: 4100, length: 0), with: "\n")
        assertCheckpointsMatchScanner(carriageReturnCheckpoints, textStorage: carriageReturnStorage)
    }

    private func assertCheckpointsMatchScanner(_ checkpoints: MarkdownBlockContextCheckpoints, textStorage: NSTextStorage, file: StaticString = #filePath, line: UInt = #line) {
        let source = textStorage.mutableString.copy() as? NSString ?? ""
        var lineStart = 0
        var lineStarts: [Int] = []
        while lineStart < source.length {
            lineStarts.append(lineStart)
            lineStart = NSMaxRange(source.lineRange(for: NSRange(location: lineStart, length: 0)))
        }
        // A sample of lines, forwards and then backwards, so lookups also start from
        // checkpoints made by later lines; the scanner's answer costs a scan from the top.
        let forwardSample = lineStarts.enumerated().filter { lineIndex, _ in lineIndex % 4 == 0 }.map { _, location in location }
        let backwardSample = lineStarts.enumerated().filter { lineIndex, _ in lineIndex % 9 == 5 }.map { _, location in location }.reversed()
        for (lineNumber, location) in (forwardSample + backwardSample).enumerated() {
            XCTAssertEqual(checkpoints.blockContext(atLineStart: location, in: textStorage, source: source),
                           MarkdownStyleScanner.blockContext(atLineContaining: location, in: source), "line at \(location)", file: file, line: line)
            guard lineNumber % 3 == 0 else { continue }
            let range = NSRange(location: location, length: min(40, source.length - location))
            XCTAssertEqual(checkpoints.spans(in: textStorage, source: source, range: range), MarkdownStyleScanner.spans(in: source, range: range),
                           "spans at \(location)", file: file, line: line)
        }
    }

    private static func longNote() -> String {
        var note = "---\ntitle: Long\n---\n\n"
        for section in 0..<60 {
            note += "# Section \(section)\n\nSome **bold** text with $x_\(section)$ and a [[Link#Heading]].\n- item\n- [ ] task\n> quote\n"
            switch section % 5 {
            case 0: note += "```swift\nlet value = \(section)\n\n---\n# not a heading\n```\n"
            case 1: note += "$$\na^2 + b^2\n\n= c^2\n$$\n"
            case 2: note += "> ```\n> quoted code\n> ```\n"
            case 3: note += "---\n\n" + String(repeating: "A long line without breaks. ", count: 90) + "\n"
            default: note += "~~~\ntilde fence\n~~~\r\nWindows line\r\n\r\n"
            }
        }
        return note
    }

    // MARK: Inline math layout

    /// A tall formula's line is made tall enough for it, and its source's last two
    /// characters, which carry that height, are never split across lines.
    func testTallInlineMathMakesItsLineTallEnough() throws {
        let latex = "\\frac{\\frac{a}{b}}{\\frac{c}{d}}"
        let text = "Some words here then $\(latex)$ more words after it to wrap around\nnext line\n"
        let configuration = EditorConfiguration(mode: .livePreview, textSize: 17)
        let styler = MarkdownTextStyler(configuration: configuration, accentColor: .systemBlue, drawsConcealedReplacements: true)
        let metrics = try XCTUnwrap(InlineMathRendering.metrics(for: LaTeXCompatibility.normalized(latex), fontSize: 17 * 1.2))
        let source = text as NSString
        let formulaRange = source.range(of: "$\(latex)$")
        for width in stride(from: 120.0, through: 400.0, by: 20.0) {
            let lines = try layOut(text, styledBy: styler, width: width)
            let formulaLine = try XCTUnwrap(lines.first { line in NSLocationInRange(NSMaxRange(formulaRange) - 1, line.characterRange) })
            XCTAssertTrue(NSLocationInRange(NSMaxRange(formulaRange) - 2, formulaLine.characterRange), "width \(width)")
            XCTAssertGreaterThanOrEqual(formulaLine.baseline - formulaLine.top + 0.5, metrics.ascent, "width \(width)")
            XCTAssertGreaterThanOrEqual(formulaLine.bottom - formulaLine.baseline + 0.5, metrics.descent, "width \(width)")
        }
    }

    /// A formula inside a rendered block or a folded section is neither drawn over the
    /// hidden source nor allowed to make its hidden lines taller.
    func testFormulasInRenderedBlocksAndFoldsLeaveNoDrawingOrHeight() {
        let styler = MarkdownTextStyler(configuration: livePreview, accentColor: .systemBlue, drawsConcealedReplacements: true)
        let table = "| $\\frac{a}{b}$ |\n| - |\n| 1 |\n"
        let tableStorage = NSTextStorage(string: table)
        let tableBlock = ConcealedBlock(range: NSRange(location: 0, length: tableStorage.length), reservedHeight: 40)
        styler.applyStyles(to: tableStorage, editedRange: NSRange(location: 0, length: 0), restyleEverything: true, revealedRange: nil, concealedBlocks: [tableBlock])
        assertNoFormulaAttributes(in: tableStorage, range: tableBlock.range)

        let note = "# Heading\nSee $\\frac{a}{b}$ here\n# Next\n"
        let noteStorage = NSTextStorage(string: note)
        let source = note as NSString
        let nextHeading = source.range(of: "# Next").location
        let fold = FoldableRegion(kind: .heading(level: 1), headerRange: NSRange(location: 0, length: 9),
                                  hiddenRange: NSRange(location: 9, length: nextHeading - 9), endLocation: nextHeading, key: "heading")
        styler.applyStyles(to: noteStorage, editedRange: NSRange(location: 0, length: 0), restyleEverything: true, revealedRange: nil,
                           concealedBlocks: [], foldedRegions: [fold])
        assertNoFormulaAttributes(in: noteStorage, range: fold.hiddenRange)
        // The same formula outside the fold is drawn and sized.
        styler.applyStyles(to: noteStorage, editedRange: NSRange(location: 0, length: 0), restyleEverything: true, revealedRange: nil, concealedBlocks: [])
        XCTAssertNotNil(noteStorage.attribute(ConcealedReplacement.mathAttributeKey, at: source.range(of: "$").location, effectiveRange: nil))
    }

    private func assertNoFormulaAttributes(in textStorage: NSTextStorage, range: NSRange, file: StaticString = #filePath, line: UInt = #line) {
        for key in [ConcealedReplacement.mathAttributeKey, ConcealedReplacement.attributeKey, NSAttributedString.Key.baselineOffset] {
            textStorage.enumerateAttribute(key, in: range) { value, attributeRange, _ in
                XCTAssertNil(value, "\(key.rawValue) at \(attributeRange)", file: file, line: line)
            }
        }
    }

    private struct LaidOutLine {
        let characterRange: NSRange
        let top: CGFloat
        let baseline: CGFloat
        let bottom: CGFloat
    }

    private func layOut(_ text: String, styledBy styler: MarkdownTextStyler, width: CGFloat) throws -> [LaidOutLine] {
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        contentStorage.addTextLayoutManager(layoutManager)
        layoutManager.textContainer = NSTextContainer(size: CGSize(width: width, height: 0))
        let textStorage = try XCTUnwrap(contentStorage.textStorage)
        textStorage.setAttributedString(NSAttributedString(string: text))
        styler.applyStyles(to: textStorage, editedRange: NSRange(location: 0, length: 0), restyleEverything: true, revealedRange: nil, concealedBlocks: [])
        var lines: [LaidOutLine] = []
        layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location, options: [.ensuresLayout]) { fragment in
            let paragraphStart = contentStorage.offset(from: contentStorage.documentRange.location, to: fragment.rangeInElement.location)
            for lineFragment in fragment.textLineFragments {
                let top = fragment.layoutFragmentFrame.minY + lineFragment.typographicBounds.minY
                lines.append(LaidOutLine(characterRange: lineFragment.characterRange.shifted(by: paragraphStart), top: top,
                                         baseline: top + lineFragment.glyphOrigin.y, bottom: top + lineFragment.typographicBounds.height))
            }
            return true
        }
        return lines
    }

    // MARK: Fonts

    func testStrongTextInAHeadingIsBoldAtTheHeadingSize() {
        let textStorage = NSTextStorage(string: "# A **bold** heading\nplain *italic* text\n")
        let styler = MarkdownTextStyler(configuration: EditorConfiguration(mode: .source, textSize: 20), accentColor: .systemBlue)
        styler.applyStyles(to: textStorage, editedRange: NSRange(location: 0, length: 0), restyleEverything: true, revealedRange: nil, concealedBlocks: [])
        let boldFont = textStorage.attribute(.font, at: 6, effectiveRange: nil) as? NSFont
        XCTAssertEqual(boldFont?.pointSize ?? 0, 35, accuracy: 0.01)
        XCTAssertTrue(boldFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        let italicFont = textStorage.attribute(.font, at: (textStorage.string as NSString).range(of: "italic").location, effectiveRange: nil) as? NSFont
        XCTAssertEqual(italicFont?.pointSize ?? 0, 20, accuracy: 0.01)
        XCTAssertTrue(italicFont?.fontDescriptor.symbolicTraits.contains(.italic) == true)
    }

    // MARK: Rendered blocks

    /// A loading embed's placeholder is not reported as the block's height: it would
    /// replace the remembered height, so the text below would jump while the embed loads.
    func testLoadingEmbedDoesNotReportItsPlaceholderHeight() async throws {
        let block = try XCTUnwrap(LivePreviewBlockScanner.blocks(in: "![[photo.png]]\n" as NSString).first)
        let lookupGate = UiStylingLookupGate()
        let environment = LivePreviewEnvironment(root: URL(fileURLWithPath: "/Vault"), textSize: 17, colorsEnabled: true, paletteHexByName: [:], drawingVersion: 0,
                                                 resolve: { _, _ in await lookupGate.waitForRelease() }, open: { _ in }, follow: { _, _ in }, updateProperties: nil)
        var reportedHeights: [CGFloat] = []
        let widget = LivePreviewWidgetView(block: block, environment: environment, revealSource: {}, reportHeight: { height in reportedHeights.append(height) })
        let hostingView = NSHostingView(rootView: widget)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(reportedHeights, [], "the loading placeholder's height")
        await lookupGate.release()
        for _ in 0..<40 where reportedHeights.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
            hostingView.layoutSubtreeIfNeeded()
        }
        XCTAssertGreaterThan(reportedHeights.last ?? 0, 1, "the height once the embed is known to be missing")
        window.contentView = nil
    }

    func testRenderedBlocksReportEmbedsTheVaultDoesNotHave() async throws {
        let imagePath = try VaultPath("photo.png")
        func environment(resolving resolvedPath: VaultPath?) -> LivePreviewEnvironment {
            LivePreviewEnvironment(root: URL(fileURLWithPath: "/Vault"), textSize: 17, colorsEnabled: true, paletteHexByName: [:], drawingVersion: 0,
                                   resolve: { _, _ in resolvedPath }, open: { _ in }, follow: { _, _ in }, updateProperties: nil)
        }
        let table = "| a |\n| - |\n| ![[photo.png]] |\n"
        let unresolved = await LivePreviewText.preparedResolvingEmbeds(table, environment: environment(resolving: nil))
        XCTAssertTrue(unresolved.hasUnresolvedEmbeds)
        XCTAssertTrue(unresolved.markdown.contains("![[photo.png]]"))
        let resolved = await LivePreviewText.preparedResolvingEmbeds(table, environment: environment(resolving: imagePath))
        XCTAssertFalse(resolved.hasUnresolvedEmbeds)
        XCTAssertFalse(resolved.markdown.contains("![["))
        let plain = await LivePreviewText.preparedResolvingEmbeds("| a |\n| - |\n| b |\n", environment: environment(resolving: nil))
        XCTAssertFalse(plain.hasUnresolvedEmbeds)
    }
}

/// Holds embed lookups until the test releases them; they then find nothing.
private actor UiStylingLookupGate {
    private var isReleased = false
    private var waitingLookups: [CheckedContinuation<Void, Never>] = []

    func waitForRelease() async -> VaultPath? {
        if !isReleased {
            await withCheckedContinuation { continuation in waitingLookups.append(continuation) }
        }
        return nil
    }

    func release() {
        isReleased = true
        for lookup in waitingLookups { lookup.resume() }
        waitingLookups.removeAll()
    }
}
