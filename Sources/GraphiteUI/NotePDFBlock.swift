/**
 * File: NotePDFBlock.swift
 * ------------------------
 * Layer: UI
 * Description: A note's reading-view blocks as a PDF prints them: callouts printed open, lists, tables, code,
 *              callouts and embedded notes divided into the parts a page may end between, pictures and PDF pages
 *              loaded before drawing, and the headings and web links the finished PDF needs.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/10/2026
 */

import SwiftUI
import PDFKit
import GraphiteCore

/// A web link in a printed block's text: the words it is written on, and where it goes.
struct NotePDFWebLink: Equatable, Sendable {
    let text: String
    let destination: URL
}

/// One block of a note as it is printed: what draws it, and the parts a page may end between.
struct NotePDFBlock: Sendable {
    enum Content: Sendable {
        /// The note's name above its text.
        case title(String)
        /// A reading-view block drawn whole by the reading view's own views.
        case reading(RenderedBlock)
        /// A list, table or code block, drawn by runs of its items, rows or lines.
        case section(MarkdownSectionUnits)
        /// A callout, drawn by runs of its blocks, each run under the callout's title.
        case callout(type: String, title: String, body: [RenderedBlock])
        /// An embedded note, drawn by runs of its blocks.
        case transclusion(path: VaultPath, heading: String?, body: [RenderedBlock])
        case footnotes([RenderedFootnote])
        /// An image or drawing on a line of its own, decoded before drawing.
        case picture(ReadingThumbnail, displaySize: EmbedDisplaySize?)
        /// A page of an embedded PDF, drawn as the PDF draws it, its text kept as text.
        case pdfPage(PrintedPDFPage)
        /// An embed the paper cannot show, such as a video, printed as its file's name.
        case fileName(String, systemImage: String)
    }

    let content: Content
    /// The heading's level and text, for the PDF's outline; nil for other blocks.
    var outlineHeading: (level: Int, title: String)?
    var webLinks: [NotePDFWebLink] = []

    /// Parts a page may end between; 1 for a block printed whole.
    var unitCount: Int {
        switch content {
        case .section(let units): units.unitCount
        case .callout(_, _, let body), .transclusion(_, _, let body): max(1, body.count)
        case .footnotes(let notes): max(1, notes.count)
        case .title, .reading, .picture, .pdfPage, .fileName: 1
        }
    }

    /// A heading or the title, which a page never ends with.
    var keepsWithNext: Bool {
        switch content {
        case .title: true
        case .reading(let block): if case .heading = block { true } else { false }
        case .section, .callout, .transclusion, .footnotes, .picture, .pdfPage, .fileName: false
        }
    }

    /// A picture or PDF page, scaled down to fit a page rather than cut.
    var scalesToFit: Bool {
        switch content {
        case .picture, .pdfPage: true
        case .title, .reading, .section, .callout, .transclusion, .footnotes, .fileName: false
        }
    }
}

/// A page of a PDF embedded in a note: the file's bytes, read off the main thread, and the
/// page's zero-based index.
struct PrintedPDFPage: Sendable {
    let fileData: Data
    let pageIndex: Int

    /// The page, read from the bytes, with its annotations; nil when the file is not a PDF
    /// or has no such page. Each call reads a new document, which stays on the thread that
    /// asked for it.
    func page() -> PDFPage? {
        PDFDocument(data: fileData)?.page(at: pageIndex)
    }
}

extension PDFPage {
    /// The page's crop box as the page is shown, turned by its rotation.
    var shownSize: CGSize {
        let box = bounds(for: .cropBox).size
        return rotation % 180 == 0 ? box : CGSize(width: box.height, height: box.width)
    }
}

/// Turns a note's reading-view blocks into printed blocks, loading what drawing them needs.
enum NotePDFBlocks {
    /// The printed blocks of a note: its title when asked for, then its blocks, with callouts
    /// opened, pictures and embedded PDF pages read, and inline images loaded into the
    /// reading view's image cache, so each block draws completely the first time.
    static func prepared(_ blocks: [RenderedBlock], title: String?, root: URL) async -> [NotePDFBlock] {
        var printed: [NotePDFBlock] = title.map { title in [NotePDFBlock(content: .title(title))] } ?? []
        for block in openedForPrinting(blocks) {
            guard !Task.isCancelled else { return printed }
            var printedBlock = await printedBlock(for: block)
            let scan = await NotePDFTextScan.scanning(markdownTexts(in: block), root: root)
            await scan.loadInlineImages()
            printedBlock.webLinks = scan.webLinks
            if case .heading(_, let level, let text, _) = block {
                printedBlock.outlineHeading = (level, await NotePDFTextScan.plainText(of: text, root: root))
            }
            printed.append(printedBlock)
        }
        return printed
    }

