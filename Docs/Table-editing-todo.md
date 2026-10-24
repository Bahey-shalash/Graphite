# Add rows and columns from the table's edges and menu: implementation TODO

Created: 2026-10-24.

Status: not started. Issue: [#107](https://github.com/Graphite-Note/Graphite/issues/107) (section 1), [#108](https://github.com/Graphite-Note/Graphite/issues/108) (section 2).

## Request

The owner, 2026-10-24, with four screenshots of a Live Preview table ("Capacitances by region" in "3_SmallSignalAnalysis_II"): "add goodnotes style add row add column etc". The screenshots show Obsidian's table editor:

- Pointing at the table shows a thin strip with a "+" along its right edge, tooltip "Add column to the right", and another along its bottom edge, tooltip "Add row below". A click adds the column or row at once.
- Right-clicking a cell opens a menu of four items: Row ›, Column ›, Sort by column (A to Z), Sort by column (Z to A).
- Row › holds Add row above, Add row below, Move row down (and up where it applies), Duplicate row, Delete row.
- Column › holds Add column to the left, Add column to the right, Move column left, Move column right, Align left, Align center, Align right, Duplicate column, Delete column.

## What exists today (2026-10-24)

- A Live Preview table is edited in place (`LivePreviewTableEditor` in `Sources/GraphiteUI/LivePreviewTableEditing.swift`): a tap opens a cell editor, Tab and Return move between cells, Return or Tab past the last row appends one.
- The rendered block's menu (`menuItems(at:)`, offered through `LivePreviewWidgets.swift`) already has Row › Add Row Above, Add Row Below, Move Row Up, Move Row Down, Delete Row and Column › Add Column Before, Add Column After, Move Column Left, Move Column Right, Align › (Left, Center, Right, None), Delete Column.
- Each command is a source edit in `MarkdownTableEditing` (`Sources/GraphiteCore/MarkdownTable.swift`) that rewrites only the characters it changes, covered by `Tests/GraphiteCoreTests/MarkdownTableTests.swift`; `Tests/GraphiteUITests/UiEditorMacTableEditingTests.swift` covers cell editing on the Mac.
- Missing: the "+" strips on the table's edges, Duplicate row and Duplicate column, Sort by column, and the screenshots' menu wording and layout (alignment flat in the Column menu).

## 1. "+" strips to add a column to the right and a row below

Issue: [#107](https://github.com/Graphite-Note/Graphite/issues/107)

- [ ] On the Mac, pointing at a Live Preview table shows a thin strip along its right edge and one along its bottom edge, each with a "+" in its middle, tooltips "Add column to the right" and "Add row below", as in the owner's screenshots. They show only while the pointer is over the table or the strip, take no space in the note's layout (drawn in the margin beside and below the table), and never cover the caption or the next block.
- [ ] A click adds an empty last column or an empty last row in one undoable edit (`MarkdownTableEditing.insertingColumn`, `insertingRow`), keeps the table's padding style, and opens the cell editor in the new column's header or the new row's first cell.
- [ ] On the iPad and the iPhone, where nothing hovers, the strips show while a cell of that table is being edited, with touch targets of at least 44 points; Apple Pencil hover shows them as the pointer does.
- [ ] Reading view shows no strips; a table inside a callout or a list item gets them the same way.
- [ ] The strips cost nothing while the pointer is elsewhere: no view or tracking area per table beyond the existing overlay, no layout pass when they appear (a check in the hosted tests that scrolling a note of 50 tables keeps its timing budget).
- [ ] Tests: hosted tests on the Mac that a click on each strip adds the column or the row to the note's source and opens the editor in it; an iPad hosted test that the strips appear while a cell is edited.
- [ ] Checked on the Mac and the iPad with the owner's "3_SmallSignalAnalysis_II" table.

## 2. The cell menu as in Obsidian: duplicate, sort, wording

Issue: [#108](https://github.com/Graphite-Note/Graphite/issues/108)

- [ ] The cell's menu (right-click on the Mac, long press on the iPad and the iPhone) has Row ›, Column ›, Sort by column (A to Z) and Sort by column (Z to A), in the owner's screenshots' order, with sentence-case titles: "Add row above", "Add row below", "Move row up", "Move row down", "Duplicate row", "Delete row"; "Add column to the left", "Add column to the right", "Move column left", "Move column right", "Align left", "Align center", "Align right", "Duplicate column", "Delete column". Commands that cannot apply (moving the first row up, deleting the header row) are hidden or disabled as today.
- [ ] Alignment sits flat in the Column menu as in the screenshots; choosing the column's current alignment again clears it (the delimiter goes back to `---`), which replaces today's Align › None.
- [ ] Duplicate row inserts a copy of the row below it; Duplicate column inserts a copy of the column (its header, alignment and cells) to its right. Both are new `MarkdownTableEditing` source edits, one undoable edit each, rewriting only the lines they change.
- [ ] Sort by column orders the body rows by that column's cell text, ascending or descending, with the header row kept first: a natural, locale-aware comparison (so "row 2" comes before "row 10", case and accents ignored), stable for equal cells, empty cells last in both orders. One undoable edit; the rows keep their own padding and line endings.
- [ ] Sorting compares the cells' visible text, not their Markdown: `$C_{GD}$`, `**bold**` and `[[link|alias]]` sort by what the reader sees, as far as `MarkdownTableEditing.editableText(ofCellSource:)` gives it.
- [ ] The commands are also in the command palette and the Edit menu while a cell is being edited, so they work from the keyboard on the Mac and the iPad (no new default shortcuts; assignable in the shortcuts settings).
- [ ] Tests: Core tests of duplicating a row and a column (with and without outer pipes, ragged rows, Windows line endings) and of sorting (natural order, accents, empty cells, ties kept in order, header untouched); a hosted test that the Mac context menu offers the screenshots' items and that Sort by column (A to Z) reorders the note's rows.
- [ ] Checked on the Mac and the iPad with the owner's "3_SmallSignalAnalysis_II" table.
