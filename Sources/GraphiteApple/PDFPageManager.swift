import Foundation
import PDFKit
import GraphiteCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// One immutable change to a PDF. The session applies each edit to the displayed
/// document and replays the list on the file's snapshot when saving, so an edit must
/// produce the same result on both.
public enum PDFEdit: Sendable {
    case insert(data: Data, at: Int)
    case duplicate(page: Int)
    case delete(pages: [Int])
    case move(from: Int, to: Int)
    case rotate(page: Int, clockwise: Bool)
    case updateInk(PDFInkUpdate)
    case addMarkup(page: Int, markup: PDFMarkup)
    case recolorMarkup(PDFAnnotationReference, color: PDFMarkupColor)
    /// Gives markup back the color it had when `markup` was read, exactly, for undoing a
    /// color change of markup another application made.
    case restoreMarkupColor(PDFAnnotationReference, from: PDFMarkup)
    case removeAnnotation(PDFAnnotationReference)
    case bookmark(page: Int, label: String)
    /// Removes the outline item at this path of child indices from the outline root.
    case removeOutlineItem(path: [Int])

    /// Inserting, deleting, or reordering pages makes PDFKit rewrite the page tree.
    public var changesPageTree: Bool {
        switch self {
        case .insert, .duplicate, .delete, .move: true
        default: false
        }
    }

    public var changesOutline: Bool {
        switch self {
        case .bookmark, .removeOutlineItem: true
        default: false
        }
    }

    /// The page whose appearance the edit changes, for thumbnail invalidation.
    public var changedPageIndex: Int? {
        switch self {
        case .rotate(let pageIndex, _), .addMarkup(let pageIndex, _): pageIndex
        case .updateInk(let update): update.pageIndex
        case .recolorMarkup(let reference, _), .restoreMarkupColor(let reference, _), .removeAnnotation(let reference): reference.pageIndex
        default: nil
        }
    }
}

public enum PDFPageManager {
    public static let drawingKey = PDFAnnotationKey(rawValue: "GraphitePencilDrawingV1")
    public static let groupKey = PDFAnnotationKey(rawValue: "GraphiteInkGroup")
    /// Written with the drawing: the annotation name of each PencilKit stroke, in order.
    public static let strokeNamesKey = PDFAnnotationKey(rawValue: "GraphiteInkStrokeNamesV1")
    /// Repeats the annotation's `/NM` name. PDFKit drops `/NM` when a save also changes the
    /// page tree (inserting, deleting, or moving pages), but keeps custom keys.
    public static let annotationNameKey = PDFAnnotationKey(rawValue: "GraphiteAnnotationName")