    private static func printedBlock(for block: RenderedBlock) async -> NotePDFBlock {
        switch block {
        case .markdown(_, let text), .pluginSection(_, let text, _):
            if let units = MarkdownSectionUnits.units(of: text) { return NotePDFBlock(content: .section(units)) }
            return NotePDFBlock(content: .reading(.markdown(id: 0, text: text)))
        case .callout(_, let type, let title, _, let body) where body.count > 1:
            return NotePDFBlock(content: .callout(type: type, title: title, body: body))
        case .transclusion(_, let path, let heading, let body):
            return NotePDFBlock(content: .transclusion(path: path, heading: heading, body: body))
        case .footnotes(_, let notes) where notes.count > 1:
            return NotePDFBlock(content: .footnotes(notes))
        case .image(_, let path, let location, let displaySize, _):
            guard let thumbnail = try? await ReadingImageCache.shared.thumbnail(for: location, kind: .block) else { // Unreadable: printed as its name.
                return NotePDFBlock(content: .fileName(path.name, systemImage: "photo"))
            }
            return NotePDFBlock(content: .picture(thumbnail, displaySize: displaySize))
        case .pdf(_, let path, let location, let options):
            guard let fileData = try? await readFile(at: location) else { // Unreadable: printed as its name.
                return NotePDFBlock(content: .fileName(path.name, systemImage: "doc.richtext"))
            }
            let page = PrintedPDFPage(fileData: fileData, pageIndex: max(0, (options.startPageNumber ?? 1) - 1))
            guard page.page() != nil else { return NotePDFBlock(content: .fileName(path.name, systemImage: "doc.richtext")) }
            return NotePDFBlock(content: .pdfPage(page))
        case .video(_, let location):
            return NotePDFBlock(content: .fileName(location.lastPathComponent, systemImage: "film"))
        case .audio(_, _, let name):
            return NotePDFBlock(content: .fileName(name, systemImage: "waveform"))
        case .baseFile(_, let path, _):
            return NotePDFBlock(content: .fileName(path.name, systemImage: "tablecells"))
        case .base:
            return NotePDFBlock(content: .fileName("Base", systemImage: "tablecells"))
        case .properties, .displayMath, .heading, .callout, .missingEmbed, .missingSection, .footnotes, .pluginCodeBlock:
            return NotePDFBlock(content: .reading(block))
        }
    }

    /// Reads a file off the main thread.
    private static func readFile(at location: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) { try Data(contentsOf: location, options: .mappedIfSafe) }.value
    }

    /// The blocks with every callout open and without its fold button, as Obsidian prints a
    /// folded callout.
    static func openedForPrinting(_ blocks: [RenderedBlock]) -> [RenderedBlock] {
        blocks.map { block in
            switch block {
            case .callout(let id, let type, let title, _, let body):
                .callout(id: id, type: type, title: title, folding: .notFoldable, body: openedForPrinting(body))
            case .transclusion(let id, let path, let heading, let body):
                .transclusion(id: id, path: path, heading: heading, body: openedForPrinting(body))
            case .properties, .markdown, .displayMath, .heading, .video, .audio, .pdf, .base, .baseFile, .missingEmbed, .missingSection, .image,
                 .footnotes, .pluginCodeBlock, .pluginSection:
                block
            }
        }
    }

    /// The Markdown a block draws, with that of the blocks inside it.
    static func markdownTexts(in block: RenderedBlock) -> [String] {
        switch block {
        case .markdown(_, let text), .displayMath(_, let text), .heading(_, _, let text, _), .pluginSection(_, let text, _): [text]
        case .callout(_, _, let title, _, let body): [title] + body.flatMap(markdownTexts(in:))
        case .transclusion(_, _, _, let body): body.flatMap(markdownTexts(in:))
        case .footnotes(_, let notes): notes.map(\.text)
        case .properties, .video, .audio, .pdf, .base, .baseFile, .missingEmbed, .missingSection, .image, .pluginCodeBlock: []
        }
    }
}
