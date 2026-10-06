import SwiftUI
import GraphiteCore
import GraphiteIndex
import GraphiteApple

/// Reading-view builds of card text, kept while the canvas is open so a card that
/// scrolls back into view, or is shown again after a zoom, does not build again.
@MainActor
final class CanvasCardRenderCache {
    struct Build {
        let key: ReadingBuildKey
        let blocks: [RenderedBlock]
        let hasMissingEmbeds: Bool
    }

    private struct Entry: Hashable {
        let sourcePath: VaultPath
        let source: String
    }

    private var builds: [Entry: Build] = [:]
    /// Oldest first, to let go of the builds used longest ago.
    private var entriesByAge: [Entry] = []
    private static let maximumBuildCount = 300

    func build(of source: String, sourcePath: VaultPath, root: URL, configuration: ReadingConfiguration) -> Build? {
        guard let build = builds[Entry(sourcePath: sourcePath, source: source)],
              build.key.describesBuild(of: source, path: sourcePath, root: root, configuration: configuration) else { return nil }
        return build
    }

    func keep(_ build: Build, of source: String, sourcePath: VaultPath) {
        let entry = Entry(sourcePath: sourcePath, source: source)
        if builds[entry] == nil { entriesByAge.append(entry) }
        builds[entry] = build
        while entriesByAge.count > Self.maximumBuildCount { builds[entriesByAge.removeFirst()] = nil }
    }
}

/// What assistive technologies are told about a card that shows its content.
struct CanvasCardAccessibility {
    let label: String
    let value: String
    /// Higher is read first.
    let sortPriority: Double
}

