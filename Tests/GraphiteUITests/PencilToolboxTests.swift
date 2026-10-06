import XCTest
@testable import GraphiteUI
import GraphiteCore

/// The state of the fixed Pencil tool bar.
@MainActor
final class PencilToolboxTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "PencilToolboxTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testStartsWithAPenAPencilAndAHighlighterAtMediumWidths() {
        let toolbox = PencilToolbox(defaults: defaults)
        XCTAssertEqual(toolbox.toolInUse, .ink)
        XCTAssertEqual(toolbox.presets.map(\.ink), [.pen, .pencil, .highlighter])
        XCTAssertEqual(toolbox.presetInUse.ink, .pen)
        XCTAssertTrue(toolbox.erasesWholeStrokes)
        XCTAssertFalse(toolbox.isRulerActive)
        for preset in toolbox.presets {
            XCTAssertEqual(preset.width, preset.ink.mediumWidth)
            XCTAssertEqual(preset.colorHex, preset.ink.defaultColorHex)
            XCTAssertEqual(preset.opacity, 1)
        }
    }

    func testEveryInkOffersThreeWidthsItCanDraw() {
        XCTAssertEqual(PencilInk.allCases.count, 8, "Every ink of the system's palette.")
        XCTAssertEqual(Set(PencilInk.allCases.map(\.title)).count, 8)
        for ink in PencilInk.allCases {
            XCTAssertEqual(ink.widthChoices.count, 3, ink.title)
            XCTAssertEqual(ink.widthChoices, ink.widthChoices.sorted(), ink.title)
            XCTAssertTrue(ink.widthChoices.allSatisfy(ink.widthRange.contains), ink.title)
            XCTAssertEqual(TextColorMarkup.canonicalHex(ink.defaultColorHex), ink.defaultColorHex, ink.title)
        }
    }

    func testEachPresetKeepsItsOwnColorWidthAndOpacity() {
        let toolbox = PencilToolbox(defaults: defaults)
        toolbox.chooseColor(hex: "#E93147")
        toolbox.chooseWidth(PencilInk.pen.widthChoices[2])
        toolbox.chooseOpacity(0.5)
        toolbox.usePreset(at: 2)
        toolbox.chooseColor(hex: "#08b94e")
        XCTAssertEqual(toolbox.presets[0].colorHex, "#e93147", "Colors are kept in one spelling.")
        XCTAssertEqual(toolbox.presets[0].width, PencilInk.pen.widthChoices[2])
        XCTAssertEqual(toolbox.presets[0].opacity, 0.5)
        XCTAssertEqual(toolbox.presets[2].colorHex, "#08b94e")
        XCTAssertEqual(toolbox.presets[2].width, PencilInk.highlighter.mediumWidth)
        XCTAssertEqual(toolbox.presets[1].colorHex, PencilInk.pencil.defaultColorHex)

        // A width between the three choices is one the options' slider gives.
        toolbox.chooseWidth(21.5)
        XCTAssertEqual(toolbox.presetInUse.width, 21.5)
        // A width the ink cannot draw, an opacity out of range and a color that is none
        // change nothing.
        toolbox.chooseWidth(123)
        toolbox.chooseWidth(.nan)
        toolbox.chooseOpacity(0)
        toolbox.chooseOpacity(1.5)
        toolbox.chooseColor(hex: "not a color")
        XCTAssertEqual(toolbox.presetInUse.width, 21.5)
        XCTAssertEqual(toolbox.presetInUse.opacity, 1)
        XCTAssertEqual(toolbox.presetInUse.colorHex, "#08b94e")
        toolbox.usePreset(at: 9)
        XCTAssertEqual(toolbox.presetInUseIndex, 2)
    }

    func testAPresetBecomesAnyInkAtThatInksMediumWidth() {
        let toolbox = PencilToolbox(defaults: defaults)
        toolbox.chooseInk(.watercolor)
        XCTAssertEqual(toolbox.presetInUse.ink, .watercolor)
        XCTAssertEqual(toolbox.presetInUse.width, PencilInk.watercolor.mediumWidth, "A pen's width would be a hairline.")
        XCTAssertEqual(toolbox.presetInUse.colorHex, PencilInk.watercolor.defaultColorHex)

        // A color still the old ink's default follows the ink; a chosen color stays.
        toolbox.chooseInk(.highlighter)
        XCTAssertEqual(toolbox.presetInUse.colorHex, PencilInk.highlighter.defaultColorHex)
        toolbox.chooseColor(hex: "#086ddd")
        toolbox.chooseInk(.fountainPen)
        XCTAssertEqual(toolbox.presetInUse.colorHex, "#086ddd")
        XCTAssertEqual(toolbox.presets.map(\.ink), [.fountainPen, .pencil, .highlighter])
    }

    func testPresetsAreAddedAfterTheOneInUseAndRemovedDownToOne() {
        let toolbox = PencilToolbox(defaults: defaults)
        toolbox.chooseColor(hex: "#e93147")
        toolbox.addPreset()
        XCTAssertEqual(toolbox.presets.map(\.ink), [.pen, .pen, .pencil, .highlighter])
        XCTAssertEqual(toolbox.presetInUseIndex, 1, "The copy is taken up, to be set up differently.")
        XCTAssertEqual(toolbox.presetInUse.colorHex, "#e93147")
        XCTAssertNotEqual(toolbox.presets[0].id, toolbox.presets[1].id)
        toolbox.chooseColor(hex: "#086ddd")
        XCTAssertEqual(toolbox.presets[0].colorHex, "#e93147")

        while toolbox.canAddPreset { toolbox.addPreset() }
        XCTAssertEqual(toolbox.presets.count, PencilToolbox.maximumPresetCount)
        toolbox.addPreset()
        XCTAssertEqual(toolbox.presets.count, PencilToolbox.maximumPresetCount)

        // Removing the last preset takes up the one before it.
        toolbox.usePreset(at: toolbox.presets.count - 1)
        toolbox.removePresetInUse()
        XCTAssertEqual(toolbox.presetInUseIndex, toolbox.presets.count - 1)
        XCTAssertEqual(toolbox.presetInUse.ink, .pencil)
        while toolbox.canRemovePreset { toolbox.removePresetInUse() }
        XCTAssertEqual(toolbox.presets.count, 1)
        toolbox.removePresetInUse()
        XCTAssertEqual(toolbox.presets.count, 1, "The bar always has something to draw with.")
        XCTAssertEqual(toolbox.presetInUseIndex, 0)
    }

    func testChoosingAColorWithTheEraserInUseTakesUpTheInkLastInUse() {
        let toolbox = PencilToolbox(defaults: defaults)
        toolbox.usePreset(at: 1)
        toolbox.use(.eraser)
        XCTAssertEqual(toolbox.selection.kind, .eraser)
        toolbox.chooseColor(hex: "#086ddd")
        XCTAssertEqual(toolbox.toolInUse, .ink)
        XCTAssertEqual(toolbox.presetInUse.ink, .pencil)
        XCTAssertEqual(toolbox.presets[1].colorHex, "#086ddd")
        toolbox.use(.lasso)
        toolbox.chooseWidth(PencilInk.pencil.widthChoices[0])
        toolbox.chooseInk(.crayon)
        XCTAssertEqual(toolbox.presets[1].width, PencilInk.pencil.mediumWidth, "The lasso has no width to choose.")
        XCTAssertEqual(toolbox.presets[1].ink, .pencil)

        toolbox.chooseEraserWidth(PencilToolbox.eraserWidthChoices[2])
        XCTAssertEqual(toolbox.eraserWidth, PencilToolbox.eraserWidthChoices[2])
        toolbox.chooseEraserWidth(5)
        XCTAssertEqual(toolbox.eraserWidth, PencilToolbox.eraserWidthChoices[2])
    }

    func testStateIsKeptBetweenLaunchesAndDamagedStateFallsBack() throws {
        let toolbox = PencilToolbox(defaults: defaults)
        toolbox.usePreset(at: 1)
        toolbox.chooseInk(.crayon)
        toolbox.chooseColor(hex: "#7852ee")
        toolbox.chooseWidth(PencilInk.crayon.widthChoices[0])
        toolbox.chooseOpacity(0.4)
        toolbox.addPreset()
        toolbox.erasesWholeStrokes = false
        toolbox.chooseEraserWidth(PencilToolbox.eraserWidthChoices[0])
        toolbox.isRulerActive = true
        toolbox.use(.lasso)

        let relaunched = PencilToolbox(defaults: defaults)
        XCTAssertEqual(relaunched.toolInUse, .lasso)
        XCTAssertEqual(relaunched.presets, toolbox.presets)
        XCTAssertEqual(relaunched.presetInUseIndex, 2)
        XCTAssertEqual(relaunched.presetInUse.ink, .crayon)
        XCTAssertEqual(relaunched.presetInUse.opacity, 0.4)
        XCTAssertFalse(relaunched.erasesWholeStrokes)
        XCTAssertEqual(relaunched.eraserWidth, PencilToolbox.eraserWidthChoices[0])
        XCTAssertFalse(relaunched.isRulerActive, "The ruler is put away with the app.")

        // Values another build would not offer fall back to ones the bar can show.
        let identifier = UUID().uuidString
        let damaged = """
        {"toolInUse":"ink","presetInUseIndex":7,"erasesWholeStrokes":true,"eraserWidth":3,
         "presets":[{"id":"\(identifier)","ink":"pen","colorHex":"purple","width":99,"opacity":4}]}
        """
        defaults.set(Data(damaged.utf8), forKey: PencilToolbox.storageKey)
        let recovered = PencilToolbox(defaults: defaults)
        XCTAssertEqual(recovered.presets.count, 1)
        XCTAssertEqual(recovered.presetInUseIndex, 0)
        XCTAssertEqual(recovered.presetInUse.id.uuidString, identifier)
        XCTAssertEqual(recovered.presetInUse.colorHex, PencilInk.pen.defaultColorHex)
        XCTAssertEqual(recovered.presetInUse.width, PencilInk.pen.widthRange.upperBound)
        XCTAssertEqual(recovered.presetInUse.opacity, 1)
        XCTAssertEqual(recovered.eraserWidth, PencilToolbox.eraserWidthChoices[1])

        // No presets, two presets with one identifier, an ink this build does not know, and
        // text that is no state at all: the three presets the bar starts with.
        let withoutPresets = ##"{"toolInUse":"eraser","presetInUseIndex":0,"erasesWholeStrokes":true,"eraserWidth":36,"presets":[]}"##
        let twin = ##"{"id":"\##(identifier)","ink":"pen","colorHex":"#1c1c1e","width":2.8,"opacity":1}"##
        let withTwins = ##"{"toolInUse":"ink","presetInUseIndex":1,"erasesWholeStrokes":true,"eraserWidth":36,"presets":[\##(twin),\##(twin)]}"##
        let withUnknownInk = ##"{"toolInUse":"ink","presetInUseIndex":0,"erasesWholeStrokes":true,"eraserWidth":36,"presets":[{"id":"\##(identifier)","ink":"quill","colorHex":"#1c1c1e","width":2.8,"opacity":1}]}"##
        for damagedState in [withoutPresets, withTwins, withUnknownInk, "not JSON"] {
            defaults.set(Data(damagedState.utf8), forKey: PencilToolbox.storageKey)
            let fallback = PencilToolbox(defaults: defaults)
            XCTAssertEqual(fallback.presets.map(\.ink), [.pen, .pencil, .highlighter], damagedState)
            XCTAssertEqual(fallback.presetInUseIndex, 0, damagedState)
        }
    }

    func testSelectionChangesExactlyWhenTheToolDoesAndCanvasesAreTold() {
        let toolbox = PencilToolbox(defaults: defaults)
        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(forName: PencilToolbox.selectionDidChange, object: toolbox, queue: nil) { _ in
            MainActor.assumeIsolated { notificationCount += 1 }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let penSelection = toolbox.selection
        XCTAssertEqual(toolbox.selection, penSelection)
        // Choosing what is already chosen tells no one.
        toolbox.usePreset(at: 0)
        toolbox.use(.ink)
        toolbox.chooseWidth(penSelection.preset.width)
        toolbox.chooseColor(hex: penSelection.preset.colorHex)
        XCTAssertEqual(notificationCount, 0)

        toolbox.chooseWidth(PencilInk.pen.widthChoices[0])
        XCTAssertNotEqual(toolbox.selection, penSelection)
        XCTAssertEqual(notificationCount, 1)
        let fineSelection = toolbox.selection
        toolbox.isRulerActive = true
        XCTAssertNotEqual(toolbox.selection, fineSelection)
        XCTAssertEqual(notificationCount, 2)
        toolbox.use(.eraser)
        XCTAssertEqual(toolbox.selection.kind, .eraser)
        XCTAssertEqual(toolbox.selection.preset, fineSelection.preset, "The ink last in use is kept while erasing.")
        XCTAssertEqual(PencilToolbarStyle(rawValue: "fixed"), .fixed)
        XCTAssertEqual(PencilToolbarStyle.allCases.map(\.title), ["Floating palette", "Fixed bar"])
    }

    // MARK: Hold to make a shape

    func testAStrokeRestsWhereItStaysWithinTheRestingRadius() {
        var rest = StrokeRest(startingAt: CGPoint(x: 100, y: 100))
        XCTAssertFalse(rest.isLongEnoughForAShape, "A tap held down is no shape.")
        // A resting Pencil trembles: still at rest, though the stroke grows a little.
        XCTAssertFalse(rest.move(to: CGPoint(x: 102, y: 101)))
        XCTAssertFalse(rest.move(to: CGPoint(x: 99, y: 103)))
        XCTAssertEqual(rest.restingPoint, CGPoint(x: 100, y: 100))
        XCTAssertFalse(rest.isLongEnoughForAShape)

        // Drawing on leaves the resting place, which moves along with the touch.
        XCTAssertTrue(rest.move(to: CGPoint(x: 120, y: 100)))
        XCTAssertEqual(rest.restingPoint, CGPoint(x: 120, y: 100))
        XCTAssertTrue(rest.move(to: CGPoint(x: 140, y: 100)))
        XCTAssertTrue(rest.isLongEnoughForAShape)
        XCTAssertFalse(rest.move(to: CGPoint(x: 140 + StrokeRest.restingRadius, y: 100)), "The radius itself is at rest.")
        XCTAssertTrue(rest.move(to: CGPoint(x: 141 + StrokeRest.restingRadius, y: 100)))
    }

    func testHoldingToMakeAShapeIsOnUntilTurnedOff() {
        XCTAssertTrue(StrokeHoldPreference.isOn(in: defaults))
        XCTAssertTrue(GraphitePreferences(defaults: defaults).makesShapesOnHold)
        let preferences = GraphitePreferences(defaults: defaults)
        preferences.makesShapesOnHold = false
        XCTAssertFalse(StrokeHoldPreference.isOn(in: defaults))
        XCTAssertFalse(GraphitePreferences(defaults: defaults).makesShapesOnHold)
    }

    // MARK: Apple Pencil's double tap and squeeze

    func testSwitchingToThePreviousToolGoesBackAndForthBetweenTwoTools() {
        let toolbox = PencilToolbox(defaults: defaults)
        toolbox.switchToPreviousTool()
        XCTAssertEqual(toolbox.toolInUse, .ink, "Nothing to go back to yet.")
        XCTAssertEqual(toolbox.presetInUseIndex, 0)
        toolbox.usePreset(at: 2)
        toolbox.switchToPreviousTool()
        XCTAssertEqual(toolbox.presetInUseIndex, 0)
        toolbox.switchToPreviousTool()
        XCTAssertEqual(toolbox.presetInUseIndex, 2)
        toolbox.use(.lasso)
        toolbox.switchToPreviousTool()
        XCTAssertEqual(toolbox.toolInUse, .ink)
        XCTAssertEqual(toolbox.presetInUseIndex, 2)
        toolbox.switchToPreviousTool()
        XCTAssertEqual(toolbox.toolInUse, .lasso)
    }

    func testChoosingAColorWhileErasingIsAChangeOfTool() {
        let toolbox = PencilToolbox(defaults: defaults)
        toolbox.usePreset(at: 1)
        toolbox.use(.eraser)
        toolbox.chooseColor(hex: "#e93147")
        XCTAssertEqual(toolbox.toolInUse, .ink)
        toolbox.switchToPreviousTool()
        XCTAssertEqual(toolbox.toolInUse, .eraser)
    }

    func testTheEraserSwitchGoesToTheEraserAndBackToTheToolBeforeIt() {
        let toolbox = PencilToolbox(defaults: defaults)
        toolbox.usePreset(at: 1)
        toolbox.switchToEraser()
        XCTAssertEqual(toolbox.toolInUse, .eraser)
        toolbox.switchToEraser()
        XCTAssertEqual(toolbox.toolInUse, .ink)
        XCTAssertEqual(toolbox.presetInUseIndex, 1)
        toolbox.use(.lasso)
        toolbox.switchToEraser()
        toolbox.switchToEraser()
        XCTAssertEqual(toolbox.toolInUse, .lasso)

        // After a relaunch while erasing there is no tool before the eraser: the switch
        // gives way to the ink last in use.
        toolbox.use(.eraser)
        let restartedWhileErasing = PencilToolbox(defaults: defaults)
        XCTAssertEqual(restartedWhileErasing.toolInUse, .eraser, "The tool in use is kept between launches.")
        XCTAssertNil(restartedWhileErasing.previousTool)
        restartedWhileErasing.switchToEraser()
        XCTAssertEqual(restartedWhileErasing.toolInUse, .ink)
        XCTAssertEqual(restartedWhileErasing.presetInUseIndex, 1)
    }

    func testThePreviousToolWhosePresetWasRemovedTakesThePresetInUse() {
        let toolbox = PencilToolbox(defaults: defaults)
        toolbox.usePreset(at: 2)
        toolbox.use(.eraser)
        toolbox.usePreset(at: 2)
        toolbox.removePresetInUse()
        XCTAssertEqual(toolbox.presets.count, 2)
        toolbox.switchToPreviousTool()
        XCTAssertEqual(toolbox.toolInUse, .eraser)
        toolbox.switchToPreviousTool()
        XCTAssertEqual(toolbox.toolInUse, .ink)
        XCTAssertTrue(toolbox.presets.indices.contains(toolbox.presetInUseIndex))
    }

    func testAPencilGestureIsAnsweredOnceHoweverManyBarsHearIt() {
        let toolbox = PencilToolbox(defaults: defaults)
        XCTAssertTrue(toolbox.acceptsPencilGesture(at: 120.5))
        XCTAssertFalse(toolbox.acceptsPencilGesture(at: 120.5), "The same double tap, heard by another bar.")
        XCTAssertTrue(toolbox.acceptsPencilGesture(at: 121.25))
    }

    // MARK: Moving through the history

    func testStepsThroughTheHistoryGoAsFarAsItGoes() {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        var text = ""
        func type(_ letter: String) {
            let before = text
            undoManager.beginUndoGrouping()
            text += letter
            registerUndo(to: before)
            undoManager.endUndoGrouping()
        }
        func registerUndo(to earlierText: String) {
            let laterText = text
            undoManager.registerUndo(withTarget: undoManager) { _ in
                text = earlierText
                registerUndo(to: laterText)
            }
        }
        for letter in ["a", "b", "c", "d"] { type(letter) }
        let availability = UndoAvailability(following: undoManager)
        XCTAssertEqual(availability.step(by: -3), -3)
        XCTAssertEqual(text, "a")
        XCTAssertTrue(availability.canRedo)
        XCTAssertEqual(availability.step(by: -5), -1, "Only one change was left to undo.")
        XCTAssertEqual(text, "")
        XCTAssertFalse(availability.canUndo)
        XCTAssertEqual(availability.step(by: 2), 2)
        XCTAssertEqual(text, "ab")
        XCTAssertEqual(availability.step(by: 9), 2)
        XCTAssertEqual(text, "abcd")
        XCTAssertEqual(availability.step(by: 0), 0)
    }

    func testTheScrubberTakesOneStepPerStepWidthOfTheDrag() {
        let stepWidth = UndoHistoryScrubber.stepWidth
        XCTAssertEqual(UndoHistoryScrubber.requestedSteps(forDragOf: 0, from: 0), 0)
        XCTAssertEqual(UndoHistoryScrubber.requestedSteps(forDragOf: -stepWidth * 0.4, from: 0), 0, "Less than half a step moves nothing.")
        XCTAssertEqual(UndoHistoryScrubber.requestedSteps(forDragOf: -stepWidth * 3, from: 0), -3)
        XCTAssertEqual(UndoHistoryScrubber.requestedSteps(forDragOf: stepWidth * 2, from: -3), -1, "A second drag starts where the first ended.")
        XCTAssertEqual(UndoHistoryScrubber.requestedSteps(forDragOf: .nan, from: -2), -2)
    }

    // MARK: Where Read/Write, Undo and Redo go

    func testDocumentControlsGoToTheTabBarWhereItHasRoom() {
        let minimumWidth = DocumentToolbarLayout.minimumTabBarWidthForControls
        XCTAssertTrue(DocumentToolbarLayout.showsControlsInTabBar(usesControlRow: true, showsTabBar: true, tabBarWidth: 1_032), "iPad portrait")
        XCTAssertTrue(DocumentToolbarLayout.showsControlsInTabBar(usesControlRow: true, showsTabBar: true, tabBarWidth: 510), "Half of iPad portrait")
        XCTAssertTrue(DocumentToolbarLayout.showsControlsInTabBar(usesControlRow: true, showsTabBar: true, tabBarWidth: minimumWidth))
        XCTAssertFalse(DocumentToolbarLayout.showsControlsInTabBar(usesControlRow: true, showsTabBar: true, tabBarWidth: minimumWidth - 1))
        XCTAssertFalse(DocumentToolbarLayout.showsControlsInTabBar(usesControlRow: true, showsTabBar: true, tabBarWidth: 402), "iPhone keeps the row")
        XCTAssertFalse(DocumentToolbarLayout.showsControlsInTabBar(usesControlRow: true, showsTabBar: false, tabBarWidth: 1_032), "Focus hides the tab bar")
        XCTAssertFalse(DocumentToolbarLayout.showsControlsInTabBar(usesControlRow: false, showsTabBar: true, tabBarWidth: 1_376), "The toolbar has room")
        XCTAssertFalse(DocumentToolbarLayout.showsControlsInTabBar(usesControlRow: true, showsTabBar: true, tabBarWidth: nil), "Not measured yet")
    }

    func testTheToolsGoInTheTabBarWhereTheyGetAtLeastTheirNarrowestRow() {
        func showsTools(width: CGFloat?, controls: Bool, tabBar: Bool = true) -> Bool {
            DocumentToolbarLayout.showsPencilToolsInTabBar(showsTabBar: tabBar, tabBarWidth: width, showsDocumentControls: controls)
        }
        XCTAssertTrue(showsTools(width: 1_032, controls: true), "iPad portrait")
        XCTAssertTrue(showsTools(width: 834, controls: true), "11-inch iPad portrait")
        XCTAssertTrue(showsTools(width: 1_056, controls: true), "iPad landscape beside the sidebar")
        XCTAssertTrue(showsTools(width: 688, controls: false), "Half of iPad landscape, the controls in the toolbar")
        XCTAssertFalse(showsTools(width: 712, controls: true), "iPad portrait beside the sidebar")
        XCTAssertFalse(showsTools(width: 516, controls: true), "Half of iPad portrait")
        XCTAssertFalse(showsTools(width: 1_376, controls: false, tabBar: false), "Focus hides the tab bar")
        XCTAssertFalse(showsTools(width: nil, controls: false), "Not measured yet")
        let narrowest = DocumentToolbarLayout.minimumPencilToolsWidthInTabBar + DocumentToolbarLayout.minimumTabsWidthBesidePencilTools
            + DocumentToolbarLayout.tabBarButtonsWidth
        XCTAssertTrue(showsTools(width: narrowest, controls: false))
        XCTAssertFalse(showsTools(width: narrowest - 1, controls: false))
    }
}
