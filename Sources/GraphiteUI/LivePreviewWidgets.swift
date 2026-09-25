import SwiftUI
import GraphiteCore
import GraphiteApple

/// What rendered Live Preview blocks need from the workspace, without depending on it.
struct LivePreviewEnvironment {
    let root: URL
    let textSize: Double
    let colorsEnabled: Bool
    let paletteHexByName: [String: String]
    let drawingVersion: Int
    let resolve: (String, Bool) async -> VaultPath?
    let open: (VaultPath) -> Void
    let follow: (String, Bool) -> Void
    /// Nil when the Properties view is turned off: the frontmatter then stays as text.
    let updateProperties: (([NoteProperty]) -> Void)?
    /// Property types assigned in `.obsidian/types.json`, which the frontmatter is read with.
    var declaredPropertyTypes: [String: PropertyType] = [:]
    /// Nil when Bases are turned off: base blocks then show their YAML.
    var baseContext: BaseEmbedContext? = nil
    /// Shows an embedded image full screen, where it can be zoomed.
    var viewImage: ((VaultPath) -> Void)? = nil
    /// Opens a Graphite drawing in the drawing editor; nil when drawings are turned off.
    var editDrawing: ((VaultPath) -> Void)? = nil
    /// Changes when the index takes in new files, so embeds not found yet look again.
    var indexVersion = 0
    /// The widest, in points, the note's column shows an embedded image; nil when the
    /// column is as wide as the window. Images are decoded for this width.
    var embeddedImageColumnWidth: CGFloat? = nil
}

/// A rendered stand-in for concealed Live Preview source.
struct LivePreviewWidgetView: View {
    let block: LivePreviewBlock
    let environment: LivePreviewEnvironment
    let revealSource: () -> Void
    let reportHeight: (CGFloat) -> Void
    @State private var parsedSource = LivePreviewParsedSource()

