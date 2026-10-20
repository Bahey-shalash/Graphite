import XCTest
@testable import GraphiteCore
import GraphiteTestSupport

final class ObsidianAppearanceTests: XCTestCase {
    /// The owner's own `Vault/.obsidian/appearance.json`, as Obsidian 1.x wrote it.
    private let ownersVaultAppearance = """
    {
      "accentColor": "#3068e8",
      "theme": "obsidian",
      "showRibbon": true,
      "cssTheme": "",
      "enabledCssSnippets": [
        "fast-text-color"
      ],
      "textFontFamily": "",
      "interfaceFontFamily": "",
      "baseFontSize": 16,
      "showViewHeader": true,
      "nativeMenus": null
    }
    """

    private let installedFamilies = ["Georgia", "Iowan Old Style", "Menlo", "Avenir Next"]

    private func installedFamily(_ name: String) -> String? {
        installedFamilies.first { family in family.caseInsensitiveCompare(name) == .orderedSame }
    }

    func testReadsTheKeysOfARealVault() throws {
        let appearance = try ObsidianAppearance(configurationData: Data(ownersVaultAppearance.utf8))
        XCTAssertEqual(appearance.accentHex, "#3068e8")
        XCTAssertEqual(appearance.baseTheme, .dark)
        XCTAssertEqual(appearance.cssTheme, "")
        XCTAssertEqual(appearance.enabledCssSnippets, ["fast-text-color"])
        XCTAssertTrue(appearance.textFontFamilies.isEmpty)
        XCTAssertTrue(appearance.interfaceFontFamilies.isEmpty)
        XCTAssertTrue(appearance.monospaceFontFamilies.isEmpty, "A key the file lacks is the default font.")
        XCTAssertEqual(appearance.baseFontSize, 16)
        XCTAssertFalse(appearance.adjustsFontSizeQuickly, "Obsidian's default for baseFontSizeAction.")
    }

    func testMissingEmptyAndMistypedValuesAreObsidiansDefaults() throws {
        for fileText in ["", "  \n", "{}"] {
            XCTAssertEqual(try ObsidianAppearance(configurationData: Data(fileText.utf8)), ObsidianAppearance(), "Reading “\(fileText)”")
        }
        XCTAssertEqual(try ObsidianAppearance(configurationData: nil), ObsidianAppearance())
        let mistyped = try ObsidianAppearance(configurationData: Data("""
        {"textFontFamily": 12, "baseFontSize": "large", "baseFontSizeAction": "yes", "accentColor": "purple", "enabledCssSnippets": "a"}
        """.utf8))
        XCTAssertTrue(mistyped.textFontFamilies.isEmpty)
        XCTAssertNil(mistyped.baseFontSize)
        XCTAssertEqual(mistyped.effectiveBaseFontSize, 16)
        XCTAssertFalse(mistyped.adjustsFontSizeQuickly)
        XCTAssertNil(mistyped.accentHex, "Only a hex color is an accent.")
        XCTAssertEqual(mistyped.enabledCssSnippets, [])
        XCTAssertThrowsError(try ObsidianAppearance(configurationData: Data("[1, 2]".utf8)), "A file that is not an object is not read as defaults.")
    }

