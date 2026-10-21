/**
 * File: NotePDFBase.swift
 * -----------------------
 * Layer: UI
 * Description: A base in a printed note, drawn as the reading view shows it: its view run over the vault's index
 *              before drawing, its card covers decoded beforehand, and its rows divided into the parts a page may
 *              end between (a row of cards, a list item, a table row).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/10/2026
 */

import SwiftUI
import GraphiteCore
import GraphiteApple

/// A base's view as it prints: its results, its covers, and where its parts start.
struct PrintedBase: Sendable {
    let result: BaseQueryResult
    /// Card covers decoded before drawing, as a drawing runs no task to load them.
    let covers: [BaseImageReference: ReadingThumbnail]
    /// The first displayed row of each part, then the row count: part `i` is the rows from
    /// `partStarts[i]` up to `partStarts[i + 1]`.
    let partStarts: [Int]
    let vaultRoot: URL

    var unitCount: Int { max(1, partStarts.count - 1) }

    /// The displayed rows of a run of parts.
    func rows(forUnits units: Range<Int>) -> Range<Int> {
        guard partStarts.count > 1 else { return 0..<0 }
        let lastPart = partStarts.count - 1
        return partStarts[min(units.lowerBound, lastPart)]..<partStarts[min(units.upperBound, lastPart)]
    }
}

enum NotePDFBases {
    /// The views a page can show; a map or kanban prints as the base's name.
    private static let printedViewTypes: Set<BaseViewType> = [.cards, .list, .table]
    /// Cover pixels per point of a card's width: sharp on paper without holding full-size pictures.
    private static let coverPixelsPerPoint: CGFloat = 2

    /// The base run over the vault as the reading view runs it, with `note` as `this`; nil
    /// when the vault cannot run it here, it fails, or its view cannot be printed.
    @MainActor
    static func printed(_ source: BaseSource, viewName: String?, note: VaultPath, vault: ReadingVault, layoutWidth: CGFloat) async -> PrintedBase? {
        guard let store = vault.store else { return nil }
        let model = BaseDocumentModel(source: source, contextPath: note, store: store, index: vault.index, preferredViewName: viewName)
        await model.reload()
        guard let result = model.result, printedViewTypes.contains(result.view.type) else { return nil }
        let cardWidth = result.view.cards.cardSize.map { size in CGFloat(size) } ?? BaseCardsView.defaultCardWidth
        let covers = await decodedCovers(of: result, root: store.root, maximumPixelDimension: Int(cardWidth * coverPixelsPerPoint))
        let rowsPerPart = result.view.type == .cards ? BaseCardGridMetrics(availableWidth: layoutWidth, preferredCardWidth: cardWidth).columnCount : 1
        return PrintedBase(result: result, covers: covers, partStarts: partStarts(of: result, rowsPerPart: rowsPerPart), vaultRoot: store.root)
    }

    /// Where each part starts: each group's rows in runs of `rowsPerPart`, a run never
    /// spanning two groups, then the row count.
    static func partStarts(of result: BaseQueryResult, rowsPerPart: Int) -> [Int] {
        var starts: [Int] = []
        var groupStart = 0
        for group in result.groups {
            starts.append(contentsOf: stride(from: groupStart, to: groupStart + group.rows.count, by: max(1, rowsPerPart)))
            groupStart += group.rows.count
        }
        return starts + [groupStart]
    }

    /// The cards' covers from files and the web, each decoded once at the size a card prints
    /// it; one that cannot be read is left out and prints as an empty photo.
    private static func decodedCovers(of result: BaseQueryResult, root: URL, maximumPixelDimension: Int) async -> [BaseImageReference: ReadingThumbnail] {
        guard result.view.type == .cards, result.view.cards.imageProperty != nil else { return [:] }
        var covers: [BaseImageReference: ReadingThumbnail] = [:]
        for row in result.rows {
            guard !Task.isCancelled else { return covers }
            guard let reference = row.presentation.coverImage, covers[reference] == nil,
                  let cover = await decodedCover(reference, root: root, maximumPixelDimension: maximumPixelDimension) else { continue }
            covers[reference] = ReadingThumbnail(image: cover, aspectRatio: CGFloat(cover.width) / CGFloat(max(cover.height, 1)), isEditableDrawing: false)
        }
        return covers
    }

    /// A cover from a file or the web; nil for a colour, or a picture that cannot be read,
    /// which prints as an empty photo as the screen shows it.
    private static func decodedCover(_ reference: BaseImageReference, root: URL, maximumPixelDimension: Int) async -> CGImage? {
        switch reference {
        case .color:
            return nil
        case .remote(let location):
            return try? await BaseThumbnailStore.downloadedThumbnail(at: location, maximumDimension: maximumPixelDimension) // Unreadable: an empty photo.
        case .vaultFile(let path):
            guard let location = try? path.url(in: root) else { return nil } // A path outside the vault: an empty photo.
            return try? await ImageFileService().displayImage(at: location, maximumPixelDimension: maximumPixelDimension) // Unreadable: an empty photo.
        }
    }
}

/// A run of a printed base's parts, drawn by the base's own cards, list or table view, with
/// the view's name above its first part as the base's toolbar shows it.
struct NotePDFBaseView: View {
    let base: PrintedBase
    let units: Range<Int>

    var body: some View {
        let result = base.result.keepingRows(at: base.rows(forUnits: units))
        VStack(alignment: .leading, spacing: 4) {
            if units.lowerBound == 0 {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(result.view.name).font(.headline)
                    Text(base.result.displayedCount == 1 ? "1 result" : "\(base.result.displayedCount) results").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
            }
            switch result.view.type {
            case .cards: BaseCardsView(result: result, actions: actions)
            case .list: BaseListView(result: result, actions: actions)
            case .table: BaseTableView(result: result, sortKeys: result.view.sort, actions: actions, sort: { _, _ in })
            case .map, .kanban, .unsupported: EmptyView()
            }
        }
        .environment(\.basesScrollVertically, false)
        .environment(\.baseRowLimit, nil)
        .environment(\.printedBaseCovers, base.covers)
    }

    /// Paper is not tapped: nothing opens or edits.
    private var actions: BaseViewActions {
        BaseViewActions(openPath: { _ in }, openLink: { _ in }, editRequest: { _, _, _ in nil }, beginEditing: { _ in },
                        toggleCheckbox: { _, _ in }, requestedCheckboxValue: { _ in nil }, thumbnails: BaseThumbnailStore(),
                        vaultRoot: base.vaultRoot, contentVersion: 0)
    }
}
