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

    /// A block's view offers "Edit Source" from a UIKit menu of its own, which SwiftUI
    /// does not work out again each time the view is drawn.
    func testABlockViewOffersEditSource() throws {
        var revealed = false
        let host = RenderedBlockHost.makeRenderedBlockHost(root: RenderedBlockRoot(view: AnyView(Text("Block")), revealSource: { revealed = true }))
        let interaction = try XCTUnwrap(host.view.interactions.compactMap { interaction in interaction as? UIContextMenuInteraction }.first)
        XCTAssertNotNil(interaction.delegate?.contextMenuInteraction(interaction, configurationForMenuAtLocation: .zero))
        let editSourceMenu = try XCTUnwrap(interaction.delegate as? RenderedBlockEditSourceMenu)
        let action = try XCTUnwrap(editSourceMenu.makeMenu().children.first as? UIAction)
        XCTAssertEqual(action.title, "Edit Source")
        action.performWithSender(nil, target: nil)
        XCTAssertTrue(revealed)
    }

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

    /// Properties at the top of a note longer than the window.
    private static let propertiesThenTextNote: String = {
        let properties = (1...8).map { propertyNumber in "property\(propertyNumber): value \(propertyNumber)" }
        let paragraphs = (1...80).map { paragraphNumber in "Paragraph \(paragraphNumber) of the note's text." }
        return "---\n" + properties.joined(separator: "\n") + "\n---\n" + paragraphs.joined(separator: "\n\n") + "\n"
    }()

    /// A drag that starts on the properties scrolls the note, as one starting on its text
    /// does, and starts editing neither the note nor a property. (Synthesized touches reach
    /// UIKit's gesture recognizers but not SwiftUI's controls, so a tap on a block's control,
    /// such as a folded callout's title, is checked in the simulator instead.)
    func testADragStartingOnThePropertiesScrollsTheNote() async throws {
        if let reason = SynthesizedTouches.unavailableReason { throw XCTSkip(reason) }
        let (_, editor) = try await openNote(Self.propertiesThenTextNote)
        try await waitForPlacementToSettle(in: editor)
        let propertiesView = try XCTUnwrap(blockViews(in: editor).first, "The properties are not rendered.")
        let window = try XCTUnwrap(window)
        // On a property's value, where a field takes a tap.
        let start = editor.convert(CGPoint(x: propertiesView.frame.midX + 40, y: propertiesView.frame.minY + propertiesView.frame.height * 0.6), to: window)
        let offsetBeforeDrag = editor.contentOffset.y
        await SynthesizedTouches(window: window).drag(from: start, to: CGPoint(x: start.x, y: start.y - 300))
        try await waitForPlacementToSettle(in: editor)
        attachScreenshot(named: "After a drag from the properties")
        XCTAssertGreaterThan(editor.contentOffset.y, offsetBeforeDrag + 150, "The note did not scroll.")
        XCTAssertFalse(editor.isFirstResponder, "The drag started editing the note.")
        XCTAssertFalse(descendants(of: propertiesView, matching: UITextField.self).contains { field in field.isFirstResponder }, "The drag started editing a property.")
        let frontmatterEnd = (editor.text as NSString).range(of: "\n---\n").location
        let frontmatterStyle = editor.textStorage.attribute(.paragraphStyle, at: frontmatterEnd, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(frontmatterStyle?.maximumLineHeight, 0.01, "The YAML is shown in place of the properties.")
    }

    /// A drawing between two lines of text, as a note with sketches has them.
    private static let drawingNote = "Text before the drawing.\n\n![[Diagram.png]]\n\nText after the drawing.\n"

    private static var diagramPNG: Data {
        UIGraphicsImageRenderer(size: CGSize(width: 400, height: 200)).pngData { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        }
    }

    /// The system reports a note's own save back as a change to a file of the vault, which
    /// changes the drawing version. The rendered blocks were rebuilt for it, and every
    /// drawing on screen showed an empty space for a few frames after each save.
    func testAChangedFileKeepsTheDrawingOnScreen() async throws {
        let (workspace, editor) = try await openNote(Self.drawingNote, attachments: ["Diagram.png": Self.diagramPNG])
        try await waitForPlacementToSettle(in: editor)
        try await waitUntil { self.blockViews(in: editor).first.map { view in view.frame.height > 100 } ?? false }
        let viewsBeforeChange = blockViews(in: editor).map(ObjectIdentifier.init)
        XCTAssertEqual(viewsBeforeChange.count, 1, "The drawing is not rendered.")

        workspace.drawingVersion += 1
        try await waitForPlacementToSettle(in: editor)
        attachScreenshot(named: "After a file changed")
        XCTAssertEqual(blockViews(in: editor).map(ObjectIdentifier.init), viewsBeforeChange, "The drawing's view was made again, which shows nothing until it finds its file.")
    }

    /// The cursor leaving a drawing's line hides its source again, and the drawing is back
    /// over its space by the end of that layout pass, above the text after it. This passes
    /// with the drawing placed a turn of the run loop later too: here TextKit has laid the
    /// line out by then. On the iPad simulator, a tap on a misspelled word below the drawing
    /// (which selects it and scrolls) left the drawing's space empty for 28 to 38 ms before
    /// the editor laid the viewport out in the same pass.
    func testADrawingTheCursorLeavesIsPlacedInTheSameLayoutPass() async throws {
        let (_, editor) = try await openNote(Self.drawingNote, attachments: ["Diagram.png": Self.diagramPNG])
        try await waitForPlacementToSettle(in: editor)
        try await waitUntil { self.blockViews(in: editor).first.map { view in view.frame.height > 100 } ?? false }
        let source = editor.text as NSString

        editor.beginEditing()
        XCTAssertTrue(editor.isFirstResponder)
        editor.selectedRange = NSRange(location: source.range(of: "Diagram").location, length: 0)
        try await waitForPlacementToSettle(in: editor)
        XCTAssertTrue(blockViews(in: editor).isEmpty, "The drawing still covers its source with the cursor in it.")

        editor.selectedRange = NSRange(location: source.range(of: "Text after").location, length: 0)
        editor.layoutIfNeeded()
        attachScreenshot(named: "Right after the cursor left the drawing")
        let drawingView = try XCTUnwrap(blockViews(in: editor).first, "The drawing was not placed in the layout pass that hid its source again.")
        let lineAfter = try XCTUnwrap(lineFrame(atCharacter: source.range(of: "Text after").location, in: editor))
        XCTAssertLessThanOrEqual(drawingView.frame.maxY, lineAfter.minY + 1, "The drawing covers the text after it.")
        XCTAssertGreaterThan(drawingView.frame.height, 100)
        editor.resignFirstResponder()
    }

    /// A flowchart between two lines of text.
    private static let diagramCode = "flowchart TD\n  A[Start] --> B{Done?}\n  B -->|yes| C[End]"
    private static let diagramNote = "Text before the diagram.\n\n```mermaid\n\(diagramCode)\n```\n\nText after the diagram.\n"

    /// Live Preview draws a diagram over its concealed fence, at the height the reading view lays it out at and above the
    /// text after it; the cursor in the fence shows its source, and leaving the fence draws the diagram again from the view
    /// kept meanwhile.
    func testADiagramIsDrawnOverItsFenceAndTheCursorInItShowsItsSource() async throws {
        let (_, editor) = try await openNote(Self.diagramNote)
        try await waitForPlacementToSettle(in: editor)
        let source = editor.text as NSString
        XCTAssertEqual(blockViews(in: editor).count, 1, "The diagram is not drawn.")
        let diagramView = try XCTUnwrap(blockViews(in: editor).first)
        attachScreenshot(named: "The diagram drawn")
        // The diagram as the reading view lays it out in the note's text font and size, scaled to the column if wider.
        let textSize = try XCTUnwrap((editor.typingAttributes[.font] as? UIFont)?.pointSize)
        let environment = LivePreviewEnvironment(root: try XCTUnwrap(vaultDirectory), textSize: Double(textSize), colorsEnabled: true, paletteHexByName: [:],
                                                 drawingVersion: 0, resolve: { _, _ in nil }, open: { _ in }, follow: { _, _ in }, updateProperties: nil)
        let request = LivePreviewDiagramRequest(source: Self.diagramCode, environment: environment)
        guard case .diagram(.flowchart(let flowchart)) = LivePreviewDiagramPreparation.content(of: request) else {
            return XCTFail("The flowchart is drawn natively")
        }
        let diagramScale = min(1, diagramView.frame.width / flowchart.layout.size.width)
        let blockVerticalPadding: CGFloat = 8
        XCTAssertEqual(diagramView.frame.height, flowchart.layout.size.height * diagramScale + blockVerticalPadding, accuracy: 1,
                       "The view holds the laid-out diagram, not its code.")
        let lineAfter = try XCTUnwrap(lineFrame(atCharacter: source.range(of: "Text after").location, in: editor))
        XCTAssertLessThanOrEqual(diagramView.frame.maxY, lineAfter.minY + 1, "The diagram covers the text after it.")

        editor.beginEditing()
        XCTAssertTrue(editor.isFirstResponder)
        let codeLocation = source.range(of: "A[Start]").location
        editor.selectedRange = NSRange(location: codeLocation, length: 0)
        try await waitForPlacementToSettle(in: editor)
        attachScreenshot(named: "The cursor in the diagram's fence")
        XCTAssertTrue(blockViews(in: editor).isEmpty, "The diagram still covers its source with the cursor in it.")
        let codeStyle = editor.textStorage.attribute(.paragraphStyle, at: codeLocation, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertNotEqual(codeStyle?.maximumLineHeight, 0.01, "The diagram's source is still concealed.")

        editor.selectedRange = NSRange(location: source.range(of: "Text after").location, length: 0)
        try await waitForPlacementToSettle(in: editor)
        attachScreenshot(named: "The cursor after the diagram")
        let drawnAgain = try XCTUnwrap(blockViews(in: editor).first, "The diagram is not drawn again.")
        XCTAssertTrue(drawnAgain === diagramView, "The view kept while the cursor was in the fence is not the one shown again.")
        let lineAfterAgain = try XCTUnwrap(lineFrame(atCharacter: source.range(of: "Text after").location, in: editor))
        XCTAssertLessThanOrEqual(drawnAgain.frame.maxY, lineAfterAgain.minY + 1, "The diagram covers the text after it.")
        editor.resignFirstResponder()
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

    private func openNote(_ text: String, attachments: [String: Data] = [:]) async throws -> (WorkspaceModel, MarkdownTextView) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LivePreviewPlacement-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        vaultDirectory = directory
        try Data(text.utf8).write(to: directory.appendingPathComponent("Placement.md"))
        for (name, contents) in attachments { try contents.write(to: directory.appendingPathComponent(name)) }
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

}
#endif