    func testFontSizeIsKeptWithinObsidiansRange() throws {
        let tooSmall = try ObsidianAppearance(configurationData: Data(#"{"baseFontSize": 4}"#.utf8))
        XCTAssertEqual(tooSmall.baseFontSize, 4, "The file's value is kept as written…")
        XCTAssertEqual(tooSmall.effectiveBaseFontSize, 10, "…and drawn at Obsidian's smallest size.")
        XCTAssertEqual(try ObsidianAppearance(configurationData: Data(#"{"baseFontSize": 64}"#.utf8)).effectiveBaseFontSize, 30)
        XCTAssertEqual(try ObsidianAppearance(configurationData: Data(#"{"baseFontSize": 17.6}"#.utf8)).baseFontSize, 18)
        XCTAssertNil(try ObsidianAppearance(configurationData: Data(#"{"baseFontSize": true}"#.utf8)).baseFontSize)
    }

    func testFontListsAreReadAsObsidianReadsThem() {
        XCTAssertEqual(FontFamilyList(obsidianValue: "\"Iowan Old Style\", Georgia, serif").families, ["Iowan Old Style", "Georgia", "serif"])
        XCTAssertEqual(FontFamilyList(obsidianValue: "'Avenir Next' ,  Menlo").families, ["Avenir Next", "Menlo"])
        XCTAssertEqual(FontFamilyList(obsidianValue: "Bookerly,,  ").families, ["Bookerly"])
        XCTAssertTrue(FontFamilyList(obsidianValue: "").isEmpty)
        XCTAssertTrue(FontFamilyList(obsidianValue: nil).isEmpty)
        XCTAssertEqual(FontFamilyList(families: ["Iowan Old Style", "Georgia"]).obsidianValue, "Iowan Old Style,Georgia",
                       "Written as Obsidian's font list writes it: names joined by commas, without quotes.")
    }

    func testTheFirstInstalledFamilyOfAListIsUsed() {
        let list = FontFamilyList(obsidianValue: "\"Bookerly\", \"iowan old style\", Georgia")
        XCTAssertEqual(list.firstAvailableFamily(installedFamily: installedFamily), .installed("Iowan Old Style"),
                       "A missing family is skipped, and the installed family keeps the system's spelling.")
        XCTAssertEqual(list.missingFamilies(installedFamily: installedFamily), ["Bookerly"])
        XCTAssertNil(FontFamilyList(obsidianValue: "Bookerly, Literata").firstAvailableFamily(installedFamily: installedFamily),
                     "No installed family means the default font.")
        XCTAssertNil(FontFamilyList().firstAvailableFamily(installedFamily: installedFamily))
    }

    func testGenericFamiliesNameTheSystemFontsDesigns() {
        XCTAssertEqual(FontFamilyList(obsidianValue: "Bookerly, serif").firstAvailableFamily(installedFamily: installedFamily), .system(.serif))
        XCTAssertEqual(FontFamilyList(obsidianValue: "ui-monospace, Menlo").firstAvailableFamily(installedFamily: installedFamily), .system(.monospaced))
        XCTAssertEqual(FontFamilyList(obsidianValue: "-apple-system").firstAvailableFamily(installedFamily: installedFamily), .system(.standard))
        XCTAssertEqual(FontFamilyList(obsidianValue: "var(--font-default), Georgia").firstAvailableFamily(installedFamily: installedFamily), .installed("Georgia"),
                       "A CSS variable names no family and is skipped.")
        XCTAssertEqual(FontFamilyList(obsidianValue: "serif, Bookerly").missingFamilies(installedFamily: installedFamily), ["Bookerly"])
    }

    func testWritingChangesOnlyTheChangedKeysAndKeepsEverythingElse() throws {
        let existing = Data(ownersVaultAppearance.utf8)
        let previous = try ObsidianAppearance(configurationData: existing)
        var changed = previous
        changed.textFontFamilies = FontFamilyList(families: ["Iowan Old Style"])
        changed.monospaceFontFamilies = FontFamilyList(families: ["Menlo"])
        changed.baseFontSize = 18
        changed.adjustsFontSizeQuickly = true
        let written = String(decoding: try changed.mergedConfigurationData(existingData: existing, changedFrom: previous), as: UTF8.self)
        XCTAssertEqual(written, """
        {
          "accentColor": "#3068e8",
          "theme": "obsidian",
          "showRibbon": true,
          "cssTheme": "",
          "enabledCssSnippets": [
            "fast-text-color"
          ],
          "textFontFamily": "Iowan Old Style",
          "interfaceFontFamily": "",
          "baseFontSize": 18,
          "showViewHeader": true,
          "nativeMenus": null,
          "monospaceFontFamily": "Menlo",
          "baseFontSizeAction": true
        }
        """, "Changed keys are replaced in place, new ones are added at the end, and the rest is kept byte for byte.")
        XCTAssertEqual(try ObsidianAppearance(configurationData: Data(written.utf8)), changed, "The written file reads back as the settings written.")
    }

    func testUnchangedListsKeepTheirQuotesAndAnObsidianChangeMadeMeanwhileSurvives() throws {
        let readByGraphite = Data(#"{"textFontFamily": "\"Iowan Old Style\", Georgia", "baseFontSize": 16}"#.utf8)
        let previous = try ObsidianAppearance(configurationData: readByGraphite)
        // Obsidian changes the font size while Graphite's settings are open.
        let changedInObsidian = Data(#"{"textFontFamily": "\"Iowan Old Style\", Georgia", "baseFontSize": 20, "cssTheme": "Minimal"}"#.utf8)
        var changed = previous
        changed.adjustsFontSizeQuickly = true
        let written = String(decoding: try changed.mergedConfigurationData(existingData: changedInObsidian, changedFrom: previous), as: UTF8.self)
        XCTAssertTrue(written.contains(#""textFontFamily": "\"Iowan Old Style\", Georgia""#), "An unchanged list keeps its quoting: \(written)")
        XCTAssertTrue(written.contains(#""baseFontSize": 20"#), "Obsidian's newer size is kept: \(written)")
        XCTAssertTrue(written.contains(#""cssTheme": "Minimal""#))
        XCTAssertTrue(written.contains(#""baseFontSizeAction": true"#))
    }

    func testANoChangeSaveLeavesTheFileUntouchedAndAnInvalidFileIsRefused() throws {
        let existing = Data("{\"baseFontSize\":16,\"zzz\":1}".utf8)
        let appearance = try ObsidianAppearance(configurationData: existing)
        XCTAssertEqual(try appearance.mergedConfigurationData(existingData: existing), existing)
        XCTAssertThrowsError(try appearance.mergedConfigurationData(existingData: Data("not json".utf8)))
    }

    func testDefaultFontsAreWrittenAsEmptyStrings() throws {
        let existing = Data(#"{"textFontFamily": "Georgia"}"#.utf8)
        let previous = try ObsidianAppearance(configurationData: existing)
        var changed = previous
        changed.textFontFamilies = FontFamilyList()
        let written = String(decoding: try changed.mergedConfigurationData(existingData: existing, changedFrom: previous), as: UTF8.self)
        XCTAssertEqual(written, "{\n  \"textFontFamily\": \"\"\n}", "Obsidian writes the default font as an empty string.")
    }

    func testTheStoreReadsAndWritesTheVaultsFileAtomically() async throws {
        let vault = try TemporaryVault.make(prefix: "Vault", for: self).root
        let store = VaultStore(root: vault)
        let initialAppearance = try await store.appearance()
        XCTAssertEqual(initialAppearance, ObsidianAppearance(), "A vault without the file has Obsidian's defaults.")
        // A save that changes nothing creates no file.
        try await store.saveAppearance(ObsidianAppearance())
        let fileLocation = vault.appendingPathComponent(".obsidian/appearance.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileLocation.path))

        var appearance = ObsidianAppearance()
        appearance.textFontFamilies = FontFamilyList(families: ["Georgia"])
        try await store.saveAppearance(appearance)
        XCTAssertEqual(try String(contentsOf: fileLocation, encoding: .utf8), "{\n  \"textFontFamily\": \"Georgia\"\n}")

        // Obsidian rewrites the file; Graphite reads its change.
        try Data(#"{"textFontFamily": "Georgia", "baseFontSize": 21, "translucency": false}"#.utf8).write(to: fileLocation)
        let reread = try await store.appearance()
        XCTAssertEqual(reread.baseFontSize, 21)
        var resized = reread
        resized.baseFontSize = 22
        try await store.saveAppearance(resized)
        let finalText = try String(contentsOf: fileLocation, encoding: .utf8)
        XCTAssertTrue(finalText.contains("\"translucency\": false"), finalText)
        XCTAssertTrue(finalText.contains("\"baseFontSize\": 22"), finalText)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: vault.appendingPathComponent(".obsidian").path)
        XCTAssertEqual(leftovers, ["appearance.json"], "The atomic write leaves no staging file behind.")
    }

    // MARK: Themes and snippets

    func testChoosingAThemeAndSnippetsIsWrittenAsObsidianWritesIt() throws {
        let existing = Data(ownersVaultAppearance.utf8)
        let previous = try ObsidianAppearance(configurationData: existing)
        var changed = previous
        changed.cssTheme = "Minimal"
        changed.enabledCssSnippets = ["fast-text-color", "latex-boxes"]
        let written = String(decoding: try changed.mergedConfigurationData(existingData: existing, changedFrom: previous), as: UTF8.self)
        XCTAssertTrue(written.contains("""
          "cssTheme": "Minimal",
          "enabledCssSnippets": [
            "fast-text-color",
            "latex-boxes"
          ],
        """), written)
        XCTAssertEqual(try ObsidianAppearance(configurationData: Data(written.utf8)), changed)
        var unchanged = try ObsidianAppearance(configurationData: Data(#"{"enabledCssSnippets": ["a","b"], "cssTheme": "Things"}"#.utf8))
        unchanged.baseFontSize = 18
        let rewritten = String(decoding: try unchanged.mergedConfigurationData(existingData: Data(#"{"enabledCssSnippets": ["a","b"], "cssTheme": "Things"}"#.utf8)), as: UTF8.self)
        XCTAssertTrue(rewritten.contains(#""enabledCssSnippets": ["a","b"]"#), "An unchanged list keeps its layout: \(rewritten)")
        var cleared = changed
        cleared.enabledCssSnippets = []
        cleared.cssTheme = ""
        let clearedText = String(decoding: try cleared.mergedConfigurationData(existingData: Data(written.utf8), changedFrom: changed), as: UTF8.self)
        XCTAssertTrue(clearedText.contains(#""cssTheme": """#) && clearedText.contains(#""enabledCssSnippets": []"#), clearedText)
    }

    func testTheStoreListsThemesAndSnippetsAndReadsTheirCSS() async throws {
        let vault = try TemporaryVault.make(prefix: "Vault", for: self).root
        let themes = vault.appendingPathComponent(".obsidian/themes"), snippets = vault.appendingPathComponent(".obsidian/snippets")
        try FileManager.default.createDirectory(at: themes.appendingPathComponent("Minimal"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: themes.appendingPathComponent("Empty"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: snippets, withIntermediateDirectories: true)
        try Data("body { --background-primary: #fff; }".utf8).write(to: themes.appendingPathComponent("Minimal/theme.css"))
        try Data("blockquote { border: 1px solid; }".utf8).write(to: snippets.appendingPathComponent("latex-boxes.css"))
        try Data("not css".utf8).write(to: snippets.appendingPathComponent("notes.txt"))
        let store = VaultStore(root: vault)
        let themeNames = await store.installedThemeNames()
        XCTAssertEqual(themeNames, ["Minimal"], "A folder without theme.css is not a theme.")
        let snippetNames = await store.snippetNames()
        XCTAssertEqual(snippetNames, ["latex-boxes"])
        let themeCSS = await store.themeStyleSheet(named: "Minimal")
        XCTAssertEqual(themeCSS, "body { --background-primary: #fff; }")
        let missingTheme = await store.themeStyleSheet(named: "Things")
        XCTAssertNil(missingTheme)
        let escapingTheme = await store.themeStyleSheet(named: "../../secret")
        XCTAssertNil(escapingTheme, "A name is one folder inside the themes folder.")
        let snippetCSS = await store.snippetStyleSheet(named: "latex-boxes")
        XCTAssertEqual(snippetCSS, "blockquote { border: 1px solid; }")
        XCTAssertTrue(ObsidianStyleFiles.isStyleFile(themes.appendingPathComponent("Minimal/theme.css")))
        XCTAssertTrue(ObsidianStyleFiles.isStyleFile(snippets.appendingPathComponent("latex-boxes.css")))
        XCTAssertFalse(ObsidianStyleFiles.isStyleFile(vault.appendingPathComponent(".obsidian/app.json")))
    }

    func testThemeDirectoryEntriesAreReadAndSearched() throws {
        let entries = try JSONDecoder().decode([ObsidianThemeDirectoryEntry].self, from: Data("""
        [{"name": "Minimal", "author": "kepano", "repo": "kepano/obsidian-minimal", "screenshot": "dark.png", "modes": ["dark", "light"]},
         {"name": "Flexoki", "author": "kepano", "repo": "kepano/flexoki-obsidian"},
         {"name": "Things", "author": "colineckert", "repo": "colineckert/obsidian-things", "modes": ["light", "dark"], "legacy": true}]
        """.utf8))
        XCTAssertEqual(entries.map(\.name), ["Minimal", "Flexoki", "Things"])
        XCTAssertEqual(entries[1].modes, [], "Modes are optional in the directory.")
        XCTAssertEqual(ObsidianThemeDirectoryEntry.search(entries, for: "flex").map(\.name), ["Flexoki"])
        XCTAssertEqual(ObsidianThemeDirectoryEntry.search(entries, for: "kepano").map(\.name), ["Minimal", "Flexoki"])
        XCTAssertEqual(ObsidianThemeInstaller.manifestValue("name", in: Data(#"{"name": "Minimal", "version": "8.1.0"}"#.utf8)), "Minimal")
    }
}
