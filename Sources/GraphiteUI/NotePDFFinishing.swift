/**
 * File: NotePDFFinishing.swift
 * ----------------------------
 * Layer: UI
 * Description: Finishes a drawn note PDF off the main thread: its title, no author, an outline that follows the
 *              note's headings, and its web links made clickable where their words were drawn.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 21/10/2026
 */

import Foundation
import PDFKit
import GraphiteCore

/// Why a note's PDF could not be made.
enum NotePDFExportError: Error, Equatable {
    /// The PDF drawing context could not be made.
    case drawingUnavailable
    /// PDFKit could not read the drawn PDF back to finish it.
    case drawnPDFUnreadable
    /// PDFKit could not write the finished PDF.
    case finishedPDFUnwritable
    /// No note is in front to print.
    case noNoteInFront
    /// The note's file is not UTF-8 text.
    case noteNotText
}

/// What PDFKit adds to a PDF a note was drawn into, which drawing cannot: an outline and
/// link annotations.
enum NotePDFFinishing {
    /// A heading of the note where it was drawn.
    struct Heading: Equatable, Sendable {
        let level: Int
        let title: String
        let pageIndex: Int
        /// The top of the heading, in PDF coordinates from the page's bottom.
        let top: CGFloat
    }

    /// The place a block with web links was drawn on a page, in PDF coordinates.
    struct LinkArea: Equatable, Sendable {
        let pageIndex: Int
        let area: CGRect
        let links: [NotePDFWebLink]
    }

    /// The PDF with its title, outline and links.
    static func finished(_ data: Data, title: String, headings: [Heading], linkAreas: [LinkArea]) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            guard let document = PDFDocument(data: data) else { throw NotePDFExportError.drawnPDFUnreadable }
            document.documentAttributes = [PDFDocumentAttribute.titleAttribute: title, PDFDocumentAttribute.creatorAttribute: "Graphite"]
            if !headings.isEmpty {
                // PDFKit writes a new outline only with a rewritten page tree (as `PDFPageManager.replay`
                // finds), so the first page is taken out and put back before the outline is made.
                if let firstPage = document.page(at: 0) {
                    document.removePage(at: 0)
                    document.insert(firstPage, at: 0)
                }
                addOutline(of: headings, to: document)
            }
            for linkArea in linkAreas { addLinks(of: linkArea, to: document) }
            guard let finishedData = document.dataRepresentation() else { throw NotePDFExportError.finishedPDFUnwritable }
            return finishedData
        }.value
    }

    /// The headings as the document's outline, each under the last heading of a higher level
    /// before it. The root is the document's before any item goes in, as PDFKit keeps only
    /// items added to a root it already has.
    static func addOutline(of headings: [Heading], to document: PDFDocument) {
        let root = PDFOutline()
        document.outlineRoot = root
        var openHeadings: [(level: Int, item: PDFOutline)] = []
        for heading in headings {
            guard let page = document.page(at: heading.pageIndex) else { continue }
            let item = PDFOutline()
            item.label = heading.title
            item.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: heading.top))
            while let last = openHeadings.last, last.level >= heading.level { openHeadings.removeLast() }
            let parent = openHeadings.last?.item ?? root
            parent.insertChild(item, at: parent.numberOfChildren)
            openHeadings.append((heading.level, item))
        }
    }

    /// Link annotations over each link's words, found by their text inside the area, in order.
    private static func addLinks(of linkArea: LinkArea, to document: PDFDocument) {
        guard let page = document.page(at: linkArea.pageIndex), let pageText = page.string as NSString? else { return }
        var usedRanges: [NSRange] = []
        for link in linkArea.links {
            let match = occurrences(of: link.text, in: pageText).lazy
                .filter { range in !usedRanges.contains(range) }
                .compactMap { range in page.selection(for: range).map { selection in (range, selection) } }
                .first { _, selection in selection.bounds(for: page).intersects(linkArea.area) }
            guard let (range, selection) = match else { continue }
            usedRanges.append(range)
            for line in selection.selectionsByLine() {
                let annotation = PDFAnnotation(bounds: line.bounds(for: page), forType: .link, withProperties: nil)
                annotation.url = link.destination
                let border = PDFBorder()
                border.lineWidth = 0
                annotation.border = border
                page.addAnnotation(annotation)
            }
        }
    }

    /// Every place `text` is written in the page's text, in reading order.
    private static func occurrences(of text: String, in pageText: NSString) -> [NSRange] {
        guard !text.isEmpty else { return [] }
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: pageText.length)
        while true {
            let found = pageText.range(of: text, options: .literal, range: searchRange)
            guard found.location != NSNotFound else { return ranges }
            ranges.append(found)
            searchRange = NSRange(location: NSMaxRange(found), length: pageText.length - NSMaxRange(found))
        }
    }
}
