#if os(iOS)
import XCTest
import SwiftUI
import GraphiteApple
import GraphiteCore
import GraphiteIndex
import PencilKit
import PDFKit
@testable import GraphiteUI

/// Undo and redo across tab switches, tab moves, and reading view, in the hosted workspace.
@MainActor
final class EditingContinuityTests: XCTestCase {
    private var window: UIWindow?
    private var vaultDirectory: URL?

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        if let vaultDirectory { try? FileManager.default.removeItem(at: vaultDirectory) }
        vaultDirectory = nil
    }

    func testSavingAQueuedInsertionUsesTheEditorsUndoHistory() async throws {
        let workspace = try await makeWorkspace(notes: ["Lecture.md": "Lecture.\n"])
        let lectureTab = try await openTab("Lecture.md", in: workspace, placement: .currentTab)
        let controller = try host(workspace)
        let session = try XCTUnwrap(workspace.document(for: lectureTab).markdownSession)
        session.viewMode = .source
        let editor = try await visibleEditor(in: controller, showing: session)
        editor.becomeFirstResponder()
        session.insert("![[Recording.m4a]]", at: NSRange(location: (session.text as NSString).length, length: 0))
        XCTAssertNotNil(session.pendingInsertion)
        try await session.save()
        XCTAssertNil(session.pendingInsertion)
        XCTAssertEqual(session.text, "Lecture.\n![[Recording.m4a]]")
        let savedNote = try Data(contentsOf: try XCTUnwrap(vaultDirectory).appendingPathComponent("Lecture.md"))
        XCTAssertEqual(String(decoding: savedNote, as: UTF8.self), session.text)
        XCTAssertTrue(editor.undoManager?.canUndo == true)
        editor.undoManager?.undo()
        try await waitUntil { session.text == "Lecture.\n" }
    }

    func testUndoSurvivesSwitchingTabsAndStaysWithItsOwnNote() async throws {
        let workspace = try await makeWorkspace(notes: ["Alpha.md": "Alpha notes.\n", "Beta.md": "Beta notes.\n"])
        let alphaTab = try await openTab("Alpha.md", in: workspace, placement: .currentTab)
        let controller = try host(workspace)
        let alphaSession = try XCTUnwrap(workspace.document(for: alphaTab).markdownSession)
        alphaSession.viewMode = .source
        let alphaEditor = try await visibleEditor(in: controller, showing: alphaSession)
        try await type(" First alpha edit.", into: alphaEditor, session: alphaSession)

        let betaTab = try await openTab("Beta.md", in: workspace, placement: .newTab)
        let betaSession = try XCTUnwrap(workspace.document(for: betaTab).markdownSession)
        betaSession.viewMode = .source
        let betaEditor = try await visibleEditor(in: controller, showing: betaSession)
        XCTAssertFalse(betaEditor === alphaEditor)
        XCTAssertFalse(betaEditor.undoManager?.canUndo == true, "A note opened fresh has no history from another note.")
        try await type(" Beta edit.", into: betaEditor, session: betaSession)

        workspace.activateTab(alphaTab)
        let returnedAlphaEditor = try await visibleEditor(in: controller, showing: alphaSession)
        XCTAssertTrue(returnedAlphaEditor === alphaEditor, "The hidden note's text view comes back with the tab.")
        XCTAssertTrue(workspace.markdownEditorRetention.hasHiddenEditor(for: betaSession))
        returnedAlphaEditor.undoManager?.undo()
        try await waitUntil { alphaSession.text == "Alpha notes.\n" }
        XCTAssertEqual(betaSession.text, "Beta notes.\n Beta edit.", "Undo in one note never changes another.")
        returnedAlphaEditor.undoManager?.redo()
        try await waitUntil { alphaSession.text == "Alpha notes.\n First alpha edit." }

        workspace.activateTab(betaTab)
        let returnedBetaEditor = try await visibleEditor(in: controller, showing: betaSession)
        XCTAssertTrue(returnedBetaEditor === betaEditor)
        returnedBetaEditor.undoManager?.undo()
        try await waitUntil { betaSession.text == "Beta notes.\n" }
        XCTAssertEqual(alphaSession.text, "Alpha notes.\n First alpha edit.")
        attachScreenshot(named: "Returned tab after undo")
    }

    /// A note opened again is styled before its text view has a width, with estimated
    /// heights for its rendered blocks. When the properties view then reported the height an
    /// earlier editor had measured, the estimate stayed in the text: the embedded PDF below
    /// was placed hundreds of points lower, and a tap where it had been landed on the text.
    func testRenderedBlocksOfANoteOpenedAgainAreWhereTheyWereBefore() async throws {
        let frontmatter = "---\ntitle: Static Logic\ncourse: EE-330\ntags:\n  - CMOS\n  - digital-design\n  - static-logic\n  - logic-families\n"
            + "  - noise-margins\n  - transistor-sizing\nrelated:\n  - \"[[Other]]\"\n---\n"
        let workspace = try await makeWorkspace(notes: ["Lecture.md": frontmatter + "\n![[Slides.pdf]]\n\nEnd.\n", "Other.md": "Other.\n"])
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .ruled), pageCount: 2)
            .write(to: try XCTUnwrap(vaultDirectory).appendingPathComponent("Slides.pdf"))
        _ = try await openTab("Lecture.md", in: workspace, placement: .currentTab)
        let controller = try host(workspace)
        let firstEditor = try await visibleEditor(in: controller, showing: try XCTUnwrap(workspace.markdownSession))
        try await waitUntil { self.renderedBlockViews(in: firstEditor).count == 2 }
        // Let the blocks report their heights and the text settle around them.
        try await Task.sleep(for: .milliseconds(600))
        firstEditor.layoutIfNeeded()
        let embedTopBefore = try XCTUnwrap(renderedBlockViews(in: firstEditor).map(\.frame.minY).max())

        _ = try await openTab("Other.md", in: workspace, placement: .currentTab)
        _ = try await visibleEditor(in: controller, showing: try XCTUnwrap(workspace.markdownSession))
        _ = try await openTab("Lecture.md", in: workspace, placement: .currentTab)
        let secondEditor = try await visibleEditor(in: controller, showing: try XCTUnwrap(workspace.markdownSession))
        try await waitUntil { self.renderedBlockViews(in: secondEditor).count == 2 }
        try await Task.sleep(for: .milliseconds(600))
        secondEditor.layoutIfNeeded()
        let embedTopAfter = try XCTUnwrap(renderedBlockViews(in: secondEditor).map(\.frame.minY).max())
        XCTAssertEqual(embedTopAfter, embedTopBefore, accuracy: 1, "The embedded PDF is where it was when the note was open before.")
        attachScreenshot(named: "Note with properties and an embedded PDF opened again")
    }

    func testUndoSurvivesMovingATabToTheOtherSide() async throws {
        let workspace = try await makeWorkspace(notes: ["Lecture.md": "Lecture.\n", "Slides.md": "Slides.\n"])
        let lectureTab = try await openTab("Lecture.md", in: workspace, placement: .currentTab)
        _ = try await openTab("Slides.md", in: workspace, placement: .otherGroup)
        let controller = try host(workspace)
        let lectureSession = try XCTUnwrap(workspace.document(for: lectureTab).markdownSession)
        lectureSession.viewMode = .source
        workspace.focusGroup(try XCTUnwrap(workspace.layout.group(containing: lectureTab)?.id))
        let editor = try await visibleEditor(in: controller, showing: lectureSession)
        let widthBeforeMove = editor.bounds.width
        try await type(" Moved note edit.", into: editor, session: lectureSession)

        let groupBeforeMove = workspace.layout.group(containing: lectureTab)?.id
        workspace.moveTabToOtherGroup(lectureTab)
        XCTAssertNotEqual(workspace.layout.group(containing: lectureTab)?.id, groupBeforeMove)
        XCTAssertTrue(workspace.layout.groups.contains { group in group.activeTabID == lectureTab })
        let movedEditor = try await visibleEditor(in: controller, showing: lectureSession)
        XCTAssertTrue(movedEditor === editor, "The moved tab keeps its text view and history.")
        XCTAssertGreaterThan(widthBeforeMove, 0)
        movedEditor.undoManager?.undo()
        try await waitUntil { lectureSession.text == "Lecture.\n" }
        movedEditor.undoManager?.redo()
        try await waitUntil { lectureSession.text == "Lecture.\n Moved note edit." }
    }

    /// SwiftUI can make a view of a note and dismantle it again while an earlier view of
    /// the note stays, as it did when the split closed in the app; the note's pane was
    /// then left empty. The text view belongs in the view that stays.
    func testTextViewEndsInTheViewThatStaysWhenANewerViewIsDismantled() async throws {
        let workspace = try await makeWorkspace(notes: ["Lecture.md": "Lecture.\n"])
        let lectureTab = try await openTab("Lecture.md", in: workspace, placement: .currentTab)
        let document = workspace.document(for: lectureTab)
        let lectureSession = try XCTUnwrap(document.markdownSession)
        let shownViews = ShownEditorViews()
        let controller = UIHostingController(rootView: EditorViews(shownViews: shownViews, session: lectureSession,
                                                                   retention: workspace.markdownEditorRetention, owner: document))
        try present(controller)
        let editor = try await visibleEditor(in: controller, showing: lectureSession)
        try await type(" Edited in the first view.", into: editor, session: lectureSession)
        editor.resignFirstResponder()

        // The view that stays and a passing view are made as the first view goes.
        shownViews.showsViewThatStays = true
        shownViews.showsPassingView = true
        shownViews.showsFirstView = false
        try await waitUntil { self.containers(in: controller).count == 2 && self.editors(in: controller).contains { shownEditor in shownEditor === editor } }
        shownViews.showsPassingView = false
        try await waitUntil { self.containers(in: controller).count == 1 }

        try await waitUntil { self.editors(in: controller).contains { shownEditor in shownEditor === editor } && editor.bounds.width > 0 }
        XCTAssertTrue(editor.superview === containers(in: controller).first, "The view that stays shows the note's text view.")
        XCTAssertFalse(workspace.markdownEditorRetention.hasHiddenEditor(for: lectureSession), "The note is on screen, not kept for later.")
        XCTAssertTrue(lectureSession.isEditorAttached)
        editor.undoManager?.undo()
        try await waitUntil { lectureSession.text == "Lecture.\n" }
    }

    /// The split opening and closing in the hosted workspace, where the note's view is
    /// made again each time.
    func testNoteStaysOnScreenWhenTheSplitOpensAndCloses() async throws {
        let workspace = try await makeWorkspace(notes: ["Lecture.md": "# Lecture\n\nA paragraph.\n\n- one\n- two\n"])
        let lectureTab = try await openTab("Lecture.md", in: workspace, placement: .currentTab)
        let controller = try host(workspace)
        let lectureSession = try XCTUnwrap(workspace.document(for: lectureTab).markdownSession)
        let editor = try await visibleEditor(in: controller, showing: lectureSession)
        try await type("Edited before the split.", into: editor, session: lectureSession)
        editor.resignFirstResponder()
        let widthBeforeSplit = editor.bounds.width

        try await openAndCloseSplit(beside: lectureTab, in: workspace, controller: controller, editor: editor, widthBeforeSplit: widthBeforeSplit)
        XCTAssertFalse(workspace.markdownEditorRetention.hasHiddenEditor(for: lectureSession), "The note is on screen, not kept for later.")
        editor.undoManager?.undo()
        try await waitUntil { lectureSession.text == "# Lecture\n\nA paragraph.\n\n- one\n- two\n" }
        attachScreenshot(named: "Note after the split closed")
    }

    /// With the cursor in the note, the same steps used to take the keyboard from the text
    /// view in the middle of SwiftUI's update.
    func testNoteStaysOnScreenWhenTheSplitOpensAndClosesWhileEditing() async throws {
        let workspace = try await makeWorkspace(notes: ["Lecture.md": "# Lecture\n\nA paragraph.\n"])
        let lectureTab = try await openTab("Lecture.md", in: workspace, placement: .currentTab)
        let controller = try host(workspace)
        let lectureSession = try XCTUnwrap(workspace.document(for: lectureTab).markdownSession)
        let editor = try await visibleEditor(in: controller, showing: lectureSession)
        let widthBeforeSplit = editor.bounds.width
        let heightBeforeSplit = editor.bounds.height

        editor.beginEditing()
        XCTAssertTrue(editor.isFirstResponder)
        try await openAndCloseSplit(beside: lectureTab, in: workspace, controller: controller, editor: editor, widthBeforeSplit: widthBeforeSplit) {
            editor.beginEditing()
        }
        // Once editing has ended, no room is left for a keyboard that went away.
        try await waitUntil { editor.isFirstResponder || abs(editor.bounds.height - heightBeforeSplit) < 1 }
        attachScreenshot(named: "Note after the split closed while editing")
    }

    /// The note's text view is made with its own initial values and on TextKit 2. Made by
    /// UIKit's `UITextView(usingTextLayoutManager:)`, its properties were left zero: Live
    /// Preview's column started full width, and the first array among them crashed the
    /// view's first layout (Read Aloud's highlights, 2026-10-11).
    func testNotesTextViewStartsWithItsInitialValuesOnTextKit2() {
        let textView = MarkdownTextView()
        XCTAssertTrue(textView.usesReadableLineLength)
        XCTAssertNotNil(textView.textLayoutManager)
        textView.frame = CGRect(x: 0, y: 0, width: 600, height: 400)
        textView.layoutIfNeeded()
    }

    /// A change around the note's view, as when the window title stops or starts being
    /// editable with the width class, makes SwiftUI dismantle the note's view and make a new
    /// one. With the cursor in the note, the text view moves to the new view with its edit.
    func testNoteMovesToItsNewViewWhenTheViewAroundItChangesWhileEditing() async throws {
        let workspace = try await makeWorkspace(notes: ["Lecture.md": "# Lecture\n\nA paragraph.\n"])
        let lectureTab = try await openTab("Lecture.md", in: workspace, placement: .currentTab)
        let document = workspace.document(for: lectureTab)
        let lectureSession = try XCTUnwrap(document.markdownSession)
        let surroundings = EditorSurroundings()
        let controller = UIHostingController(rootView: SurroundedEditor(surroundings: surroundings, session: lectureSession,
                                                                        retention: workspace.markdownEditorRetention, owner: document))
        try present(controller)
        let editor = try await visibleEditor(in: controller, showing: lectureSession)
        try await type(" Edited.", into: editor, session: lectureSession)
        XCTAssertTrue(editor.isFirstResponder)
        let firstContainer = try XCTUnwrap(editor.superview)

        surroundings.hasEditableTitle.toggle()
        try await waitUntil { self.containers(in: controller).count == 1 && editor.superview === self.containers(in: controller).first
            && editor.superview !== firstContainer && editor.bounds.width > 0 }
        XCTAssertTrue(lectureSession.isEditorAttached)
        XCTAssertFalse(workspace.markdownEditorRetention.hasHiddenEditor(for: lectureSession), "The note is on screen, not kept for later.")
        editor.undoManager?.undo()
        try await waitUntil { lectureSession.text == "# Lecture\n\nA paragraph.\n" }
        attachScreenshot(named: "Note in its new view")
    }

    /// The steps an iPad took on 2026-10-10, one by one: something inside the note's text
    /// view holds the keyboard when SwiftUI dismantles the note's view, and giving the
    /// keyboard up lays the window out at once, which makes the note's next view in the
    /// middle of that dismantling. Moving the text view into it there, while UIKit was still
    /// removing it from the old view, left SwiftUI updating without end. The new view gets the
    /// text view once the old one has let it go.
    func testAViewMadeWhileTheNoteLeavesItsViewGetsTheTextView() async throws {
        let workspace = try await makeWorkspace(notes: ["Lecture.md": "# Lecture\n\nA paragraph.\n"])
        let lectureTab = try await openTab("Lecture.md", in: workspace, placement: .currentTab)
        let document = workspace.document(for: lectureTab)
        let lectureSession = try XCTUnwrap(document.markdownSession)
        let controller = UIHostingController(rootView: EditorViews(shownViews: ShownEditorViews(), session: lectureSession,
                                                                   retention: workspace.markdownEditorRetention, owner: document))
        try present(controller)
        let editor = try await visibleEditor(in: controller, showing: lectureSession)
        let coordinator = try XCTUnwrap(editor.delegate as? NativeMarkdownEditor.Coordinator)
        let firstContainer = try XCTUnwrap(editor.superview as? MarkdownEditorContainerView)
        let field = FieldThatLaysOutAsItResigns(frame: CGRect(x: 0, y: 0, width: 120, height: 32))
        editor.addSubview(field)
        XCTAssertTrue(field.becomeFirstResponder())
        let nextContainer = MarkdownEditorContainerView(frame: firstContainer.frame)
        field.didResign = { [weak field] in
            field?.didResign = {}
            controller.view.addSubview(nextContainer)
            coordinator.viewWasMade(with: nextContainer)
        }

        coordinator.viewWasDismantled(with: firstContainer)
        XCTAssertFalse(field.isFirstResponder)
        XCTAssertTrue(editor.superview === nextContainer, "The view made meanwhile shows the note.")
        XCTAssertTrue(lectureSession.isEditorAttached)
        XCTAssertFalse(workspace.markdownEditorRetention.hasHiddenEditor(for: lectureSession), "The note is on screen, not kept for later.")
    }

    func testUndoSurvivesReadingViewAndReturningToWrite() async throws {
        let workspace = try await makeWorkspace(notes: ["Reading.md": "# Reading\n\nA paragraph.\n"])
        let tab = try await openTab("Reading.md", in: workspace, placement: .currentTab)
        let controller = try host(workspace)
        let session = try XCTUnwrap(workspace.document(for: tab).markdownSession)
        session.viewMode = .source
        let editor = try await visibleEditor(in: controller, showing: session)
        try await type("Added while writing.", into: editor, session: session)

        session.viewMode = .reading
        try await waitUntil { self.editors(in: controller).isEmpty }
        XCTAssertTrue(workspace.markdownEditorRetention.hasHiddenEditor(for: session))
        session.viewMode = .source
        let returnedEditor = try await visibleEditor(in: controller, showing: session)
        XCTAssertTrue(returnedEditor === editor)
        returnedEditor.undoManager?.undo()
        try await waitUntil { session.text == "# Reading\n\nA paragraph.\n" }
    }

    func testTextInsertedWhileHiddenIsAdoptedAsAnUndoableEdit() async throws {
        let workspace = try await makeWorkspace(notes: ["Quotes.md": "Quotes:\n", "Other.md": "Other.\n"])
        let quotesTab = try await openTab("Quotes.md", in: workspace, placement: .currentTab)
        let controller = try host(workspace)
        let quotesSession = try XCTUnwrap(workspace.document(for: quotesTab).markdownSession)
        quotesSession.viewMode = .source
        let editor = try await visibleEditor(in: controller, showing: quotesSession)
        try await type("Typed first.", into: editor, session: quotesSession)
        let otherTab = try await openTab("Other.md", in: workspace, placement: .newTab)
        let otherSession = try XCTUnwrap(workspace.document(for: otherTab).markdownSession)
        otherSession.viewMode = .source
        _ = try await visibleEditor(in: controller, showing: otherSession)

        // A quote sent from a PDF while its note is hidden goes into the note's text.
        quotesSession.insert(" Inserted while hidden.")
        XCTAssertEqual(quotesSession.text, "Quotes:\nTyped first. Inserted while hidden.")
        workspace.activateTab(quotesTab)
        let returnedEditor = try await visibleEditor(in: controller, showing: quotesSession)
        XCTAssertTrue(returnedEditor === editor)
        try await waitUntil { returnedEditor.text == "Quotes:\nTyped first. Inserted while hidden." }
        returnedEditor.undoManager?.undo()
        try await waitUntil { quotesSession.text == "Quotes:\nTyped first." }
        returnedEditor.undoManager?.undo()
        try await waitUntil { quotesSession.text == "Quotes:\n" }
    }

    func testHiddenEditorsAreBoundedAndAReleasedEditorKeepsItsText() async throws {
        let names = (1...5).map { number in "Note \(number).md" }
        let workspace = try await makeWorkspace(notes: Dictionary(uniqueKeysWithValues: names.map { name in (name, "\(name)\n") }))
        let controller = try host(workspace)
        var tabs: [UUID] = []
        var editorsByTab: [UUID: MarkdownTextView] = [:]
        for name in names {
            let tab = try await openTab(name, in: workspace, placement: tabs.isEmpty ? .currentTab : .newTab)
            let session = try XCTUnwrap(workspace.document(for: tab).markdownSession)
            session.viewMode = .source
            let editor = try await visibleEditor(in: controller, showing: session)
            try await type("Edited.", into: editor, session: session)
            tabs.append(tab)
            editorsByTab[tab] = editor
        }
        let limit = MarkdownEditorRetention.standardLimits.maximumHiddenEditorCount
        XCTAssertEqual(workspace.markdownEditorRetention.hiddenEditorCount, limit)

        // The first note was hidden longest; its text view was let go of.
        let firstSession = try XCTUnwrap(workspace.document(for: tabs[0]).markdownSession)
        XCTAssertFalse(workspace.markdownEditorRetention.hasHiddenEditor(for: firstSession))
        workspace.activateTab(tabs[0])
        let recreatedEditor = try await visibleEditor(in: controller, showing: firstSession)
        XCTAssertFalse(recreatedEditor === editorsByTab[tabs[0]])
        XCTAssertEqual(recreatedEditor.text, "Note 1.md\nEdited.", "Releasing a hidden editor never loses its text.")
        XCTAssertFalse(recreatedEditor.undoManager?.canUndo == true, "Only the kept editors keep their history.")

        // The most recently hidden notes kept theirs.
        workspace.activateTab(tabs[3])
        let fourthSession = try XCTUnwrap(workspace.document(for: tabs[3]).markdownSession)
        let keptEditor = try await visibleEditor(in: controller, showing: fourthSession)
        XCTAssertTrue(keptEditor === editorsByTab[tabs[3]])
        XCTAssertLessThanOrEqual(workspace.markdownEditorRetention.hiddenEditorCount, limit)

        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        XCTAssertEqual(workspace.markdownEditorRetention.hiddenEditorCount, 0, "A memory warning lets go of every hidden editor.")
        XCTAssertTrue(editors(in: controller).first === keptEditor, "The note on screen keeps its editor.")
    }

    func testClosingATabReleasesItsKeptEditor() async throws {
        let workspace = try await makeWorkspace(notes: ["Kept.md": "Kept.\n", "Front.md": "Front.\n"])
        let keptTab = try await openTab("Kept.md", in: workspace, placement: .currentTab)
        let controller = try host(workspace)
        let keptSession = try XCTUnwrap(workspace.document(for: keptTab).markdownSession)
        keptSession.viewMode = .source
        _ = try await visibleEditor(in: controller, showing: keptSession)
        let frontTab = try await openTab("Front.md", in: workspace, placement: .newTab)
        let frontSession = try XCTUnwrap(workspace.document(for: frontTab).markdownSession)
        frontSession.viewMode = .source
        _ = try await visibleEditor(in: controller, showing: frontSession)
        XCTAssertTrue(workspace.markdownEditorRetention.hasHiddenEditor(for: keptSession))
        await workspace.closeTab(keptTab)
        XCTAssertFalse(workspace.markdownEditorRetention.hasHiddenEditor(for: keptSession))
        XCTAssertEqual(workspace.markdownEditorRetention.hiddenEditorCount, 0)
    }

    // MARK: Helpers

    // MARK: Fonts and font size (Settings › Appearance › Font)

    /// The vault's text and monospace fonts and its font size reach Live Preview, and a font
    /// changed while the note is being edited restyles it in place: the cursor stays and the
    /// rendered blocks are kept.
    func testEditorUsesTheVaultsFontsAndSizeAndKeepsTheCursorWhenTheyChange() async throws {
        let note = "# Lecture\n\nBody text with `inline code` in it.\n\n```\nlet answer = 42\n```\n\n$$x^2$$\n\nEnd.\n"
        let workspace = try await makeWorkspace(notes: ["Lecture.md": note])
        try writeAppearance(#"{"textFontFamily": "\"Bookerly\", Georgia, serif", "monospaceFontFamily": "Courier New", "baseFontSize": 20}"#)
        await workspace.reloadVaultAppearance()
        XCTAssertEqual(workspace.noteTypography.textFamily, .installed("Georgia"), "Bookerly is not on the device, so the next family of the list is used.")
        XCTAssertEqual(workspace.noteTypography.monospaceFamily, .installed("Courier New"))
        XCTAssertEqual(workspace.noteBaseFontSize, 20)

        _ = try await openTab("Lecture.md", in: workspace, placement: .currentTab)
        let controller = try hostWithTypography(workspace)
        let session = try XCTUnwrap(workspace.markdownSession)
        session.viewMode = .livePreview
        let editor = try await visibleEditor(in: controller, showing: session)
        try await waitUntil { self.renderedBlockViews(in: editor).count == 1 }
        let expectedBodySize = GraphitePreferences.noteTextSize(20, for: DynamicTypeSize(controller.traitCollection.preferredContentSizeCategory) ?? .large)
        let source = session.text as NSString
        let bodyFont = try font(at: source.range(of: "Body").location, in: editor)
        XCTAssertEqual(bodyFont.familyName, "Georgia")
        XCTAssertEqual(Double(bodyFont.pointSize), expectedBodySize, accuracy: 0.01, "20 is the size at the default text size, grown with Dynamic Type.")
        let headingFont = try font(at: source.range(of: "Lecture").location, in: editor)
        XCTAssertEqual(headingFont.familyName, "Georgia", "Headings are in the text font…")
        XCTAssertEqual(Double(headingFont.pointSize), expectedBodySize * Double(HeadingTypography.fontScale(level: 1)), accuracy: 0.01, "…at the same multiple of the text size.")
        XCTAssertEqual(try font(at: source.range(of: "inline code").location, in: editor).familyName, "Courier New")
        XCTAssertEqual(try font(at: source.range(of: "let answer").location, in: editor).familyName, "Courier New")

        // A font changed in Settings while the note is being edited.
        editor.beginEditing()
        let cursor = NSRange(location: source.range(of: "with").location, length: 0)
        editor.selectedRange = cursor
        let blockViewBefore = try XCTUnwrap(renderedBlockViews(in: editor).first)
        workspace.updateVaultAppearance { appearance in appearance.textFontFamilies = FontFamilyList(families: ["Avenir Next"]) }
        try await waitUntil { (try? self.font(at: source.range(of: "Body").location, in: editor).familyName) == "Avenir Next" }
        XCTAssertEqual(editor.selectedRange, cursor, "Restyling keeps the cursor where it was.")
        XCTAssertTrue(editor.isFirstResponder)
        XCTAssertTrue(renderedBlockViews(in: editor).contains { view in view === blockViewBefore }, "The rendered math block is kept, not built again.")
        await workspace.saveVaultAppearanceNow()
        let written = try String(contentsOf: try XCTUnwrap(vaultDirectory).appendingPathComponent(".obsidian/appearance.json"), encoding: .utf8)
        XCTAssertTrue(written.contains(#""textFontFamily": "Avenir Next""#), written)
        XCTAssertTrue(written.contains(#""monospaceFontFamily": "Courier New""#), "Unchanged keys stay as they were: \(written)")
        attachScreenshot(named: "Live Preview in the vault's fonts")
    }

    /// Reading view draws its text in the text font and its code in the monospace font, at
    /// the vault's size: the width SwiftUI gives a line is the width of the line in that font.
    func testReadingViewUsesTheVaultsTextAndMonospaceFonts() async throws {
        var typography = NoteTypography()
        typography.textFamily = .installed("Georgia")
        typography.monospaceFamily = .installed("Courier New")
        let size = 20.0
        let root = FileManager.default.temporaryDirectory
        func renderedWidth(_ markdown: String) async throws -> CGFloat {
            let measurement = MeasuredWidth()
            let controller = UIHostingController(rootView: ObsidianMarkdownText(markdown: markdown, root: root, textSize: size, navigate: { _, _ in }, scrollToHeading: { _ in })
                .environment(\.noteTypography, typography)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { geometry in geometry.size.width } action: { width in measurement.width = width }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
            try present(controller)
            try await waitUntil { measurement.width > 0 }
            // Textual lays its text out a second time once it has measured it.
            try await Task.sleep(for: .milliseconds(300))
            return measurement.width
        }
        let words = "Illustrated quietly"
        let georgiaWidth = (words as NSString).size(withAttributes: [.font: typography.textFont(ofSize: size)]).width
        let systemWidth = (words as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: size)]).width
        XCTAssertGreaterThan(abs(georgiaWidth - systemWidth), 4, "The two fonts set these words at clearly different widths.")
        let renderedWords = try await renderedWidth(words)
        XCTAssertEqual(renderedWords, georgiaWidth, accuracy: 2, "Body text is set in Georgia.")
        let code = "iiiiiiiiii"
        // Textual sets inline code at 0.94 of the text size.
        let courierWidth = (code as NSString).size(withAttributes: [.font: typography.monospaceFont(ofSize: size * 0.94)]).width
        let renderedCode = try await renderedWidth("`\(code)`")
        XCTAssertEqual(renderedCode, courierWidth, accuracy: 2, "Inline code is set in Courier New, a monospace font as wide for i as for m.")
    }

    /// Apple Pencil never takes part in the quick font size pinch, so writing or drawing
    /// with Pencil while a finger rests on the note cannot resize its text, and a pinch on a
    /// view that zooms by itself is left to that view.
    func testQuickFontSizePinchIgnoresPencilAndViewsThatZoomThemselves() async throws {
        let recognizer = QuickFontSizePinchRecognizer()
        XCTAssertFalse(recognizer.allowedTouchTypes.contains(NSNumber(value: UITouch.TouchType.pencil.rawValue)), "Pencil touches are never delivered to the pinch.")
        XCTAssertTrue(recognizer.allowedTouchTypes.contains(NSNumber(value: UITouch.TouchType.direct.rawValue)))
        XCTAssertFalse(recognizer.isEnabled, "Off until quick adjustment is turned on.")
        XCTAssertFalse(recognizer.cancelsTouchesInView, "Taps and selection under the fingers carry on.")

        let host = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        host.addGestureRecognizer(recognizer)
        let paragraph = UIView()
        host.addSubview(paragraph)
        XCTAssertTrue(QuickFontSizePinchPolicy.acceptsTouch(ofType: .direct, in: paragraph, under: host, recognizer: recognizer))
        XCTAssertFalse(QuickFontSizePinchPolicy.acceptsTouch(ofType: .pencil, in: paragraph, under: host, recognizer: recognizer))
        let canvas = PKCanvasView()
        let strokeView = UIView()
        host.addSubview(canvas); canvas.addSubview(strokeView)
        XCTAssertFalse(QuickFontSizePinchPolicy.acceptsTouch(ofType: .direct, in: strokeView, under: host, recognizer: recognizer), "A drawing canvas keeps its fingers.")
        let embeddedPDF = PDFView()
        host.addSubview(embeddedPDF)
        XCTAssertFalse(QuickFontSizePinchPolicy.acceptsTouch(ofType: .direct, in: embeddedPDF, under: host, recognizer: recognizer), "An embedded PDF zooms itself.")
        let board = UIView()
        board.addGestureRecognizer(UIPinchGestureRecognizer())
        host.addSubview(board)
        XCTAssertFalse(QuickFontSizePinchPolicy.acceptsTouch(ofType: .direct, in: board, under: host, recognizer: recognizer), "A view with its own pinch keeps it.")

        // In the editor, the pinch follows the setting.
        let workspace = try await makeWorkspace(notes: ["Lecture.md": "Text.\n"])
        _ = try await openTab("Lecture.md", in: workspace, placement: .currentTab)
        let controller = try hostWithTypography(workspace)
        let session = try XCTUnwrap(workspace.markdownSession)
        let editor = try await visibleEditor(in: controller, showing: session)
        let editorPinch = try XCTUnwrap(editor.gestureRecognizers?.compactMap { $0 as? QuickFontSizePinchRecognizer }.first)
        XCTAssertFalse(editorPinch.isEnabled)
        workspace.updateVaultAppearance { appearance in appearance.adjustsFontSizeQuickly = true }
        try await waitUntil { editorPinch.isEnabled }
        editorPinch.adjustment?.setSize(24)
        XCTAssertEqual(workspace.noteBaseFontSize, 24)
        await workspace.saveVaultAppearanceNow()
    }

    func testPinchingMovesTheSizeInWholeStepsWithinTheRange() {
        XCTAssertEqual(NoteFontSize.size(afterPinchingBy: 1.25, from: 16), 20)
        XCTAssertEqual(NoteFontSize.size(afterPinchingBy: 0.1, from: 16), 11, "Never below Apple's smallest text size.")
        XCTAssertEqual(NoteFontSize.size(afterPinchingBy: 5, from: 16), 30, "Never above Obsidian's largest.")
        XCTAssertEqual(NoteFontSize.size(afterPinchingBy: .nan, from: 16), 16)
        var progress = QuickFontSizePinchProgress()
        XCTAssertNil(progress.size(forScale: 2), "A pinch that did not begin here changes nothing.")
        progress.begin(at: 18)
        XCTAssertEqual(progress.size(forScale: 1.1), 20)
        XCTAssertEqual(progress.size(forScale: 1.2), 22, "Measured from where the pinch began, not compounded.")
    }

    /// The vault's Obsidian accent is used until an accent is chosen in Graphite.
    func testTheVaultsAccentIsUsedUntilOneIsChosenHere() async throws {
        let workspace = try await makeWorkspace(notes: [:])
        let previousChoice = workspace.preferences.chosenAccentHex
        defer { workspace.preferences.chosenAccentHex = previousChoice }
        workspace.preferences.chosenAccentHex = nil
        try writeAppearance(##"{"accentColor": "#2E8B57"}"##)
        await workspace.reloadVaultAppearance()
        XCTAssertEqual(workspace.preferences.accentHex, "#2e8b57")
        workspace.preferences.chosenAccentHex = "#e93147"
        XCTAssertEqual(workspace.preferences.accentHex, "#e93147", "A choice made in Graphite wins.")
        workspace.preferences.chosenAccentHex = nil
        XCTAssertEqual(workspace.preferences.accentHex, "#2e8b57", "Forgetting it returns to the vault's accent.")
    }

    // MARK: The vault's Obsidian theme in notes (theme Phase 1)

    /// A test theme's heading color and size and its warning callout color reach Live
    /// Preview, the reading view and callouts, and turning the setting off restores Graphite's look.
    func testEditorAndReadingViewTakeTheVaultThemesHeadingAndCalloutColors() async throws {
        let workspace = try await makeWorkspace(notes: ["Lecture.md": "# Wide heading text\n\nBody.\n\n> [!warning] Careful\n> Text.\n"])
        let previousSetting = workspace.preferences.usesVaultTheme
        defer { workspace.preferences.usesVaultTheme = previousSetting }
        workspace.preferences.usesVaultTheme = true
        let folder = try XCTUnwrap(vaultDirectory).appendingPathComponent(".obsidian/themes/Test")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(".theme-light { --h1-color: #aa0000; --h1-size: 2em; --callout-warning: 0, 128, 0; } .theme-dark { --h1-color: #ff8080; }".utf8)
            .write(to: folder.appendingPathComponent("theme.css"))
        try writeAppearance(#"{"cssTheme": "Test"}"#)
        await workspace.reloadVaultAppearance()
        await workspace.refreshVaultTheme()
        let theme = try XCTUnwrap(workspace.noteTheme, "The theme is resolved and handed to notes.")
        let lightTraits = UITraitCollection(userInterfaceStyle: .light), darkTraits = UITraitCollection(userInterfaceStyle: .dark)
        XCTAssertEqual(ThemeColor(platform: try XCTUnwrap(theme.headingColors[0]).resolvedColor(with: lightTraits)).hex, "#aa0000")
        XCTAssertEqual(ThemeColor(platform: try XCTUnwrap(theme.headingColors[0]).resolvedColor(with: darkTraits)).hex, "#ff8080")
        XCTAssertEqual(HeadingTypography.fontScale(level: 1, theme: theme), 2)

        _ = try await openTab("Lecture.md", in: workspace, placement: .currentTab)
        let controller = try hostWithTypography(workspace)
        let session = try XCTUnwrap(workspace.markdownSession)
        session.viewMode = .source
        let editor = try await visibleEditor(in: controller, showing: session)
        let source = session.text as NSString
        let headingLocation = source.range(of: "Wide").location
        try await waitUntil { (try? self.font(at: headingLocation, in: editor).pointSize) ?? 0 > 30 }
        let headingFont = try font(at: headingLocation, in: editor)
        let bodyFont = try font(at: source.range(of: "Body").location, in: editor)
        XCTAssertEqual(headingFont.pointSize, bodyFont.pointSize * 2, accuracy: 0.01, "Live Preview and Source take the theme's heading size, relative to the text size.")
        let headingColor = try XCTUnwrap(editor.textStorage.attribute(.foregroundColor, at: headingLocation, effectiveRange: nil) as? UIColor)
        XCTAssertEqual(ThemeColor(platform: headingColor.resolvedColor(with: lightTraits)).hex, "#aa0000")

        // Callouts (in both views) take the type's color; the title stays readable on its tint.
        let warning = CalloutAppearance(type: "warning", theme: theme)
        let tint = ThemeColor(platform: UIColor(warning.color).resolvedColor(with: lightTraits))
        XCTAssertEqual(tint.hex, "#008000")
        let titleOnTint = ThemeColor(platform: UIColor(warning.titleColor).resolvedColor(with: lightTraits))
        var tintOverPage = tint
        tintOverPage.alpha = CalloutAppearance.tintOpacity
        XCTAssertGreaterThanOrEqual(titleOnTint.contrast(with: tintOverPage.composited(over: ThemeColor(red: 1, green: 1, blue: 1))), 4.5)
        XCTAssertEqual(CalloutAppearance(type: "note", theme: theme).color, CalloutAppearance(type: "note").color, "A type the theme leaves alone keeps Graphite's color.")
        attachScreenshot(named: "Source mode in a test theme")

        // Reading view: the heading is drawn at twice the text size.
        let measurement = MeasuredWidth()
        let reading = UIHostingController(rootView: ObsidianMarkdownText(markdown: "# Wide heading text", root: try XCTUnwrap(vaultDirectory), textSize: 16,
                                                                         navigate: { _, _ in }, scrollToHeading: { _ in })
            .environment(\.noteTheme, theme).fixedSize()
            .onGeometryChange(for: CGFloat.self) { geometry in geometry.size.width } action: { width in measurement.width = width }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
        try present(reading)
        try await waitUntil { measurement.width > 0 }
        try await Task.sleep(for: .milliseconds(300))
        let expectedWidth = ("Wide heading text" as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 32, weight: .semibold)]).width
        XCTAssertEqual(measurement.width, expectedWidth, accuracy: 3, "Reading view takes the theme's heading size.")

        workspace.preferences.usesVaultTheme = false
        await workspace.refreshVaultTheme()
        XCTAssertNil(workspace.noteTheme, "With the setting off, notes keep Graphite's look.")
    }

    // MARK: Theme shapes Live Preview draws, and a long note's restyle cost (theme Phase 3)

    /// A theme that changes the shapes of tags, highlights, checkboxes, headings and quotes.
    private static let shapeTheme = """
        .theme-light { --h2-color: #a03030; --tag-radius: 3px; --checkbox-radius: 50%; --blockquote-background-color: rgba(0, 0, 0, 0.05);
                       --list-marker-color: #a03030; --inline-title-color: #205080; }
        .theme-dark { --h2-color: #ff9090; --tag-radius: 3px; --checkbox-radius: 50%; --blockquote-background-color: rgba(255, 255, 255, 0.06);
                      --list-marker-color: #ff9090; --inline-title-color: #90c0ff; }
        .markdown-rendered h2 { border-bottom: 2px solid #a03030; }
        .markdown-rendered mark { border-radius: 4px; }
        .markdown-rendered a.tag { border: 1px solid #a03030; }
        """

    private func useTheme(_ css: String, in workspace: WorkspaceModel) async throws -> NoteThemeStyle {
        workspace.preferences.usesVaultTheme = true
        let folder = try XCTUnwrap(vaultDirectory).appendingPathComponent(".obsidian/themes/Shapes")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(css.utf8).write(to: folder.appendingPathComponent("theme.css"))
        try writeAppearance(#"{"cssTheme": "Shapes"}"#)
        await workspace.reloadVaultAppearance()
        await workspace.refreshVaultTheme()
        return try XCTUnwrap(workspace.noteTheme, "The theme is resolved and handed to notes.")
    }

    /// The theme's tag pill and highlight shapes, round checkboxes, heading underline and quote
    /// background are set on the text Live Preview draws.
    func testLivePreviewDrawsTheThemesShapes() async throws {
        let workspace = try await makeWorkspace(notes: ["Shapes.md": "Intro line.\n\n## Underlined heading\n\nA #tagged line with ==marked words==.\n\n- [ ] A task\n\n> A quote.\n"])
        let previousSetting = workspace.preferences.usesVaultTheme
        defer { workspace.preferences.usesVaultTheme = previousSetting }
        let theme = try await useTheme(Self.shapeTheme, in: workspace)
        XCTAssertNotNil(theme.tagRadius)
        XCTAssertNotNil(theme.highlightRadius)
        XCTAssertNotNil(theme.checkboxRadiusScale)
        XCTAssertNotNil(theme.headingOrnaments[1].underlineColor)
        XCTAssertNotNil(theme.blockquoteBackground)

        _ = try await openTab("Shapes.md", in: workspace, placement: .currentTab)
        let controller = try hostWithTypography(workspace)
        let session = try XCTUnwrap(workspace.markdownSession)
        session.viewMode = .livePreview
        let editor = try await visibleEditor(in: controller, showing: session)
        let source = session.text as NSString
        func attribute(_ key: NSAttributedString.Key, at text: String) -> Any? {
            editor.textStorage.attribute(key, at: source.range(of: text).location, effectiveRange: nil)
        }
        try await waitUntil { attribute(ConcealedReplacement.roundedBackgroundKey, at: "tagged") != nil }
        XCTAssertNotNil(attribute(ConcealedReplacement.roundedBackgroundKey, at: "marked"), "The highlight is a rounded shape.")
        XCTAssertNotNil(attribute(ConcealedReplacement.headingOrnamentKey, at: "Underlined"), "The heading carries its underline.")
        XCTAssertNotNil(attribute(ConcealedReplacement.quoteBackgroundKey, at: "A quote"), "The quote has the theme's background.")
        let checkbox = try XCTUnwrap(attribute(ConcealedReplacement.checkboxStyleKey, at: "[ ]") as? ThemedCheckboxStyle)
        XCTAssertGreaterThan(checkbox.radiusScale, 0.3, "The checkbox is round.")
        if let inlineTitle = editor.inlineTitle {
            XCTAssertEqual(ThemeColor(platform: inlineTitle.color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))).hex, "#205080",
                           "The inline title takes the theme's color.")
        }
        attachScreenshot(named: "Live Preview with a theme's shapes")
    }

    /// Typing in a 5,000-line note, with and without a theme that draws shapes: the time from a
    /// keystroke to the restyled, laid-out text, and the time to restyle the whole note when the
    /// theme changes. Each keystroke must fit in one frame (about 16 ms).
    func testLongNoteRestyleCostWithAndWithoutATheme() async throws {
        var lines: [String] = []
        for section in 0..<500 {
            lines += ["## Section \(section)", "Body text with a #tag, ==a highlight==, **bold** words and a [[Link]].", "- [ ] An open task \(section)",
                      "- [x] A finished task", "- A bullet with `code`", "> A quoted line \(section)", "1. A numbered item", "", "Plain text to type into \(section).", ""]
        }
        let workspace = try await makeWorkspace(notes: ["Long.md": lines.joined(separator: "\n")])
        let previousSetting = workspace.preferences.usesVaultTheme
        defer { workspace.preferences.usesVaultTheme = previousSetting }
        workspace.preferences.usesVaultTheme = false
        await workspace.refreshVaultTheme()

        _ = try await openTab("Long.md", in: workspace, placement: .currentTab)
        let controller = try hostWithTypography(workspace)
        let session = try XCTUnwrap(workspace.markdownSession)
        session.viewMode = .livePreview
        let editor = try await visibleEditor(in: controller, showing: session)

        /// Milliseconds per keystroke, typed at the end of a line in the middle of the note.
        func keystrokeTimes() async throws -> [Double] {
            let line = (editor.text as NSString).range(of: "Plain text to type into 250.")
            editor.beginEditing()
            editor.selectedRange = NSRange(location: NSMaxRange(line), length: 0)
            editor.scrollRangeToVisible(editor.selectedRange)
            editor.layoutIfNeeded()
            // Jumping 2,500 lines lays out the new screen over the next moments; typing starts after.
            try await Task.sleep(for: .milliseconds(1500))
            var times: [Double] = []
            for _ in 0..<40 {
                let start = ContinuousClock.now
                editor.insertText("a")
                editor.layoutIfNeeded()
                let elapsed = ContinuousClock.now - start
                times.append(Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000)
                try await Task.sleep(for: .milliseconds(20))
            }
            for _ in 0..<40 { editor.deleteBackward() }
            try await Task.sleep(for: .milliseconds(200))
            return times.sorted()
        }
        /// Milliseconds to restyle the whole note with a styler for the given theme.
        func wholeNoteRestyleTime(theme: NoteThemeStyle?) -> Double {
            var configuration = EditorConfiguration(mode: .livePreview)
            configuration.theme = theme
            let styler = MarkdownTextStyler(configuration: configuration, accentColor: .systemBlue, drawsConcealedReplacements: true)
            let storage = NSTextStorage(string: editor.text)
            let start = ContinuousClock.now
            styler.applyStyles(to: storage, editedRange: NSRange(location: 0, length: 0), restyleEverything: true, revealedMarkup: nil, concealedBlocks: [])
            let elapsed = ContinuousClock.now - start
            return Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
        }

        let plainTimes = try await keystrokeTimes()
        let plainWholeNote = wholeNoteRestyleTime(theme: nil)
        let theme = try await useTheme(Self.shapeTheme, in: workspace)
        try await waitUntil { editor.textStorage.attribute(ConcealedReplacement.roundedBackgroundKey, at: (editor.text as NSString).range(of: "#tag").location, effectiveRange: nil) != nil }
        let themedTimes = try await keystrokeTimes()
        let themedWholeNote = wholeNoteRestyleTime(theme: theme)

        func median(_ times: [Double]) -> Double { times[times.count / 2] }
        let report = String(format: "5,000 lines. Keystroke median %.2f ms, slowest %.2f ms without a theme; median %.2f ms, slowest %.2f ms with the theme. Whole-note restyle %.0f ms without, %.0f ms with.",
                            median(plainTimes), plainTimes.last ?? 0, median(themedTimes), themedTimes.last ?? 0, plainWholeNote, themedWholeNote)
        print("THEME-RESTYLE-COST " + report)
        let attachment = XCTAttachment(string: report)
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertLessThan(median(themedTimes), 16.7, "A keystroke in a long themed note fits in one frame.")
        XCTAssertLessThan(median(themedTimes), median(plainTimes) * 1.5 + 2, "The theme adds little to a keystroke.")
    }

    private func writeAppearance(_ text: String) throws {
        let folder = try XCTUnwrap(vaultDirectory).appendingPathComponent(".obsidian")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: folder.appendingPathComponent("appearance.json"))
    }

    private func font(at location: Int, in editor: MarkdownTextView) throws -> UIFont {
        try XCTUnwrap(editor.textStorage.attribute(.font, at: location, effectiveRange: nil) as? UIFont)
    }

    /// The workspace's panes with the vault's fonts, as the root view gives them.
    private func hostWithTypography(_ workspace: WorkspaceModel) throws -> UIHostingController<AnyView> {
        let controller = UIHostingController(rootView: AnyView(NavigationStack { TypographyHostedPanes(workspace: workspace) }))
        try present(controller)
        return controller
    }

    private func makeWorkspace(notes: [String: String]) async throws -> WorkspaceModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("EditingContinuity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        vaultDirectory = directory
        for (name, text) in notes { try Data(text.utf8).write(to: directory.appendingPathComponent(name)) }
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        workspace.index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        return workspace
    }

    private func openTab(_ name: String, in workspace: WorkspaceModel, placement: GraphiteUI.TabPlacement) async throws -> UUID {
        let path = try VaultPath(name)
        await workspace.open(path, placement: placement)
        return try XCTUnwrap(workspace.layout.tabID(showing: path))
    }

    private func host(_ workspace: WorkspaceModel) throws -> UIHostingController<AnyView> {
        let controller = UIHostingController(rootView: AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        }))
        try present(controller)
        return controller
    }

    private func present(_ controller: UIViewController) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
    }

    private func editors(in controller: UIViewController) -> [MarkdownTextView] {
        descendants(of: controller.view, matching: MarkdownTextView.self).filter { editor in editor.window != nil }
    }

    private func containers(in controller: UIViewController) -> [MarkdownEditorContainerView] {
        descendants(of: controller.view, matching: MarkdownEditorContainerView.self).filter { container in container.window != nil }
    }

    /// The text view on screen that shows the session's note.
    private func visibleEditor(in controller: UIViewController, showing session: MarkdownSession) async throws -> MarkdownTextView {
        try await waitUntil { self.editors(in: controller).contains { editor in editor.text == session.text && editor.bounds.width > 0 } }
        return try XCTUnwrap(editors(in: controller).first { editor in editor.text == session.text })
    }

    /// Opens the other side of the split and closes it again, checking after each step
    /// that the note's text view is the one on screen, at the width of its pane.
    private func openAndCloseSplit(beside tab: UUID, in workspace: WorkspaceModel, controller: UIViewController, editor: MarkdownTextView,
                                   widthBeforeSplit: CGFloat, beforeClosing: () -> Void = {}) async throws {
        let noteGroup = try XCTUnwrap(workspace.layout.group(containing: tab)?.id)
        workspace.splitRight()
        let otherGroup = try XCTUnwrap(workspace.layout.otherGroup(than: noteGroup)?.id)
        if controller.traitCollection.horizontalSizeClass == .regular {
            try await waitUntil { self.editors(in: controller).contains { shownEditor in shownEditor === editor } && editor.bounds.width > 0 && editor.bounds.width < widthBeforeSplit - 1 }
            XCTAssertEqual(editors(in: controller).count, 1)
        } else {
            // A compact width shows one side at a time, and the new, empty side has the focus.
            try await waitUntil { self.editors(in: controller).isEmpty }
        }

        beforeClosing()
        await workspace.closeGroup(otherGroup)
        XCTAssertFalse(workspace.layout.isSplit)
        try await waitUntil { self.editors(in: controller).contains { shownEditor in shownEditor === editor } && abs(editor.bounds.width - widthBeforeSplit) < 1 }
        XCTAssertEqual(editors(in: controller).count, 1, "The note's text view stays on screen in the pane that is left.")
        XCTAssertTrue(editor.superview is MarkdownEditorContainerView)
    }

    private func type(_ text: String, into editor: MarkdownTextView, session: MarkdownSession) async throws {
        editor.beginEditing()
        editor.selectedRange = NSRange(location: (editor.text as NSString).length, length: 0)
        let expectedText = session.text + text
        editor.insertText(text)
        try await waitUntil { session.text == expectedText }
        // Typing is one undo step once its run loop turn ends.
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(editor.undoManager?.canUndo == true)
    }

    private func attachScreenshot(named name: String) {
        guard let window else { return }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The hosted views of Live Preview's rendered blocks shown in a note's text view.
    private func renderedBlockViews(in editor: MarkdownTextView) -> [UIView] {
        editor.subviews.filter { subview in String(describing: Swift.type(of: subview)).contains("HostingView") }
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in
            ((child as? View).map { [$0] } ?? []) + descendants(of: child, matching: type)
        }
    }

}

