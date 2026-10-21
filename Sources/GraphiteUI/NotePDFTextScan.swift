/**
 * File: NotePDFTextScan.swift
 * ---------------------------
 * Layer: UI
 * Description: What a printed block's Markdown holds besides its words: the vault images drawn inside its text,
 *              loaded before the block is drawn, and its web links, which the finished PDF makes clickable; read with
 *              Foundation's Markdown parser off the main thread.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/10/2026
 */

import Foundation
import GraphiteCore

/// The inline images and web links of a block's Markdown. The reading view's own parser runs on
/// the main actor; links and images are standard Markdown in the prepared text, which
/// Foundation's parser reads anywhere.
struct NotePDFTextScan: Sendable {
    /// Images in the vault drawn inside the text.
    let inlineImageLocations: [URL]
    let webLinks: [NotePDFWebLink]

    /// The Unicode private use area, where the reading view's markers are.
    private static let privateUseScalars: ClosedRange<UInt32> = 0xE000...0xF8FF
    /// Schemes of links a PDF reader opens; Graphite's own links lead nowhere outside the app.
    private static let webSchemes: Set<String> = ["http", "https", "mailto"]

    /// Full Markdown, keeping going past syntax Foundation does not know (math, Graphite's markers).
    private static let parsingOptions = AttributedString.MarkdownParsingOptions(allowsExtendedAttributes: false, interpretedSyntax: .full,
                                                                                failurePolicy: .returnPartiallyParsedIfPossible)

    /// Parses the texts off the main thread.
    static func scanning(_ markdownTexts: [String], root: URL) async -> NotePDFTextScan {
        let candidates = markdownTexts.filter { text in text.contains("](") || text.contains("://") || text.contains("mailto:") }
        guard !candidates.isEmpty else { return NotePDFTextScan(inlineImageLocations: [], webLinks: []) }
        return await Task.detached(priority: .userInitiated) {
            var imageLocations: [URL] = []
            var webLinks: [NotePDFWebLink] = []
            for text in candidates {
                // Text Foundation cannot parse holds no link or image to find.
                let parsed = try? AttributedString(markdown: text, options: parsingOptions, baseURL: root) // Unparsed: no links.
                guard let attributedText = parsed else { continue }
                imageLocations += attributedText.runs.compactMap { run in run.imageURL }.filter { location in isInVault(location, root: root) }
                webLinks += Self.links(in: attributedText)
            }
            return NotePDFTextScan(inlineImageLocations: imageLocations, webLinks: webLinks)
        }.value
    }

    /// Loads the inline images into the reading view's cache, from which its texts draw them
    /// at once (Textual patch 18). An image that cannot be read is left out, as the reading
    /// view leaves it out.
    func loadInlineImages() async {
        for location in inlineImageLocations {
            guard !Task.isCancelled else { return }
            _ = try? await ReadingImageCache.shared.thumbnail(for: URL(fileURLWithPath: location.path), kind: .inline) // An unreadable image is not drawn.
        }
    }

    /// A heading's words without its Markdown, for the PDF's outline.
    static func plainText(of markdown: String, root: URL) async -> String {
        await Task.detached(priority: .userInitiated) {
            guard let attributedText = try? AttributedString(markdown: markdown, options: parsingOptions, baseURL: root) else { // Unparsed: listed as written.
                return markdown
            }
            // Graphite's private-use markers (highlights, colours) are not words.
            let wordScalars = String(attributedText.characters).unicodeScalars.filter { scalar in !privateUseScalars.contains(scalar.value) }
            let words = String(String.UnicodeScalarView(wordScalars))
            return words.trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }

    /// Each web link once per stretch of text it covers, its runs joined.
    private static func links(in attributedText: AttributedString) -> [NotePDFWebLink] {
        var links: [NotePDFWebLink] = []
        var currentText = ""
        var currentDestination: URL?
        for run in attributedText.runs {
            let destination = run.link.flatMap { link in webSchemes.contains(link.scheme?.lowercased() ?? "") ? link : nil }
            if destination != currentDestination {
                if let currentDestination, !currentText.isEmpty { links.append(NotePDFWebLink(text: currentText, destination: currentDestination)) }
                currentText = ""
                currentDestination = destination
            }
            if destination != nil { currentText += String(attributedText[run.range].characters) }
        }
        if let currentDestination, !currentText.isEmpty { links.append(NotePDFWebLink(text: currentText, destination: currentDestination)) }
        return links
    }

    /// Whether a location is a file inside the vault, as the reading view's image loader requires.
    private static func isInVault(_ location: URL, root: URL) -> Bool {
        let normalizedRoot = root.resolvingSymlinksInPath().path + "/"
        return location.isFileURL && URL(fileURLWithPath: location.path).resolvingSymlinksInPath().path.hasPrefix(normalizedRoot)
    }
}
