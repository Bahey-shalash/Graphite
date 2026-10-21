/**
 * File: NotePDFRenderer.swift
 * ---------------------------
 * Layer: UI
 * Description: Draws a note into a PDF as its reading view shows it: builds its blocks off the main actor,
 *              measures each at the page's layout width, lays them out on pages with NotePageFlow, and draws them
 *              into a PDF context page by page, their text kept as text.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/10/2026
 */

import SwiftUI
import PDFKit
import GraphiteCore

/// A note to print: its text and where it is, how its vault reads, and how it looks.
struct NotePDFSource {
    let text: String
    let path: VaultPath
    let vault: ReadingVault
    /// The reading view's configuration, whose vault settings (line breaks, colours,
    /// property types) the PDF keeps.
    let readingConfiguration: ReadingConfiguration
    /// The note's name, the PDF's title.
    let title: String
    let appearance: NotePDFAppearance
}

/// A finished PDF of a note.
struct NotePDF: Sendable {
    let data: Data
    let pageCount: Int
}

/// Draws one note into a PDF with one set of options. SwiftUI draws only on the main actor,
/// so measuring and drawing run there, block by block with a turn of the main actor between
/// blocks; building the blocks, reading pictures and finishing the PDF run off it.
@MainActor
final class NotePDFRenderer {
    private let source: NotePDFSource
    private let options: NotePDFOptions
    private var blocks: [NotePDFBlock] = []
    private var measuredHeights: [UnitRun: CGFloat] = [:]
    /// Pages of embedded PDFs, read once per block on the main actor that draws them.
    private var embeddedPages: [Int: PDFPage] = [:]

    /// A block drawn with a run of its parts.
    private struct UnitRun: Hashable {
        let blockIndex: Int
        let units: Range<Int>
    }

    /// Drawings of a block before its size is trusted: Textual parses, styles and lays out
    /// a text in steps that each update its state after a drawing.
    private static let minimumSettlingDrawings = 3
    /// The most drawings a block is given to stop changing size.
    private static let maximumSettlingDrawings = 10
    /// Pixels per point of what SwiftUI cannot draw as vectors into a PDF: formulas, which
    /// Textual draws as canvas symbols. Four keeps them sharp when the page is zoomed in.
    private static let rasterizationScale: CGFloat = 4
    /// Pixels per point of the picture of a block searched for gaps between its lines.
    private static let gapSearchPixelsPerPoint: CGFloat = 2
    /// The tallest picture searched for gaps, in pixels, which keeps its memory bounded.
    private static let maximumGapSearchPixelHeight: CGFloat = 16_384

    init(source: NotePDFSource, options: NotePDFOptions) {
        self.source = source
        self.options = options
    }

    /// The note as a PDF. Cancelling the task stops it between blocks and leaves nothing behind.
    /// - Parameters:
    ///   - pageLimit: Stops after this many pages, for a preview; nil prints the whole note.
    ///   - reportProgress: Called with the fraction done, from 0 to 1.
    func render(pageLimit: Int? = nil, reportProgress: (Double) -> Void) async throws -> NotePDF {
        reportProgress(0)
        let build = try await source.vault.build(source.text, note: source.path, configuration: printingConfiguration)
        try Task.checkCancellation()
        blocks = await NotePDFBlocks.prepared(build.blocks, title: options.includesFileNameAsTitle ? source.title : nil, vault: source.vault, note: source.path,
                                             layoutWidth: options.layoutWidth)
        try Task.checkCancellation()
        let flowBlocks = try await measuredFlowBlocks(pageLimit: pageLimit) { fraction in reportProgress(0.1 + 0.4 * fraction) }
        let allPlacements = await NotePageFlow.placements(of: flowBlocks, pageHeight: Double(options.layoutPageHeight), measurements: measurements)
        let placements = pageLimit.map { limit in allPlacements.filter { placement in placement.pageIndex < limit } } ?? allPlacements
        let drawing = try await draw(placements) { fraction in reportProgress(0.5 + 0.45 * fraction) }
        let data = try await NotePDFFinishing.finished(drawing.data, title: source.title, headings: drawing.headings, linkAreas: drawing.linkAreas)
        reportProgress(1)
        return NotePDF(data: data, pageCount: drawing.pageCount)
    }