/// One card with its content: Markdown, a note, an image, a PDF page, a media player,
/// a web address, or a plain description of a file or an unknown kind of card.
struct CanvasCardView: View {
    let node: CanvasNode
    let session: CanvasSession
    let environment: CanvasCardEnvironment
    let isWriting: Bool
    /// Whether this text card's Markdown is being edited in place.
    let isEdited: Bool
    /// In Read, whether the card was tapped, which lets its content scroll.
    let isFocused: Bool
    var accessibility: CanvasCardAccessibility?
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .subheadline) private var titleSize = 15.0
    /// A line of the system font is about this much taller than its point size.
    private static let titleLineHeightRatio = 1.25

    var body: some View {
        let tint = node.color.map { color in CanvasPalette.color(color, colorScheme: colorScheme) }
        let shape = RoundedRectangle(cornerRadius: CanvasPalette.cardCornerRadius)
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                CanvasPalette.card
                if let tint { tint.opacity(CanvasPalette.cardTintOpacity) }
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(tint ?? CanvasPalette.neutralLine, lineWidth: CanvasPalette.cardBorderWidth) }
            // While writing, touches on a card move and select it; only the card being
            // edited takes them itself.
            .allowsHitTesting(!isWriting || isEdited)
            .overlay(alignment: .topLeading) { title }
            .modifier(CanvasCardAccessibilityModifier(accessibility: accessibility, isSelected: session.selectedNodeIdentifiers.contains(node.id)))
    }

    @ViewBuilder private var content: some View {
        switch node.content {
        case .text(let text):
            if isEdited {
                CanvasTextCardEditor(session: session, textSize: environment.configuration.textSize)
            } else {
                scrollingContent { CanvasMarkdownContent(source: text, sourcePath: environment.canvasPath, environment: environment).padding(.horizontal, 16).padding(.vertical, 12) }
            }
        case .file(let path, let subpath):
            CanvasFileCardContent(path: path, subpath: subpath, cardSize: node.frame.size, environment: environment, isScrollable: isFocused && !isWriting)
        case .link(let address):
            CanvasLinkCardContent(address: address)
        case .group:
            // Groups are drawn beneath the cards; one never shows content of its own.
            EmptyView()
        case .unknown(let type):
            CanvasCardNotice(systemImage: "square.dashed", title: type.isEmpty ? "A card of a kind Graphite does not know" : "A card of the kind “\(type)”",
                             message: "Graphite shows where it is and keeps it in the file as it is.")
        }
    }

    /// A card's content scrolls once the card is tapped in Read, as a selected card's
    /// does in Obsidian; until then a drag on it moves the board.
    private func scrollingContent(@ViewBuilder _ scrolledContent: () -> some View) -> some View {
        ScrollView { scrolledContent().frame(maxWidth: .infinity, alignment: .topLeading) }
            .scrollDisabled(!isFocused || isWriting)
    }

    /// A file card's name above its top-left corner, as in Obsidian. In Read it opens the file.
    @ViewBuilder private var title: some View {
        if case .file(let path, let subpath) = node.content {
            Button {
                if let vaultPath = try? VaultPath(path) { environment.open(vaultPath) }
            } label: {
                Text(CanvasCardDescription.fileTitle(path: path, subpath: subpath))
                    .font(.system(size: titleSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: node.frame.width, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(!isWriting)
            // Above the card: one line of the title's size, and a small gap.
            .offset(y: -(titleSize * Self.titleLineHeightRatio + 4))
            .accessibilityHint("Opens the file")
        }
    }
}

private struct CanvasCardAccessibilityModifier: ViewModifier {
    let accessibility: CanvasCardAccessibility?
    let isSelected: Bool

    func body(content: Content) -> some View {
        if let accessibility {
            content
                .accessibilityElement(children: .contain)
                .accessibilityLabel(accessibility.label)
                .accessibilityValue(accessibility.value)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilitySortPriority(accessibility.sortPriority)
        } else {
            content
        }
    }
}

// MARK: Markdown

/// Markdown rendered by the reading view's renderer, so a card reads like a note:
/// formatting, math, callouts, links that can be followed, and embeds.
struct CanvasMarkdownContent: View {
    let source: String
    /// The file the Markdown is written in, which its links and embeds start from.
    let sourcePath: VaultPath
    let environment: CanvasCardEnvironment
    @State private var shownBuild: CanvasCardRenderCache.Build?

    var body: some View {
        let configuration = environment.configuration
        let build = currentBuild
        VStack(alignment: .leading, spacing: 12) {
            if let build {
                ReadingBlocksView(blocks: build.blocks, root: environment.root, textSize: configuration.textSize,
                                  navigate: { target, isWiki in environment.follow(target, isWiki, sourcePath) },
                                  // A link to a heading of the note itself opens the note; a text card has no headings to go to.
                                  scrollToHeading: { _ in if sourcePath != environment.canvasPath { environment.open(sourcePath) } },
                                  openPDF: environment.openPDF, updateProperties: nil)
            }
        }
        .environment(\.baseEmbedContext, environment.baseContext)
        .environment(\.readingImageActions, environment.imageActions)
        .task(id: "\(source.hashValue)-\(configuration.drawingVersion)-\(configuration.hashValueForReload)-\(build?.hasMissingEmbeds == false ? -1 : configuration.indexVersion)") {
            if currentBuild != nil { return }
            do {
                let newBuild = try await Self.build(source, sourcePath: sourcePath, root: environment.root, index: environment.index, configuration: configuration)
                try Task.checkCancellation()
                environment.renderCache.keep(newBuild, of: source, sourcePath: sourcePath)
                shownBuild = newBuild
            } catch {
                // A card whose Markdown cannot be built keeps what it showed; the text is
                // still in the file and shows in Write.
            }
        }
    }

    private static func build(_ source: String, sourcePath: VaultPath, root: URL, index: VaultIndex, configuration: ReadingConfiguration) async throws -> CanvasCardRenderCache.Build {
        let built = try await ReadingViewBuilder().build(source: source, note: sourcePath, root: root, index: index, configuration: configuration)
        let hasMissingEmbeds = MarkdownPreview.containsMissingEmbed(built.blocks) || built.hasUnresolvedEmbeds
        let key = ReadingBuildKey(source: source, path: sourcePath, root: root, configuration: configuration, dependsOnIndex: hasMissingEmbeds)
        return CanvasCardRenderCache.Build(key: key, blocks: built.blocks, hasMissingEmbeds: hasMissingEmbeds)
    }

    /// The build to show: a current one, else the last one shown, which stays up while
    /// the card's text builds again.
    private var currentBuild: CanvasCardRenderCache.Build? {
        if let cached = environment.renderCache.build(of: source, sourcePath: sourcePath, root: environment.root, configuration: environment.configuration) { return cached }
        if let shownBuild, shownBuild.key.describesBuild(of: source, path: sourcePath, root: environment.root, configuration: environment.configuration) { return shownBuild }
        return nil
    }
}

/// A text card's Markdown source, edited in place.
private struct CanvasTextCardEditor: View {
    let session: CanvasSession
    let textSize: Double
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        TextEditor(text: Binding(get: { session.textEdit?.text ?? "" }, set: { text in session.updateTextEdit(text) }))
            .font(.system(size: textSize))
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 11).padding(.vertical, 4)
            .focused($isEditorFocused)
            .onAppear { isEditorFocused = true }
            .accessibilityLabel("Card text")
            .accessibilityIdentifier("canvasCardEditor")
    }
}

