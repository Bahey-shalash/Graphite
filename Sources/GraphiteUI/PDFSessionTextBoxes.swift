import Foundation
import PDFKit
import GraphiteCore
import GraphiteApple

/// A text box of a PDF page, known by its name and the page it is on.
struct PDFTextBoxSelection: Equatable {
    let boxName: String
    let page: PDFHistoryPage

    static func == (leftSelection: PDFTextBoxSelection, rightSelection: PDFTextBoxSelection) -> Bool {
        leftSelection.boxName == rightSelection.boxName && leftSelection.page === rightSelection.page
    }
}

/// What the PDF's text boxes are doing: nothing, one selected to be moved, resized, turned or
/// formatted, or one being typed in.
enum PDFTextBoxActivity: Equatable {
    case idle
    case selected(PDFTextBoxSelection)
    case editing(PDFTextBoxSelection)

    var selection: PDFTextBoxSelection? {
        switch self {
        case .idle: nil
        case .selected(let selection), .editing(let selection): selection
        }
    }

    var isEditing: Bool {
        switch self {
        case .editing: true
        case .idle, .selected: false
        }
    }
}

/// One step of the history for a box being typed in. Typing changes the box many times; the
/// document takes the text when typing pauses for a save and when it ends (`commitTextBox`),
/// and every one of those changes is this one step, so Undo takes the box back to how it was
/// before typing began.
@MainActor
final class PDFTextBoxEditStep {
    /// The box before typing began; nil for a box made by the text tool.
    let before: PDFTextBox?
    /// The box as the document has it now; nil while a new box has not been committed, or
    /// after its text was all removed.
    fileprivate(set) var after: PDFTextBox?
    let page: PDFHistoryPage
    fileprivate var isRegistered = false

    init(before: PDFTextBox?, page: PDFHistoryPage) {
        self.before = before
        self.after = before
        self.page = page
    }
}

/// Text boxes on PDF pages. Each change is an ordinary `PDFEdit` that saving replays on the
/// file, and one step of the PDF's undo history.
extension PDFSession {
    /// A duplicate is placed this far right of and below its box, in points of the page as shown.
    static let duplicateOffsetPoints: CGFloat = 16