    /// The reading view's configuration for paper: Markdown divided into sections so pages
    /// end between them, no plugins (they draw in a web view the PDF cannot hold), and
    /// properties only when asked for.
    private var printingConfiguration: ReadingConfiguration {
        var configuration = source.readingConfiguration
        configuration.usesReadableLineLength = false
        configuration.showsProperties = options.includesProperties
        configuration.inlineTitle = nil
        configuration.textSize = NotePDFOptions.layoutTextSize
        configuration.mapsReadAloudSourceLocations = false
        configuration.pluginCodeBlockLanguages = []
        configuration.runsPluginPostProcessors = false
        configuration.marksUnresolvedLinks = false
        configuration.dividesMarkdownIntoSections = true
        return configuration
    }

    // MARK: Measuring

    /// Measures every block, giving the app a turn now and then; for a preview, only the
    /// blocks the first pages can hold.
    private func measuredFlowBlocks(pageLimit: Int?, reportProgress: (Double) -> Void) async throws -> [NotePageFlow.Block] {
        var flowBlocks: [NotePageFlow.Block] = []
        var measuredTotal: CGFloat = 0
        for (blockIndex, block) in blocks.enumerated() {
            if let pageLimit, measuredTotal > CGFloat(pageLimit + 1) * options.layoutPageHeight { break }
            measuredTotal += await height(of: blockIndex, units: 0..<block.unitCount)
            if block.unitCount > 1 { _ = await height(of: blockIndex, units: 0..<1) }
            flowBlocks.append(NotePageFlow.Block(unitCount: block.unitCount, spacingBefore: Self.blockSpacing, keepsWithNext: block.keepsWithNext,
                                                 scalesToFit: block.scalesToFit))
            reportProgress(Double(blockIndex + 1) / Double(blocks.count))
            try Task.checkCancellation()
        }
        return flowBlocks
    }

    /// The reading view's room between blocks.
    private static let blockSpacing: Double = 14

    private var measurements: NotePageFlow.Measurements {
        NotePageFlow.Measurements(height: { [unowned self] blockIndex, units in Double(await height(of: blockIndex, units: units)) },
                                  cutOffsets: { [unowned self] blockIndex, units in await cutOffsets(of: blockIndex, units: units) })
    }

    private func height(of blockIndex: Int, units: Range<Int>) async -> CGFloat {
        let run = UnitRun(blockIndex: blockIndex, units: units)
        if let height = measuredHeights[run] { return height }
        let height: CGFloat
        if case .pdfPage = blocks[blockIndex].content {
            let shownSize = embeddedPage(of: blockIndex)?.shownSize ?? CGSize(width: 1, height: 1)
            height = options.layoutWidth * shownSize.height / max(shownSize.width, 1)
        } else {
            height = await settledRenderer(of: blockIndex, units: units).height
        }
        measuredHeights[run] = height
        return height
    }

    /// Where the block can be cut without cutting a line: the gaps found in a picture of it.
    private func cutOffsets(of blockIndex: Int, units: Range<Int>) async -> [Double] {
        let (renderer, blockHeight) = await settledRenderer(of: blockIndex, units: units)
        renderer.scale = min(Self.gapSearchPixelsPerPoint, Self.maximumGapSearchPixelHeight / max(blockHeight, 1))
        guard let picture = renderer.cgImage else { return [] }
        return PrintedLineGaps.cutOffsets(in: picture, pixelsPerPoint: Double(renderer.scale))
    }

    /// A renderer of the block whose drawing has stopped changing: drawn again, with a turn
    /// of the main actor between drawings for Textual's updates, until its height holds.
    private func settledRenderer(of blockIndex: Int, units: Range<Int>) async -> (renderer: ImageRenderer<NotePDFPrintedBlock>, height: CGFloat) {
        let renderer = ImageRenderer(content: NotePDFPrintedBlock(block: blocks[blockIndex], units: units, root: source.vault.root,
                                                                  layoutWidth: options.layoutWidth, appearance: source.appearance))
        renderer.proposedSize = ProposedViewSize(width: options.layoutWidth, height: nil)
        var previousHeight: CGFloat = -1
        for drawing in 1...Self.maximumSettlingDrawings {
            var height: CGFloat = 0
            renderer.render { size, _ in height = size.height }
            if drawing >= Self.minimumSettlingDrawings, abs(height - previousHeight) < Self.sliceTolerance { return (renderer, height) }
            previousHeight = height
            await Task.yield()
        }
        return (renderer, previousHeight)
    }

    private func embeddedPage(of blockIndex: Int) -> PDFPage? {
        if let page = embeddedPages[blockIndex] { return page }
        guard case .pdfPage(let printedPage) = blocks[blockIndex].content, let page = printedPage.page() else { return nil }
        embeddedPages[blockIndex] = page
        return page
    }

