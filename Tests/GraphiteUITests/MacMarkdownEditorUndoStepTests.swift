#if os(macOS)
import AppKit
import XCTest
import GraphiteCore
@testable import GraphiteUI

/// Every change the Mac editor makes itself (an external change to the file, an insertion,
/// code formatting) is one step of the note's own undo history, and undo and redo are applied
/// exactly as recorded.
@MainActor
final class MacMarkdownEditorUndoStepTests: XCTestCase {
    private var fixture: MacMarkdownEditorFixture?

    override func tearDown() async throws {
        fixture?.tearDown()
        fixture = nil
        try await super.tearDown()
    }

    private func makeFixture(text: String) async throws -> MacMarkdownEditorFixture {
        let fixture = try await MacMarkdownEditorFixture(text: text)
        self.fixture = fixture
        return fixture
    }

    /// Lets the main queue run what the editor deferred to the next turn of the run loop.
    private func waitForTheNextTurn() async {
        let turnPassed = expectation(description: "next turn")
        DispatchQueue.main.async { turnPassed.fulfill() }
        await fulfillment(of: [turnPassed], timeout: 5)
    }

    func testAnExternalChangeIsOneUndoableStepThatRestoresTheOldTextExactly() async throws {
        let original = "---\nrule\n---\nAlpha beta\n"
        let fixture = try await makeFixture(text: original)
        let undoManager = fixture.coordinator.noteUndoManager
        XCTAssertFalse(undoManager.canUndo)

        fixture.coordinator.replaceText(with: "---\nrule\n---\nAlpha gamma beta\n", in: fixture.textView)
        XCTAssertEqual(fixture.textView.string, "---\nrule\n---\nAlpha gamma beta\n")
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()
        XCTAssertEqual(fixture.textView.string, original)
        XCTAssertFalse(undoManager.canUndo, "The change was one step.")
        XCTAssertFalse(fixture.textView.string.contains("\u{2014}"), "No dash was made of the rule.")
        undoManager.redo()
        XCTAssertEqual(fixture.textView.string, "---\nrule\n---\nAlpha gamma beta\n")
    }

    func testAnInsertionIsOneUndoableStep() async throws {
        let original = "Lecture.\n"
        let fixture = try await makeFixture(text: original)
        fixture.coordinator.resume(fixture.scrollView)
        let undoManager = fixture.coordinator.noteUndoManager
        fixture.session.insert("![[Recording.m4a]]", at: NSRange(location: (original as NSString).length, length: 0))
        XCTAssertTrue(fixture.coordinator.applyPendingInsertions(to: fixture.textView))
        XCTAssertEqual(fixture.textView.string, "Lecture.\n![[Recording.m4a]]")
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()
        XCTAssertEqual(fixture.textView.string, original)
        XCTAssertFalse(undoManager.canUndo)
    }

    func testFormattingACodeBlockIsOneUndoableStepThatPutsTheCodeBack() async throws {
        let original = "Intro\n```c\nint main(){\nreturn 0;\n}\n```\nAfter\n"
        let fixture = try await makeFixture(text: original)
        let textView = fixture.textView
        let source = original as NSString
        // The cursor enters the block, a space is typed in the code, and the cursor leaves.
        textView.setSelectedRange(NSRange(location: source.range(of: "return").location, length: 0))
        await waitForTheNextTurn()
        textView.insertText(" ", replacementRange: NSRange(location: source.range(of: "return").location, length: 0))
        let typed = textView.string
        XCTAssertEqual(typed, "Intro\n```c\nint main(){\n return 0;\n}\n```\nAfter\n")
        textView.setSelectedRange(NSRange(location: (typed as NSString).range(of: "After").location, length: 0))
        XCTAssertEqual(textView.string, typed, "Formatting waits for the next turn of the run loop.")

        await waitForTheNextTurn()
        XCTAssertEqual(textView.string, "Intro\n```c\nint main() {\n    return 0;\n}\n```\nAfter\n")

        let undoManager = fixture.coordinator.noteUndoManager
        undoManager.undo()
        XCTAssertEqual(textView.string, typed, "One undo puts the unformatted code back.")
    }

    func testMovingTheCursorThroughAnUnformattedBlockWithoutTypingLeavesTheTextAlone() async throws {
        let original = "Intro\n```c\nint main(){\nreturn 0;\n}\n```\nAfter\n"
        let fixture = try await makeFixture(text: original)
        let source = original as NSString
        for fragment in ["return", "int main", "After", "Intro"] {
            fixture.textView.setSelectedRange(NSRange(location: source.range(of: fragment).location, length: 0))
            await waitForTheNextTurn()
        }
        await waitForTheNextTurn()
        XCTAssertEqual(fixture.textView.string, original)
        XCTAssertFalse(fixture.coordinator.noteUndoManager.canUndo)
    }

    // MARK: Undo and redo are not refused

    private static let propertiesNote = "---\ntitle: Tokyo\ntags:\n  - travel\n---\nBody text\n"

    func testUndoAndRedoAreNotRefusedForCuttingIntoTheConcealedProperties() async throws {
        let fixture = try await makeFixture(text: Self.propertiesNote)
        fixture.coordinator.environment = LivePreviewEnvironment(
            root: FileManager.default.temporaryDirectory, textSize: 17, colorsEnabled: true, paletteHexByName: [:], drawingVersion: 0,
            resolve: { _, _ in nil }, open: { _ in }, follow: { _, _ in }, updateProperties: { [session = fixture.session] properties in session.replaceProperties(properties) })
        fixture.coordinator.restyleEverything(in: fixture.textView, forcesBlockScan: true)
        let propertiesEnd = (Self.propertiesNote as NSString).range(of: "Body").location
        let cuttingRange = NSRange(location: 4, length: propertiesEnd - 4)
        XCTAssertFalse(fixture.coordinator.textView(fixture.textView, shouldChangeTextIn: cuttingRange, replacementString: ""),
                       "Typing over the YAML up to its end is refused.")

        let undoManager = fixture.coordinator.noteUndoManager
        var answers: [String: Bool] = [:]
        let target = NSObject()
        undoManager.registerUndo(withTarget: target) { [weak fixture] _ in
            MainActor.assumeIsolated {
                guard let fixture else { return }
                answers["during undo"] = fixture.coordinator.textView(fixture.textView, shouldChangeTextIn: cuttingRange, replacementString: "")
                undoManager.registerUndo(withTarget: target) { [weak fixture] _ in
                    MainActor.assumeIsolated {
                        guard let fixture else { return }
                        answers["during redo"] = fixture.coordinator.textView(fixture.textView, shouldChangeTextIn: cuttingRange, replacementString: "")
                    }
                }
            }
        }
        undoManager.undo()
        undoManager.redo()
        XCTAssertEqual(answers, ["during undo": true, "during redo": true])
    }
}
#endif
