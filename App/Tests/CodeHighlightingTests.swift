#if os(iOS)
import XCTest
import SwiftUI
import GraphiteApple
@testable import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// Fenced code in the hosted workspace on the iPad is colored by its language in Live
/// Preview, Source mode and reading view, in light and dark appearance.
@MainActor
final class CodeHighlightingTests: XCTestCase {
    private var window: UIWindow?
    private var vaultDirectory: URL?
    private var workspace: WorkspaceModel?

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        workspace = nil
        if let vaultDirectory { try? FileManager.default.removeItem(at: vaultDirectory) }
        vaultDirectory = nil
    }

    private static let note = """
        # Code

        Prose with int and return stays plain.

        ```cpp
        #include <vector>
        // Sum of the values
        template <typename T>
        T sum(const std::vector<T>& values) {
            T total = 0; /* start */
            for (auto value : values) total += value;
            return total;
        }
        ```

        ```vhdl
        entity counter is
          port (CLKxCI : in std_logic); -- clock
        end entity counter;
        architecture rtl of counter is
        begin
          COUNTxDO <= x"FF" when rising_edge(CLKxCI);
        end architecture;
        ```

        ```unknownlang
        return int 42
        ```
        """

    func testCodeIsColoredInEveryView() async throws {
        let (session, controller) = try await openNote(Self.note)
        for mode in [NoteViewMode.livePreview, .source] {
            session.viewMode = mode
            let editor = try await editor(in: controller, showing: session.text)
            let textStorage = editor.textStorage
            XCTAssertEqual(foregroundColor(of: "return", in: textStorage, occurrence: 1), CodeSyntaxColors.color(for: .keyword, theme: nil), "\(mode)")
            XCTAssertEqual(foregroundColor(of: "// Sum", in: textStorage), CodeSyntaxColors.color(for: .comment, theme: nil), "\(mode)")
            XCTAssertEqual(foregroundColor(of: "std_logic", in: textStorage), CodeSyntaxColors.color(for: .typeName, theme: nil), "\(mode)")
            XCTAssertEqual(foregroundColor(of: "rising_edge", in: textStorage), CodeSyntaxColors.color(for: .function, theme: nil), "\(mode)")
            XCTAssertNotEqual(foregroundColor(of: "return", in: textStorage), CodeSyntaxColors.color(for: .keyword, theme: nil), "Prose stays plain in \(mode).")
            XCTAssertNotEqual(foregroundColor(of: "return", in: textStorage, occurrence: 2), CodeSyntaxColors.color(for: .keyword, theme: nil), "An unknown language stays plain in \(mode).")
            for style in [UIUserInterfaceStyle.light, .dark] {
                try XCTUnwrap(window).overrideUserInterfaceStyle = style
                try await Task.sleep(for: .milliseconds(400))
                attachScreenshot(named: "\(mode) \(style == .dark ? "dark" : "light")")
            }
            try XCTUnwrap(window).overrideUserInterfaceStyle = .light
        }

        session.viewMode = .reading
        try await Task.sleep(for: .seconds(2))
        let lightPixels = saturatedPixelCount(in: attachScreenshot(named: "Reading light"))
        try XCTUnwrap(window).overrideUserInterfaceStyle = .dark
        try await Task.sleep(for: .seconds(1))
        let darkPixels = saturatedPixelCount(in: attachScreenshot(named: "Reading dark"))
        XCTAssertGreaterThan(lightPixels, 500, "Reading view draws the code in syntax colors.")
        XCTAssertGreaterThan(darkPixels, 500, "Reading view draws the code in syntax colors in dark appearance.")
    }

    /// A block whose code was typed into is formatted when the cursor leaves it, and Undo
    /// takes the formatting back.
    func testAnEditedBlockIsFormattedWhenTheCursorLeavesIt() async throws {
        let note = "Intro\n\n```c\nint main(){\nreturn 0;\n\n\n}\n```\n\nAfter the block.\n"
        let (session, controller) = try await openNote(note)
        session.viewMode = .source
        let editor = try await editor(in: controller, showing: session.text)
        editor.beginEditing()
        XCTAssertTrue(editor.isFirstResponder, "The editor is being edited, as after a tap.")
        editor.selectedRange = NSRange(location: NSMaxRange((editor.text as NSString).range(of: "return 0;")), length: 0)
        try await Task.sleep(for: .milliseconds(200))
        editor.insertText("\nint y=1,z=2;")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(editor.text.contains("int main(){\nreturn 0;\nint y=1,z=2;"), "Nothing is formatted while the cursor is in the block.")
        editor.selectedRange = NSRange(location: (editor.text as NSString).range(of: "After").location, length: 0)
        try await Task.sleep(for: .milliseconds(500))
        let formatted = "Intro\n\n```c\nint main() {\n    return 0;\n    int y=1, z=2;\n}\n```\n\nAfter the block.\n"
        XCTAssertEqual(editor.text, formatted)
        XCTAssertEqual(session.text, formatted, "The note saves the formatted code.")
        attachScreenshot(named: "Formatted after leaving the block")

        editor.undoManager?.undo()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(editor.text.contains("int main(){\nreturn 0;\nint y=1,z=2;\n\n\n}"), "Undo takes back the formatting.")
    }

    /// The owner's example, in Live Preview and reading view, in Obsidian's colors and in
    /// One Monokai, light and dark, for review.
    func testCodeBlockBoxesInEachViewAndTheme() async throws {
        let note = """
            Prose before the block.

            ```C++
            // length  → scalar           → s_axilite
            // input   → pointer to DRAM  → m_axi

            uint32_t SumArray(uint32_t *input, uint32_t length) {
                #pragma HLS INTERFACE s_axilite port=length
                #pragma HLS INTERFACE m_axi     port=input offset=slave

                uint32_t sum = 0;
                for (uint32_t i = 0; i < length; ++i) sum += input[i];
                return sum;
            }
            ```

            Prose after the block.
            """
        let (session, controller) = try await openNote(note)
        let preferences = try XCTUnwrap(workspace).preferences
        let chosenTheme = preferences.codeColorTheme
        defer { preferences.codeColorTheme = chosenTheme }
        for codeTheme in [CodeColorTheme.obsidian, .oneMonokai] {
            preferences.codeColorTheme = codeTheme
            for mode in [NoteViewMode.livePreview, .reading] {
                session.viewMode = mode
                if mode == .livePreview {
                    let editor = try await editor(in: controller, showing: session.text)
                    let decoration = editor.textStorage.attribute(ConcealedReplacement.codeBlockKey, at: (editor.text as NSString).range(of: "return sum").location,
                                                                  effectiveRange: nil) as? CodeBlockLineDecoration
                    XCTAssertEqual(decoration?.background, CodeSyntaxColors.palette(codeTheme: codeTheme, noteTheme: nil).background, "\(codeTheme)")
                }
                for style in [UIUserInterfaceStyle.light, .dark] {
                    try XCTUnwrap(window).overrideUserInterfaceStyle = style
                    try await Task.sleep(for: .milliseconds(mode == .reading ? 1_200 : 500))
                    attachScreenshot(named: "\(codeTheme.title) \(mode) \(style == .dark ? "dark" : "light")")
                }
                try XCTUnwrap(window).overrideUserInterfaceStyle = .light
            }
        }
    }

    // MARK: Helpers

    private func foregroundColor(of text: String, in textStorage: NSTextStorage, occurrence: Int = 0) -> UIColor? {
        let source = textStorage.string as NSString
        var searchStart = 0
        var range = NSRange(location: NSNotFound, length: 0)
        for _ in 0...occurrence {
            range = source.range(of: text, range: NSRange(location: searchStart, length: source.length - searchStart))
            guard range.location != NSNotFound else { return nil }
            searchStart = NSMaxRange(range)
        }
        return textStorage.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? UIColor
    }

    /// Pixels whose color is clearly not gray; the accent-colored chrome is excluded by
    /// counting only the note's area below the tab bar.
    private func saturatedPixelCount(in image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var count = 0
        for row in (height / 6)..<height {
            for column in 0..<width {
                let offset = (row * width + column) * 4
                let components = [pixels[offset], pixels[offset + 1], pixels[offset + 2]]
                if let largest = components.max(), let smallest = components.min(), Int(largest) - Int(smallest) > 64 { count += 1 }
            }
        }
        return count
    }

    @discardableResult
    private func attachScreenshot(named name: String) -> UIImage {
        guard let window else { return UIImage() }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return screenshot
    }

    private func openNote(_ text: String) async throws -> (MarkdownSession, UIViewController) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CodeHighlighting-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        vaultDirectory = directory
        try Data(text.utf8).write(to: directory.appendingPathComponent("Code.md"))
        let workspace = WorkspaceModel()
        self.workspace = workspace
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        workspace.index = index
        _ = try await index.reconcile(root: directory)
        let path = try VaultPath("Code.md")
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
        return (session, controller)
    }

    private func editor(in controller: UIViewController, showing text: String) async throws -> MarkdownTextView {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let editor = descendants(of: controller.view, matching: MarkdownTextView.self).first(where: { editor in
                editor.window != nil && editor.text == text && editor.bounds.width > 0
            }) {
                try await Task.sleep(for: .milliseconds(300))
                return editor
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        return try XCTUnwrap(nil as MarkdownTextView?, "The hosted editor did not appear.")
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in
            ((child as? View).map { [$0] } ?? []) + descendants(of: child, matching: type)
        }
    }
}
#endif
