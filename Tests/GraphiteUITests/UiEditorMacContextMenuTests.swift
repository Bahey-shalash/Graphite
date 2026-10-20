#if os(macOS)
import AppKit
import XCTest
import GraphiteCore
@testable import GraphiteUI

/// The note editor's right-click menu starts with Obsidian's Add Link and Add External Link,
/// then its Color, Format, Paragraph and Insert submenus, before the system's items; the
/// system's Font submenu, which does nothing for Markdown, is left out.
@MainActor
final class UiEditorMacContextMenuTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for window in windows { window.orderOut(nil); window.contentView = nil }
        windows = []
        try await super.tearDown()
    }

    private func makeTextView(text: String, colors: [PaletteColor]?, applied: @escaping (MarkdownTextEdit) -> Void = { _ in },
                              insertedColor: @escaping (String) -> Void = { _ in }) throws -> MarkdownMacTextView {
        let scrollView = MarkdownMacTextView.makeScrollableTextView()
        let textView = try XCTUnwrap(scrollView.documentView as? MarkdownMacTextView)
        textView.string = text
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        windows.append(window)
        window.contentView = scrollView
        let menuActions = EditorContextMenuActions(
            run: { _ in }, noteState: { [weak textView] in ((textView?.string ?? "") as NSString, textView?.selectedRange() ?? NSRange()) },
            apply: applied, insertBlock: { _ in }, colors: colors, insertColor: { hex, _ in insertedColor(hex) },
            linkToNote: {}, template: nil)
        textView.contextMenuEntries = { EditorContextMenuContent.entries(actions: menuActions, editorActions: EditorActions()) }
        return textView
    }

    private func rightClickMenu(on textView: NSTextView) throws -> NSMenu {
        let window = try XCTUnwrap(textView.window)
        let click = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: textView.convert(CGPoint(x: 20, y: 10), to: nil), modifierFlags: [],
                                                     timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        return try XCTUnwrap(textView.menu(for: click))
    }

    func testTheMenuHasObsidiansSubmenusFirstAndNoFontSubmenu() throws {
        let textView = try makeTextView(text: "Some text\n", colors: PaletteColor.defaultPalette)
        let menu = try rightClickMenu(on: textView)
        let titles = menu.items.map(\.title)
        XCTAssertEqual(Array(titles.prefix(6)), ["Add Link", "Add External Link", "", "Color", "Format", "Paragraph"])
        XCTAssertEqual(titles[6], "Insert")
        XCTAssertFalse(menu.items.contains { item in item.submenu?.items.contains { subitem in subitem.action == NSSelectorFromString("orderFrontFontPanel:") } ?? false },
                       "The system's Font submenu is gone")
        let colorTitles = try XCTUnwrap(menu.items.first { item in item.title == "Color" }?.submenu).items.map(\.title)
        XCTAssertEqual(colorTitles.filter { title in !title.isEmpty }, PaletteColor.defaultPalette.map(\.name) + ["Remove"])
    }

    func testWithoutTheColorsFeatureThereIsNoColorSubmenu() throws {
        let textView = try makeTextView(text: "Some text\n", colors: nil)
        XCTAssertFalse(try rightClickMenu(on: textView).items.contains { item in item.title == "Color" })
    }

    func testChoosingAColorAndRemovingOne() throws {
        var insertedHex: String?
        var appliedEdit: MarkdownTextEdit?
        let text = "A ~={#e93147}red=~ word\n"
        let textView = try makeTextView(text: text, colors: PaletteColor.defaultPalette, applied: { edit in appliedEdit = edit },
                                        insertedColor: { hex in insertedHex = hex })
        textView.setSelectedRange(NSRange(location: (text as NSString).range(of: "red=~").location + 1, length: 0))
        let colorMenu = try XCTUnwrap(try rightClickMenu(on: textView).items.first { item in item.title == "Color" }?.submenu)
        // The right click put the cursor where it was made; put it back in the colored word.
        textView.setSelectedRange(NSRange(location: (text as NSString).range(of: "red=~").location + 1, length: 0))
        let blue = try XCTUnwrap(colorMenu.items.first { item in item.title == "blue" })
        _ = blue.target?.perform(blue.action)
        XCTAssertEqual(insertedHex, PaletteColor.defaultPalette.first { color in color.name == "blue" }?.hex)
        let remove = try XCTUnwrap(colorMenu.items.first { item in item.title == "Remove" })
        _ = remove.target?.perform(remove.action)
        let edit = try XCTUnwrap(appliedEdit)
        XCTAssertEqual((text as NSString).replacingCharacters(in: edit.range, with: edit.replacement), "A red word\n")
    }
}
#endif
