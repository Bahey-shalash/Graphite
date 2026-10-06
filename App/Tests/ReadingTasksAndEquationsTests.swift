#if os(iOS)
import XCTest
import SwiftUI
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// Ticking tasks and equation numbers in the hosted reading view.
@MainActor
final class ReadingTasksAndEquationsTests: XCTestCase {
    private var window: UIWindow?
    private var vaultDirectory: URL?

    override func setUp() async throws {
        // SwiftUI builds its accessibility elements only while an assistive technology
        // asks for them; the test switches the accessibility runtime on, as VoiceOver or
        // UI automation would.
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

    // MARK: Tasks

    func testCheckboxIsAToggleThatTicksItsTaskAndKeepsTheReadingPosition() async throws {
        func paragraphs(_ numbers: ClosedRange<Int>) -> String {
            numbers.map { number in "Paragraph \(number) of the lecture, long enough to fill a line of the note.\n\n" }.joined()
        }
        let note = paragraphs(1...8) + "- [ ] Buy milk\n- [x] Read chapter\n\n" + paragraphs(9...80)
        let workspace = try await makeWorkspace(notes: ["Tasks.md": note])
        let session = try await openInReadingView("Tasks.md", in: workspace)
        let controller = try host(workspace)
        let checkbox = try await element(in: controller) { element in element.accessibilityLabel == "Buy milk" && element.accessibilityValue == "Not completed" }
        XCTAssertTrue(checkbox.accessibilityTraits.contains(.button))
        XCTAssertTrue(checkbox.accessibilityTraits.contains(.toggleButton))
        XCTAssertGreaterThanOrEqual(checkbox.accessibilityFrame.width, 40, "A touch target of reasonable size.")
        XCTAssertGreaterThanOrEqual(checkbox.accessibilityFrame.height, 30)

        // A touch on the checkbox reaches it; a touch on the task's text goes to text
        // selection, which does not tick the task.
        let window = try XCTUnwrap(window)
        let checkboxCenter = CGPoint(x: checkbox.accessibilityFrame.midX, y: checkbox.accessibilityFrame.midY)
        func textSelectionViewCoveringCheckbox() -> UIView? {
            descendants(of: window, matching: UIView.self).first { view in
                Self.isTextSelectionView(view) && view.convert(view.bounds, to: nil).contains(checkboxCenter)
            }
        }
        // The overlay is added once the text has been laid out.
        try await waitUntil { textSelectionViewCoveringCheckbox() != nil }
        let textSelectionView = try XCTUnwrap(textSelectionViewCoveringCheckbox(), "The text selection overlay covers the list.")
        XCTAssertFalse(textSelectionView.point(inside: textSelectionView.convert(checkboxCenter, from: nil), with: nil), "The overlay leaves the checkbox out.")
        XCTAssertFalse(window.hitTest(checkboxCenter, with: nil).map(Self.isTextSelectionView) ?? true)
        let taskText = try await element(in: controller) { element in (element.accessibilityLabel ?? "").hasSuffix("Buy milk") && element.accessibilityTraits.contains(.staticText) }
        XCTAssertLessThanOrEqual(checkbox.accessibilityFrame.maxX, taskText.accessibilityFrame.minX, "The checkbox's area ends before the text.")
        let textPoint = CGPoint(x: taskText.accessibilityFrame.midX, y: taskText.accessibilityFrame.midY)
        XCTAssertTrue(window.hitTest(textPoint, with: nil).map(Self.isTextSelectionView) ?? false)

        // Read further down, with the task still in view.
        let scrollView = try await readingScrollView(in: controller)
        scrollView.setContentOffset(CGPoint(x: 0, y: 150), animated: false)
        try await Task.sleep(for: .milliseconds(300))
        let offsetBeforeTick = scrollView.contentOffset.y
        XCTAssertEqual(offsetBeforeTick, 150, accuracy: 1)
        attachScreenshot(named: "Before the tick")
        let scrolledCheckbox = try await element(in: controller) { element in element.accessibilityLabel == "Buy milk" && element.accessibilityValue == "Not completed" }
        XCTAssertTrue(scrolledCheckbox.accessibilityActivate())
        let tickedNote = note.replacingOccurrences(of: "- [ ] Buy milk", with: "- [x] Buy milk")
        try await waitUntil { session.text == tickedNote }
        _ = try await element(in: controller) { element in element.accessibilityLabel == "Buy milk" && element.accessibilityValue == "Completed" }
        try await Task.sleep(for: .milliseconds(300))
        let scrollViewAfterTick = try await readingScrollView(in: controller)
        XCTAssertTrue(scrollViewAfterTick === scrollView)
        XCTAssertEqual(scrollView.contentOffset.y, offsetBeforeTick, accuracy: 1, "The note stays where it was read.")
        attachScreenshot(named: "After the tick")
        // Saved by the note's autosave.
        let file = try XCTUnwrap(vaultDirectory).appendingPathComponent("Tasks.md")
        try await waitUntil(seconds: 5) { (try? Data(contentsOf: file)) == Data(tickedNote.utf8) }
    }

    func testTickFromReadingViewIsOneUndoStepInTheNotesEditor() async throws {
        let workspace = try await makeWorkspace(notes: ["Tasks.md": "Shopping:\n- [ ] Buy milk\n"])
        await workspace.open(try VaultPath("Tasks.md"))
        let session = try XCTUnwrap(workspace.markdownSession)
        session.viewMode = .source
        let controller = try host(workspace)
        let editor = try await visibleEditor(in: controller, showing: session)
        editor.beginEditing()
        editor.selectedRange = NSRange(location: 8, length: 0)
        editor.insertText(" today")
        try await waitUntil { session.text == "Shopping today:\n- [ ] Buy milk\n" }
        try await Task.sleep(for: .milliseconds(50))
        editor.resignFirstResponder()

        session.viewMode = .reading
        let checkbox = try await element(in: controller) { element in element.accessibilityLabel == "Buy milk" && element.accessibilityValue == "Not completed" }
        XCTAssertTrue(checkbox.accessibilityActivate())
        try await waitUntil { session.text == "Shopping today:\n- [x] Buy milk\n" }

        session.viewMode = .source
        let returnedEditor = try await visibleEditor(in: controller, showing: session)
        XCTAssertTrue(returnedEditor === editor)
        returnedEditor.undoManager?.undo()
        try await waitUntil { session.text == "Shopping today:\n- [ ] Buy milk\n" }
        returnedEditor.undoManager?.undo()
        try await waitUntil { session.text == "Shopping:\n- [ ] Buy milk\n" }
        returnedEditor.undoManager?.redo()
        returnedEditor.undoManager?.redo()
        try await waitUntil { session.text == "Shopping today:\n- [x] Buy milk\n" }
    }

    func testTaskOfAnEmbeddedNoteIsTickedInThatNote() async throws {
        let workspace = try await makeWorkspace(notes: ["Host.md": "Before the embed.\n\n![[Groceries]]\n", "Groceries.md": "- [ ] Eggs\r\n- [ ] Flour\r\n"])
        let hostSession = try await openInReadingView("Host.md", in: workspace)
        let controller = try host(workspace)
        let checkbox = try await element(in: controller) { element in element.accessibilityLabel == "Flour" && element.accessibilityValue == "Not completed" }
        XCTAssertTrue(checkbox.accessibilityActivate())
        let groceries = try XCTUnwrap(vaultDirectory).appendingPathComponent("Groceries.md")
        try await waitUntil { (try? Data(contentsOf: groceries)) == Data("- [ ] Eggs\r\n- [x] Flour\r\n".utf8) }
        _ = try await element(in: controller) { element in element.accessibilityLabel == "Flour" && element.accessibilityValue == "Completed" }
        XCTAssertEqual(hostSession.text, "Before the embed.\n\n![[Groceries]]\n", "The note that embeds the task is unchanged.")
        attachScreenshot(named: "Embedded task ticked")
    }

    // MARK: Equation numbers

    func testEquationNumberStandsAtTheRightOfTheColumnAndIsNotCutOffWhenNarrow() async throws {
        let note = "An equation with a number.\n\n$$\nE = mc^2 \\tag{1}\n$$\n\n$$\n\\begin{align}\na + b + c &= d \\tag{2} \\\\\ne &= \\frac{f}{g} \\tag{3}\n\\end{align}\n$$\n"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReadingEquations-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        vaultDirectory = directory
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        // The wide case needs a window at least as wide: on a phone only the narrow one runs.
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let widths: [CGFloat] = scene.coordinateSpace.bounds.width >= 700 ? [700, 170] : [170]
        for width in widths {
            let controller = try host(AnyView(
                MarkdownPreview(source: note, path: try VaultPath("Equations.md"), root: directory, index: index, configuration: ReadingConfiguration(),
                                headingScrollRequest: .constant(nil), handledScrollToken: .constant(nil), navigate: { _, _ in }, openPDF: { _, _ in }, updateProperties: nil)
                    .frame(width: width)
                    .frame(maxWidth: .infinity, alignment: .leading)
            ))
            let paragraph = try await element(in: controller) { element in element.accessibilityLabel == "An equation with a number." }
            // The column is centered in the note, so its right edge mirrors the left one.
            let columnLeftEdge = paragraph.accessibilityFrame.minX
            let columnRightEdge = width - columnLeftEdge
            for (label, numberCount) in [("Equation (1)", 1), ("Equation (2) (3)", 2)] {
                let equation = try await element(in: controller) { element in element.accessibilityLabel == label }
                let frame = equation.accessibilityFrame
                XCTAssertGreaterThanOrEqual(frame.minX, columnLeftEdge - 1, "\(label) at \(width) points")
                XCTAssertLessThanOrEqual(frame.maxX, columnRightEdge + 1, "\(label) at \(width) points")
                let ink = try inkImage(of: frame.insetBy(dx: -4, dy: -4))
                // The numbers' ink ends at the right edge of the column, within their side bearing.
                let lastInkColumn = try XCTUnwrap(ink.inkColumns.last)
                XCTAssertGreaterThanOrEqual(lastInkColumn, ink.pixelWidth - 8 - 10, "\(label) at \(width) points")
                if width > 400 {
                    XCTAssertEqual(ink.inkColumnRuns(separatedByMoreThan: 24).count, 2, "The formula, then its numbers, at \(width) points.")
                } else {
                    XCTAssertGreaterThan(ink.inkRowRuns(separatedByMoreThan: 4).count, numberCount, "Numbers on lines of their own at \(width) points.")
                }
                // Around the block, outside its frame, there is no ink: nothing reaches past it.
                XCTAssertFalse(ink.inkColumns.contains { column in column < 8 || column >= ink.pixelWidth - 8 }, "\(label) at \(width) points")
            }
            attachScreenshot(named: "Equation numbers at \(Int(width)) points")
            window?.isHidden = true
            window = nil
        }
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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReadingTasks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let vaultDirectory { try? FileManager.default.removeItem(at: vaultDirectory) }
        vaultDirectory = directory
        for (name, text) in notes { try Data(text.utf8).write(to: directory.appendingPathComponent(name)) }
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        try await index.refresh(paths: notes.keys.map { name in try VaultPath(name) }, root: directory)
        workspace.index = index
        return workspace
    }

    private func openInReadingView(_ name: String, in workspace: WorkspaceModel) async throws -> MarkdownSession {
        await workspace.open(try VaultPath(name))
        let session = try XCTUnwrap(workspace.markdownSession)
        session.viewMode = .reading
        return session
    }

    private func host(_ workspace: WorkspaceModel) throws -> UIHostingController<AnyView> {
        try host(AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        }))
    }

    private func host(_ rootView: AnyView) throws -> UIHostingController<AnyView> {
        let controller = UIHostingController(rootView: rootView)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        return controller
    }

    private func readingScrollView(in controller: UIViewController) async throws -> UIScrollView {
        func tallScrollView() -> UIScrollView? {
            descendants(of: controller.view, matching: UIScrollView.self).first { scrollView in scrollView.contentSize.height > scrollView.bounds.height * 2 }
        }
        try await waitUntil { tallScrollView() != nil }
        return try XCTUnwrap(tallScrollView())
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

    /// The window's pixels inside `frame`, in screen points, two pixels to the point.
    private func inkImage(of frame: CGRect) throws -> InkImage {
        let window = try XCTUnwrap(window)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(bounds: frame, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        return try XCTUnwrap(InkImage(image: image))
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

    private func waitUntil(seconds: TimeInterval = 5, _ condition: () throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !(try condition()), Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertTrue(try condition(), "The hosted reading view did not reach the expected state.")
    }
}

/// Which pixels of a picture are ink: dark on the light note.
private struct InkImage {
    let pixelWidth: Int
    let pixelHeight: Int
    private let inkPixels: [Bool]

    init?(image: UIImage) {
        guard let cgImage = image.cgImage else { return nil }
        pixelWidth = cgImage.width
        pixelHeight = cgImage.height
        var pixels = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        guard let context = CGContext(data: &pixels, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: pixelWidth * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        inkPixels = stride(from: 0, to: pixels.count, by: 4).map { offset in
            (Int(pixels[offset]) + Int(pixels[offset + 1]) + Int(pixels[offset + 2])) / 3 < 128
        }
    }

    private func isInk(horizontalPixel: Int, verticalPixel: Int) -> Bool { inkPixels[verticalPixel * pixelWidth + horizontalPixel] }

    var inkColumns: [Int] {
        (0..<pixelWidth).filter { horizontalPixel in (0..<pixelHeight).contains { verticalPixel in isInk(horizontalPixel: horizontalPixel, verticalPixel: verticalPixel) } }
    }

    func inkColumnRuns(separatedByMoreThan gap: Int) -> [ClosedRange<Int>] { Self.runs(of: inkColumns, separatedByMoreThan: gap) }

    func inkRowRuns(separatedByMoreThan gap: Int) -> [ClosedRange<Int>] {
        let inkRows = (0..<pixelHeight).filter { verticalPixel in (0..<pixelWidth).contains { horizontalPixel in isInk(horizontalPixel: horizontalPixel, verticalPixel: verticalPixel) } }
        return Self.runs(of: inkRows, separatedByMoreThan: gap)
    }

    private static func runs(of positions: [Int], separatedByMoreThan gap: Int) -> [ClosedRange<Int>] {
        var runs: [ClosedRange<Int>] = []
        for position in positions {
            if let last = runs.last, position - last.upperBound <= gap + 1 {
                runs[runs.count - 1] = last.lowerBound...position
            } else {
                runs.append(position...position)
            }
        }
        return runs
    }
}
#endif
