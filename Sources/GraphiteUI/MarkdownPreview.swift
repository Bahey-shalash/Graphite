import SwiftUI
import Combine
import Textual
import AVKit
import GraphiteCore
import GraphiteIndex
import GraphiteApple

/// Settings that shape how a note reads, gathered so the builder stays independent of views.
struct ReadingConfiguration: Equatable, Sendable {
    /// The widest reading view's column is, in points, with readable line length on. Live
    /// Preview's column is a little narrower.
    static let readableColumnWidth: CGFloat = 760

    var usesReadableLineLength = true
    var usesStrictLineBreaks = false
    var colorsEnabled = true
    var paletteHexByName: [String: String] = [:]
    var showsProperties = true
    /// Property types assigned in `.obsidian/types.json`, which the properties are read with.
    var declaredPropertyTypes: [String: PropertyType] = [:]
    /// The note's name shown as a large title above its content, or nil.
    var inlineTitle: String?
    var textSize: Double = 17
    var drawingVersion = 0
    /// Changes when the index takes in new files; a note with links or embeds not found
    /// yet is built again then.
    var indexVersion = 0
}

/// A reading-view block after links are resolved and files located.
indirect enum RenderedBlock: Identifiable {
    case properties([NoteProperty])
    case markdown(id: Int, text: String)
    case displayMath(id: Int, text: String)
    /// `anchor` is the heading's scroll target: its anchor for the note's first heading with
    /// that anchor, where a link goes, as in Obsidian; a numbered target for a repeated one
    /// (`HeadingScrollRequest.readingScrollTarget`); nil for a heading of an embedded note
    /// and a repeated one in a callout, since scroll targets must be unique.
    case heading(id: Int, level: Int, text: String, anchor: String?)
    case callout(id: Int, type: String, title: String, folding: CalloutFolding, body: [RenderedBlock])
    case video(id: Int, location: URL)
    case audio(id: Int, location: URL, name: String)
    case pdf(id: Int, path: VaultPath, location: URL, options: PDFEmbedOptions)
    case transclusion(id: Int, path: VaultPath, heading: String?, body: [RenderedBlock])
    case base(id: Int, yaml: String)
    case baseFile(id: Int, path: VaultPath, viewName: String?)
    case missingEmbed(id: Int, target: String)
    /// An embedded note that has no block or heading named `subpath`.
    case missingSection(id: Int, path: VaultPath, subpath: String)
    /// An image or drawing on a line of its own.
    case image(id: Int, path: VaultPath, location: URL, displaySize: EmbedDisplaySize?, version: Int)
    /// The note's footnotes, numbered, after its last block.
    case footnotes(id: Int, notes: [RenderedFootnote])

    var id: String {
        switch self {
        case .properties: "properties"
        case .markdown(let id, _), .displayMath(let id, _), .heading(let id, _, _, _), .callout(let id, _, _, _, _), .video(let id, _), .audio(let id, _, _),
             .pdf(let id, _, _, _), .transclusion(let id, _, _, _), .base(let id, _), .baseFile(let id, _, _), .missingEmbed(let id, _), .missingSection(let id, _, _), .image(let id, _, _, _, _),
             .footnotes(let id, _): "block-\(id)"
        }
    }
}

struct RenderedFootnote: Equatable {
    let number: Int
    let text: String

    /// Where a footnote's reference links to, and the anchor its row scrolls to.
    static func anchor(for number: Int) -> String { "footnote-\(number)" }
}

/// Image URL fragment keys Graphite adds for the preview only; the note is unchanged.
enum PreviewImageFragment {
    static let widthKey = "graphite-width"
    static let heightKey = "graphite-height"
    static let versionKey = "graphite-version"

    static func url(for location: URL, displaySize: EmbedDisplaySize?, version: Int) -> URL {
        var components = URLComponents(url: location, resolvingAgainstBaseURL: false)
        var fragmentItems = ["\(versionKey)=\(version)"]
        if let displaySize {
            fragmentItems.append("\(widthKey)=\(displaySize.width)")
            if let height = displaySize.height { fragmentItems.append("\(heightKey)=\(height)") }
        }
        components?.fragment = fragmentItems.joined(separator: "&")
        return components?.url ?? location
    }

    static func displaySize(in location: URL) -> EmbedDisplaySize? {
        var valuesByKey: [String: Double] = [:]
        for item in location.fragment?.split(separator: "&") ?? [] {
            let parts = item.split(separator: "=", maxSplits: 1)
            if parts.count == 2, let number = Double(parts[1]) { valuesByKey[String(parts[0])] = number }
        }
        return valuesByKey[widthKey].map { width in EmbedDisplaySize(width: width, height: valuesByKey[heightKey]) }
    }
}

/// The links reading view makes for Wikilinks and note links, `graphite://open?target=…`,
/// and for footnote references, `graphite://open?footnote=…`, which Graphite follows
/// itself instead of handing them to the system.
enum GraphiteOpenLink {
    static let scheme = "graphite"
    private static let host = "open"
    private static let targetKey = "target"
    private static let footnoteKey = "footnote"
    /// Present on a Markdown link's target, which is relative to the note that contains it
    /// and percent-encoded, unlike a Wikilink target.
    private static let markdownLinkKey = "markdown"

    /// The link as a Markdown link destination. URL strings leave `(` and `)` unescaped, and
    /// CommonMark ends a destination at an unbalanced `)`, which note and file names may
    /// contain; percent-encoded, they mean the same URL.
    static func markdownDestination(target: String, isWiki: Bool = true) -> String {
        var components = URLComponents()
        components.scheme = scheme; components.host = host
        components.queryItems = [URLQueryItem(name: targetKey, value: target)] + (isWiki ? [] : [URLQueryItem(name: markdownLinkKey, value: "1")])
        return markdownDestination(components.string ?? "")
    }

    static func markdownDestination(_ location: URL) -> String {
        markdownDestination(location.absoluteString)
    }

    private static func markdownDestination(_ urlString: String) -> String {
        urlString.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")
    }

    /// The target of a link made by `markdownDestination(target:isWiki:)`, or by Live Preview
    /// for a Wikilink, and whether it is a Wikilink target.
    static func target(of location: URL) -> (target: String, isWiki: Bool)? {
        guard location.scheme == scheme, let queryItems = URLComponents(url: location, resolvingAgainstBaseURL: false)?.queryItems,
              let target = queryItems.first(where: { item in item.name == targetKey })?.value else { return nil }
        return (target, !queryItems.contains { item in item.name == markdownLinkKey })
    }

    /// The link a footnote reference is shown as, to the footnote numbered `number` in the
    /// list at the end of the note.
    static func footnoteDestination(number: Int) -> String {
        var components = URLComponents()
        components.scheme = scheme; components.host = host
        components.queryItems = [URLQueryItem(name: footnoteKey, value: String(number))]
        return components.string ?? ""
    }

    /// The footnote number of a link made by `footnoteDestination(number:)`.
    static func footnoteNumber(of location: URL) -> Int? {
        guard location.scheme == scheme else { return nil }
        return URLComponents(url: location, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { item in item.name == footnoteKey })?.value.flatMap(Int.init)
    }

    /// The target for a Markdown link's destination as written, such as `../Syllabus.md`,
    /// `Lecture.pdf#page=3` or `#Some%20Heading`. The path stays percent-encoded, as link
    /// following expects of a Markdown link (so an encoded `#` in a file name is not taken
    /// for a heading); the heading or page after the `#` is decoded.
    static func markdownLinkTarget(destination: String) -> String {
        let parts = destination.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { return destination }
        return parts[0] + "#" + (parts[1].removingPercentEncoding ?? parts[1])
    }
}

/// Keeps private-use characters written in a note apart from the markers reading view adds
/// (`ObsidianInlineMarkup`), so an icon-font glyph in the note is not turned into a checkbox
/// or removed. Each such character is written as the escape lead followed by a stand-in,
/// and `ObsidianMarkdownParser` puts the original back after it has read the markers.
enum ReadingMarkerEscaping {
    /// `ObsidianInlineMarkup`'s markers, U+E000 to U+E008, and the escape lead, U+E009.
    static let escapedScalarValues: ClosedRange<UInt32> = 0xE000...0xE009
    static let escapeLead: Unicode.Scalar = "\u{E009}"
    /// A character `escapedScalarValues.lowerBound + n` is written as the lead, then the
    /// scalar `standInOffset` above it. Stand-ins follow a lead only when written here.
    private static let standInOffset: UInt32 = 0x10

    static func escaping(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { scalar in escapedScalarValues.contains(scalar.value) }) else { return text }
        var escaped = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if escapedScalarValues.contains(scalar.value), let standIn = Unicode.Scalar(scalar.value + standInOffset) {
                escaped.append(escapeLead)
                escaped.append(standIn)
            } else {
                escaped.append(scalar)
            }
        }
        return String(escaped)
    }

    /// The character an escape lead followed by `standIn` stands for, or nil when `standIn`
    /// is not a stand-in.
    static func original(ofStandIn standIn: Unicode.Scalar) -> Unicode.Scalar? {
        guard standIn.value >= standInOffset, escapedScalarValues.contains(standIn.value - standInOffset) else { return nil }
        return Unicode.Scalar(standIn.value - standInOffset)
    }
}

enum MediaFileKind {
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "webm"]
    static let audioExtensions: Set<String> = ["m4a", "mp3", "wav", "aac", "ogg", "flac", "3gp"]
}

/// A note's reading-view blocks, and whether any Wikilink embed in its text could not be
/// found, so the note is built again once the index knows more files.
struct ReadingViewBuild {
    let blocks: [RenderedBlock]
    let hasUnresolvedEmbeds: Bool
}

