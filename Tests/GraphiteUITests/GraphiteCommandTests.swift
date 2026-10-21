import XCTest
import SwiftUI
import GraphiteCore
@testable import GraphiteUI

/// The one list of commands that the menu bar, the editor and the palette read (`EX-09`).
final class GraphiteCommandTests: XCTestCase {
    func testIdentifiersAreObsidiansFormAndGraphitesOwnStartWithGraphite() {
        let obsidianWithoutColon: Set<String> = ["daily-notes", "insert-template"]
        for command in GraphiteCommand.allCases {
            XCTAssertTrue(command.identifier.contains(":") || obsidianWithoutColon.contains(command.identifier), command.identifier)
        }
        XCTAssertEqual(GraphiteCommand.toggleBold.identifier, "editor:toggle-bold")
        XCTAssertEqual(GraphiteCommand.quickSwitcher.identifier, "switcher:open")
    }

    func testNoTwoCommandsShareADefaultShortcutOnAPlatform() {
        for platform in [ShortcutPlatform.macOS, .iPadOS] {
            let table = KeyboardShortcutTable(commands: GraphiteCommand.available(on: platform).map(\.defaults), file: HotkeyFile())
            for command in GraphiteCommand.available(on: platform) {
                XCTAssertEqual(table.commandIdentifiersSharingShortcuts(with: command.identifier), [], "\(command.identifier) on \(platform)")
            }
        }
    }

    func testTheMenuBarAndEditorDefaultsAreTheShortcutsGraphiteHadInCode() {
        let table = KeyboardShortcutTable(commands: GraphiteCommand.allCases.map(\.defaults), file: HotkeyFile())
        func symbols(_ command: GraphiteCommand) -> [String] { table.combinations(for: command.identifier).map(\.symbols) }
        let expected: [GraphiteCommand: String] = [
            .newNote: "⌘N", .newTab: "⌘T", .quickSwitcher: "⌘O", .closeTab: "⌘W", .reopenClosedTab: "⇧⌘T", .save: "⌘S", .openSettings: "⌘,",
            .searchAllFiles: "⇧⌘F", .toggleReadingView: "⌘E", .commandPalette: "⌘P", .goBack: "⌘[", .goForward: "⌘]", .nextTab: "⌃⇥",
            .previousTab: "⌃⇧⇥", .goToTab1: "⌘1", .goToTab8: "⌘8", .goToLastTab: "⌘9", .increaseFontSize: "⌘+", .decreaseFontSize: "⌘-",
            .resetFontSize: "⌘0", .toggleBold: "⌘B", .toggleItalics: "⌘I", .toggleChecklist: "⌘L", .insertLink: "⌘K", .toggleHighlight: "⇧⌘H",
            .toggleStrikethrough: "⇧⌘X", .toggleCode: "⌃⌘C", .toggleComment: "⌘/", .findInNote: "⌘F", .findAndReplaceInNote: "⌥⌘F",
            .heading1: "⌃⌘1", .heading6: "⌃⌘6", .swapLineUp: "⌥⌘↑", .swapLineDown: "⌥⌘↓", .unindentList: "⇧⇥", .followLink: "⌥↩",
            .openLinkInNewTab: "⌘↩", .openLinkOnOtherSide: "⌥⌘↩", .canvasSelectAll: "⌘A", .canvasDeleteSelection: "⌫", .canvasDuplicateSelection: "⌘D",
        ]
        for (command, shortcut) in expected { XCTAssertEqual(symbols(command), [shortcut], command.identifier) }
    }

    func testEveryCommandIsBoundWhereItsShortcutIsListenedFor() {
        for command in GraphiteCommand.allCases {
            switch command.binding {
            case .menuBar:
                XCTAssertTrue(!command.macMenuTitles.isEmpty || !command.isAvailable(on: .macOS), "\(command.identifier) names its Mac menu item.")
            case .editor(let editorCommand):
                XCTAssertNotNil(command.editorCommand, command.identifier)
                if case .followLink = editorCommand { XCTAssertTrue(command.followsLink) }
            case .canvas:
                XCTAssertEqual(command.group, .canvas)
            case .commandsMenu:
                XCTAssertTrue(command.defaults.defaultCombinations.isEmpty, "\(command.identifier) has no default it could lose to the menu.")
            }
        }
    }

    func testMenuShortcutsAreSwiftUIsKeyEquivalents() {
        XCTAssertEqual(KeyCombination(.command, .character("N")).keyboardShortcut, KeyboardShortcut("n", modifiers: .command))
        XCTAssertEqual(KeyCombination([.control, .shift], .named(.tab)).keyboardShortcut, KeyboardShortcut(.tab, modifiers: [.control, .shift]))
        XCTAssertEqual(KeyCombination([], .named(.backspace)).keyboardShortcut, KeyboardShortcut(.delete, modifiers: []))
        XCTAssertNil(KeyCombination(.command, .unknown("NumpadEnter")).keyboardShortcut)
    }

    func testTheEditorTableFollowsTheVaultsChanges() {
        var file = HotkeyFile()
        file.assign([KeyCombination([.command, .control], .character("B"))], to: GraphiteCommand.toggleBold.identifier)
        let editor = EditorKeyCommandTable(table: KeyboardShortcutTable(commands: GraphiteCommand.allCases.map(\.defaults), file: file), platform: .macOS)

        XCTAssertEqual(editor.command(matching: KeyCombination([.command, .control], .character("B"))), .toggleBold)
        XCTAssertNil(editor.command(matching: KeyCombination(.command, .character("B"))))
        XCTAssertNil(editor.command(matching: KeyCombination(.option, .named(.enter))), "The Mac follows links with a click.")
        XCTAssertTrue(editor.isBound(.toggleItalics, to: KeyCombination(.command, .character("I"))))
    }
}