    /// Applies one edit. Documents that will be written pass `drawsInkOutlines` so Pencil
    /// ink is saved with its variable-width appearance; see `PDFOutlinedInkAnnotation`.
    public static func apply(_ edit: PDFEdit, to document: PDFDocument, drawsInkOutlines: Bool = false) throws {
        func page(at index: Int) throws -> PDFPage {
            guard index >= 0, index < document.pageCount, let page = document.page(at: index) else { throw GraphiteError.invalidFile("Page no longer exists.") }
            return page
        }
        switch edit {
        case .insert(let data, let insertionIndex):
            guard insertionIndex >= 0, insertionIndex <= document.pageCount,
                  let incoming = PDFDocument(data: data), !incoming.isLocked else { throw GraphiteError.invalidFile("Cannot import these PDF pages.") }
            for pageIndex in 0..<incoming.pageCount {
                guard let importedPage = incoming.page(at: pageIndex)?.copy() as? PDFPage else { throw GraphiteError.invalidFile("Cannot copy imported page.") }
                document.insert(importedPage, at: insertionIndex + pageIndex)
            }
        case .duplicate(let pageIndex):
            guard let duplicate = try page(at: pageIndex).copy() as? PDFPage else { throw GraphiteError.invalidFile("Cannot duplicate page.") }
            document.insert(duplicate, at: pageIndex + 1)
        case .delete(let indices):
            let uniqueIndices = Set(indices)
            guard uniqueIndices.count < document.pageCount else { throw GraphiteError.invalidFile("A notebook must retain at least one page.") }
            for pageIndex in uniqueIndices { _ = try page(at: pageIndex) }
            let outlineDestinations = ResolvedDestinations(in: document, includesOutline: true, includesLinks: false)
            for pageIndex in uniqueIndices.sorted(by: >) { document.removePage(at: pageIndex) }
            outlineDestinations.restore(in: document)
        case .move(let sourceIndex, let destinationIndex):
            let movedPage = try page(at: sourceIndex)
            _ = try page(at: destinationIndex)
            let outlineDestinations = ResolvedDestinations(in: document, includesOutline: true, includesLinks: false)
            document.removePage(at: sourceIndex); document.insert(movedPage, at: destinationIndex)
            outlineDestinations.restore(in: document)
        case .rotate(let pageIndex, let clockwise):
            let targetPage = try page(at: pageIndex)
            targetPage.rotation = (targetPage.rotation + (clockwise ? 90 : 270)) % 360
        case .updateInk(let update):
            try applyInkUpdate(update, to: page(at: update.pageIndex), drawsInkOutlines: drawsInkOutlines)
        case .addMarkup(let pageIndex, let markup):
            let targetPage = try page(at: pageIndex)
            targetPage.addAnnotation(try markup.makeAnnotation(on: targetPage))
        case .recolorMarkup(let reference, let color):
            let targetPage = try page(at: reference.pageIndex)
            guard let annotation = referencedAnnotation(reference, on: targetPage) else { throw GraphiteError.invalidFile("This markup no longer exists.") }
            annotation.color = color.platformColor
        case .restoreMarkupColor(let reference, let markup):
            let targetPage = try page(at: reference.pageIndex)
            guard let annotation = referencedAnnotation(reference, on: targetPage) else { throw GraphiteError.invalidFile("This markup no longer exists.") }
            annotation.color = markup.originalDetails?.platformColor ?? markup.color.platformColor
        case .removeAnnotation(let reference):
            let targetPage = try page(at: reference.pageIndex)
            guard let annotation = referencedAnnotation(reference, on: targetPage) else { throw GraphiteError.invalidFile("This annotation no longer exists.") }
            // A note's popup belongs to its markup; left behind, it would be written as a
            // popup without a parent.
            if let popup = annotation.popup, popup.page === targetPage { targetPage.removeAnnotation(popup) }
            targetPage.removeAnnotation(annotation)
        case .bookmark(let pageIndex, let label):
            let targetPage = try page(at: pageIndex)
            let outline = PDFOutline()
            outline.label = label
            outline.destination = PDFDestination(page: targetPage, at: CGPoint(x: targetPage.bounds(for: .cropBox).minX, y: targetPage.bounds(for: .cropBox).maxY))
            let root = document.outlineRoot ?? PDFOutline()
            root.insertChild(outline, at: root.numberOfChildren)
            document.outlineRoot = root
        case .removeOutlineItem(let path):
            guard let item = outlineItem(at: path, in: document) else { throw GraphiteError.invalidFile("This bookmark no longer exists.") }
            item.removeFromParent()
        }
    }

    /// The outline item at a path of child indices below the outline root.
    public static func outlineItem(at path: [Int], in document: PDFDocument) -> PDFOutline? {
        guard !path.isEmpty, var item = document.outlineRoot else { return nil }
        for childIndex in path {
            guard childIndex >= 0, childIndex < item.numberOfChildren, let child = item.child(at: childIndex) else { return nil }
            item = child
        }
        return item
    }

    /// The annotation a reference names, or, when its name was lost, the unnamed
    /// annotation of the same subtype and rectangle.
    private static func referencedAnnotation(_ reference: PDFAnnotationReference, on page: PDFPage) -> PDFAnnotation? {
        let annotations = page.annotations
        return annotations.first(where: reference.matches) ?? annotations.first(where: reference.matchesAfterNameWasLost)
    }

    private static func removeInkAnnotations(from page: PDFPage, group: String, removal: PDFInkUpdate.Removal) {
        for annotation in page.annotations where annotation.value(forAnnotationKey: groupKey) as? String == group {
            switch removal {
            case .entireGroup:
                page.removeAnnotation(annotation)
            case .strokes(let names):
                if let name = annotation.persistentName, names.contains(name) { page.removeAnnotation(annotation) }
            }
        }
    }

    private static func annotations(inGroup group: String, on page: PDFPage) -> [PDFAnnotation] {
        page.annotations.filter { annotation in annotation.value(forAnnotationKey: groupKey) as? String == group }
    }

