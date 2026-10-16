#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import GraphiteCore
@testable import GraphiteUI

/// Fenced code is colored by its language on the Mac: in Live Preview and Source mode, as
/// the editor restyles it, and in reading view.
@MainActor
final class UiCodeHighlightingMacTests: XCTestCase {
    private var vaultDirectories: [URL] = []

    override func tearDown() async throws {
        for vaultDirectory in vaultDirectories { try? FileManager.default.removeItem(at: vaultDirectory) }
        vaultDirectories = []
        try await super.tearDown()
    }

    private func makeEditor(text: String, mode: EditingMode) async throws -> (NativeMarkdownEditor.Coordinator, MarkdownMacTextView) {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("Vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        vaultDirectories.append(vault)
        try Data(text.utf8).write(to: vault.appendingPathComponent("Note.md"))
        let store = VaultStore(root: vault)
        let notePath = try VaultPath("Note.md")
        let session = try MarkdownSession(path: notePath, snapshot: try await store.read(notePath), store: store, didSave: { _ in })
        var configuration = EditorConfiguration()
        configuration.mode = mode
        let coordinator = NativeMarkdownEditor.Coordinator(session: session, configuration: configuration)
        let scrollView = MarkdownMacTextView.makeScrollableTextView()
        let textView = try XCTUnwrap(scrollView.documentView as? MarkdownMacTextView)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.delegate = coordinator
        coordinator.connect(textView)
        coordinator.restyleEverything(in: textView)
        return (coordinator, textView)
    }

    private func foregroundColor(of text: String, in textStorage: NSTextStorage, occurrence: Int = 0) -> NSColor? {
        let source = textStorage.string as NSString
        var searchStart = 0
        var range = NSRange(location: NSNotFound, length: 0)
        for _ in 0...occurrence {
            range = source.range(of: text, range: NSRange(location: searchStart, length: source.length - searchStart))
            guard range.location != NSNotFound else { return nil }
            searchStart = NSMaxRange(range)
        }
        return textStorage.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor
    }

    private static let cppNote = """
        Some prose with int in it.

        ```cpp
        #include <vector>
        int main() {
            return 42; // done
        }
        ```

        After the block.
        """

    func testACppBlockIsColoredInLivePreviewAndSourceMode() async throws {
        for mode in [EditingMode.livePreview, .source] {
            let (_, textView) = try await makeEditor(text: Self.cppNote, mode: mode)
            let textStorage = try XCTUnwrap(textView.textStorage)
            XCTAssertEqual(foregroundColor(of: "int", in: textStorage, occurrence: 1), CodeSyntaxColors.color(for: .typeName, theme: nil), "\(mode)")
            XCTAssertEqual(foregroundColor(of: "return", in: textStorage), CodeSyntaxColors.color(for: .keyword, theme: nil), "\(mode)")
            XCTAssertEqual(foregroundColor(of: "42", in: textStorage), CodeSyntaxColors.color(for: .number, theme: nil), "\(mode)")
            XCTAssertEqual(foregroundColor(of: "// done", in: textStorage), CodeSyntaxColors.color(for: .comment, theme: nil), "\(mode)")
            XCTAssertEqual(foregroundColor(of: "#include", in: textStorage), CodeSyntaxColors.color(for: .preprocessor, theme: nil), "\(mode)")
            XCTAssertEqual(foregroundColor(of: "main", in: textStorage), CodeSyntaxColors.color(for: .function, theme: nil), "\(mode)")
            // Prose outside the block keeps the text color, even its words that are C++ keywords.
            XCTAssertNotEqual(foregroundColor(of: "int", in: textStorage), CodeSyntaxColors.color(for: .typeName, theme: nil), "\(mode)")
            XCTAssertNotEqual(foregroundColor(of: "After", in: textStorage), CodeSyntaxColors.color(for: .comment, theme: nil), "\(mode)")
        }
    }

    func testAnUnknownLanguageStaysPlain() async throws {
        let (_, textView) = try await makeEditor(text: "```dataview\nreturn int 42\n```\n", mode: .source)
        let textStorage = try XCTUnwrap(textView.textStorage)
        let plainColor = foregroundColor(of: "return", in: textStorage)
        XCTAssertNotEqual(plainColor, CodeSyntaxColors.color(for: .keyword, theme: nil))
        XCTAssertEqual(foregroundColor(of: "42", in: textStorage), plainColor)
    }

    /// Typing `/*` turns the lines after it into a comment, beyond the lines an edit
    /// restyles; typing `*/` turns them back.
    func testOpeningABlockCommentRecolorsTheLinesAfterIt() async throws {
        var codeLines = (0..<40).map { index in "int value\(index) = \(index);" }
        // A blank line inside the comment does not stop the recoloring.
        codeLines.insert("", at: 25)
        let note = "Intro\n\n```c\n" + codeLines.joined(separator: "\n") + "\n```\n\nAfter int text.\n"
        let (coordinator, textView) = try await makeEditor(text: note, mode: .source)
        let textStorage = try XCTUnwrap(textView.textStorage)
        let comment = CodeSyntaxColors.color(for: .comment, theme: nil)
        let typeName = CodeSyntaxColors.color(for: .typeName, theme: nil)
        XCTAssertEqual(foregroundColor(of: "int value30", in: textStorage), typeName)

        let insertion = (textStorage.string as NSString).range(of: "int value10").location
        textView.setSelectedRange(NSRange(location: insertion, length: 0))
        textView.insertText("/*", replacementRange: NSRange(location: insertion, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        XCTAssertEqual(foregroundColor(of: "int value30", in: textStorage), comment, "A line far below the edit is now in the comment.")
        XCTAssertEqual(foregroundColor(of: "int value9", in: textStorage), typeName, "A line above the edit is unchanged.")
        XCTAssertNotEqual(foregroundColor(of: "After", in: textStorage), comment, "The comment ends with the block.")

        let closing = (textStorage.string as NSString).range(of: "int value20").location
        textView.setSelectedRange(NSRange(location: closing, length: 0))
        textView.insertText("*/", replacementRange: NSRange(location: closing, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        XCTAssertEqual(foregroundColor(of: "int value30", in: textStorage), typeName, "Closing the comment colors the code after it again.")
        XCTAssertEqual(foregroundColor(of: "int value15", in: textStorage), comment)
    }

    // MARK: Reading view

    /// Pixels of the rendered view whose color is clearly not gray: syntax colors, where
    /// plain code is black on a light gray background.
    private func saturatedPixelCount(of markdown: String) async throws -> Int {
        let root = FileManager.default.temporaryDirectory
        let view = ObsidianMarkdownText(markdown: markdown, root: root, textSize: 17, navigate: { _, _ in }, scrollToHeading: { _ in })
            .frame(width: 420, height: 220, alignment: .topLeading)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        let hostingView = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 220), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hostingView
        hostingView.frame = NSRect(x: 0, y: 0, width: 420, height: 220)
        defer { window.contentView = nil; window.orderOut(nil) }
        for _ in 0..<10 {
            hostingView.layoutSubtreeIfNeeded()
            hostingView.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        var count = 0
        for verticalPixel in 0..<bitmap.pixelsHigh {
            for horizontalPixel in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: horizontalPixel, y: verticalPixel)?.usingColorSpace(.deviceRGB) else { continue }
                let components = [color.redComponent, color.greenComponent, color.blueComponent]
                if let largest = components.max(), let smallest = components.min(), largest - smallest > 0.25 { count += 1 }
            }
        }
        return count
    }

    func testReadingViewColorsACppBlock() async throws {
        let code = "#include <vector>\nint main() {\n    return 42; // done\n}"
        let colored = try await saturatedPixelCount(of: "```cpp\n\(code)\n```")
        let plain = try await saturatedPixelCount(of: "```dataview\n\(code)\n```")
        XCTAssertGreaterThan(colored, 200, "The C++ block is drawn in syntax colors.")
        XCTAssertLessThan(plain, colored / 10, "A block in an unknown language stays plain.")
    }

    func testReadingSegmentsJoinToTheCode() throws {
        let code = "entity counter is\n  port (CLKxCI : in std_logic); -- clock\nend entity;"
        let segments = try XCTUnwrap(CodeSyntaxColors.readingSegments(code: code, language: "vhdl"))
        XCTAssertEqual(segments.map(\.content).joined(), code)
        XCTAssertTrue(segments.contains { segment in segment.content == "-- clock" && segment.type == .comment })
        XCTAssertTrue(segments.contains { segment in segment.content == "entity" && segment.type == .keyword })
        XCTAssertNil(CodeSyntaxColors.readingSegments(code: code, language: "dataview"))
    }
}
#endif
