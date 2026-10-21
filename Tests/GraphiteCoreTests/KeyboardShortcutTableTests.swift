import XCTest
@testable import GraphiteCore

final class KeyboardShortcutTableTests: XCTestCase {
    private let commandB = KeyCombination(.command, .character("B"))
    private let commandI = KeyCombination(.command, .character("I"))
    private let commandJ = KeyCombination(.command, .character("J"))

    private var commands: [ShortcutCommandDefaults] {
        [ShortcutCommandDefaults(identifier: "editor:toggle-bold", defaultCombinations: [commandB]),
         ShortcutCommandDefaults(identifier: "editor:toggle-italics", defaultCombinations: [commandI]),
         ShortcutCommandDefaults(identifier: "graphite:new-notebook", defaultCombinations: [])]
    }

    private func table(_ file: HotkeyFile = HotkeyFile()) -> KeyboardShortcutTable {
        KeyboardShortcutTable(commands: commands, file: file)
    }

    func testCommandsHaveTheirDefaultsUntilTheFileChangesThem() {
        var file = HotkeyFile()
        file.assign([commandJ], to: "editor:toggle-bold")
        let shortcuts = table(file)

        XCTAssertEqual(shortcuts.combinations(for: "editor:toggle-bold"), [commandJ])
        XCTAssertTrue(shortcuts.isChanged("editor:toggle-bold"))
        XCTAssertEqual(shortcuts.combinations(for: "editor:toggle-italics"), [commandI])
        XCTAssertFalse(shortcuts.isChanged("editor:toggle-italics"))
        XCTAssertEqual(shortcuts.commandIdentifiers(using: commandB), [], "⌘B is free once bold has another shortcut.")
    }

    func testAClashBetweenTwoCommandsIsFoundForBoth() {
        var file = HotkeyFile()
        file.assign([commandI], to: "graphite:new-notebook")
        let shortcuts = table(file)

        XCTAssertEqual(shortcuts.commandIdentifiers(using: commandI), ["editor:toggle-italics", "graphite:new-notebook"])
        XCTAssertEqual(shortcuts.commandIdentifiersSharingShortcuts(with: "editor:toggle-italics"), ["graphite:new-notebook"])
        XCTAssertEqual(shortcuts.commandIdentifiersSharingShortcuts(with: "graphite:new-notebook"), ["editor:toggle-italics"])
        XCTAssertEqual(shortcuts.check(commandI, for: "editor:toggle-bold", systemShortcuts: SystemKeyboardShortcuts(platform: .macOS)),
                       .allowed(warnings: [.usedByCommands(["editor:toggle-italics", "graphite:new-notebook"])]))
    }

    func testAssigningAShortcutInUseMovesItAndWritesOnlyTheChanges() {
        let changed = table().file(after: .assign(commandI, commandIdentifier: "editor:toggle-bold"))

        XCTAssertEqual(changed.assignedCombinations(for: "editor:toggle-bold"), [commandI])
        XCTAssertEqual(changed.assignedCombinations(for: "editor:toggle-italics"), [], "Italics lose ⌘I.")
        XCTAssertNil(changed.entries["graphite:new-notebook"], "A command the change does not touch gets no entry.")
    }

    func testGivingACommandItsDefaultAgainRemovesItsEntry() {
        var file = HotkeyFile()
        file.assign([commandJ], to: "editor:toggle-bold")

        XCTAssertNil(table(file).file(after: .assign(commandB, commandIdentifier: "editor:toggle-bold")).entries["editor:toggle-bold"])
        XCTAssertNil(table(file).file(after: .reset(commandIdentifier: "editor:toggle-bold")).entries["editor:toggle-bold"])
    }

    func testRemovingWritesAnEmptyListUnlessTheCommandHasNoDefault() {
        XCTAssertEqual(table().file(after: .remove(commandIdentifier: "editor:toggle-bold")).entries["editor:toggle-bold"], .array([]))
        XCTAssertNil(table().file(after: .remove(commandIdentifier: "graphite:new-notebook")).entries["graphite:new-notebook"])
    }

    func testResetAllKeepsTheEntriesOfCommandsTheTableDoesNotList() {
        var file = HotkeyFile()
        file.assign([commandJ], to: "editor:toggle-bold")
        file.assign([commandB], to: "obsidian-git:commit")

        let reset = table(file).file(after: .resetAll)

        XCTAssertNil(reset.entries["editor:toggle-bold"])
        XCTAssertEqual(reset.assignedCombinations(for: "obsidian-git:commit"), [commandB])
    }

