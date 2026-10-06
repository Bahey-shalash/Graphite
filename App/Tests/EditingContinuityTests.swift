#if os(iOS)
import XCTest
import SwiftUI
import GraphiteApple
import GraphiteCore
import GraphiteIndex
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

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in
            ((child as? View).map { [$0] } ?? []) + descendants(of: child, matching: type)
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertTrue(condition(), "The hosted workspace did not reach the expected state.")
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
#endif
