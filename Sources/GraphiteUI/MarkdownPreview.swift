import SwiftUI
import Combine
import Textual
import AVKit
import GraphiteCore
import GraphiteIndex
import GraphiteApple

/// Settings that shape how a note reads, gathered so the builder stays independent of views.
struct ReadingConfiguration: Equatable, Sendable {
    /// The widest the reading view's text is, in points, with readable line length on: the
    /// width of Live Preview's text (its 740-point column less the text container's 5-point
    /// padding on each side), so the text stays in place when a note switches between
    /// reading and writing.
    static let readableColumnWidth: CGFloat = 730
    /// The least room beside the text: Live Preview's 28-point inset and its 5-point padding.
    static let minimumHorizontalMargin: CGFloat = 33

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
    /// Derived source-word mapping is needed only for a note with a reading session.
    var mapsReadAloudSourceLocations = false
    /// Code block languages the vault's community plugins draw; such blocks are drawn by
    /// their plugin instead of shown as code.
    var pluginCodeBlockLanguages: Set<String> = []
    /// Whether community plugins change how notes read (Markdown post-processors); each
    /// run of Markdown is then offered to them.
    var runsPluginPostProcessors = false
    /// Whether Wikilinks no file answers are marked, for a theme's unresolved link color.
    var marksUnresolvedLinks = false
}

