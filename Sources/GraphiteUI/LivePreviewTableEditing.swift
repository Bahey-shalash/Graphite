import SwiftUI
import GraphiteCore
import Textual

/// What a rendered block's view uses to change the block's own source in the note.
struct RenderedBlockSourceEditing {
    /// Replaces the block's source with what `transform` makes of it, as one edit that can be
    /// undone; a nil result leaves the note alone. `transform` is given the block's source as
    /// the note has it now, line endings included. `editor` is the one editing the block,
    /// whose block is found at its place rather than by a key an earlier edit replaced.
    let replaceSource: (_ editor: ObjectIdentifier, _ transform: @escaping (String) -> String?) -> Void
    /// While true, the block keeps its view across the new keys its edits give it.
    let setIsEditingInView: (_ isEditing: Bool, _ editor: ObjectIdentifier) -> Void
}

/// A cell of a rendered table: row 0 is the header, then the body rows.
struct TableCellPosition: Hashable {
    let row: Int
    let column: Int
}

extension EnvironmentValues {
    /// Set on a Live Preview table, whose cells are then edited in place; nil in reading view.
    @Entry var livePreviewTableEditor: LivePreviewTableEditor? = nil
}

/// Edits a Live Preview table's cells in place, as Obsidian does: a tap on a cell opens an
/// editor over it holding the cell's Markdown, Tab and Shift-Tab go to the next and previous
/// cell, Return to the cell below, and the block's menu adds, moves and removes rows and
/// columns. Each change is written into the note as one edit of that cell's characters only
/// (`MarkdownTableEditing`): when typing pauses, and when the editor moves or closes.
///
/// One per table view, kept by the view; what it reads from the view (the table's source and
/// the way to edit it) is given again at every update, without making the view draw again.
@MainActor
@Observable
final class LivePreviewTableEditor {
    /// The coordinate space of a rendered block's whole view, which its menu's points are in.
    nonisolated static let blockCoordinateSpaceName = "LivePreviewRenderedBlock"
    /// How long typing pauses before the cell is written into the note.
    private static let commitDelay: Duration = .milliseconds(400)

    private(set) var editingCell: TableCellPosition?
    /// Asks the cell editor to take the keyboard: it changes when editing begins.
    private(set) var focusRequest = 0
    /// The edited cell's text, as `MarkdownTableEditing.editableText(ofCellSource:)` shows it.
    var draftText = "" {
        didSet { if draftText != oldValue { draftDidChange(from: oldValue) } }
    }

    @ObservationIgnored private(set) var textSize: Double = 16
    @ObservationIgnored private var tableSource: String?
    @ObservationIgnored private var table: MarkdownTable?
    @ObservationIgnored private var sourceEditing: RenderedBlockSourceEditing?
    /// The draft as last written into the note, or as the cell had it.
    @ObservationIgnored private var committedDraft = ""
    @ObservationIgnored private var commitTask: Task<Void, Never>?
    /// The table's cells as last laid out, and where the table is in the block's view.
    @ObservationIgnored var layout: StructuredText.TableLayout?
    @ObservationIgnored var tableOriginInBlock: CGPoint = .zero
    /// Where the edited cell was last drawn, for a cell the table has not laid out yet (a
    /// row just added), so the editor and its keyboard stay.
    @ObservationIgnored var lastEditingFrame: CGRect?

    var canEdit: Bool { sourceEditing != nil && table != nil }

    /// Takes the view's current table source, text size and way to edit; called as the view
    /// updates, so it changes nothing the view draws.
    func update(source: String, textSize: Double, sourceEditing: RenderedBlockSourceEditing?) {
        if source != tableSource {
            tableSource = source
            table = MarkdownTable.parse(source)
        }
        self.textSize = textSize
        self.sourceEditing = sourceEditing
    }

    // MARK: Editing a cell

    func beginEditing(at point: CGPoint) {
        guard let layout, let cell = Self.cell(at: point, in: layout) else { return }
        beginEditing(cell)
    }

    func beginEditing(_ cell: TableCellPosition) {
        guard let table, cell.row < table.rows.count, cell.column < table.columnCount else { return }
        let cellSource = cell.column < table.rows[cell.row].count ? table.rows[cell.row][cell.column].source : ""
        startEditing(cell, text: MarkdownTableEditing.editableText(ofCellSource: cellSource))
    }

