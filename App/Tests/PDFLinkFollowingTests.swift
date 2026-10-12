#if os(iOS)
import XCTest
import SwiftUI
import PDFKit
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// Opening a PDF from a note, in the hosted workspace: an embed's "Open in PDF View" and
/// page links, when the PDF is already open in another tab or on the other side.
@MainActor
final class PDFLinkFollowingTests: XCTestCase {
    private static let slidesName = "Slides.pdf"
    private static let slidesPageCount = 6

    private var window: UIWindow?
    private var vaultDirectory: URL?

    override func setUp() async throws {
        // SwiftUI builds its accessibility elements only while an assistive technology
        // asks for them; the test switches the accessibility runtime on, as VoiceOver or
        // UI automation would, to find the embed's buttons.
        try Self.setAccessibilityRuntimeEnabled(true)
    }

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        if let vaultDirectory { try? FileManager.default.removeItem(at: vaultDirectory) }
        vaultDirectory = nil
        try Self.setAccessibilityRuntimeEnabled(false)
    }

    // MARK: Embeds

    /// The embed's "Open in PDF View" did nothing when the PDF was open in another tab of
    /// the same side: the note's text view took focus back as it went off screen, from the
    /// embedded PDF inside it, and made the note's tab active again.
    func testLivePreviewEmbedOpensThePDFOpenInAnotherTabAtTheEmbedsPage() async throws {
        let workspace = try await makeWorkspace(note: "Lecture notes.\n\n![[\(Self.slidesName)#page=3]]\n")
        let slidesTab = try await openTab(Self.slidesName, in: workspace, placement: .currentTab)
        let noteTab = try await openTab("Lecture.md", in: workspace, placement: .newTab)
        XCTAssertEqual(workspace.layout.group(containing: slidesTab)?.id, workspace.layout.group(containing: noteTab)?.id)
        let controller = try host(workspace)

        try await pressOpenInPDFView(in: controller, touchingTheNote: true)

        try await expectShown(slidesTab, in: workspace)
        XCTAssertEqual(workspace.document(for: slidesTab).pdfSession?.currentPageIndex, 2, "The PDF shows the embed's page.")
        attachScreenshot(named: "PDF shown from the Live Preview embed")
    }

    func testReadingViewEmbedOpensThePDFOpenInAnotherTabAtTheEmbedsPage() async throws {
        let workspace = try await makeWorkspace(note: "Lecture notes.\n\n![[\(Self.slidesName)#page=4]]\n")
        let slidesTab = try await openTab(Self.slidesName, in: workspace, placement: .currentTab)
        let noteTab = try await openTab("Lecture.md", in: workspace, placement: .newTab)
        workspace.document(for: noteTab).markdownSession?.viewMode = .reading
        let controller = try host(workspace)

        try await pressOpenInPDFView(in: controller, touchingTheNote: false)

        try await expectShown(slidesTab, in: workspace)
        XCTAssertEqual(workspace.document(for: slidesTab).pdfSession?.currentPageIndex, 3, "The PDF shows the embed's page.")
    }

    // MARK: Page links

    /// A page link in a note that embeds a PDF did nothing when the PDF was open in another
    /// tab of the same side, for the same reason as the embed's button. The link is
    /// followed as the note's tap on it does, after a finger touched the note.
    func testPageLinkShowsThePDFOpenInAnotherTabOfTheSameSide() async throws {
        let workspace = try await makeWorkspace(note: "See [[\(Self.slidesName)#page=5|page 5]].\n\n![[\(Self.slidesName)#page=3]]\n")
        let slidesTab = try await openTab(Self.slidesName, in: workspace, placement: .currentTab)
        let noteTab = try await openTab("Lecture.md", in: workspace, placement: .newTab)
        let controller = try host(workspace)
        let editor = try await editor(in: controller)
        try await waitUntil(seconds: 10) { self.firstResponder(in: editor) != nil }
        touch(editor, at: editor.convert(CGPoint(x: editor.bounds.midX, y: 60), to: nil))

        workspace.activateTab(noteTab)
        await workspace.follow("\(Self.slidesName)#page=5", from: try VaultPath("Lecture.md"))

        try await expectShown(slidesTab, in: workspace)
        XCTAssertEqual(workspace.document(for: slidesTab).pdfSession?.currentPageIndex, 4)
    }

    /// Page links followed one after another show the PDF at each page on the other side,
    /// and the note keeps focus, so the next link can be followed. A link is followed as
    /// the note's tap on it does, here from reading view.
    func testPageLinksShowThePDFOnTheOtherSideAndTheNoteKeepsFocus() async throws {
        let workspace = try await makeWorkspace(note: "See [[\(Self.slidesName)#page=5|page five]] and [[\(Self.slidesName)#page=2|page two]].\n")
        let noteTab = try await openTab("Lecture.md", in: workspace, placement: .currentTab)
        let slidesTab = try await openTab(Self.slidesName, in: workspace, placement: .otherGroup)
        let noteGroup = try XCTUnwrap(workspace.layout.group(containing: noteTab)?.id)
        workspace.focusGroup(noteGroup)
        workspace.document(for: noteTab).markdownSession?.viewMode = .reading
        let controller = try host(workspace)
        try XCTSkipUnless(controller.traitCollection.horizontalSizeClass == .regular, "Both sides show only at a regular width.")
        let notePath = try VaultPath("Lecture.md")

        for (target, pageIndex) in [("\(Self.slidesName)#page=5", 4), ("\(Self.slidesName)#page=2", 1)] {
            workspace.activateTab(noteTab)
            await workspace.follow(target, from: notePath)
            try await waitUntil { workspace.document(for: slidesTab).pdfSession?.currentPageIndex == pageIndex }
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertEqual(workspace.layout.focusedGroupID, noteGroup, "The note keeps focus.")
            XCTAssertEqual(workspace.layout.activeTab.id, noteTab)
        }
    }

    // MARK: Helpers

    /// Presses the embed's "Open in PDF View". PDFKit makes the embedded PDF first
    /// responder as it opens, inside a Live Preview note's text view; with
    /// `touchingTheNote`, a finger comes down on the button first, which the note's text
    /// view sees as a touch on itself.
    private func pressOpenInPDFView(in controller: UIViewController, touchingTheNote: Bool) async throws {
        let openButton = try await element(in: controller) { element in element.accessibilityLabel == "Open in PDF View" }
        if touchingTheNote {
            let editor = try await editor(in: controller)
            try await waitUntil { self.firstResponder(in: editor) != nil }
            touch(editor, at: CGPoint(x: openButton.accessibilityFrame.midX, y: openButton.accessibilityFrame.midY))
        }
        XCTAssertTrue(openButton.accessibilityActivate())
    }

    /// Waits for the tab to be the active one and checks that it stays so once SwiftUI has
    /// taken the note off screen: the note's text view took focus back as it went, and
    /// its tab became active again.
    private func expectShown(_ tabID: UUID, in workspace: WorkspaceModel, file: StaticString = #filePath, line: UInt = #line) async throws {
        try await waitUntil { workspace.layout.activeTab.id == tabID }
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(workspace.layout.activeTab.id, tabID, "The tab stays in front.", file: file, line: line)
    }

    private func makeWorkspace(note: String) async throws -> WorkspaceModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PDFLinkFollowing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        vaultDirectory = directory
        try Data(note.utf8).write(to: directory.appendingPathComponent("Lecture.md"))
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: Self.slidesPageCount)
            .write(to: directory.appendingPathComponent(Self.slidesName))
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        try await index.refresh(paths: [try VaultPath("Lecture.md"), try VaultPath(Self.slidesName)], root: directory)
        workspace.index = index
        return workspace
    }

    private func openTab(_ name: String, in workspace: WorkspaceModel, placement: GraphiteUI.TabPlacement) async throws -> UUID {
        let path = try VaultPath(name)
        await workspace.open(path, placement: placement)
        return try XCTUnwrap(workspace.layout.tabID(showing: path), workspace.errorMessage ?? "")
    }

    private func host(_ workspace: WorkspaceModel) throws -> UIHostingController<AnyView> {
        let controller = UIHostingController(rootView: AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        }))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        return controller
    }

    /// The note's text view on screen.
    private func editor(in controller: UIViewController) async throws -> MarkdownTextView {
        func editors() -> [MarkdownTextView] { descendants(of: controller.view, matching: MarkdownTextView.self).filter { editor in editor.window != nil } }
        try await waitUntil { editors().first != nil }
        return try XCTUnwrap(editors().first)
    }

    private func firstResponder(in view: UIView) -> UIView? {
        view.isFirstResponder ? view : view.subviews.lazy.compactMap(firstResponder).first
    }

    /// Has the text view find the view under a finger at a point of the window, as UIKit
    /// does when a touch begins there: the text view then counts as recently touched.
    private func touch(_ editor: MarkdownTextView, at windowPoint: CGPoint) {
        _ = editor.hitTest(editor.convert(windowPoint, from: nil), with: TouchEvent())
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in
            ((child as? View).map { matchingChild in [matchingChild] } ?? []) + descendants(of: child, matching: type)
        }
    }

    private static func setAccessibilityRuntimeEnabled(_ isEnabled: Bool) throws {
        let library = try XCTUnwrap(dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW), "The simulator's accessibility library.")
        typealias Setter = @convention(c) (Int32) -> Void
        for name in ["_AXSSetAutomationEnabled", "_AXSApplicationAccessibilitySetEnabled"] {
            let symbol = try XCTUnwrap(dlsym(library, name), name)
            unsafeBitCast(symbol, to: Setter.self)(isEnabled ? 1 : 0)
        }
    }

    /// The first accessibility element on screen that satisfies `matches`, once there is one.
    private func element(in controller: UIViewController, matching matches: @escaping (NSObject) -> Bool) async throws -> NSObject {
        var found: NSObject?
        try await waitUntil(seconds: 10) {
            found = self.accessibilityElements(in: controller.view).first(where: matches)
            return found != nil
        }
        return try XCTUnwrap(found)
    }

    private func accessibilityElements(in object: NSObject) -> [NSObject] {
        var elements: [NSObject] = object.isAccessibilityElement ? [object] : []
        let count = object.accessibilityElementCount()
        if let children = object.accessibilityElements {
            elements += children.compactMap { child in child as? NSObject }.flatMap(accessibilityElements)
        } else if count != NSNotFound, count > 0 {
            elements += (0..<count).compactMap { elementIndex in object.accessibilityElement(at: elementIndex) as? NSObject }.flatMap(accessibilityElements)
        } else if let view = object as? UIView {
            elements += view.subviews.flatMap(accessibilityElements)
        }
        return elements
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

    private func waitUntil(seconds: TimeInterval = 5, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertTrue(condition(), "The hosted workspace did not reach the expected state.")
    }
}
/// An event of a touch, as UIKit passes to hit-testing when a finger comes down.
private final class TouchEvent: UIEvent {
    override var type: UIEvent.EventType { .touches }
}
#endif
