import XCTest
import GraphiteCore
import GraphiteApple
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

/// The keys and values `GraphitePreferences` keeps on the device. Stored values from earlier
/// builds are read through the same keys, so each key string, raw value and default here is
/// a promise to the person's saved settings.
@MainActor
final class GraphitePreferencesPersistedKeysTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() async throws {
        defaults = try IsolatedDeviceState.make(prefix: "GraphitePreferencesPersistedKeysTests", for: self).preferences
    }

    override func tearDown() async throws {
        defaults = nil
    }

    private func makePreferences() -> GraphitePreferences { GraphitePreferences(defaults: defaults) }

    // MARK: String-valued keys

    func testAnEmptyStoreReadsTheDocumentedDefaultOfEveryStringKey() {
        let preferences = makePreferences()

        XCTAssertEqual(preferences.drawingFormat, .png)
        XCTAssertEqual(preferences.drawingBackground, .white)
        XCTAssertEqual(preferences.defaultNoteView, .editing)
        XCTAssertEqual(preferences.defaultEditingMode, .livePreview)
        XCTAssertEqual(preferences.appearanceMode, .system)
        XCTAssertEqual(preferences.recordingCamera, .back)
        XCTAssertEqual(preferences.searchSortOrder, .fileNameAscending)
        XCTAssertEqual(preferences.drawingPaperPattern, .plain)
        XCTAssertEqual(preferences.drawingPaperSpacing, .standard)
        XCTAssertEqual(preferences.drawingPaperLineColor, .gray)
        XCTAssertEqual(preferences.drawingPaperLineStrength, .standard)
        XCTAssertEqual(preferences.notebookPaperColor, .white)
        XCTAssertEqual(preferences.notebookLineColor, .gray)
        XCTAssertEqual(preferences.notebookLineStrength, .standard)
        XCTAssertEqual(preferences.pencilToolbarStyle, .floating)
    }

    func testEachStringKeyReadsTheRawValuesStoredUnderItsExactName() {
        defaults.set("pdf", forKey: "GraphiteDrawingFormat")
        defaults.set("ivory", forKey: "GraphiteDrawingBackground")
        defaults.set("reading", forKey: "GraphiteDefaultNoteView")
        defaults.set("source", forKey: "GraphiteDefaultEditingMode")
        defaults.set("dark", forKey: "GraphiteAppearanceMode")
        defaults.set("front", forKey: "GraphiteRecordingCamera")
        defaults.set("createdOldestFirst", forKey: "GraphiteSearchSortOrder")
        defaults.set("dotted", forKey: "GraphiteDrawingPaperPattern")
        defaults.set("wide", forKey: "GraphiteDrawingPaperSpacing")
        defaults.set("blue", forKey: "GraphiteDrawingPaperLineColor")
        defaults.set("strong", forKey: "GraphiteDrawingPaperLineStrength")
        defaults.set("yellow", forKey: "GraphiteNotebookPaperColor")
        defaults.set("green", forKey: "GraphiteNotebookLineColor")
        defaults.set("light", forKey: "GraphiteNotebookLineStrength")
        defaults.set("fixed", forKey: "GraphitePencilToolbarStyle")

        let preferences = makePreferences()

        XCTAssertEqual(preferences.drawingFormat, .pdf)
        XCTAssertEqual(preferences.drawingBackground, .ivory)
        XCTAssertEqual(preferences.defaultNoteView, .reading)
        XCTAssertEqual(preferences.defaultEditingMode, .source)
        XCTAssertEqual(preferences.appearanceMode, .dark)
        XCTAssertEqual(preferences.recordingCamera, .front)
        XCTAssertEqual(preferences.searchSortOrder, .createdOldestFirst)
        XCTAssertEqual(preferences.drawingPaperPattern, .dotted)
        XCTAssertEqual(preferences.drawingPaperSpacing, .wide)
        XCTAssertEqual(preferences.drawingPaperLineColor, .blue)
        XCTAssertEqual(preferences.drawingPaperLineStrength, .strong)
        XCTAssertEqual(preferences.notebookPaperColor, .yellow)
        XCTAssertEqual(preferences.notebookLineColor, .green)
        XCTAssertEqual(preferences.notebookLineStrength, .light)
        XCTAssertEqual(preferences.pencilToolbarStyle, .fixed)
    }

    func testAnUnknownRawValueInAStringKeyReadsAsTheDefault() {
        for key in ["GraphiteDrawingFormat", "GraphiteDrawingBackground", "GraphiteDefaultNoteView", "GraphiteDefaultEditingMode",
                    "GraphiteAppearanceMode", "GraphiteRecordingCamera", "GraphiteSearchSortOrder", "GraphiteDrawingPaperPattern",
                    "GraphiteDrawingPaperSpacing", "GraphiteDrawingPaperLineColor", "GraphiteDrawingPaperLineStrength",
                    "GraphiteNotebookPaperColor", "GraphiteNotebookLineColor", "GraphiteNotebookLineStrength", "GraphitePencilToolbarStyle"] {
            defaults.set("notAValueAnyBuildWrote", forKey: key)
        }

        let preferences = makePreferences()

        XCTAssertEqual(preferences.drawingFormat, .png)
        XCTAssertEqual(preferences.drawingBackground, .white)
        XCTAssertEqual(preferences.defaultNoteView, .editing)
        XCTAssertEqual(preferences.defaultEditingMode, .livePreview)
        XCTAssertEqual(preferences.appearanceMode, .system)
        XCTAssertEqual(preferences.recordingCamera, .back)
        XCTAssertEqual(preferences.searchSortOrder, .fileNameAscending)
        XCTAssertEqual(preferences.drawingPaperPattern, .plain)
        XCTAssertEqual(preferences.drawingPaperSpacing, .standard)
        XCTAssertEqual(preferences.drawingPaperLineColor, .gray)
        XCTAssertEqual(preferences.drawingPaperLineStrength, .standard)
        XCTAssertEqual(preferences.notebookPaperColor, .white)
        XCTAssertEqual(preferences.notebookLineColor, .gray)
        XCTAssertEqual(preferences.notebookLineStrength, .standard)
        XCTAssertEqual(preferences.pencilToolbarStyle, .floating)
    }

    func testTheRawValuesOfTheStringKeyedEnumerationsAreThoseOfEarlierBuilds() {
        XCTAssertEqual(DrawingFormat.allCases.map(\.rawValue), ["png", "pdf", "svg"])
        XCTAssertEqual(DefaultNoteView.allCases.map(\.rawValue), ["editing", "reading"])
        XCTAssertEqual(EditingMode.allCases.map(\.rawValue), ["livePreview", "source"])
        XCTAssertEqual(AppearanceMode.allCases.map(\.rawValue), ["system", "light", "dark"])
        XCTAssertEqual(SearchSortOrder.allCases.map(\.rawValue), [
            "fileNameAscending", "fileNameDescending", "modifiedNewestFirst", "modifiedOldestFirst", "createdNewestFirst", "createdOldestFirst",
        ])
        XCTAssertEqual(DrawingBackground.allCases.map(\.rawValue), ["white", "ivory", "yellow", "gray", "transparent"])
        XCTAssertEqual(CameraPosition.allCases.map(\.rawValue), ["back", "front"])
        XCTAssertEqual(DrawingPaperPattern.allCases.map(\.rawValue), ["plain", "squared", "ruled", "dotted"])
        XCTAssertEqual(DrawingPaperSpacing.allCases.map(\.rawValue), ["narrow", "standard", "wide"])
        XCTAssertEqual(DrawingPaperLineColor.allCases.map(\.rawValue), ["gray", "blue", "green", "red"])
        XCTAssertEqual(DrawingPaperLineStrength.allCases.map(\.rawValue), ["light", "standard", "strong"])
        XCTAssertEqual(PencilToolbarStyle.allCases.map(\.rawValue), ["floating", "fixed"])
    }

    func testChangingAStringSettingStoresItsRawValueUnderTheSameKey() {
        let preferences = makePreferences()

        preferences.drawingFormat = .svg
        preferences.drawingBackground = .gray
        preferences.defaultNoteView = .reading
        preferences.defaultEditingMode = .source
        preferences.appearanceMode = .light
        preferences.recordingCamera = .front
        preferences.searchSortOrder = .modifiedNewestFirst
        preferences.drawingPaperPattern = .ruled
        preferences.drawingPaperSpacing = .narrow
        preferences.drawingPaperLineColor = .red
        preferences.drawingPaperLineStrength = .light
        preferences.notebookPaperColor = .ivory
        preferences.notebookLineColor = .blue
        preferences.notebookLineStrength = .strong
        preferences.pencilToolbarStyle = .fixed

        let stored = [
            "GraphiteDrawingFormat", "GraphiteDrawingBackground", "GraphiteDefaultNoteView", "GraphiteDefaultEditingMode",
            "GraphiteAppearanceMode", "GraphiteRecordingCamera", "GraphiteSearchSortOrder", "GraphiteDrawingPaperPattern",
            "GraphiteDrawingPaperSpacing", "GraphiteDrawingPaperLineColor", "GraphiteDrawingPaperLineStrength",
            "GraphiteNotebookPaperColor", "GraphiteNotebookLineColor", "GraphiteNotebookLineStrength", "GraphitePencilToolbarStyle",
        ].map { key in defaults.string(forKey: key) }
        XCTAssertEqual(stored, ["svg", "gray", "reading", "source", "light", "front", "modifiedNewestFirst", "ruled", "narrow", "red",
                                "light", "ivory", "blue", "strong", "fixed"])
    }

    // MARK: Boolean keys

    func testAnEmptyStoreReadsTheDocumentedDefaultOfEveryBooleanKey() {
        let preferences = makePreferences()

        XCTAssertTrue(preferences.usesReadableLineLength)
        XCTAssertTrue(preferences.usesSpellChecking)
        XCTAssertTrue(preferences.formatsCodeBlocks)
        XCTAssertTrue(preferences.embedsRecordingsInNote)
        XCTAssertTrue(preferences.showsInlineTitle)
        XCTAssertTrue(preferences.showsFileExtensions)
        XCTAssertTrue(preferences.drawsOnPencilDoubleTap)
        XCTAssertTrue(preferences.usesVaultTheme)
        XCTAssertTrue(preferences.makesShapesOnHold)
        XCTAssertFalse(preferences.drawingPaperAppearsInNotes)
    }

    func testEachBooleanKeyReadsAStoredValueUnderItsExactName() {
        let keys = ["GraphiteUsesReadableLineLength", "GraphiteUsesSpellChecking", "GraphiteFormatsCodeBlocks", "GraphiteEmbedsRecordingsInNote",
                    "GraphiteShowsInlineTitle", "GraphiteShowsFileExtensions", "GraphiteDrawsOnPencilDoubleTap", "GraphiteUsesVaultTheme",
                    "GraphiteMakesShapesOnHold"]
        for key in keys { defaults.set(false, forKey: key) }
        defaults.set(true, forKey: "GraphiteDrawingPaperAppearsInNotes")

        let preferences = makePreferences()

        XCTAssertFalse(preferences.usesReadableLineLength)
        XCTAssertFalse(preferences.usesSpellChecking)
        XCTAssertFalse(preferences.formatsCodeBlocks)
        XCTAssertFalse(preferences.embedsRecordingsInNote)
        XCTAssertFalse(preferences.showsInlineTitle)
        XCTAssertFalse(preferences.showsFileExtensions)
        XCTAssertFalse(preferences.drawsOnPencilDoubleTap)
        XCTAssertFalse(preferences.usesVaultTheme)
        XCTAssertFalse(preferences.makesShapesOnHold)
        XCTAssertTrue(preferences.drawingPaperAppearsInNotes)
    }

    func testChangingABooleanSettingStoresTheBooleanUnderTheSameKey() {
        let preferences = makePreferences()

        preferences.usesReadableLineLength = false
        preferences.usesSpellChecking = false
        preferences.formatsCodeBlocks = false
        preferences.embedsRecordingsInNote = false
        preferences.showsInlineTitle = false
        preferences.showsFileExtensions = false
        preferences.drawsOnPencilDoubleTap = false
        preferences.usesVaultTheme = false
        preferences.makesShapesOnHold = false
        preferences.drawingPaperAppearsInNotes = true

        let keys = ["GraphiteUsesReadableLineLength", "GraphiteUsesSpellChecking", "GraphiteFormatsCodeBlocks", "GraphiteEmbedsRecordingsInNote",
                    "GraphiteShowsInlineTitle", "GraphiteShowsFileExtensions", "GraphiteDrawsOnPencilDoubleTap", "GraphiteUsesVaultTheme",
                    "GraphiteMakesShapesOnHold", "GraphiteDrawingPaperAppearsInNotes"]
        XCTAssertEqual(keys.map { key in defaults.object(forKey: key) as? Bool }, [false, false, false, false, false, false, false, false, false, true])
    }

    // MARK: Numeric keys

    func testTheSnapshotKeysReadOnlyValuesInsideTheirRangesAndOtherwiseTheirDefaults() {
        XCTAssertEqual(makePreferences().snapshotIntervalMinutes, 5)
        XCTAssertEqual(makePreferences().snapshotHistoryDays, 7)

        let cases: [(interval: Int, history: Int, expectedInterval: Int, expectedHistory: Int)] = [
            (1, 1, 1, 1), (60, 365, 60, 365), (30, 90, 30, 90),
            (0, 0, 5, 7), (61, 366, 5, 7), (-3, -1, 5, 7),
        ]
        for testCase in cases {
            defaults.set(testCase.interval, forKey: "GraphiteSnapshotIntervalMinutes")
            defaults.set(testCase.history, forKey: "GraphiteSnapshotHistoryDays")
            let preferences = makePreferences()
            XCTAssertEqual(preferences.snapshotIntervalMinutes, testCase.expectedInterval, "interval \(testCase.interval)")
            XCTAssertEqual(preferences.snapshotHistoryDays, testCase.expectedHistory, "history \(testCase.history)")
        }
    }

    func testChangingTheSnapshotSettingsStoresIntegersUnderTheirKeys() {
        let preferences = makePreferences()

        preferences.snapshotIntervalMinutes = 15
        preferences.snapshotHistoryDays = 30

        XCTAssertEqual(defaults.object(forKey: "GraphiteSnapshotIntervalMinutes") as? Int, 15)
        XCTAssertEqual(defaults.object(forKey: "GraphiteSnapshotHistoryDays") as? Int, 30)
    }

    func testTheNotebookPaperSpacingOffersTheseSixChoicesInPoints() {
        XCTAssertEqual(NotebookPaperSpacing.choices, [11.34, 14.17, 17.01, 18, 22.68, 28.35])
    }

    func testTheNotebookPaperSpacingKeyReadsOnlyAChoiceAndOtherwiseTheStandardSpacing() {
        XCTAssertEqual(makePreferences().notebookPaperSpacing, PaperSpecification.standardSpacing)

        defaults.set(22.68, forKey: "GraphiteNotebookPaperSpacing")
        XCTAssertEqual(makePreferences().notebookPaperSpacing, 22.68)
        defaults.set(19.0, forKey: "GraphiteNotebookPaperSpacing")
        XCTAssertEqual(makePreferences().notebookPaperSpacing, PaperSpecification.standardSpacing)
        defaults.set(0.0, forKey: "GraphiteNotebookPaperSpacing")
        XCTAssertEqual(makePreferences().notebookPaperSpacing, PaperSpecification.standardSpacing)
    }

    func testChangingTheNotebookPaperSpacingStoresADoubleUnderItsKey() {
        let preferences = makePreferences()

        preferences.notebookPaperSpacing = 14.17

        XCTAssertEqual(defaults.object(forKey: "GraphiteNotebookPaperSpacing") as? Double, 14.17)
    }

    func testTheLegacyTextSizeIsReadFromItsKeyOnlyBetween12And28() {
        XCTAssertNil(makePreferences().legacyChosenTextSize)

        let cases: [(stored: Double, expected: Double?)] = [(12, 12), (17.5, 17.5), (28, 28), (11.9, nil), (28.1, nil), (0, nil), (-14, nil)]
        for testCase in cases {
            defaults.set(testCase.stored, forKey: "GraphiteTextSize")
            XCTAssertEqual(makePreferences().legacyChosenTextSize, testCase.expected, "stored \(testCase.stored)")
        }
    }

    func testTransparentNotebookPaperReadsAsWhite() {
        defaults.set("transparent", forKey: "GraphiteNotebookPaperColor")

        let preferences = makePreferences()

        XCTAssertEqual(preferences.notebookPaperColor, .white)
        XCTAssertNil(GraphitePreferences.storedNotebookPaper(template: .blank, in: defaults).paperColorHex)
    }

    func testTintedNotebookPaperIsReadFromTheStoredColorAndSpacing() {
        defaults.set("ivory", forKey: "GraphiteNotebookPaperColor")
        defaults.set(28.35, forKey: "GraphiteNotebookPaperSpacing")
        defaults.set("red", forKey: "GraphiteNotebookLineColor")
        defaults.set("strong", forKey: "GraphiteNotebookLineStrength")

        let paper = GraphitePreferences.storedNotebookPaper(template: .blank, in: defaults)

        XCTAssertEqual(paper.spacing, 28.35)
        XCTAssertEqual(paper.paperColorHex, "#fbf7ea")
        XCTAssertEqual(paper.lineColor, .red)
        XCTAssertEqual(paper.lineStrength, .strong)
    }

    // MARK: List and data keys

    func testTheDisabledCorePluginsAreStoredAsSortedRawValuesAndReadBack() {
        let preferences = makePreferences()

        preferences.setEnabled(.graph, false)
        preferences.setEnabled(.backlinks, false)
        preferences.setEnabled(.bases, false)
        preferences.setEnabled(.wordCount, false)

        XCTAssertEqual(defaults.stringArray(forKey: "GraphiteDisabledCorePlugins"), ["backlinks", "bases", "graph", "wordCount"])
        let reread = makePreferences()
        XCTAssertEqual(reread.corePluginSwitches.turnedOff, [.graph, .backlinks, .bases, .wordCount])
        XCTAssertFalse(reread.isEnabled(.graph))
        XCTAssertTrue(reread.isEnabled(.canvas))
    }

    func testAStoredDisabledPluginNoBuildKnowsIsIgnored() {
        defaults.set(["bases", "aPluginThatWasRemoved"], forKey: "GraphiteDisabledCorePlugins")

        XCTAssertEqual(makePreferences().corePluginSwitches.turnedOff, [.bases])
    }

    func testThePluginsTurnedOnAreStoredAsSortedRawValuesUnderTheirOwnKey() {
        let preferences = makePreferences()

        preferences.setEnabled(.readAloud, true)

        XCTAssertEqual(defaults.stringArray(forKey: "GraphiteEnabledCorePlugins"), ["readAloud"])
        XCTAssertEqual(makePreferences().corePluginSwitches.turnedOn, [.readAloud])
        XCTAssertTrue(makePreferences().isEnabled(.readAloud))
    }

    func testTheCorePluginRawValuesAreThoseOfEarlierBuilds() {
        XCTAssertEqual(CorePlugin.allCases.map(\.rawValue), [
            "backlinks", "outgoingLinks", "outline", "properties", "tags", "wordCount", "colors", "drawings", "audioRecorder", "readAloud",
            "bases", "templates", "dailyNotes", "footnotes", "fileRecovery", "bookmarks", "graph", "map", "canvas", "notebookImport",
            "postgreSQLMirror",
        ])
    }

    func testTheRecentCommandsAreStoredAsAStringListInTheOrderKept() {
        let preferences = makePreferences()

        preferences.recentCommandIdentifiers = ["new-note", "switcher", "community-plugin:dataview:refresh"]

        XCTAssertEqual(defaults.stringArray(forKey: "GraphiteRecentCommands"), ["new-note", "switcher", "community-plugin:dataview:refresh"])
        XCTAssertEqual(makePreferences().recentCommandIdentifiers, ["new-note", "switcher", "community-plugin:dataview:refresh"])
    }

    func testAnEmptyStoreHasNoRecentCommandsAndTheDefaultPalettes() {
        let preferences = makePreferences()

        XCTAssertEqual(preferences.recentCommandIdentifiers, [])
        XCTAssertEqual(preferences.colorPalette.map(\.name), ["red", "orange", "yellow", "green", "cyan", "blue", "purple", "pink"])
        XCTAssertEqual(preferences.colorPalette.map(\.hex), ["#e93147", "#ec7500", "#e0ac00", "#08b94e", "#00bfbc", "#086ddd", "#7852ee", "#d53984"])
        XCTAssertEqual(preferences.highlighterPalette.map(\.name), ["yellow", "green", "blue", "pink", "purple", "orange"])
        XCTAssertEqual(preferences.highlighterPalette.map(\.hex), ["#f6d743", "#8fe378", "#85c7ff", "#ff9ec9", "#c7a3ff", "#ffb35c"])
    }

    func testAStoredPaletteIsAJSONListOfIdentifierNameAndHexAndIsReadBack() throws {
        let storedJSON = ##"[{"id":"7F0A3C54-9B1E-4D7C-8E21-5A6B4C3D2E10","name":"coral","hex":"#ff7f50"},{"id":"0C1D2E3F-4A5B-4C6D-8E7F-A1B2C3D4E5F6","name":"navy","hex":"#000080"}]"##
        defaults.set(Data(storedJSON.utf8), forKey: "GraphiteColorPalette")
        defaults.set(Data(storedJSON.utf8), forKey: "GraphiteHighlighterPalette")

        let preferences = makePreferences()

        let expected = [PaletteColor(id: try XCTUnwrap(UUID(uuidString: "7F0A3C54-9B1E-4D7C-8E21-5A6B4C3D2E10")), name: "coral", hex: "#ff7f50"),
                        PaletteColor(id: try XCTUnwrap(UUID(uuidString: "0C1D2E3F-4A5B-4C6D-8E7F-A1B2C3D4E5F6")), name: "navy", hex: "#000080")]
        XCTAssertEqual(preferences.colorPalette, expected)
        XCTAssertEqual(preferences.highlighterPalette, expected)
        XCTAssertEqual(GraphitePreferences.storedColorPalette(in: defaults), expected)
        XCTAssertEqual(GraphitePreferences.storedHighlighterPalette(in: defaults), expected)
    }

    func testChangingAPaletteStoresJSONObjectsWithIdentifierNameAndHexFields() throws {
        let preferences = makePreferences()
        let identifier = try XCTUnwrap(UUID(uuidString: "7F0A3C54-9B1E-4D7C-8E21-5A6B4C3D2E10"))

        preferences.colorPalette = [PaletteColor(id: identifier, name: "coral", hex: "#ff7f50")]
        preferences.highlighterPalette = [PaletteColor(id: identifier, name: "lemon", hex: "#fff44f")]

        for (key, name, hex) in [("GraphiteColorPalette", "coral", "#ff7f50"), ("GraphiteHighlighterPalette", "lemon", "#fff44f")] {
            let data = try XCTUnwrap(defaults.data(forKey: key))
            let objects = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: String]])
            XCTAssertEqual(objects, [["id": "7F0A3C54-9B1E-4D7C-8E21-5A6B4C3D2E10", "name": name, "hex": hex]], key)
        }
    }

    func testAnUnreadablePaletteReadsAsTheDefaultPalette() {
        defaults.set(Data("not json".utf8), forKey: "GraphiteColorPalette")
        defaults.set(Data(#"[{"name":"missing the other fields"}]"#.utf8), forKey: "GraphiteHighlighterPalette")

        let preferences = makePreferences()

        XCTAssertEqual(preferences.colorPalette.map(\.name), PaletteColor.defaultPalette.map(\.name))
        XCTAssertEqual(preferences.highlighterPalette.map(\.name), PaletteColor.defaultHighlighterPalette.map(\.name))
    }

    func testThePaletteKeysForViewsThatFollowThemAreTheStoredKeys() {
        XCTAssertEqual(GraphitePreferences.colorPaletteKey, "GraphiteColorPalette")
        XCTAssertEqual(GraphitePreferences.highlighterPaletteKey, "GraphiteHighlighterPalette")
    }

    // MARK: Accent

    func testTheAccentChosenOnTheDeviceIsStoredAsACanonicalHexAndNoneRemovesTheKey() {
        defaults.set("#ABC", forKey: "GraphiteAccentColor")
        XCTAssertEqual(makePreferences().chosenAccentHex, "#aabbcc")
        XCTAssertEqual(GraphitePreferences.storedAccentHex(in: defaults), "#aabbcc")

        let preferences = makePreferences()
        preferences.chosenAccentHex = "#112233"
        XCTAssertEqual(defaults.string(forKey: "GraphiteAccentColor"), "#112233")
        preferences.chosenAccentHex = nil
        XCTAssertNil(defaults.object(forKey: "GraphiteAccentColor"))
        XCTAssertEqual(GraphitePreferences.storedAccentHex(in: defaults), GraphiteTheme.defaultAccentHex)
    }

    func testAnUnreadableStoredAccentReadsAsNoChoice() {
        defaults.set("not a color", forKey: "GraphiteAccentColor")

        XCTAssertNil(makePreferences().chosenAccentHex)
        XCTAssertEqual(GraphitePreferences.storedAccentHex(in: defaults), GraphiteTheme.defaultAccentHex)
    }

    func testTheAccentComesFromTheDeviceThenTheVaultThenTheDefault() {
        let preferences = makePreferences()
        XCTAssertEqual(preferences.accentHex, GraphiteTheme.defaultAccentHex, "Nothing chosen and no vault accent.")

        preferences.vaultAccentHex = "#445566"
        XCTAssertEqual(preferences.accentHex, "#445566", "The vault's accent when none is chosen on the device.")

        preferences.chosenAccentHex = "#112233"
        XCTAssertEqual(preferences.accentHex, "#112233", "The device's choice wins over the vault's accent.")

        preferences.chosenAccentHex = nil
        XCTAssertEqual(preferences.accentHex, "#445566", "Without a choice the vault's accent applies again.")

        preferences.vaultAccentHex = nil
        XCTAssertEqual(preferences.accentHex, GraphiteTheme.defaultAccentHex)
    }

    func testChoosingAnAccentOnTheDeviceLeavesTheVaultsAccentAsItWas() {
        let preferences = makePreferences()
        preferences.vaultAccentHex = "#445566"

        preferences.chosenAccentHex = "#112233"

        XCTAssertEqual(preferences.vaultAccentHex, "#445566")
        XCTAssertEqual(defaults.string(forKey: "GraphiteAccentColor"), "#112233")
    }
}