    private func startEditing(_ cell: TableCellPosition, text: String) {
        commitDraft()
        if editingCell == nil {
            TableCellTextField.endEditingInOtherTables()
            sourceEditing?.setIsEditingInView(true, ObjectIdentifier(self))
        }
        committedDraft = text
        editingCell = cell
        draftText = text
        focusRequest += 1
    }

    /// The cell editor lost the keyboard, as after a tap in the note's text: the editor closes.
    /// Moving between cells keeps the same text view, which keeps the keyboard.
    func focusDidLeave() {
        endEditing()
    }

    /// Writes the draft into the note and closes the editor.
    func endEditing() {
        guard editingCell != nil else { return }
        commitDraft()
        editingCell = nil
        lastEditingFrame = nil
        sourceEditing?.setIsEditingInView(false, ObjectIdentifier(self))
    }

    private func replaceSource(_ transform: @escaping (String) -> String?) {
        sourceEditing?.replaceSource(ObjectIdentifier(self), transform)
    }

    func commitDraft() {
        commitTask?.cancel()
        commitTask = nil
        guard let cell = editingCell, draftText != committedDraft else { return }
        let text = draftText
        committedDraft = text
        replaceSource { source in
            MarkdownTableEditing.replacingCell(row: cell.row, column: cell.column, with: text, in: source)
        }
    }

    /// Typing is written into the note once it pauses.
    private func draftDidChange(from oldText: String) {
        guard editingCell != nil, draftText != committedDraft else { return }
        commitTask?.cancel()
        commitTask = Task { [weak self] in
            try? await Task.sleep(for: Self.commitDelay)
            guard !Task.isCancelled else { return }
            self?.commitDraft()
        }
    }

    enum Movement {
        case next, previous, up, down
    }

    /// The keys of the cell editor, as in Obsidian: Return goes to the cell below, Tab and
    /// Shift-Tab to the next and previous cell, Escape closes the editor, and the arrows leave
    /// a cell of one line. Whether the key was taken; one that was not is typed as usual.
    func handle(_ key: TableCellKey) -> Bool {
        guard editingCell != nil else { return false }
        switch key {
        case .returnKey: move(.down)
        case .tab: move(.next)
        case .backtab: move(.previous)
        case .escape: endEditing()
        case .upArrow, .downArrow:
            guard !draftText.contains(where: \.isNewline) else { return false }
            move(key == .upArrow ? .up : .down)
        }
        return true
    }

    /// Moves the editor; past the last cell (Tab) or the last row (Return) it adds a row, as
    /// Obsidian does.
    func move(_ movement: Movement) {
        guard let cell = editingCell, let table else { return }
        let lastRow = table.rows.count - 1
        let lastColumn = table.columnCount - 1
        switch movement {
        case .next:
            if cell.column < lastColumn { beginEditing(TableCellPosition(row: cell.row, column: cell.column + 1)) }
            else if cell.row < lastRow { beginEditing(TableCellPosition(row: cell.row + 1, column: 0)) }
            else { appendRow(editingColumn: 0) }
        case .previous:
            if cell.column > 0 { beginEditing(TableCellPosition(row: cell.row, column: cell.column - 1)) }
            else if cell.row > 0 { beginEditing(TableCellPosition(row: cell.row - 1, column: lastColumn)) }
        case .up:
            if cell.row > 0 { beginEditing(TableCellPosition(row: cell.row - 1, column: cell.column)) }
        case .down:
            if cell.row < lastRow { beginEditing(TableCellPosition(row: cell.row + 1, column: cell.column)) }
            else { appendRow(editingColumn: cell.column) }
        }
    }

    private func appendRow(editingColumn column: Int) {
        guard let table else { return }
        commitDraft()
        let newRow = table.rows.count
        replaceSource { source in
            guard let bodyRowCount = MarkdownTable.parse(source)?.bodyRowCount else { return nil }
            return MarkdownTableEditing.insertingRow(atBodyIndex: bodyRowCount, in: source)
        }
        startEditing(TableCellPosition(row: newRow, column: column), text: "")
    }

    // MARK: Rows and columns