// MARK: Files

/// A file card: the note rendered, the image, a page of the PDF, a player, or the file's
/// name where Graphite has no way to show it on a card.
private struct CanvasFileCardContent: View {
    let path: String
    let subpath: String?
    let cardSize: CGSize
    let environment: CanvasCardEnvironment
    let isScrollable: Bool
    @State private var isMissing = false

    /// The subpath without its `#`.
    private var fragment: String? {
        guard let subpath, subpath.hasPrefix("#"), subpath.count > 1 else { return nil }
        return String(subpath.dropFirst())
    }

    var body: some View {
        if let vaultPath = try? VaultPath(path), !vaultPath.rawValue.isEmpty, let location = try? vaultPath.url(in: environment.root) {
            Group {
                if isMissing {
                    CanvasCardNotice(systemImage: "questionmark.square.dashed", title: "“\(vaultPath.name)” is not in this vault", message: path)
                } else {
                    found(vaultPath, at: location)
                }
            }
            .task(id: "\(path)|\(environment.configuration.indexVersion)") {
                let exists = await Task.detached { FileManager.default.fileExists(atPath: location.path) }.value
                if isMissing == exists { isMissing = !exists }
            }
        } else {
            CanvasCardNotice(systemImage: "questionmark.square.dashed", title: "This card names no file of the vault", message: path)
        }
    }

    @ViewBuilder private func found(_ vaultPath: VaultPath, at location: URL) -> some View {
        let fileExtension = vaultPath.fileExtension
        if MediaFileKind.videoExtensions.contains(fileExtension) {
            EmbeddedMediaPlayer(location: location).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if MediaFileKind.audioExtensions.contains(fileExtension) {
            EmbeddedAudioPlayer(location: location, name: vaultPath.name).padding(12).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch DocumentKind(path: vaultPath) {
            case .markdown:
                CanvasNoteCardContent(path: vaultPath, location: location, fragment: fragment, environment: environment, isScrollable: isScrollable)
            case .image:
                CanvasImageCardContent(path: vaultPath, location: location, cardWidth: cardSize.width, version: environment.configuration.drawingVersion)
            case .pdf:
                CanvasPDFCardContent(path: vaultPath, location: location, pageNumber: fragment.flatMap { fragment in PDFEmbedOptions(fragment: fragment).startPageNumber } ?? 1,
                                     cardSize: cardSize, version: environment.configuration.drawingVersion)
            case .base where environment.baseContext != nil:
                ScrollView {
                    BaseFileEmbedView(path: vaultPath, viewName: fragment, context: environment.baseContext, openWithoutContext: environment.open).padding(12)
                }
                .scrollDisabled(!isScrollable)
            default:
                CanvasCardNotice(systemImage: DocumentKind(path: vaultPath).systemImage, title: vaultPath.name, message: "Tap the name above the card to open it.")
            }
        }
    }
}

/// A note on a card: its text without the properties, or the heading's section or the
/// block its subpath names, as an embed shows it.
private struct CanvasNoteCardContent: View {
    let path: VaultPath
    let location: URL
    let fragment: String?
    let environment: CanvasCardEnvironment
    let isScrollable: Bool
    @State private var loaded: LoadedNote?

    private enum LoadedNote: Equatable {
        case text(String)
        case missingSection
        case unreadable
    }

