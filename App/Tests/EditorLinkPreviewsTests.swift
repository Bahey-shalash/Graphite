#if os(iOS)
import XCTest
import SwiftUI
import GraphiteApple
@testable import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// Page Preview in the iPad's editor, in the hosted workspace's own text view: the pointer
/// or Apple Pencil hovering on a link asks for its card beside the link, a long press shows
/// it at once, and nothing watches the pointer while Page Preview is off.
@MainActor
final class EditorLinkPreviewsTests: XCTestCase {
    private var window: UIWindow?
    private var vaultDirectory: URL?
    private var workspace: WorkspaceModel?

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        workspace = nil
        if let vaultDirectory { try? FileManager.default.removeItem(at: vaultDirectory) } // Best-effort removal of a temporary folder.
        vaultDirectory = nil
    }

    private static let note = "# Links\n\nPlain words, then [[Target|the target]] and [a lecture](Lectures/Week.md), `[[Code]]`.\n"

    func testThePointerOnALinkAsksForItsCardBesideTheLinkAndOffItCancelsIt() async throws {
        let (editor, coordinator) = try await openNote(Self.note)
        let cards = LinkPreviewModel(clock: LiveApplicationClock(), announceHover: { _ in })
        XCTAssertTrue(coordinator.linkPreviews.use(cards, sourceNote: try VaultPath("Note.md")))
        coordinator.watchPointerForLinks(in: editor)

        let onAlias = try windowPoint(atStartOf: "the target", in: editor)
        coordinator.linkPreviews.pointerMoved(to: onAlias, over: editor)
        guard case .waiting(let request) = cards.phase else { return XCTFail("The card is on its way: \(cards.phase)") }
        XCTAssertEqual(request.target, "Target")
        XCTAssertEqual(request.source, .editor)
        XCTAssertTrue(request.anchor.contains(onAlias), "The card goes beside the link's line under the pointer.")

        coordinator.linkPreviews.pointerMoved(to: try windowPoint(atStartOf: "lecture", in: editor), over: editor)
        guard case .waiting(let markdownLink) = cards.phase else { return XCTFail("\(cards.phase)") }
        XCTAssertEqual(markdownLink.target, "Lectures/Week.md")

        coordinator.linkPreviews.pointerMoved(to: try windowPoint(atStartOf: "Plain", in: editor), over: editor)
        guard case .hidden = cards.phase else { return XCTFail("Off the links, no card comes.") }
        coordinator.linkPreviews.pointerMoved(to: try windowPoint(atStartOf: "Code", in: editor), over: editor)
        guard case .hidden = cards.phase else { return XCTFail("A link written in code is text.") }
    }

    func testALongPressOnALinkShowsItsCardAtOnce() async throws {
        let (editor, coordinator) = try await openNote(Self.note)
        let cards = LinkPreviewModel(clock: LiveApplicationClock(), announceHover: { _ in })
        cards.useReading(try XCTUnwrap(workspace?.linkPreviewReading(at: .large)))
        _ = coordinator.linkPreviews.use(cards, sourceNote: try VaultPath("Note.md"))
        XCTAssertFalse(coordinator.linkPreviews.press(at: try windowPoint(atStartOf: "Plain", in: editor), in: editor))
        XCTAssertTrue(coordinator.linkPreviews.press(at: try windowPoint(atStartOf: "the target", in: editor), in: editor))
        try await waitUntil("the held link's card shows") {
            if case .shown(let request, let content) = cards.phase { return request.trigger == .press && content.path.rawValue == "Target.md" }
            return false
        }
    }

    func testThePointerIsWatchedOnlyWhilePagePreviewIsOn() async throws {
        let (editor, coordinator) = try await openNote(Self.note)
        // The text view has hover recognizers of its own; Page Preview adds one while it is on.
        let enabledHoverRecognizerCount = { editor.gestureRecognizers?.filter { recognizer in recognizer is UIHoverGestureRecognizer && recognizer.isEnabled }.count ?? 0 }
        let textViewsOwnCount = enabledHoverRecognizerCount()

        let cards = LinkPreviewModel(clock: LiveApplicationClock(), announceHover: { _ in })
        _ = coordinator.linkPreviews.use(cards, sourceNote: try VaultPath("Note.md"))
        coordinator.watchPointerForLinks(in: editor)
        XCTAssertEqual(enabledHoverRecognizerCount(), textViewsOwnCount + 1)

        XCTAssertTrue(coordinator.linkPreviews.use(nil, sourceNote: try VaultPath("Note.md")))
        coordinator.watchPointerForLinks(in: editor)
        XCTAssertEqual(enabledHoverRecognizerCount(), textViewsOwnCount)
    }

    // MARK: Helpers

    /// The middle of the first character of `substring`, in window coordinates.
    private func windowPoint(atStartOf substring: String, in editor: MarkdownTextView) throws -> CGPoint {
        editor.layoutIfNeeded()
        let location = (editor.text as NSString).range(of: substring).location
        let start = try XCTUnwrap(editor.position(from: editor.beginningOfDocument, offset: location))
        let end = try XCTUnwrap(editor.position(from: start, offset: 1))
        let rect = editor.convert(editor.firstRect(for: try XCTUnwrap(editor.textRange(from: start, to: end))), to: nil)
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    /// The note in Live Preview, in the workspace's panes, in a window of its own; Page Preview
    /// is not on in this window (no `LinkPreviewLayer`), so the tests give the editor its cards.
    private func openNote(_ text: String) async throws -> (MarkdownTextView, NativeMarkdownEditor.Coordinator) {
        let directory = hostedTemporaryLocation(named: "EditorLinkPreviews")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        vaultDirectory = directory
        try Data(text.utf8).write(to: directory.appendingPathComponent("Note.md"))
        try Data("Target.\n".utf8).write(to: directory.appendingPathComponent("Target.md"))
        let workspace = WorkspaceModel()
        self.workspace = workspace
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        workspace.index = index
        _ = try await index.reconcile(root: directory)
        let path = try VaultPath("Note.md")
        await workspace.open(path, placement: .currentTab)
        let tab = try XCTUnwrap(workspace.layout.tabID(showing: path))
        let session = try XCTUnwrap(workspace.document(for: tab).markdownSession)
        session.viewMode = .livePreview
        let controller = UIHostingController(rootView: AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        }))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        try await waitUntil { self.editors(in: controller.view).contains { editor in editor.text == session.text && editor.bounds.width > 0 } }
        let editor = try XCTUnwrap(editors(in: controller.view).first { editor in editor.text == session.text })
        editor.layoutIfNeeded()
        return (editor, try XCTUnwrap(editor.delegate as? NativeMarkdownEditor.Coordinator))
    }

    private func editors(in view: UIView) -> [MarkdownTextView] {
        view.subviews.flatMap { child in ((child as? MarkdownTextView).map { [$0] } ?? []) + editors(in: child) }.filter { editor in editor.window != nil }
    }
}
#endif