    // MARK: Drawing

    /// The PDF drawn so far, and where its headings and web links are.
    private struct Drawing {
        let data: Data
        let pageCount: Int
        let headings: [NotePDFFinishing.Heading]
        let linkAreas: [NotePDFFinishing.LinkArea]
    }

    private func draw(_ placements: [NotePageFlow.Placement], reportProgress: (Double) -> Void) async throws -> Drawing {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: options.pagePointSize)
        let documentInformation = [kCGPDFContextTitle as String: source.title, kCGPDFContextCreator as String: "Graphite"] as CFDictionary
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, documentInformation) else {
            throw NotePDFExportError.drawingUnavailable
        }
        let placementsByPage = Dictionary(grouping: placements) { placement in placement.pageIndex }
        // An empty note still makes a PDF of one empty page.
        let pageCount = max(1, (placements.map(\.pageIndex).max() ?? 0) + 1)
        var headings: [NotePDFFinishing.Heading] = []
        var linkAreas: [NotePDFFinishing.LinkArea] = []
        for pageIndex in 0..<pageCount {
            context.beginPDFPage(nil)
            for placement in placementsByPage[pageIndex] ?? [] {
                await draw(placement, in: context)
                let block = blocks[placement.blockIndex]
                let area = pageRect(of: placement)
                if let heading = block.outlineHeading, placement.units.lowerBound == 0, placement.sliceTop == 0 {
                    headings.append(NotePDFFinishing.Heading(level: heading.level, title: heading.title, pageIndex: pageIndex, top: area.maxY))
                }
                if !block.webLinks.isEmpty {
                    linkAreas.append(NotePDFFinishing.LinkArea(pageIndex: pageIndex, area: area, links: block.webLinks))
                }
            }
            context.endPDFPage()
            reportProgress(Double(pageIndex + 1) / Double(pageCount))
            await Task.yield()
            if Task.isCancelled {
                context.closePDF()
                throw CancellationError()
            }
        }
        context.closePDF()
        return Drawing(data: data as Data, pageCount: pageCount, headings: headings, linkAreas: linkAreas)
    }

    /// The place's rectangle on the page in PDF coordinates, from the page's bottom left.
    private func pageRect(of placement: NotePageFlow.Placement) -> CGRect {
        let contentRect = options.contentRect
        let top = contentRect.minY + placement.top * options.layoutScale
        let height = placement.height * options.layoutScale
        return CGRect(x: contentRect.minX, y: options.pagePointSize.height - top - height, width: contentRect.width, height: height)
    }

    private func draw(_ placement: NotePageFlow.Placement, in context: CGContext) async {
        let area = pageRect(of: placement)
        let scale = options.layoutScale * placement.scale
        if case .pdfPage = blocks[placement.blockIndex].content {
            if let page = embeddedPage(of: placement.blockIndex) { draw(page, width: options.layoutWidth * scale, top: area.maxY, in: context) }
            return
        }
        let renderer = await settledRenderer(of: placement.blockIndex, units: placement.units).renderer
        renderer.render(rasterizationScale: Self.rasterizationScale) { size, drawView in
            context.saveGState()
            // The view draws upright with its bottom left at the origin; its band from
            // `sliceTop` down goes to the top of the place on the page.
            context.translateBy(x: area.minX, y: area.maxY)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: 0, y: -(size.height - placement.sliceTop))
            let isSlice = placement.sliceTop > Self.sliceTolerance || placement.sliceBottom < size.height - Self.sliceTolerance
            if isSlice {
                context.clip(to: CGRect(x: -size.width, y: size.height - placement.sliceBottom, width: size.width * 3,
                                        height: placement.sliceBottom - placement.sliceTop))
            }
            drawView(context)
            context.restoreGState()
        }
    }

    /// How far, in points, a band may differ from the whole drawing and still be drawn whole:
    /// measured and drawn heights of one view differ by rounding.
    private static let sliceTolerance: CGFloat = 0.5

    /// An embedded PDF's page at `width`, its top at `top`, with its annotations.
    private func draw(_ page: PDFPage, width: CGFloat, top: CGFloat, in context: CGContext) {
        let shownSize = page.shownSize
        guard shownSize.width > 0 else { return }
        let scale = width / shownSize.width
        context.saveGState()
        context.translateBy(x: options.contentRect.minX, y: top - shownSize.height * scale)
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .cropBox, to: context)
        context.restoreGState()
    }
}