    var body: some View {
        Group {
            switch loaded {
            case .text(let text):
                ScrollView {
                    CanvasMarkdownContent(source: text, sourcePath: path, environment: environment)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollDisabled(!isScrollable)
            case .missingSection:
                CanvasCardNotice(systemImage: "questionmark.square.dashed", title: NoteBlocks.missingSectionMessage(subpath: fragment ?? "", noteName: path.stem), message: nil)
            case .unreadable:
                CanvasCardNotice(systemImage: "doc.text", title: path.stem, message: "This note is too large to show on a card, or is not text. Tap its name to open it.")
            case nil:
                Color.clear
            }
        }
        // The index version changes when the note is saved here or changed elsewhere.
        .task(id: "\(path.rawValue)|\(fragment ?? "")|\(environment.configuration.indexVersion)") {
            let fragment = fragment, location = location
            let newlyLoaded = await Task.detached(priority: .userInitiated) { () -> LoadedNote in
                guard let snapshot = try? AtomicFileWriter().read(location, maximumBytes: NotePreviewDocument.maximumEmbeddedNoteBytes),
                      let text = String(data: snapshot.data, encoding: .utf8) else { return .unreadable }
                let noteText = text as NSString
                let body = noteText.substring(from: FrontmatterLocator.length(in: noteText))
                guard let section = NoteBlocks.embeddedPart(of: body, subpath: fragment) else { return .missingSection }
                return .text(section)
            }.value
            if !Task.isCancelled, loaded != newlyLoaded { loaded = newlyLoaded }
        }
    }
}

/// An image card: the whole picture, as large as the card allows.
private struct CanvasImageCardContent: View {
    let path: VaultPath
    let location: URL
    let cardWidth: CGFloat
    let version: Int
    @Environment(\.displayScale) private var displayScale
    @State private var thumbnail: ReadingThumbnail?
    @State private var didFail = false

    private var displayPixelWidth: Int { Int((cardWidth * max(displayScale, 1)).rounded(.up)) }

    var body: some View {
        Group {
            if let thumbnail = thumbnail ?? ReadingImageCache.shared.lastThumbnail(for: location, kind: .block, displayPixelWidth: displayPixelWidth) {
                Image(thumbnail.image, scale: 1, label: Text(path.stem)).resizable().scaledToFit()
            } else if didFail {
                CanvasCardNotice(systemImage: "photo", title: "“\(path.name)” can't be shown", message: nil)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: "\(location.path)-\(version)-\(displayPixelWidth)") {
            do {
                let loadedThumbnail = try await ReadingImageCache.shared.thumbnail(for: location, kind: .block, displayPixelWidth: displayPixelWidth)
                if !Task.isCancelled { thumbnail = loadedThumbnail; didFail = false }
            } catch {
                if !Task.isCancelled { didFail = true }
            }
        }
    }
}

/// A PDF card: one page as a picture, the first or the one its subpath names
/// (`#page=3`). Tapping the card's name opens the PDF itself.
private struct CanvasPDFCardContent: View {
    let path: VaultPath
    let location: URL
    let pageNumber: Int
    let cardSize: CGSize
    let version: Int
    @Environment(\.displayScale) private var displayScale
    @State private var page: CanvasPDFPageImage?
    @State private var failure: CanvasPDFPageRenderer.Failure?