    /// Shows why a change of a text box or of the lasso's selection was not made, in the
    /// PDF's banner.
    func reportFailedChange(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    func textBoxes(on page: PDFPage) -> [PDFTextBox] {
        PDFPageManager.textBoxes(on: page)
    }

    /// The topmost box at a point of the page, in the page's coordinates.
    func textBox(at pagePoint: CGPoint, on page: PDFPage) -> PDFTextBox? {
        textBoxes(on: page).last { box in box.contains(pagePoint) }
    }

    func textBox(_ selection: PDFTextBoxSelection) -> PDFTextBox? {
        guard let page = selection.page.page, page.document === document else { return nil }
        return textBoxes(on: page).first { box in box.name == selection.boxName }
    }

    // MARK: Changes

    /// Puts `to` in the place of `from` on the page, as one step named `actionName`; either
    /// may be nil, for a box added or removed.
    func changeTextBox(from previous: PDFTextBox?, to next: PDFTextBox?, on page: PDFHistoryPage, actionName: String) throws {
        guard previous != next else { return }
        try transitionTextBox(from: previous, to: next, on: page)
        registerStep(named: actionName) { session in
            try session.transitionTextBox(from: next, to: previous, on: page)
        } redo: { session in
            try session.transitionTextBox(from: previous, to: next, on: page)
        }
    }

    /// Gives the document the box as typed so far, as the one step of `step`.
    func commitTextBox(_ typed: PDFTextBox, in step: PDFTextBoxEditStep) throws {
        let next: PDFTextBox? = typed.isEmpty && typed.preservedEntries.isEmpty ? nil : typed
        guard next != step.after else { return }
        try transitionTextBox(from: step.after, to: next, on: step.page)
        step.after = next
        guard !step.isRegistered else { return }
        step.isRegistered = true
        let actionName = step.before == nil ? "Add Text Box" : next == nil ? "Delete Text Box" : "Edit Text"
        registerStep(named: actionName) { session in
            try session.transitionTextBox(from: step.after, to: step.before, on: step.page)
        } redo: { session in
            try session.transitionTextBox(from: step.before, to: step.after, on: step.page)
        }
    }

    private func transitionTextBox(from previous: PDFTextBox?, to next: PDFTextBox?, on historyPage: PDFHistoryPage) throws {
        let pageIndex = try currentIndex(of: historyPage)
        switch (previous, next) {
        case (nil, nil): return
        case (nil, let added?): try apply(.addTextBox(page: pageIndex, textBox: added))
        case (let removed?, nil): try apply(.removeTextBox(removed.reference(onPageAt: pageIndex)))
        case (let replaced?, let replacement?): try apply(.replaceTextBox(replaced.reference(onPageAt: pageIndex), with: replacement))
        }
        textBoxesDidChange()
        if let selection = textBoxActivity.selection, textBox(selection) == nil, selection.page === historyPage,
           selection.boxName == previous?.name, next?.name != selection.boxName {
            textBoxActivity = .idle
        }
    }

    /// Changes the selected box, as its frame, its handle or its format popover does.
    func changeSelectedTextBox(actionName: String, _ change: (inout PDFTextBox) -> Void) throws {
        guard let selection = textBoxActivity.selection, let box = textBox(selection) else { throw PDFTextBoxError.boxMissing }
        var changed = box
        change(&changed)
        try changeTextBox(from: box, to: PDFTextBoxLayout.fitted(changed), on: selection.page, actionName: actionName)
    }

    func deleteSelectedTextBox() throws {
        guard let selection = textBoxActivity.selection, let box = textBox(selection) else { return }
        textBoxActivity = .idle
        try changeTextBox(from: box, to: nil, on: selection.page, actionName: "Delete Text Box")
    }

    /// A copy of the selected box beside it, selected in its place.
    func duplicateSelectedTextBox() throws {
        guard let selection = textBoxActivity.selection, let box = textBox(selection), let page = selection.page.page else { return }
        let quarterTurns = ((page.rotation / 90) % 4 + 4) % 4
        // Right and down as the page is shown: on the unturned page that direction turns back.
        let shownOffset = CGPoint(x: Self.duplicateOffsetPoints, y: -Self.duplicateOffsetPoints)
        let offset = PictureRotation.vector(shownOffset, turnedBy: Double(quarterTurns) * .pi / 2)
        var copy = box.renamed(UUID().uuidString)
        copy.origin = CGPoint(x: box.origin.x + offset.x, y: box.origin.y + offset.y)
        try changeTextBox(from: nil, to: copy, on: selection.page, actionName: "Duplicate Text Box")
        textBoxActivity = .selected(PDFTextBoxSelection(boxName: copy.name, page: selection.page))
    }

    // MARK: New boxes

    /// A new box with its top-left corner at a point of the page, upright as the page is
    /// shown, as wide as `PDFTextBoxDefaults` says or as fits before the page's edge, in the
    /// look the last box was given.
    func newTextBox(at pagePoint: CGPoint, on page: PDFPage, style: PDFTextBoxDefaults) -> PDFTextBox {
        let quarterTurns = ((page.rotation / 90) % 4 + 4) % 4
        let rotation = PDFTextBox.uprightRotation(forPageQuarterTurns: quarterTurns)
        var box = PDFTextBox(runs: [], origin: pagePoint, width: PDFTextBoxDefaults.newBoxWidthPoints, height: 1, rotationRadians: rotation,
                             style: style.boxStyle)
        box.width = min(PDFTextBoxDefaults.newBoxWidthPoints, max(PDFTextBoxDefaults.narrowestNewBoxWidthPoints, roomBeforeEdge(of: box, on: page)))
        var fitted = PDFTextBoxLayout.fitted(PDFTextBox(name: box.name, runs: [PDFTextRun(text: " ", attributes: style.attributes)], origin: box.origin,
                                                        width: box.width, height: 1, rotationRadians: rotation, style: style.boxStyle))
        fitted.runs = []
        return fitted
    }

    /// How far the text can run from the box's corner before the page's edge, as shown.
    private func roomBeforeEdge(of box: PDFTextBox, on page: PDFPage) -> Double {
        let cropBox = page.bounds(for: .cropBox)
        let direction = box.textDirection
        let distances = [
            direction.dx > 0.5 ? Double(cropBox.maxX - box.origin.x) : nil, direction.dx < -0.5 ? Double(box.origin.x - cropBox.minX) : nil,
            direction.dy > 0.5 ? Double(cropBox.maxY - box.origin.y) : nil, direction.dy < -0.5 ? Double(box.origin.y - cropBox.minY) : nil,
        ].compactMap { distance in distance }
        return (distances.min() ?? PDFTextBoxDefaults.newBoxWidthPoints) - PDFTextBoxDefaults.pageMarginPoints
    }
}
