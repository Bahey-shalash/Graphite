#if os(iOS)
import XCTest
import SwiftUI
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// A tap on a link in the hosted reading view follows it.
@MainActor
final class ReadingLinkFollowingTests: XCTestCase {
    private var window: UIWindow?

    override func setUp() async throws {
        // SwiftUI builds its accessibility elements only while an assistive technology
        // asks for them; the test switches the accessibility runtime on, as VoiceOver or
        // UI automation would, to find where the link is drawn.
        try Self.setAccessibilityRuntimeEnabled(true)
    }

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        try Self.setAccessibilityRuntimeEnabled(false)
    }

    private static let lausanneNote: String = {
        let paragraphs = (1...40).map { paragraphNumber in "Paragraph \(paragraphNumber) about Lausanne, long enough to fill a line of the note." }
        return "[[Geneva]]\n\n" + paragraphs.joined(separator: "\n\n") + "\n"
    }()

    /// The tap followed nothing until something laid the note out again, such as opening and
    /// closing Settings: the text's selection model, which finds the link under a tap, kept the
    /// empty layouts the text had in its first update (Textual patch 20, BUG-READING-06).
    func testTapOnALinkRightAfterSwitchingFromLivePreviewFollowsIt() async throws {
        if let reason = SynthesizedTouches.unavailableReason {
            XCTFail(reason)
            return
        }
        let workspace = try await makeWorkspace(notes: [
            "Start.md": "Read about [[Lausanne]] and [[Geneva#Old town]].\n",
            "Lausanne.md": Self.lausanneNote,
            "Geneva.md": "# Old town\n\nThe cathedral.\n\n# Lake\n\nThe jet of water.\n",
        ])
        await workspace.open(try VaultPath("Lausanne.md"))
        let session = try XCTUnwrap(workspace.markdownSession)
        session.viewMode = .livePreview
        let controller = try host(workspace)
        _ = try await visibleEditor(in: controller, showing: session)

        // The pencil's switch to the reading view.
        session.toggleReadingView(editingMode: .livePreview)
        let link = try await element(in: controller) { element in
            element.accessibilityLabel == "Geneva" && element.accessibilityTraits.contains(.staticText)
        }
        let window = try XCTUnwrap(window)
        let linkPoint = CGPoint(x: link.accessibilityFrame.minX + 12, y: link.accessibilityFrame.midY)
        // The text selection overlay takes the touch; it is added once the text is laid out.
        try await waitUntil("the text selection overlay covers the link") {
            window.hitTest(linkPoint, with: nil).map(Self.isTextSelectionView) ?? false
        }
        attachScreenshot(named: "Reading view before the tap")

        let touches = SynthesizedTouches(window: window)
        touches.begin(at: [linkPoint])
        touches.end()
        try await waitUntil("the link opens Geneva", timeoutSeconds: 5) { workspace.markdownSession?.path.rawValue == "Geneva.md" }
        attachScreenshot(named: "After the tap")
    }

    // MARK: Helpers

    private static func setAccessibilityRuntimeEnabled(_ isEnabled: Bool) throws {
        let library = try XCTUnwrap(dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW), "The simulator's accessibility library.")
        typealias Setter = @convention(c) (Int32) -> Void
        for name in ["_AXSSetAutomationEnabled", "_AXSApplicationAccessibilitySetEnabled"] {
            let symbol = try XCTUnwrap(dlsym(library, name), name)
            unsafeBitCast(symbol, to: Setter.self)(isEnabled ? 1 : 0)
        }
    }

    private static func isTextSelectionView(_ view: UIView) -> Bool {
        String(describing: type(of: view)) == "UITextInteractionView"
    }

    private func makeWorkspace(notes: [String: String]) async throws -> WorkspaceModel {
        let vault = try TemporaryVault.make(prefix: "ReadingLinks", files: notes, for: self)
        try FileManager.default.createDirectory(at: vault.cacheDirectory, withIntermediateDirectories: true)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault.root)
        workspace.store = VaultStore(root: vault.root)
        let index = try VaultIndex(databaseURL: vault.cacheDirectory.appendingPathComponent("index.sqlite"))
        try await index.refresh(paths: notes.keys.map { name in try VaultPath(name) }, root: vault.root)
        workspace.index = index
        return workspace
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

    private func visibleEditor(in controller: UIViewController, showing session: MarkdownSession) async throws -> MarkdownTextView {
        func editors() -> [MarkdownTextView] { descendants(of: controller.view, matching: MarkdownTextView.self).filter { editor in editor.window != nil } }
        try await waitUntil { editors().contains { editor in editor.text == session.text && editor.bounds.width > 0 } }
        return try XCTUnwrap(editors().first { editor in editor.text == session.text })
    }

    /// The first accessibility element on screen that satisfies `matches`, once there is one.
    private func element(in controller: UIViewController, matching matches: @escaping (NSObject) -> Bool) async throws -> NSObject {
        var found: NSObject?
        try await waitUntil {
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

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in
            ((child as? View).map { matchingChild in [matchingChild] } ?? []) + descendants(of: child, matching: type)
        }
    }
}
#endif