    var body: some View {
        let maximumPixelDimension = Int((max(cardSize.width, cardSize.height) * max(displayScale, 1)).rounded(.up))
        Group {
            if let page {
                Image(page.image, scale: 1, label: Text("\(path.stem), page \(page.pageNumber) of \(page.pageCount)")).resizable().scaledToFit()
            } else if let failure {
                CanvasCardNotice(systemImage: failure == .locked ? "lock.doc" : "doc.richtext", title: path.name,
                                 message: failure == .locked ? "This PDF needs its password. Tap its name to open it." : "This PDF can't be shown on a card.")
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(page == nil ? Color.clear : Color.white)
        .task(id: "\(location.path)-\(pageNumber)-\(version)-\(maximumPixelDimension)") {
            switch await CanvasPDFPageRenderer.shared.page(of: location, pageNumber: pageNumber, maximumPixelDimension: maximumPixelDimension) {
            case .success(let renderedPage): if !Task.isCancelled { page = renderedPage; failure = nil }
            case .failure(let renderingFailure): if !Task.isCancelled { failure = renderingFailure }
            }
        }
    }
}

/// One rendered page of a PDF. A `CGImage` is immutable once made.
struct CanvasPDFPageImage: @unchecked Sendable {
    let image: CGImage
    /// One-based.
    let pageNumber: Int
    let pageCount: Int
}

/// Draws single PDF pages for cards, one at a time and off the main thread, and keeps
/// the most recent ones.
actor CanvasPDFPageRenderer {
    enum Failure: Error, Equatable {
        case locked, unreadable
    }

    static let shared = CanvasPDFPageRenderer()
    static let largestPixelDimension = 3000
    private static let smallestPixelDimension = 64

    private final class CachedPage {
        let page: CanvasPDFPageImage
        let fileModificationDate: Date?
        init(page: CanvasPDFPageImage, fileModificationDate: Date?) { self.page = page; self.fileModificationDate = fileModificationDate }
    }

    private let cache: NSCache<NSString, CachedPage> = {
        let cache = NSCache<NSString, CachedPage>()
        cache.totalCostLimit = 48 * 1_048_576
        return cache
    }()

    /// - Parameter pageNumber: One-based; a number past the last page shows the last page.
    func page(of location: URL, pageNumber: Int, maximumPixelDimension: Int) -> Result<CanvasPDFPageImage, Failure> {
        let pixelDimension = min(max(maximumPixelDimension, Self.smallestPixelDimension), Self.largestPixelDimension)
        let modificationDate = (try? FileManager.default.attributesOfItem(atPath: location.path))?[.modificationDate] as? Date
        let cacheKey = "\(location.path)|\(pageNumber)|\(pixelDimension)" as NSString
        if let cached = cache.object(forKey: cacheKey), cached.fileModificationDate == modificationDate { return .success(cached.page) }
        guard let document = CGPDFDocument(location as CFURL) else { return .failure(.unreadable) }
        // Many PDFs are encrypted with an empty password only to restrict printing.
        if document.isEncrypted, !document.isUnlocked, !document.unlockWithPassword("") { return .failure(.locked) }
        let pageCount = document.numberOfPages
        guard pageCount > 0, let page = document.page(at: min(max(pageNumber, 1), pageCount)) else { return .failure(.unreadable) }
        let cropBox = page.getBoxRect(.cropBox)
        let isQuarterTurned = (page.rotationAngle / 90) % 2 != 0
        let displayedSize = isQuarterTurned ? CGSize(width: cropBox.height, height: cropBox.width) : cropBox.size
        guard displayedSize.width > 0, displayedSize.height > 0 else { return .failure(.unreadable) }
        let pixelsPerPoint = CGFloat(pixelDimension) / max(displayedSize.width, displayedSize.height)
        let pixelWidth = max(Int((displayedSize.width * pixelsPerPoint).rounded()), 1), pixelHeight = max(Int((displayedSize.height * pixelsPerPoint).rounded()), 1)
        guard let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return .failure(.unreadable)
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.interpolationQuality = .high
        context.scaleBy(x: pixelsPerPoint, y: pixelsPerPoint)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: displayedSize), rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { return .failure(.unreadable) }
        let renderedPage = CanvasPDFPageImage(image: image, pageNumber: min(max(pageNumber, 1), pageCount), pageCount: pageCount)
        cache.setObject(CachedPage(page: renderedPage, fileModificationDate: modificationDate), forKey: cacheKey, cost: image.bytesPerRow * image.height)
        return .success(renderedPage)
    }
}

// MARK: Web links and notices

/// A link card: the site's name and the address, which opens in the browser. The page
/// itself is not loaded on the board.
private struct CanvasLinkCardContent: View {
    let address: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        let location = CanvasSession.browsableLocation(of: address)
        Button {
            if let location { openURL(location) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Label(Self.siteName(of: location) ?? "Web link", systemImage: "globe")
                    .font(.headline)
                    .lineLimit(2)
                Text(address)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                Spacer(minLength: 0)
                Label(location == nil ? "This address can't be opened" : "Opens in your browser", systemImage: location == nil ? "exclamationmark.triangle" : "arrow.up.right.square")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(location == nil)
        .accessibilityHint("Opens the address in your browser")
    }

    /// The host without a leading `www.`, as the card's title.
    static func siteName(of location: URL?) -> String? {
        guard let host = location?.host(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// A card that has nothing to render: what it is, and why.
struct CanvasCardNotice: View {
    let systemImage: String
    let title: String
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage).font(.callout.weight(.semibold))
            if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
