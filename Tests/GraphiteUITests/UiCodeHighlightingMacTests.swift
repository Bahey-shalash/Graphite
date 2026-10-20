#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// Fenced code is colored by its language on the Mac: in Live Preview and Source mode, as
/// the editor restyles it, and in reading view.
@MainActor
final class UiCodeHighlightingMacTests: XCTestCase {
    override func tearDown() async throws {
        try await super.tearDown()
    }

    private func makeEditor(text: String, mode: EditingMode, formatsCodeBlocks: Bool = true, codeColorTheme: CodeColorTheme = .obsidian) async throws -> (NativeMarkdownEditor.Coordinator, MarkdownMacTextView) {
        let vault = try TemporaryVault.make(prefix: "Vault", for: self).root
        try Data(text.utf8).write(to: vault.appendingPathComponent("Note.md"))
        let store = VaultStore(root: vault)
        let notePath = try VaultPath("Note.md")
        let session = try MarkdownSession(path: notePath, snapshot: try await store.read(notePath), store: store, didSave: { _ in })
        var configuration = EditorConfiguration()
        configuration.mode = mode
        configuration.formatsCodeBlocks = formatsCodeBlocks
        configuration.codeColorTheme = codeColorTheme
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

    // MARK: The block's box

    private static let boxNote = "Intro paragraph.\n\n```C++\nuint32_t SumArray(uint32_t *input) {\n    uint32_t sum = 0;\n\n    return sum;\n}\n```\n\nAfter the block.\n"

    private func decoration(onLineContaining text: String, in textStorage: NSTextStorage) -> CodeBlockLineDecoration? {
        let location = (textStorage.string as NSString).range(of: text).location
        guard location != NSNotFound else { return nil }
        return textStorage.attribute(ConcealedReplacement.codeBlockKey, at: location, effectiveRange: nil) as? CodeBlockLineDecoration
    }

    private func isConcealed(_ text: String, in textStorage: NSTextStorage) -> Bool {
        let location = (textStorage.string as NSString).range(of: text).location
        return (textStorage.attribute(.font, at: location, effectiveRange: nil) as? NSFont)?.pointSize ?? 17 < 1
    }

    func testLivePreviewDrawsTheBlockAsABoxWithItsLanguageAndHidesTheFences() async throws {
        let (_, textView) = try await makeEditor(text: Self.boxNote, mode: .livePreview)
        let textStorage = try XCTUnwrap(textView.textStorage)
        XCTAssertTrue(isConcealed("```C++", in: textStorage), "The opening fence is hidden away from the cursor.")
        let closingFence = (textStorage.string as NSString).range(of: "```\n\nAfter").location
        XCTAssertLessThan((textStorage.attribute(.font, at: closingFence, effectiveRange: nil) as? NSFont)?.pointSize ?? 17, 1, "The closing fence is hidden.")
        let opening = try XCTUnwrap(decoration(onLineContaining: "```C++", in: textStorage))
        XCTAssertTrue(opening.isFirstLine)
        XCTAssertEqual(opening.languageLabel, "C++", "The language shows at the top right, as written.")
        let indented = try XCTUnwrap(decoration(onLineContaining: "    uint32_t sum", in: textStorage))
        XCTAssertEqual(indented.guideOffsets, [0], "One level of indentation, one guide.")
        XCTAssertFalse(indented.isFirstLine || indented.isLastLine)
        XCTAssertEqual(try XCTUnwrap(decoration(onLineContaining: "uint32_t SumArray", in: textStorage)).guideOffsets, [])
        let blankLine = (textStorage.string as NSString).range(of: "0;\n\n").location + 3
        XCTAssertNotNil(textStorage.attribute(ConcealedReplacement.codeBlockKey, at: blankLine, effectiveRange: nil), "A blank line is part of the box.")
        XCTAssertTrue(try XCTUnwrap(textStorage.attribute(ConcealedReplacement.codeBlockKey, at: closingFence, effectiveRange: nil) as? CodeBlockLineDecoration).isLastLine)
        XCTAssertNil(decoration(onLineContaining: "Intro", in: textStorage))
        XCTAssertNil(textStorage.attribute(.backgroundColor, at: (textStorage.string as NSString).range(of: "return").location, effectiveRange: nil),
                     "The box replaces the background behind each line's text.")
    }

    func testTheFencesShowWhileTheCursorIsInTheBlock() async throws {
        let (_, textView) = try await makeEditor(text: Self.boxNote, mode: .livePreview)
        let textStorage = try XCTUnwrap(textView.textStorage)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).range(of: "return").location, length: 0))
        XCTAssertFalse(isConcealed("```C++", in: textStorage), "Inside the block its fences show, as in Obsidian.")
        XCTAssertNil(try XCTUnwrap(decoration(onLineContaining: "```C++", in: textStorage)).languageLabel, "The fence shows the language itself.")
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).range(of: "After").location, length: 0))
        XCTAssertTrue(isConcealed("```C++", in: textStorage), "Leaving the block hides them again.")
        XCTAssertEqual(try XCTUnwrap(decoration(onLineContaining: "```C++", in: textStorage)).languageLabel, "C++")
    }

    func testSourceModeKeepsTheFencesInTheBox() async throws {
        let (_, textView) = try await makeEditor(text: Self.boxNote, mode: .source)
        let textStorage = try XCTUnwrap(textView.textStorage)
        XCTAssertFalse(isConcealed("```C++", in: textStorage))
        XCTAssertNotNil(decoration(onLineContaining: "```C++", in: textStorage))
        XCTAssertNil(try XCTUnwrap(decoration(onLineContaining: "```C++", in: textStorage)).languageLabel)
    }

    /// The box reaches across the column: beside a short line of code, the page is the
    /// box's gray; beside prose, it is the page.
    func testTheBoxIsDrawnAcrossTheColumn() async throws {
        let (coordinator, textView) = try await makeEditor(text: Self.boxNote, mode: .livePreview)
        let scrollView = try XCTUnwrap(textView.enclosingScrollView)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = scrollView
        coordinator.resume(scrollView)
        defer { window.contentView = nil }
        for _ in 0..<5 {
            textView.layoutSubtreeIfNeeded()
            textView.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
        }
        let bitmap = try XCTUnwrap(textView.bitmapImageRepForCachingDisplay(in: textView.visibleRect))
        textView.cacheDisplay(in: textView.visibleRect, to: bitmap)
        let image = try XCTUnwrap(bitmap.cgImage)
        let snapshotURL = FileManager.default.temporaryDirectory.appendingPathComponent("graphite-code-block-mac.png")
        if let destination = CGImageDestinationCreateWithURL(snapshotURL as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
        func brightness(besideLineContaining text: String) throws -> CGFloat {
            let textLayoutManager = try XCTUnwrap(textView.textLayoutManager)
            let contentStorage = try XCTUnwrap(textLayoutManager.textContentManager as? NSTextContentStorage)
            let location = try XCTUnwrap(contentStorage.location(contentStorage.documentRange.location, offsetBy: (textView.string as NSString).range(of: text).location))
            let fragment = try XCTUnwrap(textLayoutManager.textLayoutFragment(for: location))
            let pointY = fragment.layoutFragmentFrame.midY + textView.textContainerOrigin.y - textView.visibleRect.minY
            let pointX = textView.textContainerOrigin.x + fragment.layoutFragmentFrame.minX + 300
            let color = try XCTUnwrap(bitmap.colorAt(x: Int(pointX * CGFloat(bitmap.pixelsWide) / textView.visibleRect.width),
                                                     y: Int(pointY * CGFloat(bitmap.pixelsHigh) / textView.visibleRect.height))?.usingColorSpace(.deviceRGB))
            return color.brightnessComponent
        }
        let besideCode = try brightness(besideLineContaining: "return sum")
        let besideProse = try brightness(besideLineContaining: "Intro paragraph")
        XCTAssertLessThan(besideCode, besideProse - 0.02, "The box's gray reaches past the end of a short code line (snapshot: \(snapshotURL.path)).")
    }

    // MARK: Code themes

    func testACodeThemeColorsTheBoxAndItsCode() async throws {
        let (_, textView) = try await makeEditor(text: Self.boxNote, mode: .livePreview, codeColorTheme: .oneMonokai)
        let textStorage = try XCTUnwrap(textView.textStorage)
        let palette = CodeSyntaxColors.palette(codeTheme: .oneMonokai, noteTheme: nil)
        XCTAssertEqual(foregroundColor(of: "return", in: textStorage), palette.color(for: .keyword))
        XCTAssertEqual(foregroundColor(of: "SumArray", in: textStorage), palette.color(for: .function))
        XCTAssertEqual(foregroundColor(of: ";", in: textStorage), palette.text, "Punctuation takes the theme's text color.")
        XCTAssertEqual(try XCTUnwrap(decoration(onLineContaining: "return", in: textStorage)).background, palette.background)
        XCTAssertNotEqual(palette.color(for: .keyword), CodeSyntaxColors.palette(codeTheme: .obsidian, noteTheme: nil).color(for: .keyword))
    }

    /// Every theme's colors, as drawn, read on its own box in light and dark: 4.5:1 for
    /// code, comments 3:1, as for a vault theme. (A high-contrast `NSAppearance` made in a
    /// test resolves Graphite's appearance-dependent colors as the normal one, so Increase
    /// Contrast is checked on the colors the guard makes, below.)
    func testEveryCodeThemeIsReadableOnItsOwnBox() throws {
        let appearances: [(name: NSAppearance.Name, increased: Bool)] = [(.aqua, false), (.darkAqua, false)]
        for codeTheme in CodeColorTheme.allCases {
            guard let variants = codeTheme.variants else { continue }
            for variant in [variants.light, variants.dark] {
                let background = try XCTUnwrap(ThemeColor(hex: variant.background))
                for (kind, hex) in variant.colors {
                    let increased = ThemeContrastGuard.readable(try XCTUnwrap(ThemeColor(hex: hex)), on: background,
                                                                target: CodeColorTheme.minimumContrast(of: kind, increased: true))
                    XCTAssertGreaterThanOrEqual(increased.contrast(with: background), CodeColorTheme.minimumContrast(of: kind, increased: true) - 0.05)
                }
            }
        }
        func resolved(_ color: NSColor, in appearanceName: NSAppearance.Name) throws -> ThemeColor {
            var components: NSColor?
            try XCTUnwrap(NSAppearance(named: appearanceName)).performAsCurrentDrawingAppearance { components = color.usingColorSpace(.sRGB) }
            let sRGB = try XCTUnwrap(components)
            return ThemeColor(red: sRGB.redComponent, green: sRGB.greenComponent, blue: sRGB.blueComponent)
        }
        for codeTheme in CodeColorTheme.allCases where codeTheme != .obsidian {
            let palette = CodeSyntaxColors.palette(codeTheme: codeTheme, noteTheme: nil)
            for appearance in appearances {
                let background = try resolved(palette.background, in: appearance.name)
                let kinds: [CodeTokenKind?] = CodeTokenKind.allCases + [nil]
                for kind in kinds {
                    let color = try resolved(kind.map(palette.color(for:)) ?? palette.text, in: appearance.name)
                    let target = CodeColorTheme.minimumContrast(of: kind, increased: appearance.increased)
                    XCTAssertGreaterThanOrEqual(color.contrast(with: background), target - 0.05, "\(codeTheme.title) \(kind.map { "\($0)" } ?? "text") in \(appearance.name.rawValue)")
                }
            }
        }
    }

    // MARK: Formatting

    private static let unformattedNote = "Intro\n\n```c\nint main(){\nreturn 0;\n\n\n}\n```\n\nAfter the block.\n"

    /// Places the cursor at `text`'s end and types there, as the keyboard does, then moves it to `destination`
    /// and lets the formatting, made on the next turn of the run loop, happen.
    private func type(_ typed: String, after text: String, thenMoveTo destination: String,
                      in textView: MarkdownMacTextView, coordinator: NativeMarkdownEditor.Coordinator) async throws {
        let location = NSMaxRange((textView.string as NSString).range(of: text))
        textView.setSelectedRange(NSRange(location: location, length: 0))
        // The block's code is noted on the turn after the cursor enters it.
        try await Task.sleep(for: .milliseconds(50))
        textView.insertText(typed, replacementRange: NSRange(location: location, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        try await Task.sleep(for: .milliseconds(50))
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).range(of: destination).location, length: 0))
        try await Task.sleep(for: .milliseconds(100))
    }

    func testABlockEditedAndLeftIsFormattedAndUndoPutsItBack() async throws {
        let (coordinator, textView) = try await makeEditor(text: Self.unformattedNote, mode: .livePreview)
        try await type("\nint y=1,z=2;", after: "return 0;", thenMoveTo: "After", in: textView, coordinator: coordinator)
        let formatted = "Intro\n\n```c\nint main() {\n    return 0;\n    int y=1, z=2;\n}\n```\n\nAfter the block.\n"
        XCTAssertEqual(textView.string, formatted)
        XCTAssertEqual(coordinator.session.text, formatted, "The note saves the formatted code.")
        XCTAssertEqual((textView.string as NSString).substring(from: textView.selectedRange().location).prefix(5), "After", "The cursor stays where it went.")
        XCTAssertEqual(foregroundColor(of: "return", in: try XCTUnwrap(textView.textStorage)), CodeSyntaxColors.color(for: .keyword, theme: nil))

        coordinator.noteUndoManager.undo()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(textView.string, "Intro\n\n```c\nint main(){\nreturn 0;\nint y=1,z=2;\n\n\n}\n```\n\nAfter the block.\n", "Undo takes back the formatting alone.")
    }

    func testABlockOnlyPassedThroughIsLeftAlone() async throws {
        let (_, textView) = try await makeEditor(text: Self.unformattedNote, mode: .source)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).range(of: "return").location, length: 0))
        try await Task.sleep(for: .milliseconds(50))
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).range(of: "After").location, length: 0))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(textView.string, Self.unformattedNote)
    }

    func testTypingInsideTheBlockDoesNotFormatItYet() async throws {
        let (coordinator, textView) = try await makeEditor(text: Self.unformattedNote, mode: .source)
        // Typing in a text view that is not the first responder ends editing at once, as
        // leaving the note does; here it is being edited.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = textView.enclosingScrollView
        XCTAssertTrue(window.makeFirstResponder(textView))
        defer { window.contentView = nil }
        try await type(" x;", after: "return 0;", thenMoveTo: "int main", in: textView, coordinator: coordinator)
        XCTAssertTrue(textView.string.contains("int main(){\nreturn 0; x;"), "The cursor is still in the block.")
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(textView.string.contains("int main() {\n    return 0; x;\n}"), "Leaving it above formats it too.")
    }

    func testFormattingCanBeSwitchedOff() async throws {
        let (coordinator, textView) = try await makeEditor(text: Self.unformattedNote, mode: .source, formatsCodeBlocks: false)
        try await type("\nint y;", after: "return 0;", thenMoveTo: "After", in: textView, coordinator: coordinator)
        XCTAssertTrue(textView.string.contains("int main(){\nreturn 0;\nint y;"))
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