/// Which views of one note `EditorViews` shows.
@MainActor @Observable
private final class ShownEditorViews {
    var showsViewThatStays = false
    var showsFirstView = true
    var showsPassingView = false
}

/// Several SwiftUI views of one note, made and dismantled as a test asks, which SwiftUI
/// otherwise decides by itself.
private struct EditorViews: View {
    let shownViews: ShownEditorViews
    let session: MarkdownSession
    let retention: MarkdownEditorRetention
    let owner: TabDocument

    var body: some View {
        VStack(spacing: 0) {
            if shownViews.showsViewThatStays { editor }
            if shownViews.showsFirstView { editor }
            if shownViews.showsPassingView { editor }
        }
    }

    private var editor: some View {
        NativeMarkdownEditor(session: session, configuration: EditorConfiguration(mode: .source), headingScrollRequest: nil,
                             retention: retention, retentionOwner: owner) { _, _ in }
    }
}

/// A text field inside the note's text view, as a rendered block's field is, that does what
/// the keyboard does as it goes away: lays the window out at once, here making the note's
/// next view.
private final class FieldThatLaysOutAsItResigns: UITextField {
    var didResign: () -> Void = {}

    override func resignFirstResponder() -> Bool {
        let hasResigned = super.resignFirstResponder()
        didResign()
        return hasResigned
    }
}