/// Builds rendered blocks off the main actor: resolves links against the vault and index,
/// and reads transcluded notes with a size bound. One builder builds one note.
actor ReadingViewBuilder {
    private var nextIdentifier = 0
    private let imageService = ImageFileService()
    /// The note being built; blocks of a note it embeds are built with that note's path.
    private var hostNote: VaultPath?
    private var hasUnresolvedEmbeds = false
    /// Heading anchors given to a heading already, so only the first heading with an anchor
    /// is the scroll target of links to it.
    private var registeredHeadingAnchors: Set<String> = []
    /// How many of the note's own headings outside callouts have each anchor so far, which
    /// numbers them as the outline does.
    private var headingOccurrencesByAnchor: [String: Int] = [:]
    /// Above zero while a callout's body is built. The outline does not list headings in
    /// callouts, so they are not numbered.
    private var calloutDepth = 0

    func build(source: String, note: VaultPath, root: URL, index: VaultIndex, configuration: ReadingConfiguration, allowsTransclusion: Bool = true) async throws -> ReadingViewBuild {
        hostNote = note
        let sourceText = source as NSString
        // Only the frontmatter is parsed here: the body is split into blocks as text, and
        // parsing the whole note with MarkdownSemantics would cost more than the rest of the build.
        let frontmatterLength = FrontmatterLocator.length(in: sourceText)
        var rendered: [RenderedBlock] = []
        if configuration.showsProperties, frontmatterLength > 0,
           let frontmatter = try MarkdownSemantics.parse(sourceText.substring(to: frontmatterLength)).frontmatter,
           let properties = NoteProperties.parse(frontmatter, declaredTypes: configuration.declaredPropertyTypes), !properties.isEmpty {
            rendered.append(.properties(properties))
        }
        // References become raised numbers that link to the list of footnotes at the end.
        let (body, notes) = Footnotes.preparedForReading(sourceText.substring(from: frontmatterLength)) { number in
            "[\(number)](\(GraphiteOpenLink.footnoteDestination(number: number)))"
        }
        rendered += try await render(NotePreviewDocument.blocks(from: body), note: note, root: root, index: index, configuration: configuration, allowsTransclusion: allowsTransclusion)
        if !notes.isEmpty {
            var renderedNotes: [RenderedFootnote] = []
            for footnote in notes {
                renderedNotes.append(RenderedFootnote(number: footnote.number, text: try await prepared(footnote.text, note: note, root: root, index: index, configuration: configuration)))
            }
            rendered.append(.footnotes(id: identifier(), notes: renderedNotes))
        }
        return ReadingViewBuild(blocks: rendered, hasUnresolvedEmbeds: hasUnresolvedEmbeds)
    }

    private func identifier() -> Int { nextIdentifier += 1; return nextIdentifier }

    /// - Parameter allowsTransclusion: False exactly for the body of an embedded note, which
    ///   embeds no further notes so notes that embed each other end.
    private func render(_ blocks: [NotePreviewBlock], note: VaultPath, root: URL, index: VaultIndex, configuration: ReadingConfiguration, allowsTransclusion: Bool) async throws -> [RenderedBlock] {
        var rendered: [RenderedBlock] = []
        for block in blocks {
            switch block {
            case .markdown(let markdown):
                rendered.append(.markdown(id: identifier(), text: try await prepared(markdown, note: note, root: root, index: index, configuration: configuration)))
            case .heading(let level, let text, let anchor):
                rendered.append(.heading(id: identifier(), level: level, text: try await prepared(text, note: note, root: root, index: index, configuration: configuration),
                                         anchor: allowsTransclusion ? scrollTarget(forHeadingWithAnchor: anchor) : nil))
            case .callout(let type, let title, let folding, let body):
                let renderedTitle = try await prepared(title, note: note, root: root, index: index, configuration: configuration)
                calloutDepth += 1
                let renderedBody = try await render(body, note: note, root: root, index: index, configuration: configuration, allowsTransclusion: allowsTransclusion)
                calloutDepth -= 1
                rendered.append(.callout(id: identifier(), type: type, title: renderedTitle, folding: folding, body: renderedBody))
            case .embed(let embed):
                rendered.append(try await renderEmbed(embed, note: note, root: root, index: index, configuration: configuration, allowsTransclusion: allowsTransclusion))
            case .baseDefinition(let yaml):
                rendered.append(.base(id: identifier(), yaml: yaml))
            case .displayMath(let markdown):
                rendered.append(.displayMath(id: identifier(), text: try await prepared(markdown, note: note, root: root, index: index, configuration: configuration)))
            }
        }
        return rendered
    }

    /// What a heading of the note itself is scrolled to by: its anchor for the first heading
    /// with that anchor, which links go to; a repeated one outside callouts is numbered as in
    /// the outline, so each scroll target stays unique; nil for a repeated one in a callout.
    private func scrollTarget(forHeadingWithAnchor anchor: String) -> String? {
        let isFirstWithAnchor = registeredHeadingAnchors.insert(anchor).inserted
        guard calloutDepth == 0 else { return isFirstWithAnchor ? anchor : nil }
        let occurrence = headingOccurrencesByAnchor[anchor, default: 0]
        headingOccurrencesByAnchor[anchor] = occurrence + 1
        if occurrence == 0 { return isFirstWithAnchor ? anchor : nil }
        return HeadingScrollRequest.readingScrollTarget(anchor: anchor, occurrence: occurrence)
    }

    private func renderEmbed(_ embed: EmbedReference, note: VaultPath, root: URL, index: VaultIndex, configuration: ReadingConfiguration, allowsTransclusion: Bool) async throws -> RenderedBlock {
        guard let path = await resolve(embed.target, isWiki: embed.isWiki, note: note, root: root, index: index),
              let location = try? path.url(in: root) else {
            return .missingEmbed(id: identifier(), target: embed.target)
        }
        let fileExtension = path.fileExtension
        let subpath = embed.target.split(separator: "#", maxSplits: 1).dropFirst().first.map(String.init)
        if MediaFileKind.videoExtensions.contains(fileExtension) { return .video(id: identifier(), location: location) }
        if MediaFileKind.audioExtensions.contains(fileExtension) { return .audio(id: identifier(), location: location, name: path.name) }
        switch DocumentKind(path: path) {
        case .base:
            return .baseFile(id: identifier(), path: path, viewName: subpath)
        case .pdf where !(await imageService.isEditableDrawingPDF(at: location)):
            return .pdf(id: identifier(), path: path, location: location, options: subpath.map(PDFEmbedOptions.init(fragment:)) ?? PDFEmbedOptions())
        case .markdown where allowsTransclusion:
            // The note was found, so a note too large to embed, or one that is not UTF-8 text
            // or cannot be read now, is shown as a link to it rather than as missing.
            guard let snapshot = try? AtomicFileWriter().read(location, maximumBytes: NotePreviewDocument.maximumEmbeddedNoteBytes),
                  let transcludedSource = String(data: snapshot.data, encoding: .utf8) else {
                return embeddedNoteLink(to: path, subpath: subpath)
            }
            let transcludedText = transcludedSource as NSString
            let transcludedBody = transcludedText.substring(from: FrontmatterLocator.length(in: transcludedText))
            guard let section = NoteBlocks.embeddedPart(of: transcludedBody, subpath: subpath) else {
                return .missingSection(id: identifier(), path: path, subpath: subpath ?? "")
            }
            let body = try await render(NotePreviewDocument.blocks(from: section), note: path, root: root, index: index, configuration: configuration, allowsTransclusion: false)
            return .transclusion(id: identifier(), path: path, heading: subpath, body: body)
        case .image, .pdf:
            // A PDF reaches here only when it is a Graphite drawing.
            return .image(id: identifier(), path: path, location: location, displaySize: embed.displaySize, version: configuration.drawingVersion)
        default:
            let imageMarkdown = embed.isWiki ? "![[\(embed.target)]]" : "![](\(embed.target))"
            return .markdown(id: identifier(), text: try await prepared(imageMarkdown, note: note, root: root, index: index, configuration: configuration))
        }
    }

    private func embeddedNoteLink(to path: VaultPath, subpath: String?) -> RenderedBlock {
        let label = path.stem + (subpath.map { heading in " > " + heading } ?? "")
        let target = exactTarget(for: path, fragment: subpath)
        return .markdown(id: identifier(), text: "[\(Self.escapedLabel(ReadingMarkerEscaping.escaping(label)))](\(GraphiteOpenLink.markdownDestination(target: target.target, isWiki: target.isWiki)))")
    }

    private func resolve(_ target: String, isWiki: Bool, note: VaultPath, root: URL, index: VaultIndex) async -> VaultPath? {
        for candidate in WikiLinkResolver.directCandidates(target: target, source: note, isWiki: isWiki) {
            if let location = try? candidate.url(in: root), FileManager.default.fileExists(atPath: location.path) { return candidate }
        }
        guard let resolved = try? await index.resolve(target, from: note, isWiki: isWiki), resolved.count == 1 else { return nil }
        return resolved.first
    }

    /// Rewrites Obsidian links and embeds into standard Markdown the renderer understands.
    private func prepared(_ markdown: String, note: VaultPath, root: URL, index: VaultIndex, configuration: ReadingConfiguration) async throws -> String {
        // Wikilinks need `[[`, Markdown embeds `![` and Markdown links `](`; text without any
        // of them needs no link parse, which dominates building a long note.
        guard markdown.contains("[[") || markdown.contains("![") || markdown.contains("](") else { return readingText(markdown, configuration: configuration) }
        // The note's frontmatter was removed before it was split into blocks, so a block that
        // starts with `---` (a heading, then a rule) has none; parsed as it is, the text up to
        // the next rule would be taken for frontmatter and its links left as text.
        let leadingPadding = FrontmatterLocator.length(in: markdown as NSString) > 0 ? "\n" : ""
        let paddingLength = (leadingPadding as NSString).length
        let semantics = try MarkdownSemantics.parse(leadingPadding + markdown)
        let projected = NSMutableString(string: markdown)
        // Links are replaced last first, so earlier ranges stay valid; a link around an image
        // already replaced, as in `[![a](a.png)](b.md)`, no longer has its parsed range.
        var earliestReplacedLocation = Int.max
        // A link whose place in the text could not be found has an empty range; replacing
        // it would insert a second copy instead of replacing the one written.
        for link in semantics.links.reversed() where link.length > 0 {
            let linkRange = NSRange(location: link.location - paddingLength, length: link.length)
            if !link.isWiki, !link.isEmbed {
                if NSMaxRange(linkRange) <= earliestReplacedLocation, let destinationRange = notePathDestinationRange(of: link, in: projected, linkRange: linkRange) {
                    let target = markdownLinkTarget(of: link, in: note)
                    projected.replaceCharacters(in: destinationRange, with: GraphiteOpenLink.markdownDestination(target: target.target, isWiki: target.isWiki))
                    earliestReplacedLocation = linkRange.location
                }
                continue
            }
            let replacement: String
            if link.isEmbed, let path = await resolve(link.target, isWiki: link.isWiki, note: note, root: root, index: index), let location = try? path.url(in: root) {
                var isInlineImage = DocumentKind(path: path) == .image
                if DocumentKind(path: path) == .pdf { isInlineImage = await imageService.isEditableDrawingPDF(at: location) }
                if isInlineImage {
                    let displaySize = link.label.flatMap(EmbedDisplaySize.parse(label:))
                    let imageLocation = PreviewImageFragment.url(for: location, displaySize: displaySize, version: configuration.drawingVersion)
                    replacement = "![\(Self.escapedLabel(path.stem))](\(GraphiteOpenLink.markdownDestination(imageLocation)))"
                } else {
                    // The path found from this note, which may be an embedded one and is where a
                    // Markdown embed's relative path starts.
                    let fragment = link.target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().first
                        .map { subpath in link.isWiki ? String(subpath) : (subpath.removingPercentEncoding ?? String(subpath)) }
                    let target = exactTarget(for: path, fragment: fragment)
                    replacement = "[\(Self.escapedLabel(path.name))](\(GraphiteOpenLink.markdownDestination(target: target.target, isWiki: target.isWiki)))"
                }
            } else if link.isWiki {
                // An embed the index may not know yet is shown as a link until it does.
                if link.isEmbed { hasUnresolvedEmbeds = true }
                let target = linkTarget(of: link, in: note)
                replacement = "[\(Self.escapedLabel(Self.displayText(for: link)))](\(GraphiteOpenLink.markdownDestination(target: target.target, isWiki: target.isWiki)))"
            } else {
                continue
            }
            projected.replaceCharacters(in: linkRange, with: replacement)
            earliestReplacedLocation = linkRange.location
        }
        return readingText(projected as String, configuration: configuration)
    }

    private func readingText(_ markdown: String, configuration: ReadingConfiguration) -> String {
        var text = ObsidianInlineMarkup.preparedForReading(ReadingMarkerEscaping.escaping(markdown), colorsEnabled: configuration.colorsEnabled, paletteHexByName: configuration.paletteHexByName)
        if !configuration.usesStrictLineBreaks { text = ObsidianPreviewText.applyingSoftLineBreaks(to: text) }
        return text
    }

    /// Where a Markdown link's destination is written, when it is a path in the vault such
    /// as `../Syllabus.md` or `#Heading` rather than a web address. The renderer would
    /// resolve such a path against the vault folder instead of the note's own folder. A
    /// reference link, or a destination written with escapes, is left to the renderer.
    private func notePathDestinationRange(of link: NoteLink, in text: NSString, linkRange: NSRange) -> NSRange? {
        let destination = link.target
        guard !destination.isEmpty, destination.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:", options: .regularExpression) == nil,
              // The destination follows `](`, possibly inside `<>`; the same text in the label
              // or in a title after the destination is not it.
              let destinationPattern = try? NSRegularExpression(pattern: "\\]\\([ \\t]*\\n?[ \\t]*<?(" + NSRegularExpression.escapedPattern(for: destination) + ")"),
              let match = destinationPattern.matches(in: text as String, range: linkRange).last else { return nil }
        return match.range(at: 1)
    }

    /// A Markdown link's target for link following, which resolves it from the note being
    /// built. A link in an embedded note is relative to that note, so its path is resolved
    /// here.
    private func markdownLinkTarget(of link: NoteLink, in note: VaultPath) -> (target: String, isWiki: Bool) {
        let target = GraphiteOpenLink.markdownLinkTarget(destination: link.target)
        guard let hostNote, note != hostNote else { return (target, false) }
        let parts = target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let fragment = parts.count == 2 ? parts[1] : nil
        guard !parts[0].isEmpty else { return exactTarget(for: note, fragment: fragment) }
        guard let path = try? note.parent.appending(parts[0].removingPercentEncoding ?? parts[0]) else { return (target, false) }
        return exactTarget(for: path, fragment: fragment)
    }

    /// A Wikilink's target as seen from the note being built: `[[#Heading]]` in an embedded
    /// note means that note's heading, not one of the note that embeds it.
    private func linkTarget(of link: NoteLink, in note: VaultPath) -> (target: String, isWiki: Bool) {
        guard link.target.hasPrefix("#"), let hostNote, note != hostNote else { return (link.target, true) }
        return exactTarget(for: note, fragment: String(link.target.dropFirst()))
    }

    /// A target that names exactly `path` when followed from the note being built: a Markdown
    /// link relative to that note's folder, percent-encoded. A Wikilink to `Folder/Note.md`
    /// would first be looked for next to the note, and a `#` in a file name would start a
    /// heading. `fragment` is the heading, block or page, not encoded.
    private func exactTarget(for path: VaultPath, fragment: String?) -> (target: String, isWiki: Bool) {
        let relativePath = path.relativePath(from: (hostNote ?? path).parent)
        let encodedPath = relativePath.split(separator: "/", omittingEmptySubsequences: false)
            .map { component in component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(component) }
            .joined(separator: "/")
        return (encodedPath + (fragment.map { fragment in "#" + fragment } ?? ""), false)
    }

    /// How Obsidian displays a Wikilink: its alias, "Heading" for a link to a heading in
    /// the same note, "Note > Heading" for another note's heading.
    static func displayText(for link: NoteLink) -> String {
        if let label = link.label, !label.isEmpty { return label }
        let parts = link.target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let noteName = parts[0].hasSuffix(".md") ? String(parts[0].dropLast(3)) : parts[0]
        guard parts.count == 2 else { return noteName }
        let subpath = parts[1].hasPrefix("^") ? String(parts[1].dropFirst()) : parts[1]
        return noteName.isEmpty ? subpath : "\(noteName) > \(subpath)"
    }

    /// Link text shown as written. A backslash is escaped too: one before a bracket, or at
    /// the end, would otherwise escape the bracket that closes the label.
    static func escapedLabel(_ label: String) -> String {
        label.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    }
}