    /// The block menu's commands for the cell at `point`, in the block view's coordinates;
    /// for the edited cell when the point is not on one.
    func menuItems(at point: CGPoint) -> [RenderedBlockMenuItem] {
        guard let table, sourceEditing != nil else { return [] }
        let pointInTable = CGPoint(x: point.x - tableOriginInBlock.x, y: point.y - tableOriginInBlock.y)
        let tableBounds = layout?.bounds ?? .null
        let pointedCell = tableBounds.insetBy(dx: -4, dy: -4).contains(pointInTable) ? layout.flatMap { layout in Self.cell(at: pointInTable, in: layout) } : nil
        guard let cell = pointedCell ?? editingCell else { return [] }
        let isHeader = cell.row == 0
        let bodyRowIndex = cell.row - 1
        let column = cell.column
        let rowItems = [
            RenderedBlockMenuItem(title: "Add Row Above", symbolName: "arrow.up.to.line", isEnabled: !isHeader,
                                  action: { [weak self] in self?.changeTable { source in MarkdownTableEditing.insertingRow(atBodyIndex: bodyRowIndex, in: source) } }),
            RenderedBlockMenuItem(title: "Add Row Below", symbolName: "arrow.down.to.line",
                                  action: { [weak self] in self?.changeTable { source in MarkdownTableEditing.insertingRow(atBodyIndex: bodyRowIndex + 1, in: source) } }),
            RenderedBlockMenuItem(title: "Move Row Up", symbolName: "arrow.up", isEnabled: bodyRowIndex > 0,
                                  action: { [weak self] in self?.changeTable { source in MarkdownTableEditing.movingRow(atBodyIndex: bodyRowIndex, by: -1, in: source) } }),
            RenderedBlockMenuItem(title: "Move Row Down", symbolName: "arrow.down", isEnabled: !isHeader && bodyRowIndex < table.bodyRowCount - 1,
                                  action: { [weak self] in self?.changeTable { source in MarkdownTableEditing.movingRow(atBodyIndex: bodyRowIndex, by: 1, in: source) } }),
            RenderedBlockMenuItem(title: "Delete Row", symbolName: "trash", isEnabled: !isHeader,
                                  action: { [weak self] in self?.changeTable { source in MarkdownTableEditing.removingRow(atBodyIndex: bodyRowIndex, in: source) } }),
        ]
        let alignmentItems: [RenderedBlockMenuItem] = [
            ("Left", "text.alignleft", MarkdownTable.ColumnAlignment.left), ("Center", "text.aligncenter", .center),
            ("Right", "text.alignright", .right), ("None", "text.justify.leading", MarkdownTable.ColumnAlignment.none),
        ].map { title, symbolName, alignment in
            RenderedBlockMenuItem(title: title, symbolName: symbolName, isEnabled: column < table.alignments.count && table.alignments[column] != alignment,
                                  action: { [weak self] in self?.changeTable { source in MarkdownTableEditing.settingAlignment(alignment, ofColumn: column, in: source) } })
        }
        let columnItems = [
            RenderedBlockMenuItem(title: "Add Column Before", symbolName: "arrow.left.to.line",
                                  action: { [weak self] in self?.changeTable { source in MarkdownTableEditing.insertingColumn(at: column, in: source) } }),
            RenderedBlockMenuItem(title: "Add Column After", symbolName: "arrow.right.to.line",
                                  action: { [weak self] in self?.changeTable { source in MarkdownTableEditing.insertingColumn(at: column + 1, in: source) } }),
            RenderedBlockMenuItem(title: "Move Column Left", symbolName: "arrow.left", isEnabled: column > 0,
                                  action: { [weak self] in self?.changeTable { source in MarkdownTableEditing.movingColumn(at: column, by: -1, in: source) } }),
            RenderedBlockMenuItem(title: "Move Column Right", symbolName: "arrow.right", isEnabled: column < table.columnCount - 1,
                                  action: { [weak self] in self?.changeTable { source in MarkdownTableEditing.movingColumn(at: column, by: 1, in: source) } }),
            RenderedBlockMenuItem(title: "Align", symbolName: "text.alignleft", children: alignmentItems),
            RenderedBlockMenuItem(title: "Delete Column", symbolName: "trash", isEnabled: table.columnCount > 1,
                                  action: { [weak self] in self?.changeTable { source in MarkdownTableEditing.removingColumn(at: column, in: source) } }),
        ]
        return [
            RenderedBlockMenuItem(title: "Row", symbolName: "tablecells", children: rowItems),
            RenderedBlockMenuItem(title: "Column", symbolName: "tablecells", children: columnItems),
        ]
    }

    /// A change of rows or columns closes the cell editor first, writing its draft: the cells
    /// move under it.
    private func changeTable(_ transform: @escaping (String) -> String?) {
        endEditing()
        replaceSource(transform)
    }