/// What surrounds the note's view in `SurroundedEditor`.
@MainActor @Observable
private final class EditorSurroundings {
    var hasEditableTitle = true
}

/// One view of a note under a title that is editable or plain, as `GraphiteRootView`'s
/// title is with the width class: SwiftUI makes the note's view again when it changes.
private struct SurroundedEditor: View {
    let surroundings: EditorSurroundings
    let session: MarkdownSession
    let retention: MarkdownEditorRetention
    let owner: TabDocument

    var body: some View {
        NavigationStack {
            if surroundings.hasEditableTitle {
                editor.navigationTitle(.constant("Lecture"))
            } else {
                editor.navigationTitle("Lecture")
            }
        }
    }

    private var editor: some View {
        NativeMarkdownEditor(session: session, configuration: EditorConfiguration(mode: .source), headingScrollRequest: nil,
                             retention: retention, retentionOwner: owner) { _, _ in }
    }
}
extension ThemeColor {
    /// A resolved UIKit color, for comparing what notes draw with a theme's values.
    init(platform color: UIColor) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.init(red: Double(red), green: Double(green), blue: Double(blue), alpha: Double(alpha))
    }
}

/// A width a hosted view reports from its layout.
@MainActor
private final class MeasuredWidth {
    var width: CGFloat = 0
}

/// The panes with the workspace's resolved fonts in their environment, read here so a font
/// change reaches them as it reaches the root view's.
private struct TypographyHostedPanes: View {
    let workspace: WorkspaceModel

    var body: some View {
        WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
            .environment(\.noteTypography, workspace.noteTypography)
    }
}
#endif