/// A reading-view block after links are resolved and files located.
indirect enum RenderedBlock: Identifiable, Sendable {
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
    /// A code block a community plugin draws, such as a Dataview or Tasks query. `note` is
    /// the note the block is written in (an embedded note's own path), and `firstLine` the
    /// zero-based line of its opening fence there, nil when not known.
    case pluginCodeBlock(id: Int, language: String, source: String, note: VaultPath, firstLine: Int?, lineCount: Int)
    /// A run of Markdown offered to plugins' post-processors: `text` is Graphite's own
    /// rendering of it, shown unless a plugin changes the section.
    case pluginSection(id: Int, text: String, request: CommunityPluginReadingBlockRequest)

    var id: String {
        switch self {
        case .properties: "properties"
        case .markdown(let id, _), .displayMath(let id, _), .heading(let id, _, _, _), .callout(let id, _, _, _, _), .video(let id, _), .audio(let id, _, _),
             .pdf(let id, _, _, _), .transclusion(let id, _, _, _), .base(let id, _), .baseFile(let id, _, _), .missingEmbed(let id, _), .missingSection(let id, _, _), .image(let id, _, _, _, _),
             .footnotes(let id, _), .pluginCodeBlock(let id, _, _, _, _, _), .pluginSection(let id, _, _): "block-\(id)"
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
    /// Present on a Wikilink no file answers, which a theme colors as unresolved.
    private static let unresolvedKey = "unresolved"

    /// The link's destination marked as unresolved.
    static func markingUnresolved(_ destination: String) -> String {
        destination + (destination.contains("?") ? "&" : "?") + unresolvedKey + "=1"
    }

    static func isUnresolved(_ location: URL) -> Bool {
        URLComponents(url: location, resolvingAgainstBaseURL: false)?.queryItems?.contains { item in item.name == unresolvedKey } == true
    }

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
    /// `ObsidianInlineMarkup`'s markers, U+E000 to U+E008 and U+E00A to U+E00B, and the
    /// escape lead, U+E009.
    static let escapedScalarValues: ClosedRange<UInt32> = 0xE000...0xE00B
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
struct ReadingViewBuild: Sendable {
    let blocks: [RenderedBlock]
    let hasUnresolvedEmbeds: Bool
    /// Where each of the note's own top-level blocks starts in its text.
    var blockLocations: [ReadingBlockLocation] = []
    var readingSourceTokensByBlock: [String: [ReadAloudSourceToken]] = [:]
}

/// Where one of the reading view's top-level blocks starts in the note's text, and for a
/// run of Markdown where each of its lines does, to keep the note's place when it switches
/// between reading and writing.
struct ReadingBlockLocation: Equatable, Sendable {
    let blockIdentifier: String
    /// UTF-16 offsets in the note, frontmatter included.
    let noteOffset: Int
    let lineNoteOffsets: [Int]
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
        let readableBody = Footnotes.preparedForReadingKeepingOffsets(sourceText.substring(from: frontmatterLength)) { number in
            "[\(number)](\(GraphiteOpenLink.footnoteDestination(number: number)))"
        }
        let taskSource = TaskSource(noteText: source) { bodyOffset in
            readableBody.offsets.originalOffset(of: bodyOffset).map { offset in offset + frontmatterLength }
        }
        let locatedBlocks = Self.sectioned(NotePreviewDocument.locatedBlocks(from: readableBody.text, pluginCodeBlockLanguages: configuration.pluginCodeBlockLanguages),
                                           for: configuration)
        let renderedBody = try await render(locatedBlocks, note: note, root: root, index: index, configuration: configuration,
                                            allowsTransclusion: allowsTransclusion, taskSource: taskSource)
        // Each located block renders as one block, in order.
        var blockLocations = rendered.map { block in ReadingBlockLocation(blockIdentifier: block.id, noteOffset: 0, lineNoteOffsets: []) }
        for (locatedBlock, renderedBlock) in zip(locatedBlocks, renderedBody) {
            blockLocations.append(ReadingBlockLocation(blockIdentifier: renderedBlock.id,
                                                       noteOffset: taskSource.noteOffset(locatedBlock.startOffset) ?? frontmatterLength + locatedBlock.startOffset,
                                                       lineNoteOffsets: locatedBlock.lineStartOffsets.compactMap(taskSource.noteOffset)))
        }
        rendered += renderedBody
        if !readableBody.notes.isEmpty {
            var renderedNotes: [RenderedFootnote] = []
            for footnote in readableBody.notes {
                renderedNotes.append(RenderedFootnote(number: footnote.number, text: try await prepared(footnote.text, note: note, root: root, index: index, configuration: configuration)))
            }
            rendered.append(.footnotes(id: identifier(), notes: renderedNotes))
        }
        // Narration is bounded independently from preview. Unsupported or oversized
        // notes still render; they simply carry no unsafe source highlight mapping.
        var readingSourceTokensByBlock: [String: [ReadAloudSourceToken]] = [:]
        if configuration.mapsReadAloudSourceLocations, source.utf16.count <= ReadAloudDocument.maximumSourceUTF16Count {
            do {
                let spokenDocument = try ReadAloudDocument.markdown(source, paletteHexByName: configuration.paletteHexByName)
                let tokens = ReadAloudSourceToken.tokens(in: spokenDocument)
                readingSourceTokensByBlock = sourceTokens(tokens, for: locatedBlocks, rendered: renderedBody,
                                                         endOffset: readableBody.text.utf16.count, taskSource: taskSource)
            } catch is CancellationError { throw CancellationError() }
            catch { /* Preview remains available when narration cannot map this note. */ }
        }
        return ReadingViewBuild(blocks: rendered, hasUnresolvedEmbeds: hasUnresolvedEmbeds, blockLocations: blockLocations,
                                readingSourceTokensByBlock: readingSourceTokensByBlock)
    }

    private func sourceTokens(_ tokens: [ReadAloudSourceToken], for locatedBlocks: [NotePreviewDocument.LocatedBlock],
                              rendered: [RenderedBlock], endOffset: Int, taskSource: TaskSource) -> [String: [ReadAloudSourceToken]] {
        var tokensByBlock: [String: [ReadAloudSourceToken]] = [:]
        for (blockIndex, pair) in zip(locatedBlocks, rendered).enumerated() {
            let (located, block) = pair
            let nextOffset = blockIndex + 1 < locatedBlocks.count ? locatedBlocks[blockIndex + 1].startOffset : endOffset
            guard let start = taskSource.noteOffset(located.startOffset),
                  let end = taskSource.noteOffset(nextOffset), end >= start else { continue }
            var lowerBound = 0
            var upperBound = tokens.count
            while lowerBound < upperBound {
                let middleIndex = lowerBound + (upperBound - lowerBound) / 2
                if tokens[middleIndex].sourceRange.location < start { lowerBound = middleIndex + 1 }
                else { upperBound = middleIndex }
            }
            let blockTokens = tokens[lowerBound...].prefix { token in token.sourceRange.location < end }
                .filter { token in NSMaxRange(token.sourceRange) <= end }
            switch block {
            case .markdown, .heading, .displayMath:
                tokensByBlock[block.id] = blockTokens
            case .callout(_, _, _, _, let body):
                let titleEnd = located.body.first.flatMap { child in taskSource.noteOffset(child.startOffset) } ?? end
                tokensByBlock[block.id] = blockTokens.filter { token in NSMaxRange(token.sourceRange) <= titleEnd }
                tokensByBlock.merge(sourceTokens(blockTokens, for: located.body, rendered: body, endOffset: nextOffset,
                                                 taskSource: taskSource), uniquingKeysWith: { existing, _ in existing })
            default: break
            }
        }
        return tokensByBlock
    }

    private func identifier() -> Int { nextIdentifier += 1; return nextIdentifier }

    /// While plugins change how notes read, runs of Markdown are divided into Obsidian's
    /// sections, so a plugin's change shows in the section it changed and the rest of the
    /// run stays Graphite's.
    private static func sectioned(_ blocks: [NotePreviewDocument.LocatedBlock], for configuration: ReadingConfiguration) -> [NotePreviewDocument.LocatedBlock] {
        configuration.runsPluginPostProcessors ? NotePreviewDocument.dividedIntoSections(blocks) : blocks
    }

    /// The text of the note a run of blocks was split from, in which their tasks are found.
    private struct TaskSource {
        /// The whole note, frontmatter included, which a tap on a checkbox changes.
        let noteText: String
        /// Where a place in the body the blocks were split from is in `noteText`; nil for
        /// text the note does not have, such as a footnote's number.
        let noteOffset: (_ bodyOffset: Int) -> Int?

        /// The zero-based line of the note on which a place in the body is.
        func noteLine(ofBodyOffset bodyOffset: Int) -> Int? {
            guard let offset = noteOffset(bodyOffset) else { return nil }
            let prefix = (noteText as NSString).substring(to: min(offset, (noteText as NSString).length))
            return prefix.utf16.reduce(0) { lineCount, codeUnit in codeUnit == 10 ? lineCount + 1 : lineCount }
        }
    }

    /// - Parameter allowsTransclusion: False exactly for the body of an embedded note, which
    ///   embeds no further notes so notes that embed each other end.
    private func render(_ blocks: [NotePreviewDocument.LocatedBlock], note: VaultPath, root: URL, index: VaultIndex, configuration: ReadingConfiguration,
                        allowsTransclusion: Bool, taskSource: TaskSource) async throws -> [RenderedBlock] {
        var rendered: [RenderedBlock] = []
        for locatedBlock in blocks {
            switch locatedBlock.block {
            case .markdown(let markdown):
                let text = try await prepared(markdown, note: note, root: root, index: index, configuration: configuration) { lineIndex, status in
                    guard locatedBlock.lineStartOffsets.indices.contains(lineIndex), let lineStart = taskSource.noteOffset(locatedBlock.lineStartOffsets[lineIndex]) else { return nil }
                    return ReadingTasks.location(ofTaskStartingAt: lineStart, status: status, in: taskSource.noteText)
                }
                if configuration.runsPluginPostProcessors {
                    let request = CommunityPluginReadingBlockRequest(kind: .section, source: markdown, note: note,
                                                                     firstLine: taskSource.noteLine(ofBodyOffset: locatedBlock.startOffset),
                                                                     lineCount: max(1, locatedBlock.lineStartOffsets.count))
                    rendered.append(.pluginSection(id: identifier(), text: text, request: request))
                } else {
                    rendered.append(.markdown(id: identifier(), text: text))
                }
            case .heading(let level, let text, let anchor):
                rendered.append(.heading(id: identifier(), level: level, text: try await prepared(text, note: note, root: root, index: index, configuration: configuration),
                                         anchor: allowsTransclusion ? scrollTarget(forHeadingWithAnchor: anchor) : nil))
            case .callout(let type, let title, let folding, _):
                let renderedTitle = try await prepared(title, note: note, root: root, index: index, configuration: configuration)
                calloutDepth += 1
                let renderedBody = try await render(locatedBlock.body, note: note, root: root, index: index, configuration: configuration,
                                                    allowsTransclusion: allowsTransclusion, taskSource: taskSource)
                calloutDepth -= 1
                rendered.append(.callout(id: identifier(), type: type, title: renderedTitle, folding: folding, body: renderedBody))
            case .embed(let embed):
                rendered.append(try await renderEmbed(embed, note: note, root: root, index: index, configuration: configuration, allowsTransclusion: allowsTransclusion))
            case .baseDefinition(let yaml):
                rendered.append(.base(id: identifier(), yaml: yaml))
            case .displayMath(let markdown):
                rendered.append(.displayMath(id: identifier(), text: try await prepared(markdown, note: note, root: root, index: index, configuration: configuration)))
            case .pluginCodeBlock(let language, let source):
                rendered.append(.pluginCodeBlock(id: identifier(), language: language, source: source, note: note,
                                                 firstLine: taskSource.noteLine(ofBodyOffset: locatedBlock.startOffset), lineCount: locatedBlock.lineCount))
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
            let transcludedFrontmatterLength = FrontmatterLocator.length(in: transcludedText)
            guard let section = NoteBlocks.locatedEmbeddedPart(of: transcludedText.substring(from: transcludedFrontmatterLength), subpath: subpath) else {
                return .missingSection(id: identifier(), path: path, subpath: subpath ?? "")
            }
            // A task of an embedded note is ticked in that note, as in Obsidian.
            let taskSource = TaskSource(noteText: transcludedSource) { sectionOffset in transcludedFrontmatterLength + section.location + sectionOffset }
            let body = try await render(Self.sectioned(NotePreviewDocument.locatedBlocks(from: section.text, pluginCodeBlockLanguages: configuration.pluginCodeBlockLanguages),
                                                       for: configuration), note: path, root: root, index: index, configuration: configuration,
                                        allowsTransclusion: false, taskSource: taskSource)
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

    /// Where the task on a line of a block's text, given by its index, is in the note.
    private typealias TaskLocation = (_ lineIndex: Int, _ status: Unicode.Scalar) -> ReadingTasks.Location?

    /// Rewrites Obsidian links and embeds into standard Markdown the renderer understands.
    /// - Parameter taskLocation: Finds the tasks of `markdown` in the note, so their
    ///   checkboxes can be ticked; nil where the text is not lines of the note.
    private func prepared(_ markdown: String, note: VaultPath, root: URL, index: VaultIndex, configuration: ReadingConfiguration,
                          taskLocation: TaskLocation? = nil) async throws -> String {
        // Wikilinks need `[[`, Markdown embeds `![` and Markdown links `](`; text without any
        // of them needs no link parse, which dominates building a long note.
        guard markdown.contains("[[") || markdown.contains("![") || markdown.contains("](") else {
            return readingText(markdown, configuration: configuration, taskLocation: taskLocation)
        }
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
        // A link written over two lines becomes one line, after which the lines no longer
        // have the indices `taskLocation` knows them by.
        var keepsLines = true
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
                var destination = GraphiteOpenLink.markdownDestination(target: target.target, isWiki: target.isWiki)
                // With a theme, a link no file answers is marked, and drawn in the theme's unresolved color.
                if configuration.marksUnresolvedLinks, !link.isEmbed, !link.target.hasPrefix("#"),
                   await resolve(link.target, isWiki: link.isWiki, note: note, root: root, index: index) == nil {
                    destination = GraphiteOpenLink.markingUnresolved(destination)
                }
                replacement = "[\(Self.escapedLabel(Self.displayText(for: link)))](\(destination))"
            } else {
                continue
            }
            if projected.substring(with: linkRange).contains("\n") || replacement.contains("\n") { keepsLines = false }
            projected.replaceCharacters(in: linkRange, with: replacement)
            earliestReplacedLocation = linkRange.location
        }
        return readingText(projected as String, configuration: configuration, taskLocation: keepsLines ? taskLocation : nil)
    }

    private func readingText(_ markdown: String, configuration: ReadingConfiguration, taskLocation: TaskLocation? = nil) -> String {
        var text = ObsidianInlineMarkup.preparedForReading(ReadingMarkerEscaping.escaping(markdown), colorsEnabled: configuration.colorsEnabled,
                                                           paletteHexByName: configuration.paletteHexByName, taskLocation: taskLocation)
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

/// A lightweight viewport checkpoint owned by the open note, not by its rendered view. It
/// also follows where the note's blocks are on screen, to tell which character of the note
/// is at the top of the reading view.
@MainActor
final class ReadingPosition {
    var verticalOffset: CGFloat = 0
    /// Where the blocks shown start in the note.
    var blockLocations: [ReadingBlockLocation] = [] {
        didSet { if blockLocations != oldValue { blockFrames = blockFrames.filter { identifier, _ in blockLocations.contains { location in location.blockIdentifier == identifier } } } }
    }
    /// Where the visible part of the reading view begins in its own coordinates, below any
    /// bar it scrolls under.
    var visibleTop: CGFloat = 0
    /// Each block's frame in the reading view's coordinates, as last laid out, for the
    /// blocks the lazy stack holds.
    private var blockFrames: [String: CGRect] = [:]

    func record(_ frame: CGRect, ofBlock identifier: String) {
        blockFrames[identifier] = frame
    }

    func forget(_ identifier: String) {
        blockFrames[identifier] = nil
    }

    /// The note's character at the top of the reading view: the first line of the block
    /// there, or for a run of Markdown the line as far down it as the view has scrolled.
    /// Nil at the very top, with the note's first block there, or before any block was
    /// laid out.
    func topLocation() -> Int? {
        let location = blockLocationAtTop()
        return location == 0 ? nil : location
    }

    /// Whether the reading view has laid out blocks to tell where it is: then a nil
    /// `topLocation()` is the very top, not a place unknown.
    var hasLaidOutBlocks: Bool { !blockFrames.isEmpty }

    private func blockLocationAtTop() -> Int? {
        guard verticalOffset > 1 else { return nil }
        let shownBlocks = blockLocations.compactMap { location in blockFrames[location.blockIdentifier].map { frame in (location, frame) } }
            .filter { _, frame in frame.maxY > visibleTop + 1 }
        guard let (location, frame) = shownBlocks.min(by: { first, second in first.1.minY < second.1.minY }) else { return nil }
        let hiddenHeight = visibleTop - frame.minY
        guard hiddenHeight > 0, !location.lineNoteOffsets.isEmpty, frame.height > 0 else { return location.noteOffset }
        let lineIndex = min(Int(Double(hiddenHeight / frame.height) * Double(location.lineNoteOffsets.count)), location.lineNoteOffsets.count - 1)
        return location.lineNoteOffsets[lineIndex]
    }

    /// The block to show at the top for a character of the note, and how far down the
    /// block that character is, from 0 to 1.
    func block(containing noteLocation: Int) -> (identifier: String, fractionDown: Double)? {
        guard let location = blockLocations.last(where: { location in location.noteOffset <= noteLocation }) ?? blockLocations.first else { return nil }
        guard !location.lineNoteOffsets.isEmpty, let lineIndex = location.lineNoteOffsets.lastIndex(where: { offset in offset <= noteLocation }) else {
            return (location.blockIdentifier, 0)
        }
        return (location.blockIdentifier, Double(lineIndex) / Double(location.lineNoteOffsets.count))
    }

    func frame(ofBlock identifier: String) -> CGRect? { blockFrames[identifier] }
}

/// The reading view's scroll view, in whose coordinates blocks report their frames.
enum ReadingCoordinateSpace {
    static let name = "GraphiteReadingView"
}

private struct ReadingViewport: Equatable {
    let verticalOffset: CGFloat
    let maximumVerticalOffset: CGFloat
    let topInset: CGFloat
    var height: CGFloat = 0
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
    var savedPosition: ReadingPosition? = nil
    /// The note's character to start at, once, where the editor was when the note switched
    /// to reading; nil keeps the reading view's own saved position.
    var takeStartingLocation: (() -> Int?)? = nil
    /// Ticks or unticks a task of this note, or of a note it embeds; nil draws checkboxes
    /// as pictures. False when the note no longer has the task at that place.
    var toggleTask: (@MainActor (VaultPath, ReadingTasks.Location) async -> Bool)? = nil
    /// Where the word read aloud is. Only a small view inside reads it, so a new word changes
    /// the texts it leaves and enters and nothing else (`ReadingWordTracker`).
    var readingWord: ReadingWordSource? = nil
    var followsReading = false
    var suspendReadingFollow: (() -> Void)? = nil
    @State private var scrollPosition = ScrollPosition(y: 0)
    @Environment(\.noteTypography) private var typography
    @Environment(\.noteTheme) private var theme
    /// The readable column: Graphite's, or the vault theme's line width at this text size.
    private var readableColumnWidth: CGFloat { theme?.readableColumnWidth(forTextSize: configuration.textSize) ?? ReadingConfiguration.readableColumnWidth }
    @State private var hasRestoredPosition = false
    @State private var pendingRestorationOffset: CGFloat?
    /// Where this view was before it restored the saved position, when nothing was saved:
    /// its first layout settling, or a scroll that came first. Kept apart from the saved
    /// position, so it is never taken for one and restored over a scroll.
    @State private var offsetBeforeRestoring: CGFloat?
    @State private var blocks: [RenderedBlock] = []
    @State private var readingSourceTokensByBlock: [String: [ReadAloudSourceToken]] = [:]
    /// The word read, where it is drawn and where the view is scrolled, for following the
    /// word; kept out of the view's state, which each would otherwise update at every word.
    @State private var readingFollow = ReadingFollowState()
    @State private var errorMessage: String?
    /// Whether the last build had embeds it could not find, which may appear once indexed.
    @State private var hasMissingEmbeds = false
    /// What `blocks` were built from.
    @State private var shownBuildKey: ReadingBuildKey?
    /// Counts the builds shown, so the blocks' view tells a new build from the same one.
    @State private var blocksVersion = 0
    /// What the blocks do when tapped, in one object that stays (`ReadingNoteBlocks`).
    @State private var blockActions = ReadingBlockActions()
    /// The word read, one cell per text, so a word changes only the texts it leaves and enters.
    @State private var wordCells = ReadingWordCells()
    @State private var mediaPlayers = ReadingMediaPlayers()
    /// Counts the tasks ticked in embedded notes. Their text is read from their files, so
    /// the note is built again although its own text is the same.
    @State private var embeddedNoteTaskEditCount = 0
    /// Whether the next build shows a ticked task, which is not delayed as typing is.
    @State private var buildsWithoutDelay = false

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let inlineTitle = configuration.inlineTitle {
                        Text(inlineTitle)
                            .font(InlineTitleStyle.swiftUIFont(textSize: configuration.textSize, typography: typography, theme: theme))
                            .foregroundStyle(theme?.inlineTitleColor.map { color in AnyShapeStyle(Color(color)) } ?? AnyShapeStyle(.primary))
                            .accessibilityAddTraits(.isHeader)
                            .padding(.bottom, 6)
                    }
                    let _ = blockActions.update(navigate: navigate, scrollToHeading: { anchor in
                        pendingRestorationOffset = nil
                        withAnimation(GraphiteMotion.animation()) { scrollProxy.scrollTo(anchor, anchor: .top) }
                    }, openPDF: openPDF, updateProperties: updateProperties, toggleFold: folding?.toggle)
                    ReadingNoteBlocks(blocks: blocks, blocksVersion: blocksVersion, root: root, textSize: configuration.textSize,
                                      foldedKeys: folding?.foldedKeys, declaredPropertyTypes: configuration.declaredPropertyTypes,
                                      canUpdateProperties: updateProperties != nil, blockPositions: savedPosition, actions: blockActions)
                    if let errorMessage { Text(errorMessage).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: configuration.usesReadableLineLength ? readableColumnWidth : .infinity, alignment: .leading)
                .padding(.horizontal, ReadingConfiguration.minimumHorizontalMargin).padding(.vertical, 32)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition($scrollPosition)
            .coordinateSpace(.named(ReadingCoordinateSpace.name))
            .onScrollGeometryChange(for: ReadingViewport.self) { geometry in
                ReadingViewport(verticalOffset: max(0, geometry.contentOffset.y + geometry.contentInsets.top),
                                maximumVerticalOffset: max(0, geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom - geometry.containerSize.height),
                                topInset: geometry.contentInsets.top, height: geometry.containerSize.height)
            } action: { _, viewport in
                readingFollow.viewport = viewport
                savedPosition?.visibleTop = viewport.topInset
                // Until a saved position is restored, the view's first offsets must not
                // replace it. With nothing saved, they are kept aside, and recorded once the
                // view knows it has nothing to restore. An offset recorded straight away, such
                // as one taken while the view settles under the window's bars, was restored
                // as if saved, and pulled back a scroll made meanwhile.
                guard hasRestoredPosition else {
                    if (savedPosition?.verticalOffset ?? 0) == 0 { offsetBeforeRestoring = viewport.verticalOffset }
                    return
                }
                if let pendingRestorationOffset {
                    let reachableOffset = min(pendingRestorationOffset, viewport.maximumVerticalOffset)
                    guard abs(viewport.verticalOffset - reachableOffset) < 1 else { return }
                    self.pendingRestorationOffset = nil
                }
                savedPosition?.verticalOffset = viewport.verticalOffset
            }
            .onScrollPhaseChange { _, phase in
                // Direct scrolling always takes precedence over an old checkpoint,
                // including when edits have shortened the document since it was read.
                if phase == .interacting {
                    pendingRestorationOffset = nil
                    suspendReadingFollow?()
                }
            }
            .onPreferenceChange(ReadingHighlightGeometryKey.self) { frames in
                MainActor.assumeIsolated {
                    readingFollow.highlightFrames = frames
                    followReadingWordIfNeeded()
                }
            }
            .onChange(of: followsReading) { _, _ in
                wordDidMove(to: readingFollow.range)
                followReadingWordIfNeeded()
            }
            .background {
                if let readingWord {
                    ReadingWordTracker(source: readingWord) { range in
                        readingFollow.scrollProxy = scrollProxy
                        wordDidMove(to: range)
                    }
                }
            }
            .environment(\.baseEmbedContext, baseContext)
            .environment(\.readingSourceTokensByBlock, readingSourceTokensByBlock)
            .environment(\.readingWordCells, wordCells)
            .environment(\.readingFollowsSource, followsReading)
            .environment(\.readingMediaPlayers, mediaPlayers)
            .environment(\.readingTaskContext, toggleTask.map { toggleTask in
                ReadingTaskContext(note: path) { note, location in await toggle(location, in: note, with: toggleTask) }
            })
            .environment(\.embeddedImageColumnWidth, configuration.usesReadableLineLength ? readableColumnWidth : nil)
            // Runs again once blocks exist: a note opened by a link or a search match is
            // asked to scroll before it has built anything to scroll to.
            .task(id: "\(blocks.count)-\(headingScrollRequest?.token.uuidString ?? "")") {
                guard !blocks.isEmpty else { return }
                // Switched from writing, or opened where it was left: the line that was at the
                // top. A link or a search match to show wins over it.
                if !hasRestoredPosition, let startingLocation = takeStartingLocation?() {
                    hasRestoredPosition = true
                    let hasNewHeadingRequest = headingScrollRequest.map { request in request.token != handledScrollToken } ?? false
                    if !hasNewHeadingRequest { await scrollToTop(of: startingLocation, scrollProxy: scrollProxy) }
                }
                if !hasRestoredPosition {
                    hasRestoredPosition = true
                    if headingScrollRequest == nil || headingScrollRequest?.token == handledScrollToken,
                       let verticalOffset = savedPosition?.verticalOffset, verticalOffset > 0 {
                        pendingRestorationOffset = verticalOffset
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        scrollPosition.scrollTo(y: verticalOffset)
                    } else if (savedPosition?.verticalOffset ?? 0) == 0, let offsetBeforeRestoring {
                        // Nothing to restore: where the view already is, as after a first scroll.
                        savedPosition?.verticalOffset = offsetBeforeRestoring
                    }
                }
                guard let request = headingScrollRequest, request.token != handledScrollToken else { return }
                pendingRestorationOffset = nil
                handledScrollToken = request.token
                guard !request.anchor.isEmpty else { return }
                let target = request.readingScrollTarget(in: blocks)
                withAnimation(GraphiteMotion.animation()) { scrollProxy.scrollTo(target, anchor: .top) }
            }
        }
        .task(id: ReadingBuildRequest(source: source, drawingVersion: configuration.drawingVersion, renderingHash: configuration.hashValueForReload,
                                      indexVersion: hasMissingEmbeds ? configuration.indexVersion : -1, embeddedNoteTaskEditCount: embeddedNoteTaskEditCount)) {
            if let shownBuildKey, shownBuildKey.describesBuild(of: source, path: path, root: root, configuration: configuration) { return }
            if blocks.isEmpty, let cachedBuild = blocksCache?.lastBuild, cachedBuild.key.describesBuild(of: source, path: path, root: root, configuration: configuration) {
                show(cachedBuild)
                return
            }
            do {
                // Changes that follow each other quickly are built once; a note just shown
                // has nothing to show yet, so it is built at once, as is a ticked task.
                let isDelayed = !blocks.isEmpty && !buildsWithoutDelay
                buildsWithoutDelay = false
                if isDelayed { try await Task.sleep(for: .milliseconds(150)) }
                let build = try await ReadingViewBuilder().build(source: source, note: path, root: root, index: index, configuration: configuration)
                try Task.checkCancellation()
                let hasMissingEmbeds = Self.containsMissingEmbed(build.blocks) || build.hasUnresolvedEmbeds
                let key = ReadingBuildKey(source: source, path: path, root: root, configuration: configuration, dependsOnIndex: hasMissingEmbeds)
                let cachedBuild = ReadingBlocksCache.Build(key: key, blocks: build.blocks, hasMissingEmbeds: hasMissingEmbeds,
                                                          blockLocations: build.blockLocations, readingSourceTokensByBlock: build.readingSourceTokensByBlock)
                show(cachedBuild)
                blocksCache?.lastBuild = cachedBuild
            } catch is CancellationError {
            } catch { errorMessage = error.localizedDescription }
        }
    }

    /// Brings the note's character to the top: its block first, then as far down the block
    /// as the character is, once the block's height is known.
    private func scrollToTop(of noteLocation: Int, scrollProxy: ScrollViewProxy) async {
        pendingRestorationOffset = nil
        // A reading view is made anew for each switch and starts at the top. Asking for the
        // top edge would hold the view there, and SwiftUI applied it again over later scrolls.
        guard noteLocation > 0, let (identifier, fractionDown) = savedPosition?.block(containing: noteLocation) else { return }
        scrollProxy.scrollTo(identifier, anchor: .top)
        guard fractionDown > 0 else { return }
        try? await Task.sleep(for: .milliseconds(50))
        guard let savedPosition, let frame = savedPosition.frame(ofBlock: identifier) else { return }
        scrollPosition.scrollTo(y: savedPosition.verticalOffset + (frame.minY - savedPosition.visibleTop) + fractionDown * frame.height)
    }

    /// The word read moved: its text shows it, and the view follows it when it follows reading.
    private func wordDidMove(to range: NSRange?) {
        readingFollow.range = range
        wordCells.show(range)
        readingFollow.followTask?.cancel()
        guard followsReading, let range else { return }
        revealFoldedReadingSection(containing: range)
        let readingFollow = readingFollow
        let savedPosition = savedPosition
        readingFollow.followTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, !readingFollow.highlightFrames.contains(where: { frame in frame.sourceRange == range }),
                  let (identifier, _) = savedPosition?.block(containing: range.location),
                  savedPosition?.frame(ofBlock: identifier) == nil else { return }
            // Lazy stacks revise estimated heights as distant blocks appear.
            // Reconcile a bounded number of layouts instead of assuming the
            // first estimated destination reveals the actual word.
            for _ in 0..<3 {
                guard !Task.isCancelled, readingFollow.range == range else { return }
                readingFollow.scrollProxy?.scrollTo(identifier, anchor: .center)
                try? await Task.sleep(for: .milliseconds(80))
                if readingFollow.highlightFrames.contains(where: { frame in frame.sourceRange == range }) { return }
            }
        }
    }

    private func followReadingWordIfNeeded() {
        let readingViewport = readingFollow.viewport
        guard followsReading, let range = readingFollow.range, readingViewport.height > 80 else { return }
        let frame = readingFollow.highlightFrames.filter { geometry in geometry.sourceRange == range }
            .reduce(CGRect.null) { union, geometry in union.union(geometry.frame) }
        guard !frame.isNull, !frame.isEmpty,
              frame.minY < readingViewport.topInset + 40 || frame.maxY > readingViewport.height - 120 else { return }
        pendingRestorationOffset = nil
        // The word comes back a third of the way down, so the following lines are in view.
        let destination = readingViewport.verticalOffset + frame.minY - readingViewport.topInset - (readingViewport.height - readingViewport.topInset) / 3
        scrollPosition.scrollTo(y: max(0, min(destination, readingViewport.maximumVerticalOffset)))
    }

    private func revealFoldedReadingSection(containing range: NSRange) {
        guard let folding, !folding.foldedKeys.isEmpty, let locations = savedPosition?.blockLocations else { return }
        var occurrences: [String: Int] = [:]
        for (blockIndex, block) in blocks.enumerated() {
            guard case .heading(_, let level, let text, _) = block,
                  let start = locations.first(where: { location in location.blockIdentifier == block.id })?.noteOffset else { continue }
            let base = "h\(level)|" + String(repeating: "#", count: level) + " " + text
            let occurrence = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1
            let key = base + "|" + String(occurrence)
            guard folding.foldedKeys.contains(key), range.location >= start else { continue }
            let nextHeading = blocks.dropFirst(blockIndex + 1).first { candidate in
                if case .heading(_, let nextLevel, _, _) = candidate { return nextLevel <= level }
                return false
            }
            let end = nextHeading.flatMap { heading in locations.first(where: { location in location.blockIdentifier == heading.id })?.noteOffset } ?? source.utf16.count
            if range.location < end { folding.toggle(key) }
        }
    }

    private func show(_ build: ReadingBlocksCache.Build) {
        savedPosition?.blockLocations = build.blockLocations
        readingSourceTokensByBlock = build.readingSourceTokensByBlock
        wordCells.index(build.readingSourceTokensByBlock)
        wordDidMove(to: readingFollow.range)
        blocks = build.blocks; errorMessage = nil
        blocksVersion += 1
        hasMissingEmbeds = build.hasMissingEmbeds
        shownBuildKey = build.key
        mediaPlayers.keepPlaybacks(for: Self.mediaLocations(in: build.blocks))
    }

    /// Ticks a task and has the note drawn again without the delay typing gets.
    private func toggle(_ location: ReadingTasks.Location, in note: VaultPath,
                        with toggleTask: @MainActor (VaultPath, ReadingTasks.Location) async -> Bool) async -> Bool {
        let didToggle = await toggleTask(note, location)
        if note != path {
            // Also after a tap that changed nothing: the embedded note has changed since
            // it was read, and its tasks are found again.
            shownBuildKey = nil
            buildsWithoutDelay = true
            embeddedNoteTaskEditCount += 1
        } else if didToggle {
            buildsWithoutDelay = true
        }
        return didToggle
    }
}

/// Where the word read aloud is, as a function the reading view calls only from a small view
/// of its own (`ReadingWordTracker`): reading it in the view's body would update the whole
/// view, and the pane around it, at every word.
struct ReadingWordSource {
    let range: @MainActor () -> NSRange?
}

/// Reads the word read aloud and reports it when it moves. It is the only view that reads
/// it, so it is the only view SwiftUI updates for a new word.
private struct ReadingWordTracker: View {
    let source: ReadingWordSource
    let wordDidMove: (NSRange?) -> Void

    var body: some View {
        let range = source.range()
        Color.clear
            .onChange(of: range, initial: true) { _, newRange in wordDidMove(newRange) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The reading view's word read and what following it needs, kept out of the view's state.
@MainActor
fileprivate final class ReadingFollowState {
    var range: NSRange?
    var highlightFrames: [ReadingHighlightGeometry] = []
    var viewport = ReadingViewport(verticalOffset: 0, maximumVerticalOffset: 0, topInset: 0)
    var scrollProxy: ScrollViewProxy?
    var followTask: Task<Void, Never>?
}

/// The word read aloud for one text of the reading view. Only the text whose cell it is
/// reads it, so a new word updates the text it leaves and the one it enters, not every text.
@MainActor @Observable
final class ReadingWordCell {
    var range: NSRange?
}

/// The cells of the word read, one per text of the note, found by the text's first word.
/// Moving to the next word looks the text up by binary search over where the texts start;
/// nothing goes over the note.
@MainActor
final class ReadingWordCells {
    private struct TextSpan {
        let firstLocation: Int
        let end: Int
        let tokens: [ReadAloudSourceToken]
    }

    private var cells: [Int: ReadingWordCell] = [:]
    /// The word read wherever it is, for the few views that look at every word, as a
    /// callout opening for the word inside it.
    let current = ReadingWordCell()
    /// Each text with words, by where its first word starts.
    private var spans: [TextSpan] = []
    private var shownFirstLocation: Int?

    /// The cell of the text whose words these are; nil for a text without words.
    func cell(forTextWith tokens: [ReadAloudSourceToken]) -> ReadingWordCell? {
        guard let firstLocation = tokens.first?.sourceRange.location else { return nil }
        if let cell = cells[firstLocation] { return cell }
        let cell = ReadingWordCell()
        cells[firstLocation] = cell
        return cell
    }

    /// Takes the texts of a new build of the note.
    func index(_ tokensByBlock: [String: [ReadAloudSourceToken]]) {
        spans = tokensByBlock.values.compactMap { tokens in
            guard let first = tokens.first else { return nil }
            return TextSpan(firstLocation: first.sourceRange.location, end: tokens.map { token in NSMaxRange(token.sourceRange) }.max() ?? 0, tokens: tokens)
        }.sorted { leftSpan, rightSpan in leftSpan.firstLocation < rightSpan.firstLocation }
        for (firstLocation, cell) in cells where !spans.contains(where: { span in span.firstLocation == firstLocation }) {
            cell.range = nil
        }
        shownFirstLocation = nil
    }

    /// Shows the word read in the text that holds it, and in no other.
    func show(_ range: NSRange?) {
        if current.range != range { current.range = range }
        let firstLocation = range.flatMap(textFirstLocation(holding:))
        if let shownFirstLocation, shownFirstLocation != firstLocation { cells[shownFirstLocation]?.range = nil }
        shownFirstLocation = firstLocation
        guard let firstLocation else { return }
        let cell = cells[firstLocation] ?? cellCreated(at: firstLocation)
        if cell.range != range { cell.range = range }
    }

    private func cellCreated(at firstLocation: Int) -> ReadingWordCell {
        let cell = ReadingWordCell()
        cells[firstLocation] = cell
        return cell
    }

    /// The text whose words include the range: the last text starting at or before it, or one
    /// of the few before that when texts nest, as a callout's title and its body do.
    private func textFirstLocation(holding range: NSRange) -> Int? {
        var lowerIndex = 0
        var upperIndex = spans.count
        while lowerIndex < upperIndex {
            let middleIndex = (lowerIndex + upperIndex) / 2
            if spans[middleIndex].firstLocation <= range.location { lowerIndex = middleIndex + 1 } else { upperIndex = middleIndex }
        }
        let nearestNestingCount = 4
        for spanIndex in stride(from: lowerIndex - 1, through: max(0, lowerIndex - nearestNestingCount), by: -1) {
            let span = spans[spanIndex]
            guard range.location < span.end else { continue }
            if span.tokens.contains(where: { token in NSIntersectionRange(token.sourceRange, range).length > 0 }) { return span.firstLocation }
        }
        return nil
    }
}

/// What the note's blocks do when tapped: follow a link, scroll to a heading, open a PDF,
/// change the properties, fold a heading. The reading view makes new closures for these at
/// every update, as at each word read aloud; kept in one object whose identity stays, they
/// do not make the blocks' view go over every block of the note again.
@MainActor
final class ReadingBlockActions {
    private(set) var navigate: (String, Bool) -> Void = { _, _ in }
    private(set) var scrollToHeading: (String) -> Void = { _ in }
    private(set) var openPDF: (VaultPath, Int) -> Void = { _, _ in }
    private(set) var updateProperties: (([NoteProperty]) -> Void)?
    private(set) var toggleFold: ((String) -> Void)?

    func update(navigate: @escaping (String, Bool) -> Void, scrollToHeading: @escaping (String) -> Void,
                openPDF: @escaping (VaultPath, Int) -> Void, updateProperties: (([NoteProperty]) -> Void)?, toggleFold: ((String) -> Void)?) {
        self.navigate = navigate; self.scrollToHeading = scrollToHeading; self.openPDF = openPDF
        self.updateProperties = updateProperties; self.toggleFold = toggleFold
    }
}

/// The note's own blocks in the reading view. It holds only values and the actions' object,
/// and SwiftUI compares it with `==`, so the update that each word read aloud makes does not
/// go over every block of a long note again (2,600 blocks for a 0.8 MB note). It is not
/// wrapped in `.equatable()`: that makes it one view to the lazy stack around it, which then
/// makes every block of the note at once (900 ms of the main thread per word, seen while
/// this was written).
private struct ReadingNoteBlocks: View, Equatable {
    let blocks: [RenderedBlock]
    /// Which build of the note `blocks` are.
    let blocksVersion: Int
    let root: URL
    let textSize: Double
    let foldedKeys: Set<String>?
    let declaredPropertyTypes: [String: PropertyType]
    let canUpdateProperties: Bool
    let blockPositions: ReadingPosition?
    let actions: ReadingBlockActions

    nonisolated static func == (leftBlocks: ReadingNoteBlocks, rightBlocks: ReadingNoteBlocks) -> Bool {
        MainActor.assumeIsolated {
            leftBlocks.blocksVersion == rightBlocks.blocksVersion && leftBlocks.root == rightBlocks.root
                && leftBlocks.textSize == rightBlocks.textSize && leftBlocks.foldedKeys == rightBlocks.foldedKeys
                && leftBlocks.declaredPropertyTypes == rightBlocks.declaredPropertyTypes
                && leftBlocks.canUpdateProperties == rightBlocks.canUpdateProperties
                && leftBlocks.blockPositions === rightBlocks.blockPositions && leftBlocks.actions === rightBlocks.actions
        }
    }

    var body: some View {
        // Each closure asks the actions' object at the time it runs, for the latest one.
        ReadingBlocksView(blocks: blocks, root: root, textSize: textSize,
                          navigate: { [actions] target, isWiki in actions.navigate(target, isWiki) },
                          scrollToHeading: { [actions] anchor in actions.scrollToHeading(anchor) },
                          openPDF: { [actions] path, pageIndex in actions.openPDF(path, pageIndex) },
                          updateProperties: canUpdateProperties ? { [actions] properties in actions.updateProperties?(properties) } : nil,
                          folding: foldedKeys.map { keys in ReadingFolding(foldedKeys: keys) { [actions] key in actions.toggleFold?(key) } },
                          declaredPropertyTypes: declaredPropertyTypes, blockPositions: blockPositions)
    }
}

/// What starts a new build of the reading view: SwiftUI compares it at every update of the
/// view, as each word read aloud makes. The note's text is compared, not hashed: comparing a
/// text with itself, the same storage, takes no time, where hashing read the whole note at
/// every update. A long note read aloud kept the main thread hashing until the system ended
/// Graphite (`Character.hashValue` under `MarkdownPreview.body`, the owner's iPad, 2026-10-12).
private struct ReadingBuildRequest: Equatable {
    let source: String
    let drawingVersion: Int
    let renderingHash: Int
    let indexVersion: Int
    let embeddedNoteTaskEditCount: Int
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
        var blockLocations: [ReadingBlockLocation] = []
        var readingSourceTokensByBlock: [String: [ReadAloudSourceToken]] = [:]
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
        hasher.combine(mapsReadAloudSourceLocations)
        hasher.combine(paletteHexByName.sorted { firstEntry, secondEntry in firstEntry.key < secondEntry.key }.map { entry in entry.key + entry.value })
        hasher.combine(declaredPropertyTypes.sorted { firstEntry, secondEntry in firstEntry.key < secondEntry.key }.map { entry in entry.key + "=" + entry.value.rawValue })
        hasher.combine(pluginCodeBlockLanguages.sorted())
        hasher.combine(marksUnresolvedLinks)
        hasher.combine(runsPluginPostProcessors)
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
    /// Follows where the note's own blocks are as the view scrolls; nil for embedded notes.
    var blockPositions: ReadingPosition? = nil
    @Environment(\.readingTaskContext) private var taskContext
    // The word being read is not read here: it changes with every word, and this view's body
    // goes over every block of the note. Only the views that show the word, and callouts
    // (`ReadingCallout`), read it.
    @Environment(\.readingSourceTokensByBlock) private var readingSourceTokensByBlock
    /// Draws plugins' code blocks; nil where plugins do not draw, which shows them as code.
    @Environment(\.communityPluginCodeBlocks) private var pluginCodeBlocks

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
            blockView(for: entry)
                .modifier(ReadingBlockPositionReporter(blockIdentifier: entry.block.id, positions: blockPositions))
        }
    }

    @ViewBuilder private func blockView(for entry: (block: RenderedBlock, foldKey: String?, hasBody: Bool)) -> some View {
            let block = entry.block
            switch block {
            case .properties(let properties):
                PropertiesPanel(properties: properties, update: updateProperties, follow: navigate, declaredTypes: declaredPropertyTypes)
            case .markdown(_, let text):
                ObsidianMarkdownText(markdown: text, root: root, textSize: textSize, navigate: navigate, scrollToHeading: scrollToHeading,
                                     sourceTokens: readingSourceTokensByBlock[block.id])
            case .pluginSection(_, let text, let request):
                if let codeBlocks = pluginCodeBlocks {
                    CommunityPluginSectionView(host: codeBlocks, request: request, textSize: textSize) {
                        ObsidianMarkdownText(markdown: text, root: root, textSize: textSize, navigate: navigate, scrollToHeading: scrollToHeading)
                    }
                } else {
                    ObsidianMarkdownText(markdown: text, root: root, textSize: textSize, navigate: navigate, scrollToHeading: scrollToHeading,
                                         sourceTokens: readingSourceTokensByBlock[block.id])
                }
            case .displayMath(_, let text):
                // Centered, as Obsidian shows display math.
                ObsidianMarkdownText(markdown: text, root: root, textSize: textSize, navigate: navigate, scrollToHeading: scrollToHeading,
                                     sourceTokens: readingSourceTokensByBlock[block.id])
                    .frame(maxWidth: .infinity)
            case .heading(_, let level, let text, let anchor):
                let heading = ObsidianMarkdownText(markdown: String(repeating: "#", count: level) + " " + text, root: root, textSize: textSize, navigate: navigate, scrollToHeading: scrollToHeading,
                                                  sourceTokens: readingSourceTokensByBlock[block.id])
                    .overlay(alignment: .leading) {
                        if let folding, let foldKey = entry.foldKey, entry.hasBody {
                            let isFolded = folding.foldedKeys.contains(foldKey)
                            Button { folding.toggle(foldKey) } label: {
                                // 28 points, Apple's smallest comfortable touch target, centered where
                                // the 22-point chevron was.
                                Image(systemName: isFolded ? "chevron.right" : "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .tint(.secondary)
                            .opacity(isFolded ? 1 : 0.45)
                            .offset(x: -29)
                            .accessibilityLabel(isFolded ? "Unfold \(text)" : "Fold \(text)")
                        }
                    }
                if let anchor { heading.id(anchor) } else { heading }
            case .callout(_, let type, let title, let folding, let body):
                ReadingCallout(type: type, title: title, folding: folding, root: root, textSize: textSize, navigate: navigate,
                               scrollToHeading: scrollToHeading, sourceTokens: readingSourceTokensByBlock[block.id], blocksInside: body) {
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
                        // The embedded note's tasks are ticked in that note.
                        .environment(\.readingTaskContext, taskContext.map { context in ReadingTaskContext(note: path, toggle: context.toggle) })
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
            case .pluginCodeBlock(_, let language, let source, let note, let firstLine, let lineCount):
                if let codeBlocks = pluginCodeBlocks {
                    CommunityPluginCodeBlockView(host: codeBlocks, request: CommunityPluginReadingBlockRequest(kind: .codeBlock(language: language), source: source, note: note,
                                                                                                             firstLine: firstLine, lineCount: lineCount),
                                                 textSize: textSize)
                } else {
                    ObsidianMarkdownText(markdown: "```" + language + "\n" + source + "\n```", root: root, textSize: textSize, navigate: navigate, scrollToHeading: scrollToHeading)
                }
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

/// A callout in the reading view, which opens while the word being read is inside it.
private struct ReadingCallout<Content: View>: View {
    let type: String
    let title: String
    let folding: CalloutFolding
    let root: URL
    let textSize: Double
    let navigate: (String, Bool) -> Void
    let scrollToHeading: (String) -> Void
    let sourceTokens: [ReadAloudSourceToken]?
    /// The callout's own blocks.
    let blocksInside: [RenderedBlock]
    let content: () -> Content
    @Environment(\.readingSourceTokensByBlock) private var readingSourceTokensByBlock
    @Environment(\.readingWordCells) private var readingWordCells
    @Environment(\.readingFollowsSource) private var readingFollowsSource
    /// The word read: the reading view's current word.
    private var readingActiveSourceRange: NSRange? { readingWordCells?.current.range }

    init(type: String, title: String, folding: CalloutFolding, root: URL, textSize: Double, navigate: @escaping (String, Bool) -> Void,
         scrollToHeading: @escaping (String) -> Void, sourceTokens: [ReadAloudSourceToken]?, blocksInside: [RenderedBlock],
         @ViewBuilder content: @escaping () -> Content) {
        self.type = type; self.title = title; self.folding = folding; self.root = root; self.textSize = textSize
        self.navigate = navigate; self.scrollToHeading = scrollToHeading; self.sourceTokens = sourceTokens
        self.blocksInside = blocksInside; self.content = content
    }

    var body: some View {
        CalloutView(type: type, title: title, folding: folding, root: root, textSize: textSize, navigate: navigate,
                    scrollToHeading: scrollToHeading, sourceTokens: sourceTokens,
                    automaticallyExpandsForReading: containsReadingWord(blocksInside), content: content)
    }

    private func containsReadingWord(_ blocks: [RenderedBlock]) -> Bool {
        guard readingFollowsSource, let range = readingActiveSourceRange else { return false }
        return blocks.contains { block in
            if readingSourceTokensByBlock[block.id]?.contains(where: { token in NSIntersectionRange(token.sourceRange, range).length > 0 }) == true { return true }
            if case .callout(_, _, _, _, let body) = block { return containsReadingWord(body) }
            return false
        }
    }
}

/// Reports a block's frame in the reading view as it scrolls, where the note's place is
/// followed (`ReadingPosition`); does nothing for embedded notes.
private struct ReadingBlockPositionReporter: ViewModifier {
    let blockIdentifier: String
    let positions: ReadingPosition?

    func body(content: Content) -> some View {
        if let positions {
            content.onGeometryChange(for: CGRect.self) { geometry in
                geometry.frame(in: .named(ReadingCoordinateSpace.name))
            } action: { frame in
                positions.record(frame, ofBlock: blockIdentifier)
            }
            // A block the lazy stack lets go stops reporting, possibly from a frame still
            // across the top after a fast scroll; it is not on screen.
            .onDisappear { positions.forget(blockIdentifier) }
        } else {
            content
        }
    }
}

/// One Markdown run rendered with Obsidian-like styles and Graphite's link handling.
///
/// The word read aloud changes several times a second, and every text of the note on screen
/// hears of it. This view only finds whether the word is in its text; the text is drawn
/// again only when it is (`ObsidianMarkdownTextContent`). Drawing every text of a long note
/// again at each word took the main thread whole while a note was read aloud.
struct ObsidianMarkdownText: View {
    let markdown: String
    let root: URL
    let textSize: Double
    let navigate: (String, Bool) -> Void
    let scrollToHeading: (String) -> Void
    var sourceTokens: [ReadAloudSourceToken]? = nil
    /// The reading view's cells of the word read, one per text; nil elsewhere, as in Live
    /// Preview's rendered blocks, which pass the word in the environment.
    @Environment(\.readingWordCells) private var readingWordCells

    var body: some View {
        if let readingWordCells {
            WordCellText(markdown: markdown, root: root, textSize: textSize, navigate: navigate, scrollToHeading: scrollToHeading,
                         sourceTokens: sourceTokens, cell: sourceTokens.flatMap { tokens in readingWordCells.cell(forTextWith: tokens) })
        } else {
            WordEnvironmentText(markdown: markdown, root: root, textSize: textSize, navigate: navigate, scrollToHeading: scrollToHeading,
                                sourceTokens: sourceTokens)
        }
    }

    /// Graphite's line spacing in reading view without a theme: Textual's own.
    static let graphiteLineSpacing = 0.0

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

/// A text of the reading view: it hears the word read only through its own cell, which
/// changes only when the word enters or leaves this text.
private struct WordCellText: View {
    let markdown: String
    let root: URL
    let textSize: Double
    let navigate: (String, Bool) -> Void
    let scrollToHeading: (String) -> Void
    let sourceTokens: [ReadAloudSourceToken]?
    let cell: ReadingWordCell?

    var body: some View {
        ObsidianMarkdownTextContent(markdown: markdown, root: root, textSize: textSize, navigate: navigate, scrollToHeading: scrollToHeading,
                                    sourceTokens: sourceTokens, activeRange: cell?.range)
            .equatable()
    }
}

/// A text that finds the word read in the environment, as Live Preview's rendered blocks give it.
private struct WordEnvironmentText: View {
    let markdown: String
    let root: URL
    let textSize: Double
    let navigate: (String, Bool) -> Void
    let scrollToHeading: (String) -> Void
    let sourceTokens: [ReadAloudSourceToken]?
    @Environment(\.readingActiveSourceRange) private var readingActiveSourceRange

    var body: some View {
        ObsidianMarkdownTextContent(markdown: markdown, root: root, textSize: textSize, navigate: navigate, scrollToHeading: scrollToHeading,
                                    sourceTokens: sourceTokens, activeRange: activeRangeInText)
            .equatable()
    }

    private var activeRangeInText: NSRange? {
        guard let range = readingActiveSourceRange, let sourceTokens,
              sourceTokens.contains(where: { token in NSIntersectionRange(token.sourceRange, range).length > 0 }) else { return nil }
        return range
    }
}

/// The text of `ObsidianMarkdownText`, drawn again only when what it shows changes: the
/// word read aloud reaches it only while the word is inside it.
private struct ObsidianMarkdownTextContent: View, Equatable {
    let markdown: String
    @Environment(\.accent) private var accent
    @Environment(\.noteTypography) private var typography
    @Environment(\.noteTheme) private var theme
    @Environment(\.codeColorTheme) private var codeColorTheme
    let root: URL
    let textSize: Double
    let navigate: (String, Bool) -> Void
    let scrollToHeading: (String) -> Void
    let sourceTokens: [ReadAloudSourceToken]?
    /// The word being read, when it is in this text; nil otherwise.
    let activeRange: NSRange?
    @Environment(\.readingHighlightFill) private var readingHighlightFill

    /// The same text, read at the same word. The closures are left out: their owners make
    /// new ones at every update, which do the same.
    nonisolated static func == (leftText: ObsidianMarkdownTextContent, rightText: ObsidianMarkdownTextContent) -> Bool {
        leftText.markdown == rightText.markdown && leftText.root == rightText.root && leftText.textSize == rightText.textSize
            && leftText.sourceTokens == rightText.sourceTokens && leftText.activeRange == rightText.activeRange
    }

    var body: some View {
        if let numberedEquation {
            NumberedEquationView(equation: numberedEquation, textSize: textSize)
                .background {
                    if let activeRange, sourceTokens?.contains(where: { token in
                        token.isEquation && NSIntersectionRange(token.sourceRange, activeRange).length > 0
                    }) == true {
                        RoundedRectangle(cornerRadius: 3).fill(ReadAloudHighlightStyle.color)
                        GeometryReader { geometry in
                            Color.clear.preference(key: ReadingHighlightGeometryKey.self,
                                                   value: [ReadingHighlightGeometry(sourceRange: activeRange,
                                                                                     frame: geometry.frame(in: .named(ReadingCoordinateSpace.name)))])
                        }
                        .allowsHitTesting(false)
                    }
                }
        } else {
            StructuredText(markdown, parser: ObsidianMarkdownParser(baseURL: root, textSize: textSize, sourceTokens: sourceTokens,
                                                                    themeColors: ReadingThemeColors(theme: theme)))
                // StructuredText parses again only when its text changes, and the parse sizes
                // footnote numbers and colors the theme's links and tags, so a new text size or
                // theme starts a new view.
                .id(textSize)
                .id(sourceTokens)
                .id(theme?.tokens.fingerprint)
                .font(typography.textSwiftUIFont(size: textSize))
                .foregroundStyle(theme?.textNormal.map { color in AnyShapeStyle(Color(color)) } ?? AnyShapeStyle(.primary))
                .textual.lineSpacing(.fontScaled(theme?.lineHeight.map { height in max(0, height - 1.2) } ?? ObsidianMarkdownText.graphiteLineSpacing))
                .textual.textSelection(.enabled)
                .textual.inlineStyle(inlineStyle)
                .textual.codeBlockStyle(ObsidianCodeBlockStyle(monospaceFont: typography.monospaceSwiftUIFont(size: textSize), theme: theme, codeTheme: codeColorTheme))
                // Code is colored as the editor colors it (`CodeSyntaxColors`).
                .textual.highlighterTheme(CodeSyntaxColors.highlighterTheme(codeTheme: codeColorTheme, noteTheme: theme))
                .textual.codeSegmenter(CodeSyntaxColors.readingSegments)
                .textual.listItemStyle(ObsidianListItemStyle(textSize: textSize, theme: theme))
                .textual.imageAttachmentLoader(VaultImageLoader(root: root))
                .textual.headingStyle(ObsidianHeadingStyle(theme: theme, typography: typography, textSize: textSize))
                .textual.tableStyle(ObsidianTableStyle(theme: theme))
                .textual.thematicBreakStyle(ObsidianThematicBreakStyle(theme: theme))
                .textual.tableCellStyle(ObsidianTableCellStyle(theme: theme))
                .textual.blockQuoteStyle(ObsidianBlockQuoteStyle(theme: theme))
                .tint(accent)
                .environment(\.openURL, ObsidianMarkdownText.linkAction(root: root, navigate: navigate, scrollToHeading: scrollToHeading))
                .textual.readingHighlight(activeRange, color: readingHighlightFill, coordinateSpace: ReadingCoordinateSpace.name)
        }
    }

    /// Links in the accent, and inline code in the monospace font. SF Mono keeps Textual's
    /// own code style, which follows a heading's size; another family is set as a font.
    private var inlineStyle: InlineStyle {
        // With a theme, the parser colors each link (internal, unresolved, external) and tag.
        var linkedStyle = theme == nil ? InlineStyle.default.link(.foregroundColor(accent)) : InlineStyle.default.link(KeptTextProperty())
        if theme?.linksAreUnderlined == true { linkedStyle = InlineStyle.default.link(.underlineStyle(.single)) }
        // The theme's bold and italic colors.
        if let boldColor = theme?.boldColor { linkedStyle = linkedStyle.strong(.fontWeight(.semibold), .foregroundColor(Color(boldColor))) }
        if let italicColor = theme?.italicColor { linkedStyle = linkedStyle.emphasis(.italic, .foregroundColor(Color(italicColor))) }
        let codeBackground = theme?.codeBackground.map { color in Color(color) }
        guard case .installed = typography.monospaceFamily else {
            guard let codeBackground else { return linkedStyle }
            return linkedStyle.code(.monospaced, .fontScale(0.94), .backgroundColor(codeBackground))
        }
        if let codeBackground {
            return linkedStyle.code(.font(typography.monospaceSwiftUIFont(size: textSize)), .fontScale(0.94), .backgroundColor(codeBackground))
        }
        return linkedStyle.code(.font(typography.monospaceSwiftUIFont(size: textSize)), .fontScale(0.94))
    }


    /// The display formula with equation numbers that is all of the text, which is laid
    /// out with its numbers at the right of the column. One the typesetter cannot draw is
    /// left to the Markdown renderer, which shows it as its source.
    private var numberedEquation: NumberedEquation? {
        guard let equation = ObsidianInlineMarkup.numberedEquation(aloneIn: markdown), NumberedEquationView.canDraw(equation, textSize: textSize) else { return nil }
        return equation
    }

}

struct KeptTextProperty: TextProperty {
    func apply(in attributes: inout AttributeContainer, environment: TextEnvironmentValues) {}
}

/// The theme's colors the reading view's parser gives runs: links by kind, tags, highlights.
struct ReadingThemeColors: Hashable {
    let link: Color
    let unresolvedLink: Color
    let externalLink: Color
    let tag: Color?
    let tagBackground: Color?
    let highlight: Color
    let highlightText: Color?
    /// Tag pills and highlights with the theme's corners and border, at a 16-point text
    /// size; `parser.textSize` scales them.
    let tagRadius: Double
    let tagBorder: Color?
    let tagBorderWidth: Double
    let highlightRadius: Double

    /// Nil without a theme, so the reading view keeps Graphite's own colors.
    init?(theme: NoteThemeStyle?) {
        guard let theme else { return nil }
        highlightText = theme.highlightTextColor.map { color in Color(color) }
        // Graphite's tags are pills, as Obsidian's are by default.
        tagRadius = theme.tagRadius ?? Double(NoteThemeStyle.pillRadius)
        tagBorder = theme.tagBorderColor.map { color in Color(color) }
        tagBorderWidth = theme.tagBorderWidth ?? 0
        highlightRadius = theme.highlightRadius ?? 0
        let link = theme.linkColor ?? theme.accent
        self.link = link.map { color in Color(color) } ?? .accentColor
        unresolvedLink = (theme.unresolvedLinkColor ?? link).map { color in Color(color) } ?? .accentColor
        externalLink = (theme.externalLinkColor ?? link).map { color in Color(color) } ?? .accentColor
        tag = (theme.tagColor ?? theme.accent).map { color in Color(color) }
        tagBackground = theme.tagBackground.map { color in Color(color) }
        highlight = theme.highlightBackground.map { color in Color(color) } ?? Color.yellow.opacity(0.35)
    }
}

struct ObsidianMarkdownParser: MarkupParser {
    let baseURL: URL?
    let textSize: Double
    var sourceTokens: [ReadAloudSourceToken]? = nil
    /// The vault theme's colors, or nil for Graphite's.
    var themeColors: ReadingThemeColors? = nil

    func attributedString(for input: String) throws -> AttributedString {
        // The Markdown parser recurses once per nesting level; a note nested deeper than
        // this would exhaust the stack (see MarkdownNesting), so it is shown as plain text.
        if MarkdownNesting.exceedsSafeDepth(input) { return AttributedString(input) }
        // A numbered formula that is a block of its own is drawn by `NumberedEquationView`;
        // one that reaches here is among other text, and takes its numbers after its rows.
        let markdown = ObsidianInlineMarkup.inliningEquationNumbers(in: input)
        var attributed = try AttributedStringMarkdownParser(baseURL: baseURL, syntaxExtensions: [.math]).attributedString(for: markdown)
        Self.applyMarkers(start: ObsidianInlineMarkup.colorStartMarker, hexEnd: ObsidianInlineMarkup.colorHexEndMarker, end: ObsidianInlineMarkup.colorEndMarker, to: &attributed) { hex, range, text in
            if let color = Color(graphiteHex: hex) { text[range].foregroundColor = color }
        }
        let themeColors = themeColors, textSize = textSize
        Self.applyMarkers(start: ObsidianInlineMarkup.highlightStartMarker, hexEnd: nil, end: ObsidianInlineMarkup.highlightEndMarker, to: &attributed) { _, range, text in
            guard let themeColors else { text[range].backgroundColor = Color.yellow.opacity(0.35); return }
            // The theme's highlight, with its rounded ends and text color.
            text[range][RoundedRunBackgroundAttribute.self] = RoundedRunBackground(
                color: themeColors.highlight, cornerRadius: NoteThemeStyle.scaled(themeColors.highlightRadius, textSize: textSize), horizontalPadding: 1)
            if let highlightText = themeColors.highlightText { text[range].foregroundColor = highlightText }
        }
        // A footnote reference is found by its link, not by markers around its number: the
        // references are added to the note's text before `ReadingMarkerEscaping` escapes it,
        // so markers added there would be escaped as the note's own characters.
        var footnoteReferenceRanges: [Range<AttributedString.Index>] = []
        for (link, range) in attributed.runs[\.link] where link.flatMap(GraphiteOpenLink.footnoteNumber(of:)) != nil {
            footnoteReferenceRanges.append(range)
        }
        for range in footnoteReferenceRanges {
            attributed[range].font = .system(size: max(textSize * 0.7, GraphitePreferences.smallestNoteTextSize), weight: .semibold)
            attributed[range].baselineOffset = textSize * 0.35
        }
        if let themeColors { Self.applyThemeColors(themeColors, textSize: textSize, to: &attributed) }
        replaceTaskMarkers(in: &attributed)
        Self.restoreEscapedCharacters(in: &attributed)
        if let sourceTokens { _ = ReadingSourceAlignment.apply(sourceTokens, to: &attributed) }
        return attributed
    }

    /// Links in the theme's colors by kind, as Obsidian draws internal, unresolved and external
    /// links, and `#tags` in its tag color.
    static func applyThemeColors(_ colors: ReadingThemeColors, textSize: Double, to text: inout AttributedString) {
        var linkRuns: [(Range<AttributedString.Index>, Color)] = []
        for (link, range) in text.runs[\.link] {
            guard let link else { continue }
            let color: Color
            if link.scheme == GraphiteOpenLink.scheme {
                color = GraphiteOpenLink.isUnresolved(link) ? colors.unresolvedLink : colors.link
            } else if link.isFileURL {
                color = colors.link
            } else {
                color = colors.externalLink
            }
            linkRuns.append((range, color))
        }
        for (range, color) in linkRuns { text[range].foregroundColor = color }
        guard let tagColor = colors.tag, let tagPattern = Self.tagPattern else { return }
        let plain = String(text.characters)
        let nsPlain = plain as NSString
        for match in tagPattern.matches(in: plain, range: NSRange(location: 0, length: nsPlain.length)) {
            guard let stringRange = Range(match.range, in: plain),
                  let lower = AttributedString.Index(stringRange.lowerBound, within: text),
                  let upper = AttributedString.Index(stringRange.upperBound, within: text) else { continue }
            let range = lower..<upper
            // Not inside code or a link.
            guard !text[range].runs.contains(where: { run in run.link != nil || run.inlinePresentationIntent?.contains(.code) == true }) else { continue }
            text[range].foregroundColor = tagColor
            // A pill: the theme's background, corners and border, narrow enough that the space
            // between two tags still shows between their pills.
            if colors.tagBackground != nil || colors.tagBorder != nil {
                text[range][RoundedRunBackgroundAttribute.self] = RoundedRunBackground(
                    color: colors.tagBackground ?? .clear, cornerRadius: NoteThemeStyle.scaled(colors.tagRadius, textSize: textSize),
                    horizontalPadding: NoteThemeStyle.scaled(1.5, textSize: textSize), borderColor: colors.tagBorder,
                    borderWidth: CGFloat(colors.tagBorderWidth))
            }
        }
    }

    /// Obsidian's tags: `#` after a space or the start, then letters, digits, `_`, `-` and `/`,
    /// not only digits.
    private static let tagPattern = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}_/#&])#(?![\\p{N}]+(?![\\p{L}_/-]))[\\p{L}\\p{N}_/-]+")

    /// A task marked at the start of a list item becomes that item's checkbox, which
    /// `ObsidianListItemStyle` draws in place of the bullet; a completed task's text is
    /// dimmed and struck through, as in Obsidian. A task marked anywhere else, as in an
    /// indented code block or a table cell, is not a task and reads as the note has it.
    ///
    /// A long task list is one block, so this makes one pass over the text rather than
    /// searching it again for each task.
    private func replaceTaskMarkers(in text: inout AttributedString) {
        guard text.unicodeScalars.contains(where: ReadingTasks.isTaskMarker) else { return }
        struct TaskParagraph {
            let task: ReadingTasks.MarkedTask
            let markerIndex: AttributedString.Index
            /// Where the task's text starts, after the marked task and the space that follows it.
            let contentStart: AttributedString.Index
            let end: AttributedString.Index
        }
        var taskParagraphs: [TaskParagraph] = []
        var previousListItem: PresentationIntent.IntentType?
        for (presentationIntent, paragraphRange) in text.runs[\.presentationIntent] {
            let components = presentationIntent?.components ?? []
            // The first paragraph of a list item: a paragraph inside an item other than the
            // one the paragraph before it is in.
            let listItem = components.count > 1 && components[0].kind == .paragraph && Self.isListItem(components[1]) ? components[1] : nil
            defer { previousListItem = components.first(where: Self.isListItem) }
            guard let listItem, listItem != previousListItem,
                  let markedTask = ReadingTasks.markedTask(at: paragraphRange.lowerBound, in: text.unicodeScalars[paragraphRange]) else { continue }
            var contentStart = markedTask.end
            while contentStart < paragraphRange.upperBound, text.unicodeScalars[contentStart].properties.isWhitespace { contentStart = text.unicodeScalars.index(after: contentStart) }
            taskParagraphs.append(TaskParagraph(task: markedTask.task, markerIndex: paragraphRange.lowerBound, contentStart: contentStart, end: paragraphRange.upperBound))
        }
        for paragraph in taskParagraphs where paragraph.task.isChecked && paragraph.contentStart < paragraph.end {
            text[paragraph.contentStart..<paragraph.end].strikethroughStyle = .single
            text[paragraph.contentStart..<paragraph.end].foregroundColor = .secondary
        }
        var replaced = AttributedString()
        var sliceStart = text.startIndex
        var remainingTaskParagraphs = taskParagraphs[...]
        for markerIndex in text.unicodeScalars.indices where markerIndex >= sliceStart && ReadingTasks.isTaskMarker(text.unicodeScalars[markerIndex]) {
            guard let markedTask = ReadingTasks.markedTask(at: markerIndex, in: text.unicodeScalars) else { continue }
            replaced.append(text[sliceStart..<markerIndex])
            var attributes = text[markerIndex..<markedTask.end].runs.first?.attributes ?? AttributeContainer()
            if let paragraph = remainingTaskParagraphs.first, paragraph.markerIndex == markerIndex {
                remainingTaskParagraphs.removeFirst()
                attributes[AttributeScopes.TextualAttributes.AttachmentAttribute.self] = AnyAttachment(TaskCheckboxAttachment(task: paragraph.task))
                attributes[ReadingTaskAttribute.self] = paragraph.task
                replaced.append(AttributedString("\u{FFFC}", attributes: attributes))
                sliceStart = paragraph.contentStart
            } else {
                replaced.append(AttributedString(markedTask.task.sourceText, attributes: attributes))
                sliceStart = markedTask.end
            }
        }
        replaced.append(text[sliceStart..<text.endIndex])
        text = replaced
    }

    private static func isListItem(_ intent: PresentationIntent.IntentType) -> Bool {
        if case .listItem = intent.kind { return true }
        return false
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
    /// The vault's theme: the bullet and number color.
    var theme: NoteThemeStyle? = nil

    func makeBody(configuration: Configuration) -> some View {
        let task = configuration.content.runs.first?[ReadingTaskAttribute.self]
        HStack(alignment: .firstLineCenter, spacing: textSize * 0.5) {
            if let task {
                ReadingTaskCheckbox(task: task, label: Self.firstParagraphText(of: configuration.content), pointSize: textSize)
            } else {
                configuration.marker
                    .foregroundStyle(theme?.listMarkerColor.map { color in AnyShapeStyle(Color(color)) } ?? AnyShapeStyle(.primary))
            }
            configuration.block
        }
        // The checkbox sits where the bullet would be.
        .padding(.leading, task != nil ? textSize * 0.55 : 0)
    }

    /// The text of a list item's first paragraph, without the items nested under it.
    private static func firstParagraphText(of content: AttributedSubstring) -> String {
        guard let firstParagraph = content.runs[\.presentationIntent].first(where: { _ in true }) else { return "" }
        return String(content[firstParagraph.1].characters).replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
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

/// Stands in the text for a task's checkbox, which `ObsidianListItemStyle` draws where the
/// item's bullet would be. Nothing is drawn for it; copied text has the checkbox as written.
struct TaskCheckboxAttachment: Attachment {
    let task: ReadingTasks.MarkedTask

    var selectionStyle: AttachmentSelectionStyle { .text }
    var description: String { task.sourceText + " " }

    var body: some View { EmptyView() }

    /// As little room as an attachment can take: for one of no size, the text shows the
    /// picture of a missing image.
    func sizeThatFits(_ proposal: ProposedViewSize, in environment: TextEnvironmentValues) -> CGSize { CGSize(width: 1, height: 1) }
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

/// Code blocks as the editor draws them (`CodeBlockLineDecoration`), in the vault's
/// monospace font: one box without a border, as in Obsidian, the language at its top right,
/// and the code inset from its edges. The default style's `.monospaced()` would leave a
/// chosen text font in place for code.
struct ObsidianCodeBlockStyle: StructuredText.CodeBlockStyle {
    let monospaceFont: Font
    /// The vault's theme: its code background and text color, corners and border.
    var theme: NoteThemeStyle? = nil
    /// The code theme, whose box and text colors win over the vault theme's.
    var codeTheme = CodeColorTheme.obsidian

    @MainActor
    func makeBody(configuration: Configuration) -> some View {
        let language = configuration.languageHint.map { hint in NotePreviewDocument.codeBlockLanguage(ofFenceInfo: hint) } ?? ""
        let cornerRadius = CodeSyntaxColors.blockCornerRadius(theme: theme)
        let palette = CodeSyntaxColors.palette(codeTheme: codeTheme, noteTheme: theme)
        Overflow {
            configuration.label
                .font(monospaceFont)
                .textual.lineSpacing(.fontScaled(0.39))
                .textual.fontScale(0.882)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, language.isEmpty ? 12 : 26)
                .padding(.bottom, 12)
                .padding(.horizontal, 15)
        }
        .foregroundStyle(Color(palette.text))
        .background(Color(palette.background))
        .overlay(alignment: .topTrailing) {
            if !language.isEmpty {
                Text(language)
                    .font(.footnote)
                    .foregroundStyle(Color(palette.quietText))
                    .padding(.top, 7)
                    .padding(.trailing, 15)
                    .accessibilityLabel("\(language) code")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            // A theme's border, when it gives one; Graphite's box has none.
            if let borderWidth = theme?.codeBlockBorderWidth, borderWidth > 0, let borderColor = theme?.codeBlockBorderColor {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(Color(borderColor), lineWidth: CGFloat(min(borderWidth, 6)))
            }
        }
        .textual.blockSpacing(.fontScaled(top: 0.88, bottom: 0))
    }
}

/// The sizes Live Preview gives headings (`HeadingTypography`), so a heading does not jump
/// when the note switches to reading.
struct ObsidianHeadingStyle: StructuredText.HeadingStyle {
    /// The vault's theme: heading sizes, weights, colors and fonts (`HeadingTypography`).
    var theme: NoteThemeStyle? = nil
    var typography = NoteTypography.standard
    var textSize: Double = 17

    func makeBody(configuration: Configuration) -> some View {
        let level = min(max(configuration.headingLevel, 1), 6)
        let index = level - 1
        let headingColor = theme?.headingColors[index]
        // The theme's heading font, unless `appearance.json` names a text font, which wins.
        let family = typography.usesAppearanceTextFont ? nil : theme?.headingFamilies[index]
        let ornament = theme?.headingOrnaments[index]
        // The family is set around the scale, which scales the font it finds.
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            // Text a theme puts before a heading (`::before`), such as a level marker.
            if let prefix = ornament?.prefix {
                Text(prefix)
                    .foregroundStyle(ornament?.prefixColor.map { color in AnyShapeStyle(Color(color)) } ?? AnyShapeStyle(.secondary))
                    .accessibilityHidden(true)
            }
            configuration.label
        }
        .textCase(ornament?.isUppercase == true ? .uppercase : nil)
        .textual.fontScale(HeadingTypography.fontScale(level: level, theme: theme))
        .modifier(OptionalFontFamily(family: family, textSize: textSize))
        .fontWeight(Self.swiftUIWeight(HeadingTypography.weight(level: level, theme: theme)))
        .italic(theme?.headingItalic[index] == true)
        .foregroundStyle(headingColor.map { color in AnyShapeStyle(Color(color)) } ?? AnyShapeStyle(.primary))
        .modifier(HeadingOrnamentShapes(ornament: ornament, textSize: textSize))
        .textual.blockSpacing(.fontScaled(top: 1.2, bottom: 0.5))
    }

    static func swiftUIWeight(_ weight: PlatformFont.Weight) -> Font.Weight {
        switch weight {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .semibold
        }
    }
}

/// A theme's heading background and underline, across the column as Obsidian draws them.
private struct HeadingOrnamentShapes: ViewModifier {
    let ornament: NoteThemeStyle.HeadingOrnament?
    let textSize: Double

    func body(content: Content) -> some View {
        if let ornament, ornament.background != nil || ornament.underlineColor != nil {
            content
                .padding(.horizontal, ornament.background == nil ? 0 : NoteThemeStyle.scaled(6, textSize: textSize))
                .padding(.bottom, ornament.underlineWidth.map { width in CGFloat(width) + NoteThemeStyle.scaled(3, textSize: textSize) } ?? 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ornament.background.map { color in AnyShapeStyle(Color(color)) } ?? AnyShapeStyle(Color.clear),
                            in: RoundedRectangle(cornerRadius: NoteThemeStyle.scaled(4, textSize: textSize)))
                .overlay(alignment: .bottom) {
                    if let underlineColor = ornament.underlineColor, let width = ornament.underlineWidth {
                        Rectangle().fill(Color(underlineColor)).frame(height: CGFloat(min(max(width, 0.5), 6))).accessibilityHidden(true)
                    }
                }
        } else {
            content
        }
    }
}

/// A heading in the theme's font family, at the note's text size before the heading's scale.
private struct OptionalFontFamily: ViewModifier {
    let family: ResolvedFontFamily?
    let textSize: Double

    func body(content: Content) -> some View {
        if let family {
            content.font(NoteTypography.swiftUIFont(family, size: textSize))
        } else {
            content
        }
    }
}

/// Tables as in Obsidian: a table wider than the note wraps its text and shrinks its images
/// until it fits, and scrolls sideways only when it cannot become that narrow.
struct ObsidianTableStyle: StructuredText.TableStyle {
    /// The vault's theme: table borders and header shading.
    var theme: NoteThemeStyle? = nil

    func makeBody(configuration: Configuration) -> some View {
        let borderStyle = theme?.tableBorderColor.map { color in AnyShapeStyle(Color(color)) } ?? AnyShapeStyle(.secondary.opacity(0.35))
        let headerStyle = theme?.tableHeaderBackground.map { color in AnyShapeStyle(Color(color)) } ?? AnyShapeStyle(.secondary.opacity(0.12))
        Overflow { overflowState in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .textual.tableCellSpacing(horizontal: 1, vertical: 1)
                .textual.tableBackground { layout in
                    FilledRectangles(rectangles: Self.headerShading(in: layout), style: headerStyle)
                    // A theme's stripes on every second row.
                    if let stripe = theme?.tableStripeBackground {
                        FilledRectangles(rectangles: Self.stripes(in: layout), style: Color(stripe))
                    }
                }
                .textual.tableOverlay { layout in
                    FilledRectangles(rectangles: Self.hairlines(in: layout), style: borderStyle)
                }
                .padding(1)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(borderStyle, lineWidth: 1))
                .offeredScrollContainerWidth(overflowState.containerWidth)
        }
        .textual.blockSpacing(.init(top: 4, bottom: 12))
    }

    /// The header shading reaches the middle of the gap below it.
    private static func headerShading(in layout: StructuredText.TableLayout) -> [CGRect] {
        guard layout.numberOfRows > 0 else { return [] }
        var headerBounds = layout.rowBounds(0)
        if let firstDivider = layout.horizontalDividers().first { headerBounds.size.height = firstDivider.midY - headerBounds.minY }
        return [headerBounds.integral]
    }

    /// The body's second, fourth, … rows.
    private static func stripes(in layout: StructuredText.TableLayout) -> [CGRect] {
        stride(from: 2, to: layout.numberOfRows, by: 2).map { row in layout.rowBounds(row).integral }
    }

    /// Gaps between cells include padding, so a hairline is drawn in their middle.
    private static func hairlines(in layout: StructuredText.TableLayout) -> [CGRect] {
        layout.horizontalDividers().map { divider in CGRect(x: divider.minX, y: divider.midY - 0.5, width: divider.width, height: 1) }
            + layout.verticalDividers().map { divider in CGRect(x: divider.midX - 0.5, y: divider.minY, width: 1, height: divider.height) }
    }
}

/// Rectangles of one color, each a view of its own. A `Canvas` over the whole table is drawn
/// into one texture, and a long table is taller than a texture can be: its lines and header
/// shading were then not drawn at all.
private struct FilledRectangles<Style: ShapeStyle>: View {
    let rectangles: [CGRect]
    let style: Style

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(rectangles.indices, id: \.self) { rectangleIndex in
                let rectangle = rectangles[rectangleIndex]
                Rectangle().fill(style)
                    .frame(width: rectangle.width, height: rectangle.height)
                    .offset(x: rectangle.minX, y: rectangle.minY)
            }
        }
    }
}

extension View {
    /// Offers the view the width of the scroll view around it; see `ScrollContainerWidthProposal`.
    fileprivate func offeredScrollContainerWidth(_ containerWidth: CGFloat?) -> some View {
        ScrollContainerWidthProposal(containerWidth: containerWidth) { self }
    }
}

/// Offers its content the width of the scroll view around it. A scroll view offers no width
/// along the way it scrolls, so a table inside one would never wrap. The content keeps the
/// width it answers with, which is wider than the scroll view when it cannot fit.
private struct ScrollContainerWidthProposal: Layout {
    /// Nil until the scroll view has been laid out; the content then takes the width it likes.
    let containerWidth: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(contentProposal(for: proposal)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: contentProposal(for: proposal))
    }

    private func contentProposal(for proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: containerWidth ?? proposal.width, height: proposal.height)
    }
}

struct ObsidianTableCellStyle: StructuredText.TableCellStyle {
    /// The vault's theme: the header's text color.
    var theme: NoteThemeStyle? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(configuration.row == 0 ? .semibold : .regular)
            .foregroundStyle(configuration.row == 0 ? (theme?.tableHeaderTextColor.map { color in AnyShapeStyle(Color(color)) } ?? AnyShapeStyle(.primary)) : AnyShapeStyle(.primary))
            .textual.padding(.fontScaled(top: 0.35, leading: 0.6, bottom: 0.35, trailing: 0.6))
    }
}

struct ObsidianBlockQuoteStyle: StructuredText.BlockQuoteStyle {
    /// The vault's theme: the bar's color and thickness, and the quote's muted text.
    var theme: NoteThemeStyle? = nil

    func makeBody(configuration: Configuration) -> some View {
        let barStyle = theme?.blockquoteBorderColor.map { color in AnyShapeStyle(Color(color)) } ?? AnyShapeStyle(.tint.opacity(0.7))
        let barWidth = theme?.blockquoteBorderThickness.map { thickness in CGFloat(min(max(thickness, 1), 8)) } ?? 3
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: barWidth / 2).fill(barStyle).frame(width: barWidth)
            configuration.label
                .foregroundStyle(theme?.textMuted.map { color in AnyShapeStyle(Color(color)) } ?? AnyShapeStyle(.secondary))
                .textual.padding(.horizontal, .fontScaled(0.9))
                .textual.padding(.vertical, .fontScaled(theme?.blockquoteBackground == nil ? 0 : 0.5))
        }
        // A theme's quote box spans the column, as in Obsidian, with its background and corners.
        .frame(maxWidth: theme?.blockquoteBackground == nil ? nil : .infinity, alignment: .leading)
        .background(theme?.blockquoteBackground.map { color in AnyShapeStyle(Color(color)) } ?? AnyShapeStyle(Color.clear),
                    in: RoundedRectangle(cornerRadius: CGFloat(min(theme?.blockquoteRadius ?? 0, 24))))
    }
}

/// A horizontal rule in the theme's color and thickness, or the system's divider.
struct ObsidianThematicBreakStyle: StructuredText.ThematicBreakStyle {
    var theme: NoteThemeStyle? = nil

    func makeBody(configuration: Configuration) -> some View {
        ThemedRule(theme: theme).textual.blockSpacing(.fontScaled(top: 1, bottom: 1))
    }
}

/// A dashed or dotted line across the column.
private struct DashedRule: View {
    let color: Color
    let thickness: CGFloat
    let isDotted: Bool

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                path.move(to: CGPoint(x: 0, y: thickness / 2))
                path.addLine(to: CGPoint(x: geometry.size.width, y: thickness / 2))
            }
            .stroke(color, style: StrokeStyle(lineWidth: thickness, lineCap: isDotted ? .round : .butt, dash: isDotted ? [0.1, thickness * 3] : [thickness * 4, thickness * 3]))
        }
    }
}

/// The rule itself, shared by reading view and Live Preview.
struct ThemedRule: View {
    let theme: NoteThemeStyle?

    var body: some View {
        let thickness = CGFloat(min(max(theme?.horizontalRuleThickness ?? 1, 0.5), 6))
        if let style = theme?.horizontalRuleStyle {
            // Dashed or dotted, as the theme draws its rule.
            DashedRule(color: theme?.horizontalRuleColor.map { color in Color(color) } ?? Color(NoteThemeStyle.systemSeparator), thickness: thickness, isDotted: style == "dotted")
                .frame(height: thickness).accessibilityHidden(true)
        } else if let color = theme?.horizontalRuleColor {
            Rectangle().fill(Color(color)).frame(height: thickness)
                .accessibilityHidden(true)
        } else {
            Divider()
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
    let sourceTokens: [ReadAloudSourceToken]?
    let automaticallyExpandsForReading: Bool
    @ViewBuilder let content: () -> Body
    @Environment(\.accent) private var accent
    @Environment(\.noteTypography) private var typography
    @Environment(\.noteTheme) private var theme
    @State private var localIsExpanded: Bool
    @Environment(\.calloutFoldNote) private var foldNote

    /// The person's expansion, kept where Read Aloud can see it when the note is known.
    private var isExpanded: Bool {
        get {
            guard let foldNote else { return localIsExpanded }
            return foldNote.store.isExpanded(notePath: foldNote.notePath, key: ReadAloudFolding.calloutKey(type: type, title: foldKeyTitle),
                                             initially: folding != .collapsed)
        }
        nonmutating set {
            localIsExpanded = newValue
            foldNote?.store.setExpanded(newValue, notePath: foldNote?.notePath ?? "", key: ReadAloudFolding.calloutKey(type: type, title: foldKeyTitle))
        }
    }
    /// The title as written in the note, which the fold key is made of.
    var foldKeyTitle: String
    /// Graphite's 8 points, or the theme's corner radius.
    private var calloutRadius: CGFloat { theme?.calloutRadius.map { radius in NoteThemeStyle.scaled(radius, textSize: textSize) } ?? 8 }

    init(type: String, title: String, folding: CalloutFolding, root: URL, textSize: Double, navigate: @escaping (String, Bool) -> Void,
         scrollToHeading: ((String) -> Void)? = nil, sourceTokens: [ReadAloudSourceToken]? = nil,
         automaticallyExpandsForReading: Bool = false, foldKeyTitle: String? = nil, @ViewBuilder content: @escaping () -> Body) {
        self.type = type; self.title = title; self.folding = folding; self.root = root; self.textSize = textSize; self.navigate = navigate
        self.scrollToHeading = scrollToHeading; self.content = content
        self.sourceTokens = sourceTokens
        self.automaticallyExpandsForReading = automaticallyExpandsForReading
        _localIsExpanded = State(initialValue: folding != .collapsed)
        self.foldKeyTitle = foldKeyTitle ?? title
    }

    var body: some View {
        let appearance = CalloutAppearance(type: type, theme: theme)
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if folding != .notFoldable { withAnimation(GraphiteMotion.animation(.snappy)) { isExpanded.toggle() } }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: appearance.systemImage).foregroundStyle(appearance.titleColor)
                    // A link in the title takes the tap before the fold button does.
                    StructuredText(title, parser: ObsidianMarkdownParser(baseURL: root, textSize: textSize, sourceTokens: sourceTokens))
                        .id(textSize)
                        .id(sourceTokens)
                        .font(typography.textSwiftUIFont(size: textSize).weight(.semibold))
                        .foregroundStyle(appearance.titleColor)
                        .textual.inlineStyle(InlineStyle.default.link(.foregroundColor(accent)))
                        .textual.imageAttachmentLoader(VaultImageLoader(root: root))
                        .environment(\.openURL, ObsidianMarkdownText.linkAction(root: root, navigate: navigate, scrollToHeading: scrollToHeading))
                    if folding != .notFoldable {
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(appearance.titleColor)
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
        .background(appearance.color.opacity(theme?.calloutTintOpacity ?? CalloutAppearance.tintOpacity), in: RoundedRectangle(cornerRadius: calloutRadius))
        .overlay {
            // A theme's callout border, in the callout's own color.
            if let borderWidth = theme?.calloutBorderWidth {
                RoundedRectangle(cornerRadius: calloutRadius).strokeBorder(appearance.color, lineWidth: CGFloat(min(max(borderWidth, 0.5), 6)))
            }
        }
    }
}

/// Obsidian's callout types, their aliases, colors, and icons.
struct CalloutAppearance {
    /// The opacity of the callout's color behind it.
    static let tintOpacity = 0.1
    /// The color the callout is tinted with.
    var color: Color
    /// The title, its icon and its fold chevron: the same color, darkened in light
    /// appearance until it reads on the tint (the system colors alone read about 2:1 there).
    var titleColor: Color
    let systemImage: String

    init(type: String) {
        let systemColor: PlatformColor
        switch type {
        case "abstract", "summary", "tldr": (systemColor, systemImage) = (.systemCyan, "list.clipboard")
        case "info": (systemColor, systemImage) = (.systemBlue, "info.circle")
        case "todo": (systemColor, systemImage) = (.systemBlue, "checkmark.circle")
        case "tip", "hint", "important": (systemColor, systemImage) = (.systemTeal, "flame")
        case "success", "check", "done": (systemColor, systemImage) = (.systemGreen, "checkmark")
        case "question", "help", "faq": (systemColor, systemImage) = (.systemOrange, "questionmark.circle")
        case "warning", "caution", "attention": (systemColor, systemImage) = (.systemOrange, "exclamationmark.triangle")
        case "failure", "fail", "missing": (systemColor, systemImage) = (.systemRed, "xmark")
        case "danger", "error": (systemColor, systemImage) = (.systemRed, "bolt")
        case "bug": (systemColor, systemImage) = (.systemRed, "ladybug")
        case "example": (systemColor, systemImage) = (.systemPurple, "list.bullet")
        case "quote", "cite": (systemColor, systemImage) = (.systemGray, "quote.opening")
        default: (systemColor, systemImage) = (.systemBlue, "pencil")
        }
        color = Color(systemColor)
        titleColor = Color(PlatformColor.legibleOnOwnTint(systemColor, tintOpacity: Self.tintOpacity))
    }

    /// The type's colors from the vault's theme when it sets them (an unknown type takes the
    /// note color, as in Obsidian), its title kept readable on the tint; else Graphite's.
    init(type: String, theme: NoteThemeStyle?) {
        self.init(type: type)
        let lowercasedType = type.lowercased()
        guard let themed = theme?.calloutColors[lowercasedType] ?? theme?.calloutColors[ObsidianCalloutTypes.canonicalType(lowercasedType)] else { return }
        color = Color(themed.tint)
        titleColor = Color(themed.title)
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
        let fittedWidth = min(max(proposal.width ?? naturalWidth, Self.narrowestFittedWidth), naturalWidth)
        return CGSize(width: fittedWidth, height: fittedWidth * height / width)
    }
    /// The narrowest, in points, an image is drawn where it is offered less, as in a table
    /// too crowded to fit the note: narrower, a figure can no longer be made out.
    private static let narrowestFittedWidth: Double = 48
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
    /// Opens the drawing editor over an image; nil where drawings are off.
    var drawOnImage: ((VaultPath) -> Void)? = nil

    static func == (leftActions: ReadingImageActions, rightActions: ReadingImageActions) -> Bool {
        leftActions.providerIdentity == rightActions.providerIdentity && (leftActions.editDrawing == nil) == (rightActions.editDrawing == nil)
            && (leftActions.drawOnImage == nil) == (rightActions.drawOnImage == nil)
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
                                  view: imageActions.map { imageActions in { imageActions.viewImage(path) } },
                                  drawOnImage: DrawableImages.canDrawOn(path) ? imageActions?.drawOnImage.map { drawOnImage in { drawOnImage(path) } } : nil)
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
