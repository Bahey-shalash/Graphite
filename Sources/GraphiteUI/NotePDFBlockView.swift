/**
 * File: NotePDFBlockView.swift
 * ----------------------------
 * Layer: UI
 * Description: A printed block, or a run of its parts, drawn by the reading view's own views at the page's
 *              layout width, in light colours and without anything that only works on screen.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/10/2026
 */

import SwiftUI
import GraphiteCore

/// The fonts and colours a note is printed with: the vault's fonts, Graphite's light colours
/// whatever the app's theme, and the person's accent for links.
struct NotePDFAppearance {
    let typography: NoteTypography
    let codeColorTheme: CodeColorTheme
    let accent: Color
}

/// One printed block with only the parts in `units`, as the reading view draws them.
struct NotePDFBlockView: View {
    let block: NotePDFBlock
    let units: Range<Int>
    let root: URL
    let layoutWidth: CGFloat
    let typography: NoteTypography

    private var textSize: Double { NotePDFOptions.layoutTextSize }

    var body: some View {
        content.frame(width: layoutWidth, alignment: .leading)
    }

    @ViewBuilder private var content: some View {
        switch block.content {
        case .title(let title):
            Text(title)
                .font(InlineTitleStyle.swiftUIFont(textSize: textSize, typography: typography, theme: nil))
                .padding(.bottom, 6)
        case .reading(.properties(let properties)):
            NotePDFProperties(properties: properties, textSize: textSize)
        case .reading(let renderedBlock):
            blocks([renderedBlock])
        case .section(let sectionUnits):
            ObsidianMarkdownText(markdown: sectionUnits.markdown(forUnits: units), root: root, textSize: textSize,
                                 navigate: { _, _ in }, scrollToHeading: { _ in })
        case .callout(let type, let title, let body):
            blocks([.callout(id: 0, type: type, title: title, folding: .notFoldable, body: Array(body[units.clamped(to: body.indices)]))])
        case .transclusion(let path, let heading, let body):
            blocks([.transclusion(id: 0, path: path, heading: heading, body: Array(body[units.clamped(to: body.indices)]))])
        case .footnotes(let notes):
            blocks([.footnotes(id: 0, notes: Array(notes[units.clamped(to: notes.indices)]))])
        case .picture(let thumbnail, let displaySize):
            EmbeddedImageView(image: thumbnail.image, aspectRatio: thumbnail.aspectRatio,
                              displayWidth: displaySize.map { size in CGFloat(size.fittedWidth(aspectRatio: thumbnail.aspectRatio)) },
                              edit: nil, view: nil)
        case .base(let base):
            NotePDFBaseView(base: base, units: units)
        case .pdfPage:
            // Drawn by the renderer from the PDF itself, which keeps its text as text.
            Color.clear
        case .fileName(let name, let systemImage):
            Label(name, systemImage: systemImage)
                .font(.system(size: textSize * 0.9))
                .foregroundStyle(.secondary)
        }
    }

    private func blocks(_ renderedBlocks: [RenderedBlock]) -> some View {
        ReadingBlocksView(blocks: renderedBlocks, root: root, textSize: textSize, navigate: { _, _ in }, scrollToHeading: { _ in },
                          openPDF: { _, _ in }, updateProperties: nil)
    }
}

/// The note's properties on paper: each name and its value as text. The reading view's panel
/// edits its values in text fields, platform views that a drawing cannot hold.
private struct NotePDFProperties: View {
    let properties: [NoteProperty]
    let textSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Properties").font(.system(size: textSize * 1.1, weight: .semibold)).padding(.bottom, 4)
            ForEach(properties) { property in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(property.key).foregroundStyle(.secondary).frame(width: textSize * 9, alignment: .leading)
                    Text(property.value.displayText)
                }
                .font(.system(size: textSize * 0.9))
            }
        }
        .padding(.bottom, 8)
    }
}

/// A printed block in the environment it is printed in, the one view type the renderer draws.
struct NotePDFPrintedBlock: View {
    let block: NotePDFBlock
    let units: Range<Int>
    let root: URL
    let layoutWidth: CGFloat
    let appearance: NotePDFAppearance

    var body: some View {
        NotePDFBlockView(block: block, units: units, root: root, layoutWidth: layoutWidth, typography: appearance.typography)
            .printedNoteEnvironment(appearance, layoutWidth: layoutWidth)
    }
}

extension View {
    /// The environment a printed block is drawn in: light colours and Graphite's own theme
    /// whatever the app shows, the vault's fonts, and text that is drawn rather than
    /// selectable, as nothing on paper can be tapped.
    func printedNoteEnvironment(_ appearance: NotePDFAppearance, layoutWidth: CGFloat) -> some View {
        self
            .environment(\.colorScheme, .light)
            .environment(\.noteTheme, nil)
            .environment(\.noteTypography, appearance.typography)
            .environment(\.codeColorTheme, appearance.codeColorTheme)
            .environment(\.accent, appearance.accent)
            .tint(appearance.accent)
            // Not selectable, and code and wide tables wrap: paper does not scroll.
            .environment(\.readingIsPrinted, true)
            .environment(\.embeddedImageColumnWidth, layoutWidth)
    }
}
