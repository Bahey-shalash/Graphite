import XCTest
import GraphiteCore
@testable import GraphiteUI

@MainActor
final class UiSheetsEditorLogicTests: XCTestCase {
    // MARK: Properties panel

    /// The reading view parses the note again only after a delay. A second quick edit
    /// used to start from the old list and undo the first.
    func testASecondQuickPanelEditBuildsOnTheFirst() {
        let parsedProperties = [NoteProperty(key: "done", value: .checkbox(false)), NoteProperty(key: "tags", value: .list(["a", "b", "c"]))]
        var editing = PropertyListEditing()
        _ = editing.replacing("tags", with: .list(["b", "c"]), parsedProperties: parsedProperties)
        let secondCommit = editing.replacing("done", with: .checkbox(true), parsedProperties: parsedProperties)
        XCTAssertEqual(secondCommit, [NoteProperty(key: "done", value: .checkbox(true)), NoteProperty(key: "tags", value: .list(["b", "c"]))])

        // Once the note is parsed again, its properties are the ones edits build on, so an
        // edit made in another app is not overwritten.
        editing.parsedPropertiesChanged()
        let reparsedProperties = [NoteProperty(key: "done", value: .checkbox(true)), NoteProperty(key: "tags", value: .list(["x"]))]
        XCTAssertEqual(editing.properties(parsedProperties: reparsedProperties), reparsedProperties)
        XCTAssertNil(editing.adding(" done ", parsedProperties: reparsedProperties))
    }

    func testChangeTypeNeverInventsOrMergesValues() {
        let date = PropertyDateText.parse("2026-01-05")?.date
        XCTAssertNotNil(date)
        XCTAssertEqual(PropertyValueKind.converted(.list(["a", "b, c", "d"]), to: .list), .list(["a", "b, c", "d"]))
        XCTAssertEqual(PropertyValueKind.converted(.date("2026-01-05"), to: .dateTime), .dateTime("2026-01-05T00:00"))
        XCTAssertEqual(PropertyValueKind.converted(.dateTime("2026-01-05T14:30"), to: .date), .date("2026-01-05"))
        XCTAssertEqual(PropertyValueKind.converted(.text("2026-01-05"), to: .date), .date("2026-01-05"))
        XCTAssertNil(PropertyValueKind.converted(.text("abc"), to: .number))
        XCTAssertNil(PropertyValueKind.converted(.text("abc"), to: .date))
        XCTAssertNil(PropertyValueKind.converted(.text("maybe"), to: .checkbox))
        XCTAssertNil(PropertyValueKind.converted(.list(["1", "2"]), to: .number))
        XCTAssertNil(PropertyValueKind.converted(.unsupported("a: 1"), to: .text))
        XCTAssertEqual(PropertyValueKind.converted(.text("1,5"), to: .number), .number(1.5))
        XCTAssertEqual(PropertyValueKind.converted(.list(["True"]), to: .checkbox), .checkbox(true))
        XCTAssertEqual(PropertyValueKind.converted(.empty, to: .number), .number(0))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(PropertyValueKind.converted(.empty, to: .date, now: now), .date(PropertyDateText.text(for: now, pattern: PropertyDateText.datePattern)))
    }

    func testTypedNumbersAreReadAsWrittenOrRefused() {
        let english = Locale(identifier: "en_US")
        let german = Locale(identifier: "de_DE")
        XCTAssertEqual(PropertyNumberText.number(from: "1,5", locale: german), 1.5)
        XCTAssertEqual(PropertyNumberText.number(from: "1,000", locale: english), 1_000)
        XCTAssertEqual(PropertyNumberText.number(from: "1,000", locale: german), 1)
        XCTAssertEqual(PropertyNumberText.number(from: "1,234,567.5", locale: english), 1_234_567.5)
        XCTAssertEqual(PropertyNumberText.number(from: "1.234,5", locale: german), 1_234.5)
        // A shown number keeps its meaning when edited, in every language.
        XCTAssertEqual(PropertyNumberText.number(from: "2.125", locale: german), 2.125)
        XCTAssertEqual(PropertyNumberText.number(from: " -3 ", locale: english), -3)
        XCTAssertEqual(PropertyNumberText.number(from: "1e3", locale: english), 1_000)
        for refusedText in ["", "nan", "inf", "-infinity", "0x10", "1,2,3.4.5", "1.234,5,6", "abc", "1e999"] {
            XCTAssertNil(PropertyNumberText.number(from: refusedText, locale: english), refusedText)
        }
    }