    private static func applyInkUpdate(_ update: PDFInkUpdate, to page: PDFPage, drawsInkOutlines: Bool) throws {
        // Read before the removal, which may remove the annotation that carries it.
        let keptRecordCarrier = update.defersEditableRecord ? annotations(inGroup: update.group, on: page).first : nil
        let keptRecordValues = (drawing: keptRecordCarrier?.value(forAnnotationKey: drawingKey), strokeNames: keptRecordCarrier?.value(forAnnotationKey: strokeNamesKey))
        removeInkAnnotations(from: page, group: update.group, removal: update.removal)
        for stroke in update.addedStrokes {
            guard let annotation = PDFInkAnnotationFactory.annotation(for: stroke, group: update.group, drawsOutline: drawsInkOutlines) else { continue }
            page.addAnnotation(annotation)
        }
        // Exactly one annotation, the group's first, carries the re-editing record, so a
        // replay of the same edits always leaves the record in the same place.
        let groupAnnotations = annotations(inGroup: update.group, on: page)
        for annotation in groupAnnotations.dropFirst() {
            if annotation.value(forAnnotationKey: drawingKey) != nil { annotation.removeValue(forAnnotationKey: drawingKey) }
            if annotation.value(forAnnotationKey: strokeNamesKey) != nil { annotation.removeValue(forAnnotationKey: strokeNamesKey) }
        }
        guard let carrier = groupAnnotations.first else { return }
        if update.defersEditableRecord {
            guard carrier !== keptRecordCarrier else { return }
            for (key, keptValue) in [(drawingKey, keptRecordValues.drawing), (strokeNamesKey, keptRecordValues.strokeNames)] {
                if let keptValue { carrier.setValue(keptValue, forAnnotationKey: key) } else { carrier.removeValue(forAnnotationKey: key) }
            }
        } else if let record = update.editableRecord {
            carrier.setValue(record.drawingData.base64EncodedString(), forAnnotationKey: drawingKey)
            carrier.setValue(PDFInkGroups.encodeStrokeNames(record.strokeNames), forAnnotationKey: strokeNamesKey)
        } else {
            carrier.removeValue(forAnnotationKey: drawingKey)
            carrier.removeValue(forAnnotationKey: strokeNamesKey)
        }
    }

    /// When a write also rewrites the page tree, PDFKit drops keys it does not know from
    /// annotations it read from the file, unless they were set again since. Setting
    /// Graphite's keys again keeps stroke data, stroke names and ink groups.
    ///
    /// The rewrite also drops the standard `/NM` name. Graphite's own annotations repeat it
    /// in `annotationNameKey`; another application's named markup gets the same backup
    /// here, so edits recorded against its name still find it in the written file.
    public static func preserveGraphiteKeysThroughPageTreeRewrite(in document: PDFDocument) {
        let graphiteKeys = [groupKey, drawingKey, strokeNamesKey, annotationNameKey]
        for pageIndex in 0..<document.pageCount {
            for annotation in document.page(at: pageIndex)?.annotations ?? [] {
                for key in graphiteKeys {
                    if let storedValue = annotation.value(forAnnotationKey: key) { annotation.setValue(storedValue, forAnnotationKey: key) }
                }
                if annotation.value(forAnnotationKey: annotationNameKey) == nil,
                   let standardName = annotation.value(forAnnotationKey: .name) as? String, !standardName.isEmpty {
                    annotation.setValue(standardName, forAnnotationKey: annotationNameKey)
                }
            }
        }
    }

    /// Replays edits on a document that will be written.
    static func replay(_ edits: [PDFEdit], on document: PDFDocument) throws {
        var rewritesPageTree = edits.contains(where: \.changesPageTree)
        let changesOutline = edits.contains(where: \.changesOutline)
        // Resolving every page's links reads all annotations, so only documents that will
        // be written do it; the displayed document's links are not saved. Outline entries
        // are resolved by each page removal, as in the displayed document, so both keep
        // the same outline and later outline paths name the same entries.
        let linkDestinations = rewritesPageTree ? ResolvedDestinations(in: document, includesOutline: false, includesLinks: true) : nil
        for edit in edits { try apply(edit, to: document, drawsInkOutlines: true) }
        // PDFKit writes a changed outline only together with a rewritten page tree, so an
        // outline change alone takes the first page out and puts it back.
        if changesOutline, !rewritesPageTree, let firstPage = document.page(at: 0) {
            let destinations = ResolvedDestinations(in: document, includesOutline: true, includesLinks: true)
            document.removePage(at: 0)
            document.insert(firstPage, at: 0)
            destinations.restore(in: document)
            rewritesPageTree = true
        }
        linkDestinations?.restore(in: document)
        if rewritesPageTree { preserveGraphiteKeysThroughPageTreeRewrite(in: document) }
    }

