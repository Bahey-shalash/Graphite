#if os(macOS)
import AppKit
import XCTest
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// Changes other groups handed to the editor, reading view, and Live Preview files.
@MainActor
final class UiEditorAreaHandoffTests: XCTestCase {
    private var vault: URL!

    override func setUp() async throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("EditorAreaVault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: vault)
    }

    private func write(_ text: String, to path: String) throws {
        let location = vault.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: location)
    }

    private func makeSession(text: String) async throws -> MarkdownSession {
        try write(text, to: "Note.md")
        let store = VaultStore(root: vault)
        let notePath = try VaultPath("Note.md")
        return try MarkdownSession(path: notePath, snapshot: try await store.read(notePath), store: store, didSave: { _ in })
    }

    /// The links of rendered text, in order, with their text.
    private func links(in markdown: String) throws -> [(text: String, location: URL)] {
        let attributed = try ObsidianMarkdownParser(baseURL: vault, textSize: 17).attributedString(for: markdown)
        return attributed.runs.compactMap { run in run.link.map { location in (String(attributed[run.range].characters), location) } }
    }

    private func headingAnchors(_ blocks: [RenderedBlock]) -> [String?] {
        blocks.compactMap { block in
            if case .heading(_, _, _, let anchor) = block { return .some(anchor) }
            return nil
        }
    }

    // MARK: Headings that read the same (F511)

    func testOutlineNumbersHeadingsThatReadTheSameAndTheEditorFindsEach() {
        let body = "## Notes\nFirst\n## Other\n## notes\nSecond\n"
        let outline = NoteLinksInspector.outlineHeadings(in: body)
        XCTAssertEqual(outline.map(\.occurrence), [0, 0, 1])
        let second = outline[2]
        let request = HeadingScrollRequest(anchor: second.anchor, occurrence: second.occurrence)
        XCTAssertEqual(HeadingLocator.lineLocation(ofHeadingWithAnchor: request.anchor, occurrence: request.occurrence, in: body as NSString),
                       (body as NSString).range(of: "## notes").location)
    }

    func testReadingViewScrollsToTheRequestedOccurrenceOfAHeading() async throws {
        let index = try VaultIndex(databaseURL: vault.appendingPathComponent(".index.sqlite"))
        let source = "## Notes\nFirst\n\n> [!note] Aside\n> ## Notes\n\n## Notes\nSecond\n"
        let build = try await ReadingViewBuilder().build(source: source, note: try VaultPath("Note.md"), root: vault, index: index, configuration: ReadingConfiguration())
        let anchor = NotePreviewDocument.anchor(forHeading: "Notes")
        let numberedTarget = HeadingScrollRequest.readingScrollTarget(anchor: anchor, occurrence: 1)
        // The heading in the callout is not in the outline, so the note's second heading
        // outside callouts is numbered 1.
        XCTAssertEqual(headingAnchors(build.blocks), [anchor, numberedTarget])
        XCTAssertEqual(HeadingScrollRequest(anchor: anchor).readingScrollTarget(in: build.blocks), anchor)
        XCTAssertEqual(HeadingScrollRequest(anchor: anchor, occurrence: 1).readingScrollTarget(in: build.blocks), numberedTarget)
        XCTAssertEqual(HeadingScrollRequest(anchor: anchor, occurrence: 4).readingScrollTarget(in: build.blocks), anchor,
                       "An occurrence the note no longer has shows the first heading")
    }

    // MARK: Queued insertions (F179)

    func testEveryQueuedInsertionIsAppliedInOneEditorUpdate() async throws {
        let text = "Intro\n"
        let session = try await makeSession(text: text)
        let coordinator = NativeMarkdownEditor.Coordinator(session: session, configuration: EditorConfiguration())
        let scrollView = MarkdownMacTextView.scrollableTextView()
        let textView = try XCTUnwrap(scrollView.documentView as? MarkdownMacTextView)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.string = text
        textView.delegate = coordinator
        coordinator.connect(textView)
        session.isEditorAttached = true
        let end = NSRange(location: (text as NSString).length, length: 0)
        session.insertBlock("![[First.png]]", at: end)
        session.insertBlock("![[Second.png]]", at: end)

        XCTAssertTrue(coordinator.applyPendingInsertions(to: textView))
        XCTAssertNil(session.pendingInsertion)
        let result = textView.string as NSString
        XCTAssertLessThan(result.range(of: "![[First.png]]").location, result.range(of: "![[Second.png]]").location, result as String)
        XCTAssertNotEqual(result.range(of: "![[Second.png]]").location, NSNotFound, result as String)
        XCTAssertEqual(session.text, result as String)
        XCTAssertFalse(coordinator.applyPendingInsertions(to: textView), "Nothing is left to apply")
    }

    // MARK: Vault tab size (F326)

    func testOutdentUsesTheVaultsTabSizeForSpaceIndentedLines() throws {
        let text = "- Parent\n    - Child\n" as NSString
        let childLine = NSRange(location: text.range(of: "- Child").location, length: 0)
        let outdented = try XCTUnwrap(MarkdownEditing.edit(for: .outdent, in: text, selection: childLine, indentUnit: "\t", tabSize: 2))
        XCTAssertEqual(text.replacingCharacters(in: outdented.range, with: outdented.replacement), "- Parent\n  - Child\n")

        var settings = ObsidianSettings()
        settings.tabSize = 2
        XCTAssertEqual(EditingBehavior(settings: settings).tabSize, 2)
    }

    // MARK: Link completion keeps a written alias (F59)

    func testChosenSuggestionKeepsTheAliasAlreadyWritten() throws {
        let text = "See [[Nte|my alias]] here" as NSString
        let cursor = text.range(of: "Nte").location + 2
        guard case .link(let query)? = LinkCompletion.context(in: text, cursor: cursor) else { return XCTFail("No link query") }
        let choice = CompletionProvider.LinkChoice(wikilinkTarget: "Note", markdownPath: "Note.md", fragment: nil, label: "Note")
        let wikilink = CompletionProvider.linkEdit(query: query, choice: choice, usesWikilinks: true)
        XCTAssertEqual(text.replacingCharacters(in: wikilink.range, with: wikilink.replacement), "See [[Note|my alias]] here")
        let markdownLink = CompletionProvider.linkEdit(query: query, choice: choice, usesWikilinks: false)
        XCTAssertEqual(text.replacingCharacters(in: markdownLink.range, with: markdownLink.replacement), "See [my alias](Note.md) here")

        var aliasedChoice = choice
        aliasedChoice.alias = "Chosen"
        let replaced = CompletionProvider.linkEdit(query: query, choice: aliasedChoice, usesWikilinks: true)
        XCTAssertEqual(text.replacingCharacters(in: replaced.range, with: replaced.replacement), "See [[Note|Chosen]] here")
    }

    // MARK: Setext headings restyle their neighbor (F330)

    func testEditingASetextUnderlineRestylesTheTitleAboveIt() {
        let styler = MarkdownTextStyler(configuration: EditorConfiguration(), accentColor: .controlAccentColor)
        let textStorage = NSTextStorage(string: "Title\n===\nText")
        styler.applyStyles(to: textStorage, editedRange: NSRange(location: 0, length: 0), restyleEverything: true, revealedRange: nil, concealedBlocks: [])
        let headingFont = textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertGreaterThan(headingFont?.pointSize ?? 0, styler.baseFont.pointSize, "The title is a heading at first")

        textStorage.replaceCharacters(in: NSRange(location: 8, length: 1), with: "x")
        styler.applyStyles(to: textStorage, editedRange: NSRange(location: 8, length: 1), restyleEverything: false, revealedRange: nil, concealedBlocks: [])
        let titleFont = textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(titleFont?.pointSize ?? 0, styler.baseFont.pointSize, accuracy: 0.01, "The title is plain text once its underline is gone")
    }

    // MARK: Declared property types (F71, F222)

    func testDeclaredPropertyTypesReachReadingViewAndPropertyEdits() async throws {
        try write(#"{"types":{"code":"text"}}"#, to: ".obsidian/types.json")
        let source = "---\ncode: 007\ncount: 3\n---\nBody\n"
        let session = try await makeSession(text: source)
        await session.loadDeclaredPropertyTypes()
        XCTAssertEqual(session.declaredPropertyTypes, ["code": .text])

        let index = try VaultIndex(databaseURL: vault.appendingPathComponent(".index.sqlite"))
        var configuration = ReadingConfiguration()
        configuration.declaredPropertyTypes = session.declaredPropertyTypes
        let build = try await ReadingViewBuilder().build(source: source, note: session.path, root: vault, index: index, configuration: configuration)
        guard case .properties(let properties)? = build.blocks.first else { return XCTFail("No properties block") }
        XCTAssertEqual(properties.first { property in property.key == "code" }?.value, .text("007"))

        // Changing another property keeps the declared text as written.
        let edited = properties.map { property in property.key == "count" ? NoteProperty(key: "count", value: .number(4)) : property }
        session.replaceProperties(edited)
        XCTAssertEqual(session.text, "---\ncode: 007\ncount: 4\n---\nBody\n")

        var otherTypes = configuration
        otherTypes.declaredPropertyTypes = [:]
        XCTAssertNotEqual(configuration.hashValueForReload, otherTypes.hashValueForReload, "A change of types builds the note again")
    }

    func testLivePreviewBlocksAreRebuiltWhenDeclaredTypesChange() {
        func environment(declaring declaredTypes: [String: PropertyType]) -> LivePreviewEnvironment {
            var environment = LivePreviewEnvironment(root: vault, textSize: 17, colorsEnabled: true, paletteHexByName: [:], drawingVersion: 0,
                                                     resolve: { _, _ in nil }, open: { _ in }, follow: { _, _ in }, updateProperties: { _ in })
            environment.declaredPropertyTypes = declaredTypes
            return environment
        }
        XCTAssertNotEqual(LivePreviewWidgetSignature(environment: environment(declaring: [:]), accentHex: "", notePath: "Note.md"),
                          LivePreviewWidgetSignature(environment: environment(declaring: ["code": .text]), accentHex: "", notePath: "Note.md"))
    }

    // MARK: Live Preview links stay whole (F191)

    func testLivePreviewLinksKeepUnbalancedParenthesesAndTrailingBackslashes() throws {
        let prepared = LivePreviewText.prepared("[[Report (draft]] and [[Note|C:\\]] end", colorsEnabled: false, paletteHexByName: [:])
        let renderedLinks = try links(in: prepared)
        XCTAssertEqual(renderedLinks.map(\.text), ["Report (draft", "C:\\"])
        XCTAssertEqual(renderedLinks.compactMap { link in GraphiteOpenLink.target(of: link.location)?.target }, ["Report (draft", "Note"])
    }

    func testLivePreviewImageNamedWithAParenthesisKeepsItsWholeLocation() async throws {
        let imagePath = try VaultPath("Scan 2) final.png")
        let environment = LivePreviewEnvironment(root: vault, textSize: 17, colorsEnabled: false, paletteHexByName: [:], drawingVersion: 0,
                                                 resolve: { _, _ in imagePath }, open: { _ in }, follow: { _, _ in }, updateProperties: nil)
        let preparation = await LivePreviewText.preparedResolvingEmbeds("| a |\n| - |\n| ![[Scan 2) final.png]] |\n", environment: environment)
        let attributed = try AttributedString(markdown: preparation.markdown)
        XCTAssertEqual(attributed.runs.compactMap(\.imageURL).map(\.lastPathComponent), ["Scan 2) final.png"], preparation.markdown)
        XCTAssertFalse(String(attributed.characters).contains("final.png"), preparation.markdown)
    }

    // MARK: A dropped link moved by the pane still answers its drop (F671)

    /// The pane moves a dropped item's range past typing made while its link was prepared;
    /// the editor must still recognize the drop it answers, or that stale request would
    /// later capture another item dropped at the same place.
    func testInsertionMovedByThePaneAnswersItsDrop() throws {
        let textWhenDropped = "Some text here"
        var history = CharacterEditHistory()
        var pendingRequests = PendingInsertionRequests()
        let dropRequest = InsertionRequest(range: NSRange(location: 10, length: 0), revision: history.revision)
        pendingRequests.remember(dropRequest)

        let typedText = "New. "
        let currentText = typedText + textWhenDropped
        history.record(CharacterEdit(editedRange: NSRange(location: 0, length: (typedText as NSString).length), changeInLength: (typedText as NSString).length))
        let rangeMovedByPane = try XCTUnwrap(WorkspaceModel.insertionRange(dropRequest.range, chosenIn: textWhenDropped, currentText: currentText))
        XCTAssertEqual(rangeMovedByPane, NSRange(location: 15, length: 0))

        let answeredRequest = try XCTUnwrap(pendingRequests.take(preparedFor: rangeMovedByPane, in: history))
        XCTAssertEqual(answeredRequest.requested, dropRequest)
        XCTAssertEqual(answeredRequest.currentTarget(in: history), rangeMovedByPane, "The link goes where the pane put it")
        XCTAssertEqual(pendingRequests.count, 0)

        // A later drop at the old place answers only its own request.
        let laterDrop = InsertionRequest(range: dropRequest.range, revision: history.revision)
        pendingRequests.remember(laterDrop)
        XCTAssertEqual(pendingRequests.take(preparedFor: laterDrop.range, in: history)?.currentTarget(in: history), laterDrop.range)
    }

    // MARK: Reading view build kept by the session (P11)

    func testSessionKeepsOneReadingBuildCacheForItsNote() async throws {
        let session = try await makeSession(text: "Body\n")
        XCTAssertTrue(session.readingBlocksCache === session.readingBlocksCache)
        let key = ReadingBuildKey(source: "Body\n", path: session.path, root: vault, configuration: ReadingConfiguration(), dependsOnIndex: false)
        session.readingBlocksCache.lastBuild = ReadingBlocksCache.Build(key: key, blocks: [], hasMissingEmbeds: false)
        XCTAssertNotNil(session.readingBlocksCache.lastBuild, "The build outlives the reading view that made it")
    }
}
#endif