    func testEachKindOfSystemClashIsFoundFromThePlatformsTable() {
        let mac = SystemKeyboardShortcuts(platform: .macOS)
        let iPad = SystemKeyboardShortcuts(platform: .iPadOS)
        let commandTab = KeyCombination(.command, .named(.tab))
        let commandQ = KeyCombination(.command, .character("Q"))
        let commandH = KeyCombination(.command, .character("H"))

        guard case .refused(.takenBySystem(let switcher)) = table().check(commandTab, for: "editor:toggle-bold", systemShortcuts: mac) else {
            return XCTFail("⌘Tab belongs to the system on the Mac.")
        }
        XCTAssertEqual(switcher.purpose, .switchApplications)
        guard case .allowed(let warnings) = table().check(commandQ, for: "editor:toggle-bold", systemShortcuts: mac),
              case .standardInEveryApplication(let quit)? = warnings.first else {
            return XCTFail("⌘Q is allowed after a warning.")
        }
        XCTAssertEqual(quit.purpose, .quit)
        XCTAssertEqual(table().check(commandH, for: "editor:toggle-bold", systemShortcuts: mac),
                       .allowed(warnings: [.standardInEveryApplication(SystemKeyboardShortcut(combination: commandH, kind: .standard, purpose: .hide))]))
        XCTAssertEqual(table().check(commandH, for: "editor:toggle-bold", systemShortcuts: iPad),
                       .refused(.takenBySystem(SystemKeyboardShortcut(combination: commandH, kind: .reserved, purpose: .homeScreen))), "⌘H goes home on the iPad.")
        XCTAssertEqual(table().check(commandJ, for: "editor:toggle-bold", systemShortcuts: mac), .allowed(warnings: []))
        XCTAssertEqual(table().check(KeyCombination(.shift, .character("J")), for: "editor:toggle-bold", systemShortcuts: mac), .refused(.needsModifier))
    }

    func testEveryReservedShortcutOfThePlanIsInTheTables() {
        let mac = SystemKeyboardShortcuts(platform: .macOS)
        let reservedOnMac: [KeyCombination] = [
            KeyCombination(.command, .named(.tab)), KeyCombination(.command, .named(.space)), KeyCombination(.control, .named(.space)),
            KeyCombination([.command, .shift], .character("3")), KeyCombination([.command, .shift], .character("4")), KeyCombination([.command, .shift], .character("5")),
            KeyCombination([.command, .control], .character("Q")), KeyCombination([.command, .option], .character("D")), KeyCombination([.command, .option], .named(.escape)),
            KeyCombination(.control, .named(.arrowUp)), KeyCombination(.control, .named(.arrowDown)),
            KeyCombination(.control, .named(.arrowLeft)), KeyCombination(.control, .named(.arrowRight)),
        ]
        for combination in reservedOnMac { XCTAssertEqual(mac.shortcut(matching: combination)?.kind, .reserved, "\(combination)") }
        let standardEverywhere: [KeyCombination] = ["Q", "C", "V", "X", "Z", "A", ","].map { key in KeyCombination(.command, .character(key)) }
            + [KeyCombination([.command, .shift], .character("Z")), KeyCombination(.command, .character("M")), KeyCombination(.command, .character("`"))]
        for platform in [ShortcutPlatform.macOS, .iPadOS] {
            for combination in standardEverywhere {
                XCTAssertEqual(SystemKeyboardShortcuts(platform: platform).shortcut(matching: combination)?.kind, .standard, "\(combination) on \(platform)")
            }
        }
        let iPad = SystemKeyboardShortcuts(platform: .iPadOS)
        for combination in [KeyCombination(.command, .character("H")), KeyCombination(.command, .named(.space)), KeyCombination(.command, .named(.tab))] {
            XCTAssertEqual(iPad.shortcut(matching: combination)?.kind, .reserved, "\(combination)")
        }
    }

    func testAKeyGraphiteDoesNotKnowIsNeverMatched() {
        var file = HotkeyFile()
        file.assign([KeyCombination(.command, .unknown("NumpadEnter"))], to: "editor:toggle-bold")
        XCTAssertEqual(table(file).commandIdentifiers(using: KeyCombination(.command, .unknown("NumpadEnter"))), [])
    }
}