    func testDatesKeepTheirWrittenFormAndTime() throws {
        let spaced = try XCTUnwrap(PropertyDateText.parse("2026-09-23 14:30"))
        XCTAssertEqual(PropertyDateText.text(for: spaced.date, pattern: spaced.pattern), "2026-09-23 14:30")
        let withSeconds = try XCTUnwrap(PropertyDateText.parse("2026-09-23T14:30:45"))
        XCTAssertEqual(PropertyDateText.text(for: withSeconds.date, pattern: withSeconds.pattern), "2026-09-23T14:30:45")
        let withFraction = try XCTUnwrap(PropertyDateText.parse("2026-09-23T14:30:00.250"))
        XCTAssertEqual(PropertyDateText.text(for: withFraction.date, pattern: withFraction.pattern), "2026-09-23T14:30:00.250")
        XCTAssertNil(PropertyDateText.parse("2026-02-30"))
        XCTAssertNil(PropertyDateText.parse("next week"))

        // Moving the day in a date-only picker keeps the time; a picker that shows the
        // time keeps the seconds while the minute is unchanged.
        let nextDay = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: spaced.date))
        let movedDay = PropertyDateText.combining(pickedDate: nextDay, original: spaced.date, pickerShowsTime: false)
        XCTAssertEqual(PropertyDateText.text(for: movedDay, pattern: spaced.pattern), "2026-09-24 14:30")
        let pickedWithoutSeconds = try XCTUnwrap(PropertyDateText.parse("2026-09-24T14:30")).date
        let keptSeconds = PropertyDateText.combining(pickedDate: pickedWithoutSeconds, original: withSeconds.date, pickerShowsTime: true)
        XCTAssertEqual(PropertyDateText.text(for: keptSeconds, pattern: withSeconds.pattern), "2026-09-24T14:30:45")
    }

    // MARK: Base property sheet

    func testExternalLinksEmbedsAndMarkdownLinksSurviveTheCellEditor() throws {
        let note = """
        ---
        site: "[Official site](https://example.com/page)"
        cover: "![[cover.png]]"
        related: "[Dune](Books/Dune.md)"
        links:
          - "[Home](https://example.org)"
          - "![[diagram.png]]"
          - "[[Other]]"
        ---
        Body
        """
        let entries = try XCTUnwrap(BaseFrontmatter.entries(fromYAML: try XCTUnwrap(try MarkdownSemantics.parse(note).frontmatter)))
        func draft(_ key: String, kind: BasePropertyEditorKind, withWrittenNode: Bool) throws -> BasePropertyDraft {
            let node = try XCTUnwrap(entries.first { entry in entry.key == key }?.node)
            let value = BaseFrontmatter.value(of: node, declaredType: nil, source: nil, calendar: BaseDateFormatting.displayCalendar)
            return BasePropertyDraft(kind: kind, currentValue: value, writtenNode: withWrittenNode ? node : nil)
        }

        // Without the written text, an external link keeps its address.
        XCTAssertEqual(try draft("site", kind: .text, withWrittenNode: false).text, "[Official site](https://example.com/page)")
        XCTAssertEqual(try draft("links", kind: .list, withWrittenNode: false).text, "[Home](https://example.org)\n[[diagram.png]]\n[[Other]]")
        // With it, every value is shown exactly as written.
        XCTAssertEqual(try draft("cover", kind: .text, withWrittenNode: true).text, "![[cover.png]]")
        XCTAssertEqual(try draft("related", kind: .text, withWrittenNode: true).text, "[Dune](Books/Dune.md)")
        XCTAssertEqual(try draft("links", kind: .list, withWrittenNode: true).text, "[Home](https://example.org)\n![[diagram.png]]\n[[Other]]")

        // Saving the shown list writes it back unchanged.
        let listValue = try draft("links", kind: .list, withWrittenNode: true).editedValue(kind: .list)
        let updatedNote = try BasePropertyEditing.settingProperty("links", to: listValue ?? nil, in: note, declaredTypes: [:])
        XCTAssertEqual(NoteProperties.parse(try XCTUnwrap(try MarkdownSemantics.parse(updatedNote).frontmatter))?.first { property in property.key == "links" }?.value,
                       .list(["[Home](https://example.org)", "![[diagram.png]]", "[[Other]]"]))
    }

    func testValuesTheCellEditorCannotHoldAreReadOnly() {
        let object = BaseValue.object(BaseObject(entries: [BaseObjectEntry(key: "a", value: .number(1)), BaseObjectEntry(key: "b", value: .string("two"))]))
        XCTAssertNotNil(BasePropertyDraft(kind: .text, currentValue: object).readOnlyReason)
        XCTAssertNotNil(BasePropertyDraft(kind: .list, currentValue: object).readOnlyReason)
        XCTAssertNotNil(BasePropertyDraft(kind: .text, currentValue: .list([.string("a"), .string("b")])).readOnlyReason)
        XCTAssertNotNil(BasePropertyDraft(kind: .list, currentValue: .list([.string("a"), .list([.string("b")])])).readOnlyReason)
        XCTAssertNil(BasePropertyDraft(kind: .list, currentValue: .list([.string("a"), .number(2)])).readOnlyReason)
    }

    func testAnUnreadableDateIsNotReplacedWithToday() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var draft = BasePropertyDraft(kind: .date, currentValue: .string("next week"), now: now)
        XCTAssertFalse(draft.hasDate)
        XCTAssertEqual(draft.unreadableDateText, "next week")
        XCTAssertEqual(draft.editedValue(kind: .date), .some(.empty))
        draft.hasDate = true
        XCTAssertEqual(draft.editedValue(kind: .date), .some(.date(PropertyDateText.text(for: now, pattern: PropertyDateText.datePattern))))
    }

    /// The sheet is created again whenever its parent updates, which used to give an empty
    /// or unreadable date a new "now", so an unchanged Save cleared `next week`.
    func testSaveWritesOnlyADraftTheUserChanged() {
        let loadedDraft = BasePropertyDraft(kind: .date, currentValue: .string("next week"), now: Date(timeIntervalSince1970: 1_800_000_000))
        var draft = BasePropertyDraft(kind: .date, currentValue: .string("next week"), now: Date(timeIntervalSince1970: 1_900_000_000))
        XCTAssertFalse(draft.needsSaving(comparedTo: loadedDraft))
        // Turning the date on and off again keeps the unreadable value.
        draft.hasDate = true
        draft.date = Date(timeIntervalSince1970: 2_000_000_000)
        draft.hasDate = false
        XCTAssertFalse(draft.needsSaving(comparedTo: loadedDraft))
        draft.hasDate = true
        XCTAssertTrue(draft.needsSaving(comparedTo: loadedDraft))

        let loadedText = BasePropertyDraft(kind: .text, currentValue: .string("Dune"))
        var text = loadedText
        XCTAssertFalse(text.needsSaving(comparedTo: loadedText))
        text.text = "Dune Messiah"
        XCTAssertTrue(text.needsSaving(comparedTo: loadedText))

        // Turning off a readable date clears it.
        let loadedDate = BasePropertyDraft(kind: .date, currentValue: .date(BaseDate(date: Date(timeIntervalSince1970: 1_800_000_000), hasTime: false)))
        var clearedDate = loadedDate
        clearedDate.hasDate = false
        XCTAssertTrue(clearedDate.needsSaving(comparedTo: loadedDate))
    }

    func testChangingTheDayKeepsTheWrittenTimeAndSeconds() throws {
        let written = try XCTUnwrap(PropertyDateText.parse("2026-09-23 14:30:45"))
        var draft = BasePropertyDraft(kind: .date, currentValue: .date(BaseDate(date: written.date, hasTime: true)),
                                      writtenNode: .scalar(text: "2026-09-23 14:30:45", isPlain: true))
        draft.date = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: draft.date))
        // A property declared as a date is written as one.
        XCTAssertEqual(draft.editedValue(kind: .date), .some(.date("2026-09-24")))

        var dateTimeDraft = BasePropertyDraft(kind: .dateTime, currentValue: .date(BaseDate(date: written.date, hasTime: true)),
                                              writtenNode: .scalar(text: "2026-09-23 14:30:45", isPlain: true))
        dateTimeDraft.date = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: dateTimeDraft.date))
        XCTAssertEqual(dateTimeDraft.editedValue(kind: .dateTime), .some(.dateTime("2026-09-24 14:30:45")))

        var withoutWrittenText = BasePropertyDraft(kind: .dateTime, currentValue: .date(BaseDate(date: written.date, hasTime: true)))
        withoutWrittenText.date = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: withoutWrittenText.date))
        XCTAssertEqual(withoutWrittenText.editedValue(kind: .dateTime), .some(.dateTime("2026-09-24T14:30:45")))
    }

    func testCellEditorNumbersAreReadWithGroupingAndRefuseNonNumbers() {
        var draft = BasePropertyDraft(kind: .number, currentValue: .number(3))
        XCTAssertEqual(draft.text, "3")
        draft.text = "2.5"
        XCTAssertEqual(draft.editedValue(kind: .number), .some(.number(2.5)))
        draft.text = "1,234.5"
        XCTAssertEqual(draft.editedValue(kind: .number), .some(.number(1_234.5)))
        draft.text = "nan"
        XCTAssertEqual(draft.editedValue(kind: .number), PropertyValue??.none, "Text that is not a number is refused, not saved as empty")
        draft.text = "  "
        XCTAssertEqual(draft.editedValue(kind: .number), .some(.empty))
    }

    // MARK: Base view sheet

    func testAMapViewWithANotANumberZoomOpensWithoutAZoom() {
        var view = BaseView(id: 0, type: .map, name: "Map")
        view.map.defaultZoom = .nan
        view.cards.cardSize = .infinity
        let draft = BaseViewDraft(view: view)
        XCTAssertNil(draft.defaultZoom)
        XCTAssertNil(draft.cardSize)
        XCTAssertEqual(draft, BaseViewDraft(view: view))
    }

    func testAnEditedViewDraftIsNotSavedOverAChangedFile() {
        let alpha = BaseView(id: 0, type: .table, name: "Alpha")
        var editing = BaseViewEditing(view: alpha)

        // An untouched draft follows the file.
        var sortedAlpha = alpha
        sortedAlpha.sort = [BaseSortKey(property: .note("status"), direction: .descending)]
        editing.fileLoaded(sortedAlpha)
        XCTAssertNil(editing.fileChange)
        XCTAssertEqual(editing.original.sort, sortedAlpha.sort)
        XCTAssertFalse(editing.hasChanges)

        // An edited draft is kept but cannot be saved over another app's change.
        editing.draft.limit = 20
        editing.draft.hasLimit = true
        editing.fileLoaded(sortedAlpha)
        XCTAssertNil(editing.fileChange)
        editing.fileLoaded(BaseView(id: 0, type: .cards, name: "Beta"))
        XCTAssertEqual(editing.fileChange, .viewChanged)
        XCTAssertTrue(editing.draft.hasLimit)
        editing.fileLoaded(nil)
        XCTAssertEqual(editing.fileChange, .viewRemoved)

        // The same view moved to another position in the file is a change too.
        var movedAlpha = BaseView(id: 1, type: .table, name: "Alpha")
        movedAlpha.sort = sortedAlpha.sort
        editing.fileLoaded(movedAlpha)
        XCTAssertEqual(editing.fileChange, .viewChanged)

        let beta = BaseView(id: 0, type: .cards, name: "Beta")
        editing.discardChanges(reloading: beta)
        XCTAssertNil(editing.fileChange)
        XCTAssertEqual(editing.draft, BaseViewDraft(view: beta))
        XCTAssertEqual(editing.viewPosition, 0)

        let missingView = BaseViewEditing(viewAt: 2, in: BaseDefinition(views: [alpha]))
        XCTAssertEqual(missingView.fileChange, .viewRemoved)
    }

    /// A name written with surrounding spaces used to be trimmed by any save, which broke
    /// `![[file.base#name]]` embeds that use the exact name.
    func testSavingAnotherSettingKeepsAViewNameWrittenWithSpaces() throws {
        let yaml = "views:\n  - type: table\n    name: \" Alpha \"\n  - type: table\n    name: Beta\n"
        let view = try XCTUnwrap(BaseDefinition.parse(yaml).views.first)
        XCTAssertEqual(view.name, " Alpha ")
        let original = BaseViewDraft(view: view)
        var draft = original
        draft.hasLimit = true
        draft.limit = 50
        var editor = try BaseDefinitionEditor(yaml: yaml)
        try draft.apply(to: &editor, original: original, viewPosition: view.id)
        let savedViews = try BaseDefinition.parse(editor.yaml()).views
        XCTAssertEqual(savedViews.map(\.name), [" Alpha ", "Beta"])
        XCTAssertEqual(savedViews.map(\.limit), [50, nil])

        // Editing the name itself still saves it trimmed.
        draft.name = "  Gamma "
        var renamingEditor = try BaseDefinitionEditor(yaml: yaml)
        try draft.apply(to: &renamingEditor, original: original, viewPosition: view.id)
        XCTAssertEqual(try BaseDefinition.parse(renamingEditor.yaml()).views.first?.name, "Gamma")
    }

    /// The step used to follow the value, so minus at 20 went straight to 10.
    func testTheLimitStepperReachesEveryLimitUpToTwentyFromAbove() {
        XCTAssertEqual(BaseViewDraft.decreasedLimit(20), 19)
        XCTAssertEqual(BaseViewDraft.decreasedLimit(25), 20)
        XCTAssertEqual(BaseViewDraft.decreasedLimit(30), 20)
        XCTAssertEqual(BaseViewDraft.decreasedLimit(40), 30)
        XCTAssertEqual(BaseViewDraft.decreasedLimit(1), 1)
        XCTAssertEqual(BaseViewDraft.increasedLimit(19), 20)
        XCTAssertEqual(BaseViewDraft.increasedLimit(20), 30)
        XCTAssertEqual(BaseViewDraft.increasedLimit(100_000), 100_000)
        var limit = 50
        var reachedLimits: Set<Int> = [limit]
        while limit > 1 {
            limit = BaseViewDraft.decreasedLimit(limit)
            reachedLimits.insert(limit)
        }
        XCTAssertTrue(Set(1...20).isSubset(of: reachedLimits))
    }

    /// A removed row's binding can still be called while the list updates; a position
    /// past the end used to trap.
    func testRowAccessorsIgnoreAPositionPastTheEnd() {
        var draft = BaseViewDraft(view: BaseView(id: 0, type: .table, name: "Books"))
        draft.filterExpressions = ["rating > 3", "done"]
        draft.sort = [BaseSortKey(property: .note("rating"), direction: .descending)]
        draft.filterExpressions?.remove(at: 1)
        draft.setFilterExpression("typed after removal", at: 1)
        XCTAssertEqual(draft.filterExpression(at: 1), "")
        XCTAssertEqual(draft.filterExpressions, ["rating > 3"])
        draft.setFilterExpression("rating > 4", at: 0)
        XCTAssertEqual(draft.filterExpression(at: 0), "rating > 4")

        draft.sort.remove(at: 0)
        draft.setSortDirection(.ascending, at: 0)
        XCTAssertEqual(draft.sortDirection(at: 0), .ascending)
        XCTAssertTrue(draft.sort.isEmpty)

        draft.filterExpressions = nil
        draft.setFilterExpression("ignored", at: 0)
        XCTAssertNil(draft.filterExpressions)
    }
}