    var body: some View {
        // The source button has its own column so it never covers a player's or viewer's controls.
        HStack(alignment: .top, spacing: 8) {
            // The vertical stack keeps dividers inside the content horizontal.
            VStack(alignment: .leading, spacing: 0) { content }.frame(maxWidth: .infinity, alignment: .leading)
            if block.kind != .horizontalRule {
                Button("Edit Source", systemImage: "chevron.left.forwardslash.chevron.right") { revealSource() }
                    .labelStyle(.iconOnly).font(.caption).foregroundStyle(.secondary).buttonStyle(.borderless)
                    .frame(width: 28, height: 28)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel("Edit source")
            }
        }
        // The reserved space follows the view's natural height, not the frame it was given.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 4)
        // While an embed inside is loading, its placeholder's height is not reported: it
        // would replace the block's remembered height, so the text below would jump up
        // while the embed loads and back down when it appears. The measurement becomes a
        // height again when loading ends, even if the loaded embed is just as tall.
        .backgroundPreferenceValue(LivePreviewEmbedLoadingKey.self) { isLoadingEmbed in
            Color.clear.onGeometryChange(for: CGFloat?.self) { geometry in isLoadingEmbed ? nil : geometry.size.height } action: { height in
                if let height { reportHeight(height) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var content: some View {
        switch block.kind {
        case .frontmatter:
            if let properties = parsedSource.properties(from: block.markdown, declaredTypes: environment.declaredPropertyTypes) {
                PropertiesPanel(properties: properties, update: environment.updateProperties, follow: environment.follow,
                                declaredTypes: environment.declaredPropertyTypes)
            } else {
                Label("These properties are not valid YAML. Edit the source to fix them.", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange).onTapGesture(perform: revealSource)
            }
        case .table:
            RenderedMarkdownBlock(markdown: block.markdown, environment: environment)
                .contentShape(Rectangle())
                .onTapGesture(perform: revealSource)
        case .mathBlock:
            // Centered, as Obsidian shows display math.
            RenderedMarkdownBlock(markdown: block.markdown, environment: environment)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(perform: revealSource)
        case .embed(let embed):
            LivePreviewEmbedView(embed: embed, environment: environment, revealSource: revealSource)
        case .baseDefinition(let yaml):
            // No tap-to-reveal here: taps belong to the base's rows; the Edit Source button reveals it.
            BaseCodeBlockView(yaml: yaml, context: environment.baseContext)
        case .horizontalRule:
            Divider().padding(.vertical, 10)
        case .callout:
            if case .callout(let type, let title, let folding, let bodyBlocks)? = parsedSource.calloutBlock(from: block.markdown) {
                LivePreviewCalloutView(type: type, title: title, folding: folding, bodyBlocks: bodyBlocks, environment: environment, revealSource: revealSource)
            }
        }
    }
}

/// Whether an embed in a rendered block is still loading.
private struct LivePreviewEmbedLoadingKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// A rendered block's source, parsed once per change of the source rather than on every
/// view update: the editor replaces its rendered blocks' views after each save.
/// A reference, so remembering a parse during a view update changes no view state.
@MainActor
private final class LivePreviewParsedSource {
    private var propertiesSource: (markdown: String, declaredTypes: [String: PropertyType])?
    private var parsedProperties: [NoteProperty]?
    private var calloutSource: String?
    private var parsedCalloutBlock: NotePreviewBlock?

    /// The frontmatter's properties, or nil when its YAML is not valid.
    func properties(from markdown: String, declaredTypes: [String: PropertyType]) -> [NoteProperty]? {
        if propertiesSource?.markdown != markdown || propertiesSource?.declaredTypes != declaredTypes {
            let yaml = (try? MarkdownSemantics.parse(markdown))?.frontmatter ?? ""
            parsedProperties = NoteProperties.parse(yaml, declaredTypes: declaredTypes)
            propertiesSource = (markdown, declaredTypes)
        }
        return parsedProperties
    }

    func calloutBlock(from markdown: String) -> NotePreviewBlock? {
        if calloutSource != markdown {
            parsedCalloutBlock = NotePreviewDocument.blocks(from: markdown).first
            calloutSource = markdown
        }
        return parsedCalloutBlock
    }
}

/// A callout drawn as a box, as in Obsidian's Live Preview. Its title folds it; a tap on
/// its body shows the source.
private struct LivePreviewCalloutView: View {
    let type: String
    let title: String
    let folding: CalloutFolding
    let bodyBlocks: [NotePreviewBlock]
    let environment: LivePreviewEnvironment
    let revealSource: () -> Void

    var body: some View {
        CalloutView(type: type, title: LivePreviewText.prepared(title, colorsEnabled: environment.colorsEnabled, paletteHexByName: environment.paletteHexByName),
                    folding: folding, root: environment.root, textSize: environment.textSize, navigate: environment.follow) {
            LivePreviewBlockStack(blocks: bodyBlocks, environment: environment, allowsNoteEmbeds: true, revealSource: revealSource)
                .contentShape(Rectangle())
                .onTapGesture(perform: revealSource)
        }
    }
}

/// Reading-view blocks inside a Live Preview view: a callout's body or an embedded note.
private struct LivePreviewBlockStack: View {
    let blocks: [NotePreviewBlock]
    let environment: LivePreviewEnvironment
    /// Embedded notes are shown one level deep, so notes that embed each other end.
    let allowsNoteEmbeds: Bool
    let revealSource: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
    }

    /// Type-erased, because a callout can contain callouts.
    private func view(for block: NotePreviewBlock) -> AnyView {
        switch block {
        case .markdown(let markdown):
            AnyView(RenderedMarkdownBlock(markdown: markdown, environment: environment))
        case .heading(let level, let text, _):
            AnyView(RenderedMarkdownBlock(markdown: String(repeating: "#", count: level) + " " + text, environment: environment))
        case .callout(let type, let title, let folding, let bodyBlocks):
            AnyView(LivePreviewCalloutView(type: type, title: title, folding: folding, bodyBlocks: bodyBlocks, environment: environment, revealSource: revealSource))
        case .embed(let embed):
            AnyView(LivePreviewEmbedView(embed: embed, environment: environment, allowsNoteEmbeds: allowsNoteEmbeds, revealSource: revealSource))
        case .baseDefinition(let yaml):
            AnyView(BaseCodeBlockView(yaml: yaml, context: environment.baseContext))
        case .displayMath(let markdown):
            AnyView(RenderedMarkdownBlock(markdown: markdown, environment: environment).frame(maxWidth: .infinity))
        }
    }
}

/// A table or math block, with embedded images resolved against the vault first.
private struct RenderedMarkdownBlock: View {
    let markdown: String
    let environment: LivePreviewEnvironment
    @State private var prepared: PreparedMarkdown?
    /// The `preparationTaskKey` of the last completed preparation. A preparation's own
    /// result can change the key (an unresolved embed starts following the index), which
    /// must not prepare the text again.
    @State private var settledPreparationTaskKey: String?

    private struct PreparedMarkdown {
        let sourceKey: String
        let markdown: String
        let hasUnresolvedEmbeds: Bool
    }

    /// Everything the prepared text depends on besides the index. The editor keeps this
    /// view while colors, the palette, or a drawing change, so a preparation made for
    /// anything else is stale and is not shown.
    private var sourceKey: String {
        let palette = environment.paletteHexByName.sorted { firstEntry, secondEntry in firstEntry.key < secondEntry.key }
            .map { entry in "\(entry.key)=\(entry.value)" }.joined(separator: ",")
        return "\(markdown.hashValue)|\(environment.drawingVersion)|\(environment.colorsEnabled)|\(palette)"
    }

    /// An embed not found yet (the vault may still be indexing) is looked up again when
    /// the index changes; a table whose embeds were all found is not prepared again.
    private var preparationTaskKey: String {
        let key = sourceKey
        let followsIndex = LivePreviewText.hasWikiEmbed(markdown) && (prepared?.sourceKey != key || prepared?.hasUnresolvedEmbeds == true)
        return "\(key)|\(followsIndex ? environment.indexVersion : -1)"
    }

    var body: some View {
        let key = sourceKey
        let preparedMarkdown = prepared?.sourceKey == key ? prepared?.markdown : nil
        ObsidianMarkdownText(markdown: preparedMarkdown ?? LivePreviewText.prepared(markdown, colorsEnabled: environment.colorsEnabled, paletteHexByName: environment.paletteHexByName),
                             root: environment.root, textSize: environment.textSize, navigate: environment.follow,
                             // `follow` scrolls the note to a heading written as `#heading`,
                             // and a heading's anchor is its own anchor.
                             scrollToHeading: { anchor in environment.follow("#" + anchor, true) })
            .task(id: preparationTaskKey) {
                guard preparationTaskKey != settledPreparationTaskKey else { return }
                let preparation = await LivePreviewText.preparedResolvingEmbeds(markdown, environment: environment)
                guard !Task.isCancelled else { return }
                prepared = PreparedMarkdown(sourceKey: key, markdown: preparation.markdown, hasUnresolvedEmbeds: preparation.hasUnresolvedEmbeds)
                settledPreparationTaskKey = preparationTaskKey
            }
    }
}

/// Wikilinks shown as their display text, plus colors and highlights, for rendered blocks.
enum LivePreviewText {
    private static let wikiEmbedPattern = try? NSRegularExpression(pattern: "!\\[\\[([^\\]|\\n]+)(?:\\|([^\\]\\n]+))?\\]\\]")

    /// Whether `markdown` may embed a vault file that `preparedResolvingEmbeds` looks up.
    static func hasWikiEmbed(_ markdown: String) -> Bool { markdown.contains("![[") }

    /// Also turns `![[image.png|300]]` into an image the renderer can show.
    /// `hasUnresolvedEmbeds` tells whether an embed was not found in the vault.
    @MainActor
    static func preparedResolvingEmbeds(_ markdown: String, environment: LivePreviewEnvironment) async -> (markdown: String, hasUnresolvedEmbeds: Bool) {
        guard let wikiEmbedPattern, hasWikiEmbed(markdown) else {
            return (prepared(markdown, colorsEnabled: environment.colorsEnabled, paletteHexByName: environment.paletteHexByName), false)
        }
        var hasUnresolvedEmbeds = false
        let source = markdown as NSString
        let output = NSMutableString(string: markdown)
        let codeRanges = MarkdownCodeRanges.ranges(in: source)
        for match in wikiEmbedPattern.matches(in: markdown, range: NSRange(location: 0, length: source.length)).reversed()
        where !MarkdownCodeRanges.range(match.range, isInside: codeRanges) {
            let target = source.substring(with: match.range(at: 1))
            let label = match.range(at: 2).location == NSNotFound ? nil : source.substring(with: match.range(at: 2))
            guard let path = await environment.resolve(target, true) else {
                hasUnresolvedEmbeds = true
                continue
            }
            guard DocumentKind(path: path) == .image, let location = try? path.url(in: environment.root) else { continue }
            let imageLocation = PreviewImageFragment.url(for: location, displaySize: label.flatMap(EmbedDisplaySize.parse(label:)), version: environment.drawingVersion)
            output.replaceCharacters(in: match.range, with: "![\(ReadingViewBuilder.escapedLabel(path.stem))](\(GraphiteOpenLink.markdownDestination(imageLocation)))")
        }
        return (prepared(output as String, colorsEnabled: environment.colorsEnabled, paletteHexByName: environment.paletteHexByName), hasUnresolvedEmbeds)
    }

    private static let wikilinkPattern = try? NSRegularExpression(pattern: "(?<!!)\\[\\[([^\\]|\\n]+)(?:\\|([^\\]\\n]+))?\\]\\]")

    static func prepared(_ markdown: String, colorsEnabled: Bool, paletteHexByName: [String: String]) -> String {
        var text = markdown
        if let wikilinkPattern {
            let source = text as NSString
            let output = NSMutableString(string: text)
            let codeRanges = MarkdownCodeRanges.ranges(in: source)
            for match in wikilinkPattern.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed()
            where !MarkdownCodeRanges.range(match.range, isInside: codeRanges) {
                var target = source.substring(with: match.range(at: 1))
                let alias = match.range(at: 2).location == NSNotFound ? nil : source.substring(with: match.range(at: 2))
                // `[[Note\|alias]]` in a table: the backslash escapes the pipe.
                if alias != nil, target.hasSuffix("\\") { target.removeLast() }
                // Escaped and percent-encoded as in reading view, so a backslash at the end of
                // the label or an unbalanced parenthesis in the target keeps the link whole.
                let label = ReadingViewBuilder.escapedLabel(alias ?? (target.hasPrefix("#") ? String(target.dropFirst()) : target))
                output.replaceCharacters(in: match.range, with: "[\(label)](\(GraphiteOpenLink.markdownDestination(target: target)))")
            }
            text = output as String
        }
        return ObsidianInlineMarkup.preparedForReading(text, colorsEnabled: colorsEnabled, paletteHexByName: paletteHexByName)
    }
}

/// An embed resolved against the vault: an image or drawing, video, audio, PDF, or a link.
private struct LivePreviewEmbedView: View {
    let embed: EmbedReference
    let environment: LivePreviewEnvironment
    var allowsNoteEmbeds = true
    let revealSource: () -> Void
    @Environment(\.displayScale) private var displayScale
    @State private var resolution: EmbedResolution = .loading
    /// The `resolutionKey` of the last completed lookup. A lookup's own result changes the
    /// key (a missing embed starts following the index), which must not look it up again.
    @State private var settledResolutionKey: String?

    enum EmbedResolution {
        case loading
        case missing
        /// The file is in the vault, but it cannot be shown: a damaged or unsupported image.
        case unreadable(VaultPath)
        /// Decoded off the main thread for the width it is shown at.
        case image(path: VaultPath, image: CGImage, aspectRatio: CGFloat, isEditableDrawing: Bool)
        case video(URL)
        case audio(URL, String)
        case pdf(VaultPath, URL, PDFEmbedOptions)
        /// An embedded note, or the section under one of its headings.
        case note(VaultPath, heading: String?, blocks: [NotePreviewBlock])
        /// An embedded note that has no block or heading named by the embed's subpath.
        case missingSection(VaultPath, subpath: String)
        case file(VaultPath)
    }

    /// An embedded note's content, read off the main thread.
    private enum EmbeddedNotePart: Sendable {
        case blocks([NotePreviewBlock])
        case missingSection
    }

    var body: some View {
        Group {
            switch resolution {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 60)
            case .missing:
                Label("“\(embed.target)” is not in this vault yet.", systemImage: "questionmark.square.dashed")
                    .font(.callout).foregroundStyle(.secondary).onTapGesture(perform: revealSource)
            case .unreadable(let path):
                Label("“\(path.name)” cannot be shown. The file may be damaged or in a format that is not supported.", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.secondary).onTapGesture(perform: revealSource)
            case .image(let path, let image, let aspectRatio, let isEditableDrawing):
                // The </> button shows the source.
                EmbeddedImageView(image: image, aspectRatio: aspectRatio,
                                  displayWidth: embed.displaySize.map { size in CGFloat(size.fittedWidth(aspectRatio: aspectRatio)) },
                                  edit: isEditableDrawing ? environment.editDrawing.map { editDrawing in { editDrawing(path) } } : nil,
                                  view: environment.viewImage.map { viewImage in { viewImage(path) } } ?? revealSource)
            case .video(let location):
                EmbeddedMediaPlayer(location: location)
            case .audio(let location, let name):
                EmbeddedAudioPlayer(location: location, name: name)
            case .pdf(let path, let location, let options):
                EmbeddedPDFViewer(location: location, startPageNumber: options.startPageNumber, height: options.height.map { height in CGFloat(height) }) { pageIndex in
                    environment.follow(path.rawValue + "#page=\(pageIndex + 1)", true)
                }
            case .note(let path, let heading, let blocks):
                // Drawn like reading view's embedded notes: a link to the note, then its content.
                VStack(alignment: .leading, spacing: 10) {
                    Button { environment.follow(path.rawValue + (heading.map { "#" + $0 } ?? ""), true) } label: {
                        Label(path.stem + (heading.map { " > " + $0 } ?? ""), systemImage: "doc.text").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    LivePreviewBlockStack(blocks: blocks, environment: environment, allowsNoteEmbeds: false, revealSource: revealSource)
                }
                .padding(.leading, 16)
                .overlay(alignment: .leading) { Rectangle().fill(.tint.opacity(0.6)).frame(width: 3) }
            case .missingSection(let path, let subpath):
                Label(NoteBlocks.missingSectionMessage(subpath: subpath, noteName: path.stem), systemImage: "questionmark.square.dashed")
                    .font(.callout).foregroundStyle(.secondary).onTapGesture(perform: revealSource)
            case .file(let path) where DocumentKind(path: path) == .base:
                BaseFileEmbedView(path: path, viewName: embed.target.split(separator: "#", maxSplits: 1).dropFirst().first.map(String.init),
                                  context: environment.baseContext, openWithoutContext: environment.open)
            case .file(let path):
                Button { environment.open(path) } label: {
                    Label(path.name, systemImage: "doc.text")
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .preference(key: LivePreviewEmbedLoadingKey.self, value: isLoading)
        .task(id: resolutionKey) {
            guard resolutionKey != settledResolutionKey else { return }
            await resolve()
            guard !Task.isCancelled else { return }
            settledResolutionKey = resolutionKey
        }
    }

    /// An embed not found yet (the vault may still be indexing) looks again when the
    /// index changes; one found is not reloaded for every save elsewhere. An image is
    /// decoded again when the width it is shown at changes.
    private var resolutionKey: String {
        "\(embed.target)-\(environment.drawingVersion)-\(isMissing ? environment.indexVersion : -1)-\(displayPixelWidth ?? 0)"
    }

    private var displayPixelWidth: Int? {
        EmbeddedImageDisplayWidth.pixelWidth(columnWidth: environment.embeddedImageColumnWidth, displaySize: embed.displaySize, displayScale: displayScale)
    }

    private var isMissing: Bool {
        if case .missing = resolution { return true }
        return false
    }

    private var isLoading: Bool {
        if case .loading = resolution { return true }
        return false
    }

    private func resolve() async {
        guard let path = await environment.resolve(embed.target, embed.isWiki), let location = try? path.url(in: environment.root) else {
            resolution = .missing
            return
        }
        let fileExtension = path.fileExtension
        if MediaFileKind.videoExtensions.contains(fileExtension) { resolution = .video(location); return }
        if MediaFileKind.audioExtensions.contains(fileExtension) { resolution = .audio(location, path.name); return }
        let isDrawingPDF = DocumentKind(path: path) == .pdf ? await ImageFileService().isEditableDrawingPDF(at: location) : false
        if DocumentKind(path: path) == .image || isDrawingPDF {
            // Widget views are discarded off screen and after a drawing is saved; the shared
            // cache makes an image again only when its file changed.
            guard let thumbnail = try? await ReadingImageCache.shared.thumbnail(for: location, kind: .block, displayPixelWidth: displayPixelWidth) else {
                resolution = .unreadable(path); return
            }
            resolution = .image(path: path, image: thumbnail.image, aspectRatio: thumbnail.aspectRatio, isEditableDrawing: thumbnail.isEditableDrawing)
            return
        }
        let subpath = embed.target.split(separator: "#", maxSplits: 1).dropFirst().first.map(String.init)
        if DocumentKind(path: path) == .pdf {
            resolution = .pdf(path, location, subpath.map(PDFEmbedOptions.init(fragment:)) ?? PDFEmbedOptions())
            return
        }
        if DocumentKind(path: path) == .markdown && allowsNoteEmbeds,
           let part = await Task.detached(priority: .userInitiated, operation: { Self.embeddedNotePart(at: location, subpath: subpath) }).value {
            switch part {
            case .blocks(let blocks): resolution = .note(path, heading: subpath, blocks: blocks)
            case .missingSection: resolution = .missingSection(path, subpath: subpath ?? "")
            }
            return
        }
        resolution = .file(path)
    }

    /// The embedded part of a note, read and parsed off the main thread: the coordinated
    /// read waits for a file provider to download a note that is not on the device yet.
    nonisolated private static func embeddedNotePart(at location: URL, subpath: String?) -> EmbeddedNotePart? {
        guard let snapshot = try? AtomicFileWriter().read(location, maximumBytes: NotePreviewDocument.maximumEmbeddedNoteBytes),
              let source = String(data: snapshot.data, encoding: .utf8), let body = try? MarkdownSemantics.parse(source).body else { return nil }
        guard let part = NoteBlocks.embeddedPart(of: body, subpath: subpath) else { return .missingSection }
        return .blocks(NotePreviewDocument.blocks(from: part))
    }
}