/// A heading to scroll to, with a token so the same heading can be requested twice.
struct HeadingScrollRequest: Equatable {
    /// The heading to show; empty for the top of the note.
    let anchor: String
    /// Which of the headings with `anchor` to show, from zero, for notes where several headings read the same.
    var occurrence: Int = 0
    /// Text to show and mark while editing, such as a search match; the reading view
    /// shows the heading above it instead.
    var textRange: NSRange? = nil
    let token = UUID()

    /// The reading-view scroll target of the `occurrence`th heading with `anchor`. An
    /// anchor is one line of text, so the line break keeps a repeated heading's target
    /// apart from every anchor.
    static func readingScrollTarget(anchor: String, occurrence: Int) -> String {
        occurrence == 0 ? anchor : anchor + "\n" + String(occurrence)
    }

    /// The target this request scrolls reading view to: its numbered heading when the note
    /// has it, otherwise the first heading with its anchor.
    func readingScrollTarget(in blocks: [RenderedBlock]) -> String {
        let numberedTarget = Self.readingScrollTarget(anchor: anchor, occurrence: occurrence)
        let hasNumberedTarget = blocks.contains { block in
            if case .heading(_, _, _, let headingAnchor) = block { return headingAnchor == numberedTarget }
            return false
        }
        return hasNumberedTarget ? numberedTarget : anchor
    }
}