    // MARK: Geometry

    /// The cell whose row and column contain `point`, in the table's coordinates; a point in
    /// the gap between cells goes to the nearer one, and one past an edge to the edge cell.
    static func cell(at point: CGPoint, in layout: StructuredText.TableLayout) -> TableCellPosition? {
        guard layout.numberOfRows > 0, layout.numberOfColumns > 0 else { return nil }
        let row = layout.rowIndices.last { row in
            row == 0 || point.y >= (layout.rowBounds(row - 1).maxY + layout.rowBounds(row).minY) / 2
        } ?? 0
        let column = layout.columnIndices.last { column in
            column == 0 || point.x >= (layout.columnBounds(column - 1).maxX + layout.columnBounds(column).minX) / 2
        } ?? 0
        return TableCellPosition(row: row, column: column)
    }

    /// Where the edited cell is drawn, or, for a row not laid out yet, below the last row.
    func frame(of cell: TableCellPosition, in layout: StructuredText.TableLayout) -> CGRect? {
        if cell.row < layout.numberOfRows, cell.column < layout.numberOfColumns {
            return layout.cellBounds(row: cell.row, column: cell.column)
        }
        guard let lastEditingFrame else { return nil }
        guard cell.row >= layout.numberOfRows, layout.numberOfRows > 0, cell.column < layout.numberOfColumns else { return lastEditingFrame }
        let columnBounds = layout.cellBounds(row: layout.numberOfRows - 1, column: cell.column)
        return CGRect(x: columnBounds.minX, y: columnBounds.maxY, width: columnBounds.width, height: columnBounds.height)
    }
}

/// Puts the cell editing layer over a table while a `LivePreviewTableEditor` is in the
/// environment; reading view's tables get nothing.
struct LivePreviewTableEditingOverlay: ViewModifier {
    @Environment(\.livePreviewTableEditor) private var editor

    func body(content: Content) -> some View {
        if let editor, editor.canEdit {
            content.textual.interactiveTableOverlay { layout in
                LivePreviewTableEditingLayer(layout: layout, editor: editor)
            }
        } else {
            content
        }
    }
}

/// A tap target over the whole table, and the edited cell's text field over that cell.
private struct LivePreviewTableEditingLayer: View {
    let layout: StructuredText.TableLayout
    @Bindable var editor: LivePreviewTableEditor
    @Environment(\.noteTypography) private var typography
    @Environment(\.noteTheme) private var theme
    @Environment(\.accent) private var accent

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { location in editor.beginEditing(at: location) }
            if let cell = editor.editingCell, let frame = editor.frame(of: cell, in: layout) {
                cellField(for: cell, frame: frame)
            }
        }
        .onGeometryChange(for: CGPoint.self) { geometry in
            geometry.frame(in: .named(LivePreviewTableEditor.blockCoordinateSpaceName)).origin
        } action: { origin in
            editor.tableOriginInBlock = origin
        }
        .onChange(of: layout, initial: true) { _, newLayout in editor.layout = newLayout }
        // Text selection's overlay would otherwise take the taps.
        .textual.excludedFromTextInteraction()
    }

    private func cellField(for cell: TableCellPosition, frame: CGRect) -> some View {
        let textSize = editor.textSize
        return TableCellTextField(text: $editor.draftText,
                                  font: typography.textFont(ofSize: textSize, weight: cell.row == 0 ? .semibold : .regular),
                                  focusRequest: editor.focusRequest, handleKey: editor.handle,
                                  focusDidChange: { isFocused in
                                      // Focus going elsewhere, such as a tap in the note's text, closes the editor.
                                      if !isFocused { editor.focusDidLeave() }
                                  })
            .padding(.vertical, textSize * 0.35)
            .padding(.horizontal, textSize * 0.6)
            // Centered in the row's height, as the rendered cells are.
            .frame(width: frame.width, alignment: .leading)
            .frame(minHeight: frame.height, alignment: .leading)
            .background(theme?.background.map { color in AnyShapeStyle(Color(color)) } ?? AnyShapeStyle(.background))
            .overlay(Rectangle().stroke(accent, lineWidth: 2))
            .offset(x: frame.minX, y: frame.minY)
            .onAppear { editor.lastEditingFrame = frame }
            .onChange(of: frame) { _, newFrame in editor.lastEditingFrame = newFrame }
    }
}
