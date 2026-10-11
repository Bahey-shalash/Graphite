#if os(iOS)
import XCTest
import SwiftUI
import GraphiteApple
@testable import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// Live Preview's rendered blocks, in the hosted workspace's own text view, stay over the
/// space their text reserves for them after a jump to a heading and after a change of
/// appearance: no block's view covers a heading or another block's view.
@MainActor
final class LivePreviewBlockPlacementTests: XCTestCase {
    private var window: UIWindow?
    private var vaultDirectory: URL?

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        if let vaultDirectory { try? FileManager.default.removeItem(at: vaultDirectory) }
        vaultDirectory = nil
    }

    /// Two-line callouts under headings, as in the callout sample note.
    private static let calloutNote: String = (1...14).map { sectionNumber in
        let callouts = (1...3).map { calloutNumber in "> [!tip]\n> Callout \(calloutNumber) of section \(sectionNumber).\n" }
        return "## Section \(sectionNumber)\n\n" + callouts.joined(separator: "\n")
    }.joined(separator: "\n")

    /// Properties taller than the window, with a callout on the line right after them, as a
    /// lecture note's properties are followed by its slides.
    private static let propertiesThenCalloutNote: String = {
        let properties = (1...60).map { propertyNumber in "property\(propertyNumber): value \(propertyNumber)" }
        return "---\n" + properties.joined(separator: "\n") + "\n---\n> [!note]\n> Right after the properties.\n\nText after the callout.\n"
    }()

    /// A jump lays the text above the heading out again while the callouts take their
    /// measured heights; the callout just above the heading was drawn over it.
    func testTheCalloutAboveAHeadingJumpedToDoesNotCoverIt() async throws {
        let (workspace, editor) = try await openNote(Self.calloutNote)
        try await waitForPlacementToSettle(in: editor)

        await workspace.follow("Placement#Section 9", from: try VaultPath("Placement.md"))
        try await waitForPlacementToSettle(in: editor)
        attachScreenshot(named: "After the jump to Section 9")

        let headingLocation = (editor.text as NSString).range(of: "## Section 9").location
        let headingLine = try XCTUnwrap(lineFrame(atCharacter: headingLocation, in: editor), "The heading is not laid out.")
        XCTAssertTrue(editor.bounds.intersects(headingLine), "The jump did not bring the heading on screen.")
        XCTAssertLessThan(headingLine.minY - editor.bounds.minY, 100, "The heading is not at the top.")
        XCTAssertGreaterThan(blockViews(in: editor).count, 0, "The callouts are not rendered.")
        assertNoBlockViewCoversAHeading(in: editor)
    }

    /// A change of appearance restyles every paragraph, and a block's fragment then has no
    /// frame until TextKit lays it out again. With the end of the properties and the callout
    /// on screen, the views were also rebuilt whenever TextKit had no viewport range, and
    /// the rebuilt views' heights restyled the note again without end, freezing the editor.
    func testAChangeOfAppearanceKeepsEveryBlockInItsPlace() async throws {
        let (_, editor) = try await openNote(Self.propertiesThenCalloutNote)
        try await waitForPlacementToSettle(in: editor)
        XCTAssertGreaterThan(blockViews(in: editor).count, 0, "The properties are not rendered.")
        assertBlockViewsDoNotOverlap(in: editor)

        for style in [UIUserInterfaceStyle.dark, .light] {
            try XCTUnwrap(window).overrideUserInterfaceStyle = style
            try await waitForPlacementToSettle(in: editor)
            attachScreenshot(named: style == .dark ? "Dark" : "Light again")
            assertBlockViewsDoNotOverlap(in: editor)
        }

        // Scrolled so that the properties' end and the callout are both on screen.
        let calloutLocation = (editor.text as NSString).range(of: "> [!note]").location
        let calloutTop = try XCTUnwrap(topOfBlock(atCharacter: calloutLocation, in: editor))
        editor.setContentOffset(CGPoint(x: 0, y: max(0, calloutTop - editor.bounds.height / 2)), animated: false)
        try await waitForPlacementToSettle(in: editor)
        try XCTUnwrap(window).overrideUserInterfaceStyle = .dark
        try await waitForPlacementToSettle(in: editor)
        attachScreenshot(named: "Dark with the callout on screen")
        assertBlockViewsDoNotOverlap(in: editor)
        XCTAssertEqual(blockViews(in: editor).count, 2, "The properties and the callout are not both shown.")
    }

    // MARK: Checks

    private func assertNoBlockViewCoversAHeading(in editor: MarkdownTextView, file: StaticString = #filePath, line: UInt = #line) {
        let source = editor.text as NSString
        var checkedHeadings = 0
        source.enumerateSubstrings(in: NSRange(location: 0, length: source.length), options: .byLines) { lineText, lineRange, _, _ in
            guard lineText?.hasPrefix("#") == true, let headingLine = self.lineFrame(atCharacter: lineRange.location, in: editor),
                  editor.bounds.intersects(headingLine) else { return }
            checkedHeadings += 1
            for blockView in self.blockViews(in: editor) where blockView.frame.insetBy(dx: 0, dy: 1).intersects(headingLine) {
                XCTFail("A block's view at \(blockView.frame) covers \(lineText ?? "") at \(headingLine).", file: file, line: line)
            }
        }
        XCTAssertGreaterThan(checkedHeadings, 0, "No heading was on screen.", file: file, line: line)
    }

    private func assertBlockViewsDoNotOverlap(in editor: MarkdownTextView, file: StaticString = #filePath, line: UInt = #line) {
        let blockViews = blockViews(in: editor)
        for (index, blockView) in blockViews.enumerated() {
            for laterView in blockViews.dropFirst(index + 1) where blockView.frame.insetBy(dx: 0, dy: 1).intersects(laterView.frame) {
                XCTFail("Block views at \(blockView.frame) and \(laterView.frame) overlap.", file: file, line: line)
            }
        }
    }

    /// The rendered blocks' views on screen: each is the view of its own hosting controller.
    private func blockViews(in editor: MarkdownTextView) -> [UIView] {
        editor.subviews.filter { subview in !subview.isHidden && isViewOfHostingController(subview) }
    }

    /// SwiftUI puts responders of its own between a hosting controller and its view; the
    /// chain reaches the view's superview after the controller.
    private func isViewOfHostingController(_ view: UIView) -> Bool {
        var responder = view.next
        while let currentResponder = responder, !(currentResponder is UIView) {
            if currentResponder is UIHostingController<AnyView> { return true }
            responder = currentResponder.next
        }
        return false
    }

    /// Where the first line at a character is drawn, in the text view, once TextKit has laid it out.
    private func lineFrame(atCharacter characterIndex: Int, in editor: MarkdownTextView) -> CGRect? {
        guard let fragment = layoutFragment(atCharacter: characterIndex, in: editor),
              let firstLine = fragment.textLineFragments.first else { return nil }
        return firstLine.typographicBounds.offsetBy(dx: fragment.layoutFragmentFrame.minX + editor.textContainerInset.left,
                                                     dy: fragment.layoutFragmentFrame.minY + editor.textContainerInset.top)
    }

    /// The top of the block at a character, with the text before it laid out, as a jump does.
    private func topOfBlock(atCharacter characterIndex: Int, in editor: MarkdownTextView) -> CGFloat? {
        guard let textLayoutManager = editor.textLayoutManager,
              let contentStorage = textLayoutManager.textContentManager as? NSTextContentStorage,
              let location = contentStorage.location(contentStorage.documentRange.location, offsetBy: characterIndex),
              let precedingRange = NSTextRange(location: contentStorage.documentRange.location, end: location) else { return nil }
        textLayoutManager.ensureLayout(for: precedingRange)
        return layoutFragment(atCharacter: characterIndex, in: editor).map { fragment in fragment.layoutFragmentFrame.minY + editor.textContainerInset.top }
    }

    private func layoutFragment(atCharacter characterIndex: Int, in editor: MarkdownTextView) -> NSTextLayoutFragment? {
        guard let textLayoutManager = editor.textLayoutManager,
              let contentStorage = textLayoutManager.textContentManager as? NSTextContentStorage,
              let location = contentStorage.location(contentStorage.documentRange.location, offsetBy: characterIndex),
              let fragment = textLayoutManager.textLayoutFragment(for: location), fragment.state == .layoutAvailable else { return nil }
        return fragment
    }

    // MARK: Hosting

    private func openNote(_ text: String) async throws -> (WorkspaceModel, MarkdownTextView) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LivePreviewPlacement-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        vaultDirectory = directory
        try Data(text.utf8).write(to: directory.appendingPathComponent("Placement.md"))
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        workspace.index = index
        _ = try await index.reconcile(root: directory)
        let path = try VaultPath("Placement.md")
        await workspace.open(path, placement: .currentTab)
        let tab = try XCTUnwrap(workspace.layout.tabID(showing: path))
        let session = try XCTUnwrap(workspace.document(for: tab).markdownSession)
        session.viewMode = .livePreview
        let controller = UIHostingController(rootView: AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        }))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        try await waitUntil { self.editors(in: controller).contains { editor in editor.text == session.text && editor.bounds.width > 0 } }
        let editor = try XCTUnwrap(editors(in: controller).first { editor in editor.text == session.text })
        editor.layoutIfNeeded()
        return (workspace, editor)
    }

    private func editors(in controller: UIViewController) -> [MarkdownTextView] {
        descendants(of: controller.view, matching: MarkdownTextView.self).filter { editor in editor.window != nil }
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in
            ((child as? View).map { [$0] } ?? []) + descendants(of: child, matching: type)
        }
    }

    /// Waits until the block views and the scroll position have not moved for half a second,
    /// past the time a jump keeps its heading at the top while the blocks settle.
    private func waitForPlacementToSettle(in editor: MarkdownTextView) async throws {
        let deadline = Date().addingTimeInterval(8)
        let earliestEnd = Date().addingTimeInterval(1.6)
        var lastSnapshot: [CGRect] = []
        var unchangedChecks = 0
        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
            let snapshot = blockViews(in: editor).map(\.frame).sorted { leftFrame, rightFrame in leftFrame.minY < rightFrame.minY }
                + [CGRect(origin: editor.contentOffset, size: .zero)]
            unchangedChecks = snapshot == lastSnapshot ? unchangedChecks + 1 : 0
            lastSnapshot = snapshot
            if unchangedChecks >= 10, Date() >= earliestEnd { return }
        }
        XCTFail("The rendered blocks did not settle.")
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

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertTrue(condition(), "The hosted editor did not reach the expected state.")
    }
}
#endif