struct MarkdownPreview: View {
    let source: String
    let path: VaultPath
    let root: URL
    let index: VaultIndex
    let configuration: ReadingConfiguration
    @Binding var headingScrollRequest: HeadingScrollRequest?
    /// The last request shown, kept by the note's session so switching tabs or views
    /// does not jump to it again.
    @Binding var handledScrollToken: UUID?
    let navigate: (String, Bool) -> Void
    /// Opens a PDF in the PDF pane at a zero-based page index.
    let openPDF: (VaultPath, Int) -> Void
    let updateProperties: (([NoteProperty]) -> Void)?
    /// Lets bases in the note run; nil shows their YAML.
    var baseContext: BaseEmbedContext? = nil
    /// Folded headings, shared with the editor; nil where headings do not fold.
    var folding: ReadingFolding? = nil
    /// Keeps the last build of the note across switches between reading and editing, which
    /// discard this view; nil builds the note each time it is shown.
    var blocksCache: ReadingBlocksCache? = nil
    @State private var blocks: [RenderedBlock] = []
    @State private var errorMessage: String?
    /// Whether the last build had embeds it could not find, which may appear once indexed.
    @State private var hasMissingEmbeds = false
    /// What `blocks` were built from.
    @State private var shownBuildKey: ReadingBuildKey?
    @State private var mediaPlayers = ReadingMediaPlayers()

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let inlineTitle = configuration.inlineTitle {
                        Text(inlineTitle)
                            .font(.system(size: configuration.textSize * InlineTitleStyle.fontScale, weight: .bold))
                            .accessibilityAddTraits(.isHeader)
                            .padding(.bottom, 6)
                    }
                    ReadingBlocksView(blocks: blocks, root: root, textSize: configuration.textSize, navigate: navigate, scrollToHeading: { anchor in
                        withAnimation { scrollProxy.scrollTo(anchor, anchor: .top) }
                    }, openPDF: openPDF, updateProperties: updateProperties, folding: folding, declaredPropertyTypes: configuration.declaredPropertyTypes)
                    if let errorMessage { Text(errorMessage).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: configuration.usesReadableLineLength ? ReadingConfiguration.readableColumnWidth : .infinity, alignment: .leading)
                .padding(.horizontal, 28).padding(.vertical, 32)
                .frame(maxWidth: .infinity)
            }
            .environment(\.baseEmbedContext, baseContext)
            .environment(\.readingMediaPlayers, mediaPlayers)
            .environment(\.embeddedImageColumnWidth, configuration.usesReadableLineLength ? ReadingConfiguration.readableColumnWidth : nil)
            // Runs again once blocks exist: a note opened by a link or a search match is
            // asked to scroll before it has built anything to scroll to.
            .task(id: "\(blocks.count)-\(headingScrollRequest?.token.uuidString ?? "")") {
                guard let request = headingScrollRequest, request.token != handledScrollToken, !blocks.isEmpty else { return }
                handledScrollToken = request.token
                guard !request.anchor.isEmpty else { return }
                let target = request.readingScrollTarget(in: blocks)
                withAnimation { scrollProxy.scrollTo(target, anchor: .top) }
            }
        }
        .task(id: "\(configuration.drawingVersion)-\(configuration.hashValueForReload)-\(source.hashValue)-\(hasMissingEmbeds ? configuration.indexVersion : -1)") {
            if let shownBuildKey, shownBuildKey.describesBuild(of: source, path: path, root: root, configuration: configuration) { return }
            if blocks.isEmpty, let cachedBuild = blocksCache?.lastBuild, cachedBuild.key.describesBuild(of: source, path: path, root: root, configuration: configuration) {
                show(cachedBuild)
                return
            }
            do {
                // Changes that follow each other quickly are built once; a note just shown
                // has nothing to show yet, so it is built at once.
                if !blocks.isEmpty { try await Task.sleep(for: .milliseconds(150)) }
                let build = try await ReadingViewBuilder().build(source: source, note: path, root: root, index: index, configuration: configuration)
                try Task.checkCancellation()
                let hasMissingEmbeds = Self.containsMissingEmbed(build.blocks) || build.hasUnresolvedEmbeds
                let key = ReadingBuildKey(source: source, path: path, root: root, configuration: configuration, dependsOnIndex: hasMissingEmbeds)
                let cachedBuild = ReadingBlocksCache.Build(key: key, blocks: build.blocks, hasMissingEmbeds: hasMissingEmbeds)
                show(cachedBuild)
                blocksCache?.lastBuild = cachedBuild
            } catch is CancellationError {
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func show(_ build: ReadingBlocksCache.Build) {
        blocks = build.blocks; errorMessage = nil
        hasMissingEmbeds = build.hasMissingEmbeds
        shownBuildKey = build.key
        mediaPlayers.keepPlaybacks(for: Self.mediaLocations(in: build.blocks))
    }
}

/// What a reading-view build depends on.
struct ReadingBuildKey: Equatable {
    let source: String
    let path: VaultPath
    let root: URL
    let drawingVersion: Int
    let renderingHash: Int
    /// The index version of a build that had embeds it could not find; nil when later
    /// indexing cannot change the build.
    let indexVersion: Int?

    init(source: String, path: VaultPath, root: URL, configuration: ReadingConfiguration, dependsOnIndex: Bool) {
        self.source = source; self.path = path; self.root = root
        drawingVersion = configuration.drawingVersion
        renderingHash = configuration.hashValueForReload
        indexVersion = dependsOnIndex ? configuration.indexVersion : nil
    }

    /// Whether building `source` with `configuration` now would give the blocks built for this key.
    func describesBuild(of source: String, path: VaultPath, root: URL, configuration: ReadingConfiguration) -> Bool {
        self.path == path && self.root == root && drawingVersion == configuration.drawingVersion
            && renderingHash == configuration.hashValueForReload && (indexVersion == nil || indexVersion == configuration.indexVersion)
            && self.source == source
    }
}

/// The last reading-view build of one note, kept by the note's session so that switching
/// from editing back to reading shows the note at once instead of building it again.
@MainActor
final class ReadingBlocksCache {
    struct Build {
        let key: ReadingBuildKey
        let blocks: [RenderedBlock]
        let hasMissingEmbeds: Bool
    }

    var lastBuild: Build?

    init() {}
}

extension MarkdownPreview {
    /// The audio and video files the blocks embed.
    static func mediaLocations(in blocks: [RenderedBlock]) -> Set<URL> {
        blocks.reduce(into: Set<URL>()) { locations, block in
            switch block {
            case .video(_, let location), .audio(_, let location, _): locations.insert(location)
            case .callout(_, _, _, _, let body), .transclusion(_, _, _, let body): locations.formUnion(mediaLocations(in: body))
            default: break
            }
        }
    }

    static func containsMissingEmbed(_ blocks: [RenderedBlock]) -> Bool {
        blocks.contains { block in
            switch block {
            case .missingEmbed: true
            case .callout(_, _, _, _, let body), .transclusion(_, _, _, let body): containsMissingEmbed(body)
            default: false
            }
        }
    }
}

extension ReadingConfiguration {
    /// Everything except the drawing version (tracked separately) that changes rendering.
    var hashValueForReload: Int {
        var hasher = Hasher()
        hasher.combine(usesStrictLineBreaks); hasher.combine(colorsEnabled); hasher.combine(showsProperties)
        hasher.combine(paletteHexByName.sorted { firstEntry, secondEntry in firstEntry.key < secondEntry.key }.map { entry in entry.key + entry.value })
        hasher.combine(declaredPropertyTypes.sorted { firstEntry, secondEntry in firstEntry.key < secondEntry.key }.map { entry in entry.key + "=" + entry.value.rawValue })
        return hasher.finalize()
    }
}

/// Renders a list of blocks; used for the note itself, callout bodies, and transclusions.
/// Folded headings in reading view: the same keys as the editor's (`NoteFolding`), so a
/// heading folded while editing is folded when reading, and the other way round.
struct ReadingFolding {
    let foldedKeys: Set<String>
    let toggle: (String) -> Void
}

struct ReadingBlocksView: View {
    let blocks: [RenderedBlock]
    let root: URL
    let textSize: Double
    let navigate: (String, Bool) -> Void
    let scrollToHeading: (String) -> Void
    let openPDF: (VaultPath, Int) -> Void
    let updateProperties: (([NoteProperty]) -> Void)?
    /// Only the note's own top-level blocks fold; callouts and embeds do not.
    var folding: ReadingFolding? = nil
    /// The types the properties block was parsed with, which also decide how it shows them.
    var declaredPropertyTypes: [String: PropertyType] = [:]

    /// Each block with its heading's fold key, and whether a folded heading above hides it.
    private var visibleBlocks: [(block: RenderedBlock, foldKey: String?, hasBody: Bool)] {
        guard let folding else { return blocks.map { block in (block, nil, false) } }
        var result: [(block: RenderedBlock, foldKey: String?, hasBody: Bool)] = []
        var occurrences: [String: Int] = [:]
        var hidingLevel: Int?
        for (blockIndex, block) in blocks.enumerated() {
            var foldKey: String?
            var level: Int?
            if case .heading(_, let headingLevel, let text, _) = block {
                level = headingLevel
                // The editor's key: the heading line as written, and which occurrence it is.
                let base = "h\(headingLevel)|" + String(repeating: "#", count: headingLevel) + " " + text
                let occurrence = occurrences[base, default: 0]
                occurrences[base] = occurrence + 1
                foldKey = base + "|" + String(occurrence)
            }
            if let hidden = hidingLevel {
                if let level, level <= hidden { hidingLevel = nil } else { continue }
            }
            // Something under the heading, before the next heading of its level or higher.
            let hasBody: Bool = {
                guard let level, blockIndex + 1 < blocks.count else { return false }
                if case .heading(_, let nextLevel, _, _) = blocks[blockIndex + 1], nextLevel <= level { return false }
                return true
            }()
            result.append((block, foldKey, hasBody))
            if let level, let foldKey, hasBody, folding.foldedKeys.contains(foldKey) { hidingLevel = level }
        }
        return result
    }

    var body: some View {
        ForEach(visibleBlocks, id: \.block.id) { entry in
            let block = entry.block
            switch block {
            case .properties(let properties):
                PropertiesPanel(properties: properties, update: updateProperties, follow: navigate, declaredTypes: declaredPropertyTypes)
            case .markdown(_, let text):
                ObsidianMarkdownText(markdown: text, root: root, textSize: textSize, navigate: navigate, scrollToHeading: scrollToHeading)
            case .displayMath(_, let text):
                // Centered, as Obsidian shows display math.
                ObsidianMarkdownText(markdown: text, root: root, textSize: textSize, navigate: navigate, scrollToHeading: scrollToHeading)
                    .frame(maxWidth: .infinity)
            case .heading(_, let level, let text, let anchor):
                let heading = ObsidianMarkdownText(markdown: String(repeating: "#", count: level) + " " + text, root: root, textSize: textSize, navigate: navigate, scrollToHeading: scrollToHeading)
                    .overlay(alignment: .leading) {
                        if let folding, let foldKey = entry.foldKey, entry.hasBody {
                            let isFolded = folding.foldedKeys.contains(foldKey)
                            Button { folding.toggle(foldKey) } label: {
                                Image(systemName: isFolded ? "chevron.right" : "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(width: 22, height: 22)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .tint(.secondary)
                            .opacity(isFolded ? 1 : 0.45)
                            .offset(x: -26)
                            .accessibilityLabel(isFolded ? "Unfold \(text)" : "Fold \(text)")
                        }
                    }
                if let anchor { heading.id(anchor) } else { heading }
            case .callout(_, let type, let title, let folding, let body):
                CalloutView(type: type, title: title, folding: folding, root: root, textSize: textSize, navigate: navigate, scrollToHeading: scrollToHeading) {
                    ReadingBlocksView(blocks: body, root: root, textSize: textSize, navigate: navigate, scrollToHeading: scrollToHeading, openPDF: openPDF, updateProperties: nil)
                }
            case .video(_, let location):
                EmbeddedMediaPlayer(location: location)
            case .audio(_, let location, let name):
                EmbeddedAudioPlayer(location: location, name: name)
            case .pdf(_, let path, let location, let options):
                EmbeddedPDFViewer(location: location, startPageNumber: options.startPageNumber, height: options.height.map { height in CGFloat(height) },
                                  openInPane: { pageIndex in openPDF(path, pageIndex) })
            case .transclusion(_, let path, let heading, let body):
                VStack(alignment: .leading, spacing: 10) {
                    Button { navigate(path.rawValue + (heading.map { "#" + $0 } ?? ""), true) } label: {
                        Label(path.stem + (heading.map { " > " + $0 } ?? ""), systemImage: "doc.text").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    ReadingBlocksView(blocks: body, root: root, textSize: textSize, navigate: navigate, scrollToHeading: scrollToHeading, openPDF: openPDF, updateProperties: nil)
                }
                .padding(.leading, 16)
                .overlay(alignment: .leading) { Rectangle().fill(.tint.opacity(0.6)).frame(width: 3) }
            case .base(_, let yaml):
                BaseCodeBlockView(yaml: yaml)
            case .baseFile(_, let path, let viewName):
                BaseFileEmbedView(path: path, viewName: viewName, openWithoutContext: { basePath in navigate(basePath.rawValue, true) })
            case .image(_, let path, let location, let displaySize, let version):
                ReadingImageBlock(path: path, location: location, displaySize: displaySize, version: version)
            case .footnotes(_, let notes):
                VStack(alignment: .leading, spacing: 8) {
                    Divider().padding(.bottom, 4)
                    ForEach(notes, id: \.number) { footnote in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(footnote.number).").font(.system(size: textSize * 0.9).monospacedDigit()).foregroundStyle(.secondary)
                            ObsidianMarkdownText(markdown: footnote.text, root: root, textSize: textSize * 0.9, navigate: navigate, scrollToHeading: scrollToHeading)
                        }
                        .id(RenderedFootnote.anchor(for: footnote.number))
                    }
                }
                .padding(.top, 12)
            case .missingEmbed(_, let target):
                Label("“\(target)” is not in this vault yet.", systemImage: "questionmark.square.dashed")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            case .missingSection(_, let path, let subpath):
                Button { navigate(path.rawValue, true) } label: {
                    Label(NoteBlocks.missingSectionMessage(subpath: subpath, noteName: path.stem), systemImage: "questionmark.square.dashed")
                        .font(.callout).foregroundStyle(.secondary)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// One Markdown run rendered with Obsidian-like styles and Graphite's link handling.
struct ObsidianMarkdownText: View {
    let markdown: String
    @Environment(\.accent) private var accent
    let root: URL
    let textSize: Double
    let navigate: (String, Bool) -> Void
    let scrollToHeading: (String) -> Void

    var body: some View {
        StructuredText(markdown, parser: ObsidianMarkdownParser(baseURL: root, textSize: textSize))
            // StructuredText parses again only when its text changes, and the parse sizes
            // task checkboxes, so a new text size starts a new view.
            .id(textSize)
            .font(.system(size: textSize))
            .textual.textSelection(.enabled)
            .textual.inlineStyle(InlineStyle.default.link(.foregroundColor(accent)))
            .textual.listItemStyle(ObsidianListItemStyle(textSize: textSize))
            .textual.imageAttachmentLoader(VaultImageLoader(root: root))
            .textual.headingStyle(ObsidianHeadingStyle())
            .textual.tableStyle(ObsidianTableStyle())
            .textual.tableCellStyle(ObsidianTableCellStyle())
            .textual.blockQuoteStyle(ObsidianBlockQuoteStyle())
            .tint(accent)
            .environment(\.openURL, Self.linkAction(root: root, navigate: navigate, scrollToHeading: scrollToHeading))
    }

    /// Follows links in rendered Markdown: Wikilinks and note links inside Graphite, files
    /// in the vault by their path, and anything else, such as web pages, with the system.
    /// - Parameter scrollToHeading: Scrolls this view to a heading of its own note; nil
    ///   leaves `#Heading` links to `navigate`.
    static func linkAction(root: URL, navigate: @escaping (String, Bool) -> Void, scrollToHeading: ((String) -> Void)?) -> OpenURLAction {
        OpenURLAction { location in
            if let number = GraphiteOpenLink.footnoteNumber(of: location) {
                scrollToHeading?(RenderedFootnote.anchor(for: number))
                return .handled
            }
            if let link = GraphiteOpenLink.target(of: location) {
                // A block (`#^id`) has no scroll target in reading view; following it shows
                // the heading above the block.
                if link.target.hasPrefix("#"), !link.target.hasPrefix("#^"), let scrollToHeading {
                    scrollToHeading(NotePreviewDocument.anchor(forHeading: String(link.target.dropFirst())))
                } else {
                    navigate(link.target, link.isWiki)
                }
                return .handled
            }
            if location.scheme == GraphiteOpenLink.scheme { return .handled }
            if location.isFileURL {
                // Resolving symbolic links drops `/private` from a path that exists but not from
                // one that does not, so both spellings of each path are compared.
                let rootPaths = Set([root.standardizedFileURL.path, root.standardizedFileURL.resolvingSymlinksInPath().path]).map { path in path + "/" }
                let locationPaths = [location.standardizedFileURL.path, location.standardizedFileURL.resolvingSymlinksInPath().path]
                for locationPath in locationPaths {
                    guard let rootPath = rootPaths.first(where: { rootPath in locationPath.hasPrefix(rootPath) }) else { continue }
                    navigate(String(locationPath.dropFirst(rootPath.count)) + (location.fragment(percentEncoded: false).map { fragment in "#" + fragment } ?? ""), true)
                    break
                }
                return .handled
            }
            return .systemAction
        }
    }
}

/// Parses Markdown with math, then turns Graphite's private color, highlight, and task
/// markers into text attributes and checkboxes.
struct ObsidianMarkdownParser: MarkupParser {
    let baseURL: URL?
    let textSize: Double

    func attributedString(for input: String) throws -> AttributedString {
        // The Markdown parser recurses once per nesting level; a note nested deeper than
        // this would exhaust the stack (see MarkdownNesting), so it is shown as plain text.
        if MarkdownNesting.exceedsSafeDepth(input) { return AttributedString(input) }
        var attributed = try AttributedStringMarkdownParser(baseURL: baseURL, syntaxExtensions: [.math]).attributedString(for: input)
        Self.applyMarkers(start: ObsidianInlineMarkup.colorStartMarker, hexEnd: ObsidianInlineMarkup.colorHexEndMarker, end: ObsidianInlineMarkup.colorEndMarker, to: &attributed) { hex, range, text in
            if let color = Color(graphiteHex: hex) { text[range].foregroundColor = color }
        }
        Self.applyMarkers(start: ObsidianInlineMarkup.highlightStartMarker, hexEnd: nil, end: ObsidianInlineMarkup.highlightEndMarker, to: &attributed) { _, range, text in
            text[range].backgroundColor = Color.yellow.opacity(0.35)
        }
        // A footnote reference is found by its link, not by markers around its number: the
        // references are added to the note's text before `ReadingMarkerEscaping` escapes it,
        // so markers added there would be escaped as the note's own characters.
        var footnoteReferenceRanges: [Range<AttributedString.Index>] = []
        for (link, range) in attributed.runs[\.link] where link.flatMap(GraphiteOpenLink.footnoteNumber(of:)) != nil {
            footnoteReferenceRanges.append(range)
        }
        for range in footnoteReferenceRanges {
            attributed[range].font = .system(size: textSize * 0.7, weight: .semibold)
            attributed[range].baselineOffset = textSize * 0.35
        }
        replaceTaskMarkers(in: &attributed)
        Self.restoreEscapedCharacters(in: &attributed)
        return attributed
    }

    /// A task's marker becomes a checkbox; a completed task's text is dimmed and struck
    /// through, as in Obsidian.
    ///
    /// A long task list is one block, so this makes one pass over the text rather than
    /// searching it again for each task.
    private func replaceTaskMarkers(in text: inout AttributedString) {
        guard let uncheckedMarker = ObsidianInlineMarkup.uncheckedTaskMarker.unicodeScalars.first,
              let checkedMarker = ObsidianInlineMarkup.checkedTaskMarker.unicodeScalars.first else { return }
        let markers: Set<Unicode.Scalar> = [uncheckedMarker, checkedMarker]
        guard text.unicodeScalars.contains(where: { scalar in markers.contains(scalar) }) else { return }
        var completedTaskRanges: [Range<AttributedString.Index>] = []
        for (_, paragraphRange) in text.runs[\.presentationIntent] {
            guard let markerIndex = text.unicodeScalars[paragraphRange].firstIndex(of: checkedMarker) else { continue }
            var contentStart = text.unicodeScalars.index(after: markerIndex)
            while contentStart < paragraphRange.upperBound, text.unicodeScalars[contentStart].properties.isWhitespace { contentStart = text.unicodeScalars.index(after: contentStart) }
            if contentStart < paragraphRange.upperBound { completedTaskRanges.append(contentStart..<paragraphRange.upperBound) }
        }
        for range in completedTaskRanges {
            text[range].strikethroughStyle = .single
            text[range].foregroundColor = .secondary
        }
        var replaced = AttributedString()
        var sliceStart = text.startIndex
        for markerIndex in text.unicodeScalars.indices where markers.contains(text.unicodeScalars[markerIndex]) {
            let markerRange = markerIndex..<text.unicodeScalars.index(after: markerIndex)
            replaced.append(text[sliceStart..<markerIndex])
            var attributes = text[markerRange].runs.first?.attributes ?? AttributeContainer()
            let isChecked = text.unicodeScalars[markerIndex] == checkedMarker
            attributes[AttributeScopes.TextualAttributes.AttachmentAttribute.self] = AnyAttachment(TaskCheckboxAttachment(isChecked: isChecked, pointSize: textSize))
            replaced.append(AttributedString("\u{FFFC}", attributes: attributes))
            sliceStart = markerRange.upperBound
        }
        replaced.append(text[sliceStart..<text.endIndex])
        text = replaced
    }

    /// Puts back the private-use characters of the note that `ReadingMarkerEscaping` kept
    /// apart from the markers, once the markers are gone.
    private static func restoreEscapedCharacters(in text: inout AttributedString) {
        guard text.unicodeScalars.contains(ReadingMarkerEscaping.escapeLead) else { return }
        var restored = AttributedString()
        var sliceStart = text.startIndex
        var scalarIndex = text.unicodeScalars.startIndex
        while scalarIndex < text.unicodeScalars.endIndex {
            let nextIndex = text.unicodeScalars.index(after: scalarIndex)
            guard text.unicodeScalars[scalarIndex] == ReadingMarkerEscaping.escapeLead, nextIndex < text.unicodeScalars.endIndex,
                  let original = ReadingMarkerEscaping.original(ofStandIn: text.unicodeScalars[nextIndex]) else {
                scalarIndex = nextIndex
                continue
            }
            let escapeEnd = text.unicodeScalars.index(after: nextIndex)
            restored.append(text[sliceStart..<scalarIndex])
            let attributes = text[scalarIndex..<escapeEnd].runs.first?.attributes ?? AttributeContainer()
            restored.append(AttributedString(String(original), attributes: attributes))
            sliceStart = escapeEnd
            scalarIndex = escapeEnd
        }
        restored.append(text[sliceStart..<text.endIndex])
        text = restored
    }

    /// Applies attributes between paired markers (outer first, so inner ones win), then
    /// removes the markers.
    ///
    /// Markers are single scalars and are found as scalars: a marker followed by a combining
    /// mark, as in `==\u{0301}e==`, is one Character with it.
    private static func applyMarkers(start: Character, hexEnd: Character?, end: Character, to text: inout AttributedString,
                                     apply: (String, Range<AttributedString.Index>, inout AttributedString) -> Void) {
        guard let startMarker = start.unicodeScalars.first, let endMarker = end.unicodeScalars.first else { return }
        let hexEndMarker = hexEnd?.unicodeScalars.first
        let scalars = Array(text.unicodeScalars)
        guard scalars.contains(startMarker) else { return }
        var openings: [(contentStartOffset: Int, colorToken: String)] = []
        var ranges: [(start: Int, end: Int, colorToken: String)] = []
        var offset = 0
        while offset < scalars.count {
            let scalar = scalars[offset]
            if scalar == startMarker {
                var colorToken = ""
                var contentStart = offset + 1
                if let hexEndMarker, let hexEndOffset = scalars[(offset + 1)...].firstIndex(of: hexEndMarker) {
                    colorToken = String(String.UnicodeScalarView(scalars[(offset + 1)..<hexEndOffset]))
                    contentStart = hexEndOffset + 1
                }
                openings.append((contentStart, colorToken))
                offset = contentStart
                continue
            }
            if scalar == endMarker, let opening = openings.popLast() {
                ranges.append((opening.contentStartOffset, offset, opening.colorToken))
            }
            offset += 1
        }
        for range in ranges.sorted(by: { firstRange, secondRange in firstRange.start < secondRange.start }) where range.end > range.start {
            let lowerBound = text.unicodeScalars.index(text.unicodeScalars.startIndex, offsetBy: range.start)
            let upperBound = text.unicodeScalars.index(text.unicodeScalars.startIndex, offsetBy: range.end)
            apply(range.colorToken, lowerBound..<upperBound, &text)
        }
        // Remove marker scalars (and any hex between start and hex end), last first.
        var removalOffsets: [Range<Int>] = []
        offset = 0
        while offset < scalars.count {
            if scalars[offset] == startMarker {
                let hexEndOffset = hexEndMarker.flatMap { hexEndMarker in scalars[(offset + 1)...].firstIndex(of: hexEndMarker) } ?? offset
                removalOffsets.append(offset..<(hexEndOffset + 1))
                offset = hexEndOffset + 1
                continue
            }
            if scalars[offset] == endMarker { removalOffsets.append(offset..<(offset + 1)) }
            offset += 1
        }
        for removal in removalOffsets.reversed() {
            let lowerBound = text.unicodeScalars.index(text.unicodeScalars.startIndex, offsetBy: removal.lowerBound)
            let upperBound = text.unicodeScalars.index(text.unicodeScalars.startIndex, offsetBy: removal.upperBound)
            text.removeSubrange(lowerBound..<upperBound)
        }
    }
}

/// List items as in Obsidian: a task's checkbox takes the place of its bullet.
struct ObsidianListItemStyle: StructuredText.ListItemStyle {
    let textSize: Double

    func makeBody(configuration: Configuration) -> some View {
        let isTask = isTask(configuration.content)
        HStack(alignment: .firstLineCenter, spacing: textSize * 0.5) {
            if !isTask { configuration.marker }
            configuration.block
        }
        // The checkbox sits where the bullet would be.
        .padding(.leading, isTask ? textSize * 0.55 : 0)
    }

    private func isTask(_ content: AttributedSubstring) -> Bool {
        guard let firstAttachment = content.runs.first?[AttributeScopes.TextualAttributes.AttachmentAttribute.self] else { return false }
        return [true, false].contains { isChecked in firstAttachment == AnyAttachment(TaskCheckboxAttachment(isChecked: isChecked, pointSize: textSize)) }
    }
}

extension VerticalAlignment {
    /// The vertical center of a view's first line of text, which keeps list markers level
    /// with the first line of a wrapped item.
    private enum FirstLineCenterAlignment: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            (context.height - (context[.lastTextBaseline] - context[.firstTextBaseline])) / 2
        }
    }

    static let firstLineCenter = VerticalAlignment(FirstLineCenterAlignment.self)
}

/// A task checkbox drawn inline in reading view.
struct TaskCheckboxAttachment: Attachment {
    let isChecked: Bool
    let pointSize: Double

    var selectionStyle: AttachmentSelectionStyle { .text }
    var description: String { isChecked ? "[x]" : "[ ]" }

    var body: some View {
        Image(systemName: isChecked ? "checkmark.square.fill" : "square")
            .font(.system(size: pointSize * 0.95))
            .foregroundStyle(isChecked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .accessibilityLabel(isChecked ? "Completed task" : "Task")
    }

    func sizeThatFits(_ proposal: ProposedViewSize, in environment: TextEnvironmentValues) -> CGSize {
        CGSize(width: pointSize * 1.35, height: pointSize * 1.05)
    }

    func baselineOffset(in environment: TextEnvironmentValues) -> CGFloat { -pointSize * 0.17 }
}

extension Color {
    /// `#rrggbb` or `#rrggbbaa`, as stored by the Colors syntax.
    init?(graphiteHex hex: String) {
        guard let canonical = TextColorMarkup.canonicalHex(hex) else { return nil }
        let digits = Array(canonical.dropFirst())
        func component(_ position: Int) -> Double { Double(Int(String(digits[position..<position + 2]), radix: 16) ?? 0) / 255 }
        self.init(.sRGB, red: component(0), green: component(2), blue: component(4), opacity: digits.count == 8 ? component(6) : 1)
    }
}

// MARK: Obsidian-like styles

struct ObsidianHeadingStyle: StructuredText.HeadingStyle {
    private static let fontScales: [CGFloat] = [1.8, 1.6, 1.4, 1.27, 1.13, 1.0]
    func makeBody(configuration: Configuration) -> some View {
        let level = min(max(configuration.headingLevel, 1), 6)
        configuration.label
            .textual.fontScale(Self.fontScales[level - 1])
            .textual.blockSpacing(.fontScaled(top: 1.2, bottom: 0.5))
            .fontWeight(.bold)
    }
}

struct ObsidianTableStyle: StructuredText.TableStyle {
    func makeBody(configuration: Configuration) -> some View {
        Overflow { _ in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .textual.tableCellSpacing(horizontal: 1, vertical: 1)
                .textual.tableBackground { layout in
                    Canvas { context, _ in
                        guard layout.numberOfRows > 0 else { return }
                        // The header shading reaches the middle of the gap below it.
                        var headerBounds = layout.rowBounds(0)
                        if let firstDivider = layout.horizontalDividers().first { headerBounds.size.height = firstDivider.midY - headerBounds.minY }
                        context.fill(Path(headerBounds.integral), with: .color(.secondary.opacity(0.12)))
                    }
                }
                .textual.tableOverlay { layout in
                    // Gaps between cells include padding, so draw a hairline in their middle.
                    Canvas { context, _ in
                        let lineColor = GraphicsContext.Shading.color(.secondary.opacity(0.35))
                        for divider in layout.horizontalDividers() {
                            context.fill(Path(CGRect(x: divider.minX, y: divider.midY - 0.5, width: divider.width, height: 1)), with: lineColor)
                        }
                        for divider in layout.verticalDividers() {
                            context.fill(Path(CGRect(x: divider.midX - 0.5, y: divider.minY, width: 1, height: divider.height)), with: lineColor)
                        }
                    }
                }
                .padding(1)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.35), lineWidth: 1))
        }
        .textual.blockSpacing(.init(top: 4, bottom: 12))
    }
}

struct ObsidianTableCellStyle: StructuredText.TableCellStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(configuration.row == 0 ? .semibold : .regular)
            .textual.padding(.fontScaled(top: 0.35, leading: 0.6, bottom: 0.35, trailing: 0.6))
    }
}

struct ObsidianBlockQuoteStyle: StructuredText.BlockQuoteStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5).fill(.tint.opacity(0.7)).frame(width: 3)
            configuration.label.foregroundStyle(.secondary).textual.padding(.horizontal, .fontScaled(0.9))
        }
    }
}