    /// A PDF with only the given pages. The document is written and read back first so
    /// that annotation names and appearance streams are carried exactly as they are saved;
    /// copying live pages into a new document drops them.
    public static func export(pages: [Int], from document: PDFDocument) throws -> Data {
        let selectedPages = Set(pages)
        guard !selectedPages.isEmpty else { throw GraphiteError.invalidFile("Select at least one page to export.") }
        guard selectedPages.allSatisfy({ pageIndex in pageIndex >= 0 && pageIndex < document.pageCount }) else { throw GraphiteError.invalidFile("Cannot export missing page.") }
        guard let writtenData = document.dataRepresentation(), let exported = PDFDocument(data: writtenData), exported.pageCount == document.pageCount else {
            throw GraphiteError.invalidFile("Could not prepare the pages for export.")
        }
        // Outline entries and links to pages that are not exported are removed rather than
        // written as destinations to the first page.
        let destinations = ResolvedDestinations(in: exported, includesOutline: true, includesLinks: true)
        for pageIndex in (0..<exported.pageCount).reversed() where !selectedPages.contains(pageIndex) {
            exported.removePage(at: pageIndex)
        }
        destinations.restore(in: exported)
        preserveGraphiteKeysThroughPageTreeRewrite(in: exported)
        guard exported.pageCount == selectedPages.count, let exportedData = exported.dataRepresentation() else { throw GraphiteError.invalidFile("Could not export the selected pages.") }
        return exportedData
    }
}

/// Outline entries and links with the page each one points to, resolved before pages are
/// removed.
///
/// PDFKit resolves outline and link destinations lazily. One whose page is removed before
/// anything read it loses its page, and PDFKit then writes it as a destination to the
/// first page: a moved page's bookmark or table-of-contents entry would open page 1.
/// Resolving them first keeps them on their page wherever it moves. An outline entry
/// whose page is removed is removed with it (an entry with children keeps them and loses
/// only its destination), and a link to a removed page loses its destination.
private struct ResolvedDestinations {
    private struct OutlineTarget {
        let item: PDFOutline
        let page: PDFPage
        let destination: PDFDestination
    }

    private struct LinkTarget {
        let annotation: PDFAnnotation
        let page: PDFPage
        let destination: PDFDestination
    }

    /// In outline order, each parent before its children.
    private var outlineTargets: [OutlineTarget] = []
    private var linkTargets: [LinkTarget] = []

    init(in document: PDFDocument, includesOutline: Bool, includesLinks: Bool) {
        if includesOutline, let root = document.outlineRoot {
            var pendingItems: [PDFOutline] = (0..<root.numberOfChildren).reversed().compactMap { childIndex in root.child(at: childIndex) }
            while let item = pendingItems.popLast() {
                if let destination = item.destination, let page = destination.page {
                    outlineTargets.append(OutlineTarget(item: item, page: page, destination: destination))
                }
                pendingItems.append(contentsOf: (0..<item.numberOfChildren).reversed().compactMap { childIndex in item.child(at: childIndex) })
            }
        }
        guard includesLinks else { return }
        for pageIndex in 0..<document.pageCount {
            for annotation in document.page(at: pageIndex)?.annotations ?? [] where annotation.type == "Link" {
                guard let destination = annotation.destination ?? (annotation.action as? PDFActionGoTo)?.destination, let page = destination.page else { continue }
                linkTargets.append(LinkTarget(annotation: annotation, page: page, destination: destination))
            }
        }
    }

    func restore(in document: PDFDocument) {
        // Children first, so a parent whose children were all removed is seen without them.
        for target in outlineTargets.reversed() {
            if Self.contains(target.page, in: document) {
                if target.item.destination?.page !== target.page { target.item.destination = Self.destination(copying: target.destination, on: target.page) }
            } else if target.item.numberOfChildren == 0 {
                target.item.removeFromParent()
            } else {
                target.item.action = nil
                target.item.destination = nil
            }
        }
        for target in linkTargets {
            let currentDestination = target.annotation.destination ?? (target.annotation.action as? PDFActionGoTo)?.destination
            if Self.contains(target.page, in: document) {
                guard currentDestination?.page !== target.page else { continue }
                let destination = Self.destination(copying: target.destination, on: target.page)
                if target.annotation.action is PDFActionGoTo {
                    target.annotation.action = PDFActionGoTo(destination: destination)
                } else {
                    target.annotation.destination = destination
                }
            } else {
                if target.annotation.action is PDFActionGoTo { target.annotation.action = nil }
                target.annotation.destination = nil
            }
        }
    }