// MARK: Callouts

struct CalloutView<Body: View>: View {
    let type: String
    let title: String
    let folding: CalloutFolding
    let root: URL
    let textSize: Double
    let navigate: (String, Bool) -> Void
    /// Scrolls to a heading of the note that shows the callout; nil leaves `#Heading` links
    /// in the title to `navigate`.
    let scrollToHeading: ((String) -> Void)?
    @ViewBuilder let content: () -> Body
    @Environment(\.accent) private var accent
    @State private var isExpanded: Bool

    init(type: String, title: String, folding: CalloutFolding, root: URL, textSize: Double, navigate: @escaping (String, Bool) -> Void,
         scrollToHeading: ((String) -> Void)? = nil, @ViewBuilder content: @escaping () -> Body) {
        self.type = type; self.title = title; self.folding = folding; self.root = root; self.textSize = textSize; self.navigate = navigate
        self.scrollToHeading = scrollToHeading; self.content = content
        _isExpanded = State(initialValue: folding != .collapsed)
    }

    var body: some View {
        let appearance = CalloutAppearance(type: type)
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if folding != .notFoldable { withAnimation(.snappy) { isExpanded.toggle() } }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: appearance.systemImage).foregroundStyle(appearance.color)
                    // A link in the title takes the tap before the fold button does.
                    StructuredText(title, parser: ObsidianMarkdownParser(baseURL: root, textSize: textSize))
                        .id(textSize)
                        .font(.system(size: textSize).weight(.semibold))
                        .foregroundStyle(appearance.color)
                        .textual.inlineStyle(InlineStyle.default.link(.foregroundColor(accent)))
                        .textual.imageAttachmentLoader(VaultImageLoader(root: root))
                        .environment(\.openURL, ObsidianMarkdownText.linkAction(root: root, navigate: navigate, scrollToHeading: scrollToHeading))
                    if folding != .notFoldable {
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(appearance.color)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(folding == .notFoldable ? "" : (isExpanded ? "Collapses the callout" : "Expands the callout"))
            if isExpanded { content() }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appearance.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Obsidian's callout types, their aliases, colors, and icons.
struct CalloutAppearance {
    let color: Color
    let systemImage: String

    init(type: String) {
        switch type {
        case "abstract", "summary", "tldr": (color, systemImage) = (.cyan, "list.clipboard")
        case "info": (color, systemImage) = (.blue, "info.circle")
        case "todo": (color, systemImage) = (.blue, "checkmark.circle")
        case "tip", "hint", "important": (color, systemImage) = (.teal, "flame")
        case "success", "check", "done": (color, systemImage) = (.green, "checkmark")
        case "question", "help", "faq": (color, systemImage) = (.orange, "questionmark.circle")
        case "warning", "caution", "attention": (color, systemImage) = (.orange, "exclamationmark.triangle")
        case "failure", "fail", "missing": (color, systemImage) = (.red, "xmark")
        case "danger", "error": (color, systemImage) = (.red, "bolt")
        case "bug": (color, systemImage) = (.red, "ladybug")
        case "example": (color, systemImage) = (.purple, "list.bullet")
        case "quote", "cite": (color, systemImage) = (.gray, "quote.opening")
        default: (color, systemImage) = (.blue, "pencil")
        }
    }
}

// MARK: Attachments and media

private struct VaultImageLoader: AttachmentLoader {
    let root: URL
    func attachment(for location: URL, text: String, environment: ColorEnvironmentValues) async throws -> VaultImageAttachment {
        let fileLocation = URL(fileURLWithPath: location.path)
        let normalizedRoot = root.resolvingSymlinksInPath().path + "/"
        guard location.isFileURL, fileLocation.resolvingSymlinksInPath().path.hasPrefix(normalizedRoot) else {
            throw GraphiteError.outsideVault
        }
        let thumbnail = try await ReadingImageCache.shared.thumbnail(for: fileLocation, kind: .inline)
        return VaultImageAttachment(image: thumbnail.image, description: text, displaySize: PreviewImageFragment.displaySize(in: location))
    }
}

private struct VaultImageAttachment: Attachment {
    /// Pixels decoded when the image was loaded, off the main thread, so drawing the text
    /// does not decode the image again.
    let image: CGImage
    let description: String
    /// Obsidian's `|width` or `|widthxheight` sizing.
    let displaySize: EmbedDisplaySize?
    @MainActor var body: some View {
        Image(image, scale: 1, label: Text(description)).resizable().scaledToFit()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, in environment: TextEnvironmentValues) -> CGSize {
        let width = Double(image.width), height = Double(image.height)
        guard width > 0, height > 0 else { return CGSize(width: 300, height: 200) }
        let naturalWidth = displaySize?.fittedWidth(aspectRatio: width / height) ?? width
        let fittedWidth = min(proposal.width ?? naturalWidth, naturalWidth)
        return CGSize(width: fittedWidth, height: fittedWidth * height / width)
    }
    /// Encoded only when the text is copied or exported: showing the image never needs it.
    func pngData() -> Data? { try? ImageEncoding.pngData(from: image) }
}

/// What reading view and Live Preview show an image or drawing file with.
struct ReadingThumbnail: @unchecked Sendable {
    // Sendable by hand only for `image`: a CGImage is immutable once made.
    /// Pixels decoded off the main thread when the file was read, no larger than the place
    /// the image is shown needs, so drawing it decodes nothing.
    let image: CGImage
    /// Width over height, 1 when the image has no size.
    let aspectRatio: CGFloat
    /// Whether the file is a Graphite drawing that can be edited; false for an inline image,
    /// which is not checked.
    let isEditableDrawing: Bool
}

enum ReadingThumbnailKind: String {
    /// An image or drawing on a line of its own, which can be opened for editing.
    case block
    /// An image inside text, drawn by the text renderer.
    case inline

    /// The longest side in pixels, whatever the width the image is shown at. An inline
    /// image is laid out at its pixel size, so its limit also sets how large it appears.
    var maximumDimension: Int { self == .block ? 2400 : 1800 }
}

extension EnvironmentValues {
    /// The widest, in points, a note's column shows an image on a line of its own; nil when
    /// the column is as wide as the window.
    @Entry var embeddedImageColumnWidth: CGFloat? = nil
}

/// The width an image on a line of its own is decoded for.
enum EmbeddedImageDisplayWidth {
    /// The widest the image is shown, in pixels: the note's column, or the narrower width
    /// Obsidian's `|400` gives it. Nil when neither bounds it, and only the kind's longest
    /// side then does.
    static func pixelWidth(columnWidth: CGFloat?, displaySize: EmbedDisplaySize?, displayScale: CGFloat) -> Int? {
        let boundingWidths = [columnWidth, displaySize.map { size in CGFloat(size.width) }].compactMap { width in width }
        guard let narrowestWidth = boundingWidths.min(), narrowestWidth.isFinite, narrowestWidth > 0 else { return nil }
        // A scale below 1 is a view not yet on a screen; it is decoded again once it is.
        let pixelWidth = (narrowestWidth * max(displayScale, 1)).rounded(.up)
        // Past the kind's longest side the width no longer changes what is decoded.
        return Int(min(pixelWidth, CGFloat(ReadingThumbnailKind.block.maximumDimension)))
    }
}

/// Thumbnails already made, so an image scrolled back into view, or a note shown again, is
/// not read and scaled again. An entry is used only while its file has the modification
/// date and size it was made from: saving a drawing makes that drawing again and leaves the
/// note's other images cached.
final class ReadingImageCache: @unchecked Sendable {
    // Sendable by hand: NSCache is thread-safe, and the class has no other mutable state.
    static let shared = ReadingImageCache()

    /// A small share of the device's memory, counted in decoded bytes. NSCache
    /// also empties itself when the system runs short of memory.
    static let defaultTotalCostLimit = Int(min(ProcessInfo.processInfo.physicalMemory / 32, 128 * 1024 * 1024))

    private final class Entry {
        let fileModificationDate: Date
        let fileByteCount: Int
        let thumbnail: ReadingThumbnail

        init(fileModificationDate: Date, fileByteCount: Int, thumbnail: ReadingThumbnail) {
            self.fileModificationDate = fileModificationDate; self.fileByteCount = fileByteCount; self.thumbnail = thumbnail
        }
    }

    private let entries = NSCache<NSString, Entry>()

    init(totalCostLimit: Int = ReadingImageCache.defaultTotalCostLimit) {
        entries.totalCostLimit = totalCostLimit
    }

    /// The thumbnail last made for the file, which may be older than the file; shown while
    /// `thumbnail(for:kind:displayPixelWidth:)` checks it, so a row scrolled back into view
    /// does not show a progress indicator first.
    func lastThumbnail(for location: URL, kind: ReadingThumbnailKind, displayPixelWidth: Int? = nil) -> ReadingThumbnail? {
        entries.object(forKey: Self.key(for: location, kind: kind, displayPixelWidth: displayPixelWidth))?.thumbnail
    }

    /// The file's thumbnail, decoded off the main thread unless the cached one is current.
    /// - Parameter displayPixelWidth: The widest the image is shown, in pixels, which it is
    ///   decoded for; nil to bound only its longest side.
    func thumbnail(for location: URL, kind: ReadingThumbnailKind, displayPixelWidth: Int? = nil) async throws -> ReadingThumbnail {
        let key = Self.key(for: location, kind: kind, displayPixelWidth: displayPixelWidth)
        let attributes = try? FileManager.default.attributesOfItem(atPath: location.path)
        let modificationDate = attributes?[.modificationDate] as? Date
        let byteCount = (attributes?[.size] as? NSNumber)?.intValue
        if let modificationDate, let byteCount, let entry = entries.object(forKey: key),
           entry.fileModificationDate == modificationDate, entry.fileByteCount == byteCount {
            return entry.thumbnail
        }
        let limit = PreviewPixelLimit(maximumPixelDimension: kind.maximumDimension, displayPixelWidth: displayPixelWidth)
        let image = try await ImageFileService().displayImage(at: location, limit: limit)
        let thumbnail = ReadingThumbnail(image: image, aspectRatio: image.height > 0 ? CGFloat(image.width) / CGFloat(image.height) : 1,
                                         isEditableDrawing: kind == .block && DrawingMetadataReader.hasEditableStrokes(at: location))
        if let modificationDate, let byteCount {
            entries.setObject(Entry(fileModificationDate: modificationDate, fileByteCount: byteCount, thumbnail: thumbnail), forKey: key,
                              cost: image.bytesPerRow * image.height)
        }
        return thumbnail
    }

    private static func key(for location: URL, kind: ReadingThumbnailKind, displayPixelWidth: Int?) -> NSString {
        "\(kind.rawValue)|\(displayPixelWidth.map(String.init) ?? "")|\(location.standardizedFileURL.path)" as NSString
    }
}

/// The player of an audio or video embed. It stops when released, so a player no view
/// keeps does not play on unseen.
final class EmbeddedMediaPlayback {
    let location: URL
    let player: AVPlayer

    init(location: URL) {
        self.location = location
        player = AVPlayer(url: location)
    }

    deinit { player.pause() }
}

/// The players of one note's reading view. Its blocks are rows of a lazy stack, which
/// stops showing a row scrolled out of view and may discard it; keeping the players here
/// lets a recording play on while the user reads further down the note.
final class ReadingMediaPlayers {
    private var playbacks: [URL: EmbeddedMediaPlayback] = [:]

    func existingPlayback(for location: URL) -> EmbeddedMediaPlayback? { playbacks[location] }

    func playback(for location: URL) -> EmbeddedMediaPlayback {
        if let playback = playbacks[location] { return playback }
        let playback = EmbeddedMediaPlayback(location: location)
        playbacks[location] = playback
        return playback
    }

    /// Keeps a player that started playing, unless the note keeps one for its file already.
    func keep(_ playback: EmbeddedMediaPlayback) {
        if playbacks[playback.location] == nil { playbacks[playback.location] = playback }
    }

    /// Whether this is the player the note keeps for its file.
    func isKept(_ playback: EmbeddedMediaPlayback) -> Bool {
        playbacks[playback.location] === playback
    }

    /// Releases, and so stops, the players of embeds the note no longer has.
    func keepPlaybacks(for locations: Set<URL>) {
        playbacks = playbacks.filter { location, _ in locations.contains(location) }
    }
}

extension EnvironmentValues {
    @Entry var readingMediaPlayers: ReadingMediaPlayers? = nil
}

/// An inline video: its first frame, name, and length until played, then the system player.
struct EmbeddedMediaPlayer: View {
    let location: URL
    @Environment(\.readingMediaPlayers) private var mediaPlayers
    @State private var playback: EmbeddedMediaPlayback?
    @State private var posterImage: CGImage?
    @State private var aspectRatio: CGFloat = 16 / 9
    @State private var durationSeconds: Double?
    /// False for a video the system cannot play, such as WebM.
    @State private var isPlayable = true

    var body: some View {
        Group {
            if isPlayable {
                ZStack {
                    Color.black
                    if let playback, playback.location == location {
                        VideoPlayer(player: playback.player)
                    } else {
                        poster
                    }
                }
                .aspectRatio(aspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.secondary.opacity(0.3)))
            } else {
                unplayableNotice
            }
        }
        .task(id: location) {
            if playback?.location != location { playback = mediaPlayers?.existingPlayback(for: location) }
            await loadPoster()
        }
        .onDisappear {
            // Outside reading view nothing keeps the player, so the video stops out of view.
            guard let playback, mediaPlayers?.isKept(playback) != true else { return }
            playback.player.pause()
            self.playback = nil
        }
    }

    private var poster: some View {
        Button {
            let newPlayback = mediaPlayers?.playback(for: location) ?? EmbeddedMediaPlayback(location: location)
            playback = newPlayback
            newPlayback.player.play()
        } label: {
            ZStack {
                if let posterImage {
                    Image(decorative: posterImage, scale: 1).resizable().aspectRatio(contentMode: .fit)
                }
                Image(systemName: "play.fill")
                    .font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 64, height: 64).background(.black.opacity(0.55), in: Circle())
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Text(location.lastPathComponent).lineLimit(1)
                        Spacer()
                        if let durationSeconds {
                            Text(Duration.seconds(durationSeconds).formatted(.time(pattern: durationSeconds >= 3600 ? .hourMinuteSecond : .minuteSecond)))
                                .monospacedDigit()
                        }
                    }
                    .font(.caption.weight(.medium)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play \(location.lastPathComponent)")
    }

    /// Shown instead of a play button that could not play; the file can still be opened
    /// in another app.
    private var unplayableNotice: some View {
        HStack(spacing: 12) {
            Label("“\(location.lastPathComponent)” can't be played in Graphite.", systemImage: "film")
                .font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            ShareLink(item: location) { Label("Open In…", systemImage: "square.and.arrow.up") }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private func loadPoster() async {
        let asset = AVURLAsset(url: location)
        if let isPlayable = try? await asset.load(.isPlayable), !isPlayable {
            self.isPlayable = false
            return
        }
        isPlayable = true
        if let duration = try? await asset.load(.duration), duration.seconds.isFinite { durationSeconds = duration.seconds }
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let (naturalSize, transform) = try? await track.load(.naturalSize, .preferredTransform) {
            let displayedSize = naturalSize.applying(transform)
            if abs(displayedSize.height) > 0 { aspectRatio = abs(displayedSize.width) / abs(displayedSize.height) }
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1600, height: 1600)
        // A frame a little way in avoids the black or title frames recordings often start with.
        let length = durationSeconds ?? 0
        let posterTime = CMTime(seconds: min(length / 2, max(1, min(length * 0.05, 20))), preferredTimescale: 600)
        posterImage = try? await generator.image(at: posterTime).image
    }
}

/// A compact player for audio embeds such as lecture recordings.
struct EmbeddedAudioPlayer: View {
    let location: URL
    let name: String
    @Environment(\.readingMediaPlayers) private var mediaPlayers
    @State private var playback: EmbeddedMediaPlayback?
    @State private var isPlaying = false
    /// Playback reached the end, so Play starts from the beginning.
    @State private var hasFinished = false
    private static let endToleranceSeconds = 0.25
    @State private var elapsedSeconds: Double = 0
    @State private var durationSeconds: Double = 0
    @State private var timeObserver: Any?

    private var player: AVPlayer? { playback?.player }

    var body: some View {
        HStack(spacing: 12) {
            Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill") { togglePlayback() }
                .labelStyle(.iconOnly).font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.subheadline.weight(.medium)).lineLimit(1)
                Slider(value: Binding(get: { elapsedSeconds }, set: { newValue in
                    elapsedSeconds = newValue
                    player?.seek(to: CMTime(seconds: newValue, preferredTimescale: 600))
                }), in: 0...max(durationSeconds, 1))
                HStack {
                    Text(Duration.seconds(elapsedSeconds).formatted(.time(pattern: .minuteSecond)))
                    Spacer()
                    Text(Duration.seconds(durationSeconds).formatted(.time(pattern: .minuteSecond)))
                }
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .task(id: location) {
            // A row shown again, after it was scrolled out of view, finds its player where it was.
            // The note keeps a player once it plays, so rows never played hold none.
            let audioPlayback = playback?.location == location ? playback : nil
            let currentPlayback = audioPlayback ?? mediaPlayers?.existingPlayback(for: location) ?? EmbeddedMediaPlayback(location: location)
            playback = currentPlayback
            let audioPlayer = currentPlayback.player
            isPlaying = audioPlayer.rate != 0
            let currentSeconds = audioPlayer.currentTime().seconds
            elapsedSeconds = currentSeconds.isFinite ? currentSeconds : 0
            if let duration = try? await audioPlayer.currentItem?.asset.load(.duration) { durationSeconds = duration.seconds.isFinite ? duration.seconds : 0 }
            // The view may have gone while the duration loaded; its observer would never be removed.
            guard !Task.isCancelled else { return }
            if let timeObserver { audioPlayer.removeTimeObserver(timeObserver) }
            timeObserver = audioPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { time in
                Task { @MainActor in elapsedSeconds = time.seconds }
            }
            // The button follows the player, which stops by itself at the end of the
            // recording or when a call or another app interrupts it.
            // The player is asked rather than the reported status, which may be older than a tap.
            for await _ in audioPlayer.publisher(for: \.timeControlStatus).values {
                guard isPlaying, audioPlayer.rate == 0 else { continue }
                isPlaying = false
                let currentSeconds = audioPlayer.currentTime().seconds
                hasFinished = durationSeconds > 0 && currentSeconds >= durationSeconds - Self.endToleranceSeconds
            }
        }
        // Playback goes on out of view while the note keeps the player; one it does not keep,
        // such as in Live Preview, stops as the row goes.
        .onDisappear {
            if let timeObserver { player?.removeTimeObserver(timeObserver) }
            timeObserver = nil
            guard let playback, mediaPlayers?.isKept(playback) != true else { return }
            playback.player.pause()
            isPlaying = false
            self.playback = nil
        }
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            // Play after the end starts the recording again, as in other players.
            if hasFinished || (durationSeconds > 0 && player.currentTime().seconds >= durationSeconds - Self.endToleranceSeconds) {
                player.seek(to: .zero); elapsedSeconds = 0
            }
            if let playback { mediaPlayers?.keep(playback) }
            player.play()
        }
        hasFinished = false
        isPlaying.toggle()
    }
}


/// What reading view can do with an image. Closures cannot be compared, so two values are
/// equal when the same workspace provides them with the same abilities; views that read
/// them then do not update each time the note is drawn again.
struct ReadingImageActions: Equatable {
    let providerIdentity: ObjectIdentifier
    /// Shows an image from a note full screen, where it can be zoomed.
    let viewImage: (VaultPath) -> Void
    /// Opens a Graphite drawing in the drawing editor; nil where drawings cannot be edited.
    let editDrawing: ((VaultPath) -> Void)?

    static func == (leftActions: ReadingImageActions, rightActions: ReadingImageActions) -> Bool {
        leftActions.providerIdentity == rightActions.providerIdentity && (leftActions.editDrawing == nil) == (rightActions.editDrawing == nil)
    }
}

extension EnvironmentValues {
    @Entry var readingImageActions: ReadingImageActions? = nil
}

/// An image or drawing on its own line in reading view.
private struct ReadingImageBlock: View {
    let path: VaultPath
    let location: URL
    let displaySize: EmbedDisplaySize?
    let version: Int
    @Environment(\.readingImageActions) private var imageActions
    @Environment(\.embeddedImageColumnWidth) private var columnWidth
    @Environment(\.displayScale) private var displayScale
    @State private var loadedThumbnail: ReadingThumbnail?
    @State private var didFail = false

    private var displayPixelWidth: Int? {
        EmbeddedImageDisplayWidth.pixelWidth(columnWidth: columnWidth, displaySize: displaySize, displayScale: displayScale)
    }

    var body: some View {
        Group {
            if let thumbnail = loadedThumbnail ?? (didFail ? nil : ReadingImageCache.shared.lastThumbnail(for: location, kind: .block, displayPixelWidth: displayPixelWidth)) {
                EmbeddedImageView(image: thumbnail.image, aspectRatio: thumbnail.aspectRatio,
                                  displayWidth: displaySize.map { size in CGFloat(size.fittedWidth(aspectRatio: thumbnail.aspectRatio)) },
                                  edit: thumbnail.isEditableDrawing ? imageActions?.editDrawing.map { editDrawing in { editDrawing(path) } } : nil,
                                  view: imageActions.map { imageActions in { imageActions.viewImage(path) } })
            } else if didFail {
                Label("“\(path.name)” can't be shown.", systemImage: "photo").font(.callout).foregroundStyle(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .task(id: "\(location.path)-\(version)-\(displayPixelWidth ?? 0)") {
            do {
                loadedThumbnail = try await ReadingImageCache.shared.thumbnail(for: location, kind: .block, displayPixelWidth: displayPixelWidth)
            } catch {
                didFail = true
            }
        }
    }
}