    private static func contains(_ page: PDFPage, in document: PDFDocument) -> Bool {
        page.document === document && document.index(for: page) != NSNotFound
    }

    private static func destination(copying destination: PDFDestination, on page: PDFPage) -> PDFDestination {
        let copiedDestination = PDFDestination(page: page, at: destination.point)
        copiedDestination.zoom = destination.zoom
        return copiedDestination
    }
}

public actor PDFFileService {
    private let writer: AtomicFileWriter
    public init(writer: AtomicFileWriter = AtomicFileWriter()) { self.writer = writer }
    public func create(paper: PaperSpecification, pageCount: Int, at destination: URL) throws -> FileRevision {
        try writer.write(PDFTemplateGenerator.documentData(paper: paper, pageCount: pageCount), to: destination, expecting: .absent)
    }

    /// Replays `edits` on the baseline snapshot (or the file itself) and replaces the file
    /// atomically if it still has `revision`. When `savedSnapshotDestination` is given,
    /// the exact bytes written are also copied there, so the caller can make them its
    /// next baseline and drop the edits that are now part of the file.
    public func save(url: URL, revision: FileRevision, edits: [PDFEdit], baselineURL: URL? = nil, savedSnapshotDestination: URL? = nil) throws -> FileRevision {
        do {
            return try writer.replace(url, expecting: .revision(revision)) { staging in
                var coordinationError: NSError?
                var replayResult: Result<Void, Error>?
                NSFileCoordinator().coordinate(readingItemAt: baselineURL ?? url, options: [], error: &coordinationError) { source in
                    replayResult = Result {
                        if baselineURL == nil, try FileRevision.read(source) != revision { throw GraphiteError.conflict }
                        guard let document = PDFDocument(url: source), !document.isLocked else { throw GraphiteError.invalidFile("This PDF is locked or unreadable.") }
                        guard document.allowsDocumentChanges, document.allowsCommenting else { throw GraphiteError.unavailable("This PDF does not permit editing.") }
                        try PDFPageManager.replay(edits, on: document)
                        guard document.write(to: staging), let reopened = PDFDocument(url: staging), reopened.pageCount == document.pageCount else {
                            throw GraphiteError.invalidFile("PDF verification failed. The original file was preserved.")
                        }
                    }
                }
                if let coordinationError { throw coordinationError }
                guard let replayResult else { throw GraphiteError.unavailable("Unable to read PDF for saving.") }
                try replayResult.get()
                if let savedSnapshotDestination { try FileManager.default.copyItem(at: staging, to: savedSnapshotDestination) }
            }
        } catch {
            // Only a completed replacement makes the copy a valid baseline.
            if let savedSnapshotDestination { try? FileManager.default.removeItem(at: savedSnapshotDestination) }
            throw error
        }
    }

    public func saveCopy(baselineURL: URL, edits: [PDFEdit], destination: URL) throws -> FileRevision {
        try writer.replace(destination, expecting: .absent) { staging in
            guard let document = PDFDocument(url: baselineURL) else { throw GraphiteError.invalidFile("The open PDF snapshot is unavailable.") }
            try PDFPageManager.replay(edits, on: document)
            guard document.write(to: staging), PDFDocument(url: staging)?.pageCount == document.pageCount else { throw GraphiteError.invalidFile("Could not verify the PDF copy.") }
        }
    }
    public func export(baselineURL: URL, edits: [PDFEdit], pages: [Int]) throws -> Data {
        guard let document = PDFDocument(url: baselineURL) else { throw GraphiteError.invalidFile("The PDF snapshot is unavailable.") }
        try PDFPageManager.replay(edits, on: document)
        return try PDFPageManager.export(pages: pages, from: document)
    }
}

public extension PDFAnnotation {
    /// The name Graphite gave this annotation, or its standard `/NM` name.
    var persistentName: String? {
        let name = (value(forAnnotationKey: PDFPageManager.annotationNameKey) as? String) ?? (value(forAnnotationKey: .name) as? String)
        return name?.isEmpty == false ? name : nil
    }

    /// Stores the name as the standard `/NM` and in Graphite's own key; see `annotationNameKey`.
    func setPersistentName(_ name: String) {
        setValue(name, forAnnotationKey: .name)
        setValue(name, forAnnotationKey: PDFPageManager.annotationNameKey)
    }
}
