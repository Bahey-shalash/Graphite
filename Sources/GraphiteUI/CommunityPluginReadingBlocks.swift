import SwiftUI
import WebKit
import GraphiteCore
#if canImport(UIKit)
import UIKit
#endif

/// A part of a note that plugins draw in the reading view, as the note has it: a code block
/// in a language a plugin draws, or a section offered to the plugins' post-processors.
struct CommunityPluginReadingBlockRequest: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case codeBlock(language: String)
        /// A run of the note's Markdown, which Graphite shows itself unless a plugin changes it.
        case section
        /// A plugin's view in a tab or sidebar panel (its leaf's identifier).
        case view(identifier: String)
    }

    let kind: Kind
    /// The code between the fences, or the section's Markdown.
    let source: String
    /// The note the block is written in.
    let note: VaultPath
    /// The zero-based line of the block's opening fence in `note`, nil when not known.
    let firstLine: Int?
    /// Lines the block spans, fences included.
    let lineCount: Int
}

/// The last copy of a block a plugin drew, with the height it was shown at.
struct CommunityPluginCodeBlockCopy {
    let html: String
    var height: CGFloat
}

extension EnvironmentValues {
    /// Draws plugins' code blocks in the reading view; nil where plugins do not draw them,
    /// which shows such blocks as code.
    @Entry var communityPluginCodeBlocks: CommunityPluginHost? = nil
}

/// One code block shown in a note: its copy of what the plugin drew, kept current. The
/// plugin draws the block in the runtime's page (`community-plugin-runtime-reading.js`);
/// this holds the copy Graphite shows and sends taps back.
@MainActor @Observable
final class CommunityPluginShownCodeBlock {
    enum Appearance: Equatable {
        case drawing
        case drawn(html: String)
        /// No plugin changed the section, which Graphite shows itself.
        case unchanged
        case failed(String)
    }

    /// How long the plugin has to draw a block before the note says it did not.
    static let drawingTimeout: Duration = .seconds(20)
    /// How long a tap waits for the plugin before it is given up.
    static let tapTimeout: Duration = .seconds(5)

    let blockIdentifier = UUID().uuidString
    private(set) var appearance: Appearance = .drawing
    /// The copy's height in points, as its web view measured it.
    var height: CGFloat = 0
    @ObservationIgnored private weak var host: CommunityPluginHost?
    @ObservationIgnored private var request: CommunityPluginReadingBlockRequest?
    /// Ticks the note's task on a line of a section, counted from the section's first line.
    @ObservationIgnored var tickTask: ((Int) -> Void)?

    init(host: CommunityPluginHost) {
        self.host = host
    }

    /// The vault's folder, whose files a block's pictures load from.
    var vaultRoot: URL? { host?.workspace?.folderAccess?.root }

    /// Asks the plugin to draw the block, showing the last copy meanwhile.
    func draw(_ request: CommunityPluginReadingBlockRequest, width: CGFloat) async {
        guard let host else { return }
        // Drawing again under the same identifier replaces the plugin's earlier block there;
        // a separate release could arrive after this drawing and remove it.
        self.request = request
        host.shownCodeBlocks[blockIdentifier] = self
        if let lastCopy = host.lastCodeBlockCopies[request] {
            appearance = .drawn(html: lastCopy.html)
            height = lastCopy.height
        } else {
            appearance = .drawing
        }
        var message: [String: Any] = [
            "operation": "codeBlock.render", "blockIdentifier": blockIdentifier, "source": request.source,
            "sourcePath": request.note.rawValue, "lineCount": request.lineCount, "width": Double(max(width, 200)),
        ]
        switch request.kind {
        case .codeBlock(let language): message["language"] = language
        case .section: message["kind"] = "section"
        case .view: return
        }
        message.merge(host.sectionInformation(for: request)) { _, new in new }
        do {
            let answer = try await host.send(message, timeout: Self.drawingTimeout)
            guard self.request == request else { return }
            if let styles = answer["styles"] as? String { host.updatePluginStyleSheets(styles) }
            if answer["isDrawn"] as? Bool == true, answer["isChanged"] as? Bool == false {
                appearance = .unchanged
                self.request = nil
                host.shownCodeBlocks[blockIdentifier] = nil
            } else if answer["isDrawn"] as? Bool == true, let html = answer["html"] as? String {
                receive(html: html)
            } else {
                appearance = .failed(answer["message"] as? String ?? "The plugin did not draw this block.")
            }
        } catch {
            guard self.request == request else { return }
            appearance = .failed(error.localizedDescription)
        }
    }

    /// Shows a plugin's view at `size`, the size of its tab or sidebar panel.
    func attachView(_ viewIdentifier: String, size: CGSize) async {
        guard let host else { return }
        request = CommunityPluginReadingBlockRequest(kind: .view(identifier: viewIdentifier), source: "", note: .root, firstLine: nil, lineCount: 0)
        host.shownCodeBlocks[blockIdentifier] = self
        appearance = .drawing
        let message: [String: Any] = ["operation": "view.attach", "blockIdentifier": blockIdentifier, "leafIdentifier": viewIdentifier,
                                      "width": Double(size.width), "height": Double(size.height)]
        do {
            let answer = try await host.send(message, timeout: Self.drawingTimeout)
            if let styles = answer["styles"] as? String { host.updatePluginStyleSheets(styles) }
            if answer["isDrawn"] as? Bool == true, let html = answer["html"] as? String { receive(html: html) }
            else { appearance = .failed(answer["message"] as? String ?? "The plugin did not show this view.") }
        } catch {
            appearance = .failed(error.localizedDescription)
        }
    }

    /// The tab or panel showing a view changed size; the view lays out again.
    func resizeView(to size: CGSize) {
        guard let host, case .view = request?.kind, size.width > 0, size.height > 0 else { return }
        let blockIdentifier = blockIdentifier
        Task { _ = try? await host.send(["operation": "view.resize", "blockIdentifier": blockIdentifier, "width": Double(size.width), "height": Double(size.height)],
                                         timeout: .seconds(5)) }
    }

    func receive(html: String) {
        appearance = .drawn(html: html)
        if let request { host?.keepCopy(CommunityPluginCodeBlockCopy(html: html, height: height), for: request) }
    }

    func heightDidChange(_ newHeight: CGFloat) {
        guard abs(newHeight - height) >= 0.5 else { return }
        height = newHeight
        if let request { host?.lastCodeBlockCopies[request]?.height = newHeight }
    }

    /// A tap on the copy, as the path of element positions from the block down to the
    /// element tapped, delivered to that element in the plugin's block.
    func tap(elementPath: [Int]) {
        deliver(["eventType": "tap", "elementPath": elementPath])
    }

    /// Text typed into a field of the copy (a query's filter), given to the plugin's field.
    func enter(_ value: String, elementPath: [Int]) {
        deliver(["eventType": "input", "elementPath": elementPath, "value": value])
    }

    /// A key pressed in a field of the copy, delivered to the plugin's field.
    func press(_ key: String, elementPath: [Int]) {
        deliver(["eventType": "key", "elementPath": elementPath, "key": key])
    }

    /// A context menu, hover or drag in the copy, delivered to the plugin's block: `details`
    /// carries the element's path, the position in the block, and a drag's phase.
    func forward(_ type: String, details: [String: Any]) {
        guard ["contextmenu", "hover", "gesture"].contains(type) else { return }
        var event: [String: Any] = ["eventType": type, "x": details["x"] as? Double ?? 0, "y": details["y"] as? Double ?? 0]
        if let path = details["path"] as? [Int] { event["elementPath"] = path }
        for key in ["phase", "pointerType"] { if let value = details[key] as? String { event[key] = value } }
        if let overPath = details["overPath"] as? [Int] { event["overPath"] = overPath }
        deliver(event)
    }

    private func deliver(_ event: [String: Any]) {
        guard let host else { return }
        var message = event
        message["operation"] = "codeBlock.event"
        message["blockIdentifier"] = blockIdentifier
        // Live Preview's blocks move as the note is edited above them; a plugin that edits its
        // block through `getSectionInfo` in answer to the tap reads where the block is now.
        if let request, request.firstLine == nil, case .codeBlock = request.kind {
            message["sectionIsCurrent"] = true
            message.merge(host.sectionInformation(for: request)) { _, new in new }
        }
        Task {
            guard let answer = try? await host.send(message, timeout: Self.tapTimeout) else { return }
            if let taskLine = answer["taskLine"] as? Int { tickTask?(taskLine) }
            if let html = answer["html"] as? String { receive(html: html) }
        }
    }

    /// The note no longer shows the block: the plugin's block and what it keeps up to date go.
    func release() {
        guard let host, request != nil else { return }
        request = nil
        host.shownCodeBlocks[blockIdentifier] = nil
        let blockIdentifier = blockIdentifier
        Task { _ = try? await host.send(["operation": "codeBlock.release", "blockIdentifier": blockIdentifier], timeout: .seconds(5)) }
    }
}

extension CommunityPluginHost {
    /// Copies kept at most, so a long session of reading many notes does not keep every
    /// block's HTML; the copies least recently drawn go first.
    static let maximumKeptCopies = 64

    func keepCopy(_ copy: CommunityPluginCodeBlockCopy, for request: CommunityPluginReadingBlockRequest) {
        lastCodeBlockCopies[request] = copy
        keptCopyOrder.removeAll { keptRequest in keptRequest == request }
        keptCopyOrder.append(request)
        while keptCopyOrder.count > Self.maximumKeptCopies { lastCodeBlockCopies[keptCopyOrder.removeFirst()] = nil }
    }

    /// What `getSectionInfo` answers for a block: the note's text and the block's first line.
    /// A request without a first line (Live Preview's, whose blocks move with each edit) is
    /// looked for in the note as it is now, and has none unless exactly one block matches, so
    /// a plugin never edits another block's lines.
    func sectionInformation(for request: CommunityPluginReadingBlockRequest) -> [String: Any] {
        // `getSectionInfo` gives a plugin the whole note; only an open note's text is at hand.
        guard let noteText = openNoteText(at: request.note), (noteText as NSString).length <= 1_048_576 else {
            return request.firstLine.map { firstLine in ["firstLine": firstLine] } ?? [:]
        }
        var information: [String: Any] = ["noteText": noteText]
        if let firstLine = request.firstLine {
            information["firstLine"] = firstLine
        } else if case .codeBlock(let language) = request.kind,
                  let place = LivePreviewBlockScanner.onlyPluginCodeBlock(language: language, code: request.source, in: noteText) {
            information["firstLine"] = place.firstLine
            information["lineCount"] = place.lineCount
        }
        return information
    }

    /// The text of a note open in Graphite, as its editor holds it.
    func openNoteText(at path: VaultPath) -> String? {
        workspace?.openMarkdownSession(at: path)?.text
    }

    /// The name of the plugin that draws a code block language, for what the note shows
    /// while it draws.
    func pluginName(drawingLanguage language: String) -> String? {
        codeBlockLanguageOwners[language].flatMap(pluginName(of:))
    }

    /// Whether plugins change how notes read, so the reading view offers sections to them.
    var runsMarkdownPostProcessors: Bool { !postProcessingPluginIdentifiers.isEmpty }
}

/// A plugin's code block in the reading view: what the plugin drew, shown in a web view
/// that runs no script of the page, sized to its content.
struct CommunityPluginCodeBlockView: View {
    let host: CommunityPluginHost
    let request: CommunityPluginReadingBlockRequest
    let textSize: Double
    @State private var shownBlock: CommunityPluginShownCodeBlock?
    @State private var availableWidth: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accent) private var accent

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { geometry in geometry.size.width } action: { width in availableWidth = width }
            .task(id: DrawingKey(request: request, hasWidth: availableWidth > 0)) {
                guard availableWidth > 0 else { return }
                let block = shownBlock ?? CommunityPluginShownCodeBlock(host: host)
                shownBlock = block
                await block.draw(request, width: availableWidth)
            }
            .onDisappear {
                shownBlock?.release()
                shownBlock = nil
            }
    }

    /// Drawn again when the block's text changes, or once its width is known.
    private struct DrawingKey: Equatable {
        let request: CommunityPluginReadingBlockRequest
        let hasWidth: Bool
    }

    @ViewBuilder private var content: some View {
        switch shownBlock?.appearance ?? .drawing {
        case .drawing:
            HStack(spacing: 8) {
                ProgressView()
                Text(drawingDescription).font(.callout).foregroundStyle(.secondary)
            }
            .frame(minHeight: 44, alignment: .leading)
            .accessibilityElement(children: .combine)
        case .drawn(let html):
            if let shownBlock {
                CommunityPluginCodeBlockDisplay(block: shownBlock, html: html, styleSheets: host.pluginStyleSheets,
                                                isDark: colorScheme == .dark, textSize: textSize, accentHex: accent.sRGBHex,
                                                bodyClasses: host.pluginBodyClasses, bodyStyle: host.pluginBodyStyle, hasTheme: !host.activeThemeName.isEmpty)
                    .frame(height: max(shownBlock.height, 1))
            }
        case .unchanged:
            // Only sections end here, and they are shown by `CommunityPluginSectionView`.
            Text(request.source).textSelection(.enabled)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.secondary)
                Text(request.source)
                    .font(.system(size: textSize * 0.85, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var drawingDescription: String {
        if case .codeBlock(let language) = request.kind, let pluginName = host.pluginName(drawingLanguage: language) { return "\(pluginName) is drawing this block…" }
        return "Drawing this block…"
    }
}

/// A section of a note while plugins change how notes read: Graphite's own rendering, until
/// a plugin's post-processor changes the section, which then shows as the plugin drew it.
struct CommunityPluginSectionView<NativeContent: View>: View {
    let host: CommunityPluginHost
    let request: CommunityPluginReadingBlockRequest
    let textSize: Double
    @ViewBuilder let nativeContent: () -> NativeContent
    @State private var shownBlock: CommunityPluginShownCodeBlock?
    @State private var availableWidth: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accent) private var accent
    @Environment(\.readingTaskContext) private var taskContext

    var body: some View {
        Group {
            if let shownBlock, case .drawn(let html) = shownBlock.appearance {
                CommunityPluginCodeBlockDisplay(block: shownBlock, html: html, styleSheets: host.pluginStyleSheets,
                                                isDark: colorScheme == .dark, textSize: textSize, accentHex: accent.sRGBHex,
                                                bodyClasses: host.pluginBodyClasses, bodyStyle: host.pluginBodyStyle, hasTheme: !host.activeThemeName.isEmpty)
                    .frame(height: max(shownBlock.height, 1))
            } else {
                nativeContent()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { geometry in geometry.size.width } action: { width in availableWidth = width }
        .task(id: SectionKey(request: request, hasWidth: availableWidth > 0)) {
            guard availableWidth > 0 else { return }
            let block = shownBlock ?? CommunityPluginShownCodeBlock(host: host)
            shownBlock = block
            block.tickTask = { lineIndex in Task { await tickTask(onSectionLine: lineIndex) } }
            await block.draw(request, width: availableWidth)
        }
        .onDisappear {
            shownBlock?.release()
            shownBlock = nil
        }
    }

    /// A task checkbox of the section, tapped in the plugin's version of it: ticked in the
    /// note as Graphite's own checkboxes tick it, provided the line still holds that task.
    private func tickTask(onSectionLine lineIndex: Int) async {
        guard let taskContext, let firstLine = request.firstLine else { return }
        let noteText: String?
        if let openText = host.openNoteText(at: request.note) {
            noteText = openText
        } else if let store = host.workspace?.store, let snapshot = try? await store.read(request.note, maximumBytes: NotePreviewDocument.maximumEmbeddedNoteBytes) {
            noteText = String(data: snapshot.data, encoding: .utf8)
        } else {
            noteText = nil
        }
        guard let noteText else { return }
        let lines = noteText.components(separatedBy: "\n")
        let noteLine = firstLine + lineIndex
        guard lines.indices.contains(noteLine) else { return }
        let lineStart = lines[..<noteLine].reduce(0) { offset, line in offset + (line as NSString).length + 1 }
        guard let openingBracket = lines[noteLine].firstIndex(of: "["),
              let status = lines[noteLine][lines[noteLine].index(after: openingBracket)...].unicodeScalars.first,
              let location = ReadingTasks.location(ofTaskStartingAt: lineStart, status: status, in: noteText) else { return }
        _ = await taskContext.toggle(request.note, location)
    }

    private struct SectionKey: Equatable {
        let request: CommunityPluginReadingBlockRequest
        let hasWidth: Bool
    }
}

/// The page a block's copy is shown in. It loads only the runtime's style sheet and the
/// vault's files through the plugin scheme; script in the copy never runs
/// (`allowsContentJavaScript` is off), and Graphite's own script, in its own content world,
/// measures the page and reports taps.
enum CommunityPluginCodeBlockPage {
    static let messageHandlerName = "graphiteCodeBlock"

    static var shell: String {
        """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <link rel="stylesheet" href="community-plugin-runtime.css">
        <style id="graphite-plugin-styles"></style>
        <style>
        html, body { background: transparent !important; margin: 0; padding: 0; overflow-x: auto; overflow-y: hidden; }
        body { -webkit-user-select: text; }
        .graphite-code-block-root { padding: 1px 0; }
        .graphite-code-block-root > * { margin-top: 0; }
        body.graphite-view-page { height: 100vh; overflow: hidden; }
        /* With a theme, a view fills its tab or panel on the theme's page color, as in Obsidian;
           a block sits on the note's own page. */
        html:has(body.graphite-view-page.graphite-themed), body.graphite-view-page.graphite-themed { background: var(--background-primary) !important; }
        body.graphite-view-page .graphite-code-block-root { height: 100vh; padding: 0; }
        /* A long press on an element with a context menu opens the plugin's menu, not the
           system's; an element the plugin drags is dragged, not scrolled. */
        [data-graphite-listens~="menu"] { -webkit-touch-callout: none; -webkit-user-select: none; user-select: none; }
        [draggable="true"] { touch-action: none; -webkit-user-drag: none; }
        .graphite-code-block-root > .workspace-leaf { height: 100%; display: flex; flex-direction: column; }
        .graphite-code-block-root > .workspace-leaf > .workspace-leaf-content { display: flex; flex-direction: column; height: 100%; }
        .graphite-code-block-root .view-content { flex: 1 1 auto; overflow: auto; padding: 8px 6px; -webkit-overflow-scrolling: touch; }
        </style>
        </head><body class="theme-light is-mobile is-ios"><div class="markdown-preview-view markdown-rendered graphite-code-block-root"></div></body></html>
        """
    }

    /// Runs in Graphite's content world: shows copies, reports the page's height, and turns
    /// taps into element paths, cancelling them here so nothing happens twice.
    static let script = """
    (function () {
        'use strict';
        const handler = window.webkit.messageHandlers.graphiteCodeBlock;
        function root() { return document.querySelector('.graphite-code-block-root'); }
        function blockElement() { return root() && root().firstElementChild; }
        /// Element positions from the block's element down to `element`, which is how the
        /// plugin's block finds the same element.
        function pathTo(element) {
            const path = [];
            while (element && element !== blockElement()) {
                path.unshift(Array.prototype.indexOf.call(element.parentElement.children, element));
                element = element.parentElement;
            }
            return path;
        }
        /// Brings `current` to what `wanted` holds by changing only what differs, so a field
        /// being typed in stays the same element, keeps its text and caret, and the keyboard
        /// keeps every key; replacing the page's HTML would drop keys typed meanwhile.
        function morph(current, wanted) {
            const currentChildren = Array.from(current.childNodes);
            const wantedChildren = Array.from(wanted.childNodes);
            wantedChildren.forEach((wantedChild, position) => {
                const currentChild = currentChildren[position];
                if (!currentChild) { current.appendChild(wantedChild.cloneNode(true)); return; }
                const isSameKind = currentChild.nodeType === wantedChild.nodeType && currentChild.nodeName === wantedChild.nodeName;
                if (!isSameKind) { current.replaceChild(wantedChild.cloneNode(true), currentChild); return; }
                if (currentChild.nodeType !== Node.ELEMENT_NODE) {
                    if (currentChild.nodeValue !== wantedChild.nodeValue) currentChild.nodeValue = wantedChild.nodeValue;
                    return;
                }
                const isBeingTyped = currentChild === document.activeElement && 'value' in currentChild;
                for (const attribute of Array.from(currentChild.attributes)) {
                    if (!wantedChild.hasAttribute(attribute.name)) currentChild.removeAttribute(attribute.name);
                }
                for (const attribute of Array.from(wantedChild.attributes)) {
                    if (isBeingTyped && attribute.name === 'value') continue;
                    if (currentChild.getAttribute(attribute.name) !== attribute.value) currentChild.setAttribute(attribute.name, attribute.value);
                }
                if (currentChild.tagName === 'INPUT') {
                    if (currentChild.type === 'checkbox' || currentChild.type === 'radio') currentChild.checked = wantedChild.hasAttribute('checked');
                    else if (!isBeingTyped) currentChild.value = wantedChild.getAttribute('value') || '';
                }
                if (currentChild.tagName === 'TEXTAREA' && !isBeingTyped) currentChild.value = wantedChild.textContent;
                if (!isBeingTyped) morph(currentChild, wantedChild);
            });
            for (const extraChild of currentChildren.slice(wantedChildren.length)) extraChild.remove();
        }
        let lastHeight = -1;
        function reportHeight() {
            const element = root();
            const height = Math.ceil(element ? element.getBoundingClientRect().height : document.documentElement.scrollHeight);
            if (height !== lastHeight) { lastHeight = height; handler.postMessage({ kind: 'height', height }); }
        }
        window.GraphiteCodeBlock = {
            show(html, styleSheets, isDark, textSize, accent, fillsSpace, bodyClasses, bodyStyle, hasTheme) {
                document.body.classList.toggle('graphite-view-page', Boolean(fillsSpace));
                // A plugin's view is not a note's rendering; only blocks get the note's styles.
                root().classList.toggle('markdown-rendered', !fillsSpace);
                root().classList.toggle('markdown-preview-view', !fillsSpace);
                const styleElement = document.getElementById('graphite-plugin-styles');
                if (styleElement.textContent !== styleSheets) styleElement.textContent = styleSheets;
                // The classes and inline style plugins and the theme set on the plugins' page body
                // (Style Settings, Minimal Theme Settings' schemes and options, the accent).
                const body = document.body;
                const previousClasses = (body.dataset.graphitePageClasses || '').split(' ').filter(Boolean);
                for (const className of previousClasses) body.classList.remove(className);
                for (const className of String(bodyClasses || '').split(' ').filter(Boolean)) body.classList.add(className);
                body.dataset.graphitePageClasses = String(bodyClasses || '');
                if ((body.dataset.graphitePageStyle || '') !== String(bodyStyle || '')) {
                    body.setAttribute('style', String(bodyStyle || ''));
                    body.dataset.graphitePageStyle = String(bodyStyle || '');
                }
                document.body.classList.toggle('theme-dark', isDark);
                document.body.classList.toggle('theme-light', !isDark);
                document.body.classList.toggle('graphite-themed', Boolean(hasTheme));
                document.body.style.setProperty('--font-text-size', textSize + 'px');
                // A view uses Obsidian's interface sizes, which follow the system's text size too.
                const scale = fillsSpace ? textSize / 15 : 1;
                for (const [name, size] of [['--font-ui-smaller', 12], ['--font-ui-small', 13], ['--font-ui-medium', 15], ['--font-ui-large', 20]]) {
                    document.body.style.setProperty(name, (size * scale) + 'px');
                }
                // A theme derives its accent colors from --accent-h, -s and -l, which the page's
                // inline style carries; without one, Graphite's accent is set directly.
                if (accent && !hasTheme) {
                    document.body.style.setProperty('--color-accent', accent);
                    document.body.style.setProperty('--interactive-accent', accent);
                    document.body.style.setProperty('--text-accent', accent);
                }
                const element = root();
                if (element.innerHTML !== html) {
                    const template = document.createElement('template');
                    template.innerHTML = html;
                    morph(element, template.content);
                }
                reportHeight();
            },
        };
        new ResizeObserver(reportHeight).observe(document.documentElement);
        document.addEventListener('click', (event) => {
            const element = event.target instanceof Element ? event.target : null;
            if (suppressesNextClick) {
                suppressesNextClick = false;
                event.preventDefault();
                event.stopPropagation();
                return;
            }
            if (!blockElement() || !element || !blockElement().contains(element)) return;
            // Typing goes to text fields here; the plugin hears the text, not the tap.
            if (element.matches('input:not([type=checkbox]):not([type=radio]):not([type=button]):not([type=submit]), textarea, select')) return;
            event.preventDefault();
            event.stopPropagation();
            handler.postMessage({ kind: 'tap', path: pathTo(element) });
        }, true);
        /// The nearest element, from `element` up to the block, that the plugin listens to for
        /// `kind` of event (`data-graphite-listens`, written by the plugins' page).
        function listener(element, kind) {
            for (let current = element; current && blockElement() && blockElement().contains(current); current = current.parentElement) {
                if ((current.getAttribute('data-graphite-listens') || '').split(' ').includes(kind)) return current;
                if (kind === 'drag' && current.getAttribute('draggable') === 'true') return current;
            }
            return null;
        }
        /// A position measured from the block's top left corner, which the plugins' page
        /// finds in its own block.
        function positionOf(event) {
            const bounds = blockElement().getBoundingClientRect();
            return { x: event.clientX - bounds.left, y: event.clientY - bounds.top };
        }
        function inBlock(event) {
            const element = event.target instanceof Element ? event.target : null;
            return blockElement() && element && blockElement().contains(element) ? element : null;
        }
        /// A tap that ended a long press or a drag is not a tap.
        let suppressesNextClick = false;
        function send(type, element, event, extra) {
            handler.postMessage(Object.assign({ kind: 'event', type, path: element ? pathTo(element) : null }, positionOf(event), extra || {}));
        }

        // A right-click, or a two-finger click on a trackpad.
        document.addEventListener('contextmenu', (event) => {
            const element = inBlock(event);
            if (!element || !listener(element, 'menu')) return;
            event.preventDefault();
            send('contextmenu', element, event);
        }, true);

        // A long press on a touch screen opens the menu, as in Obsidian on iPad.
        let longPress = null;
        document.addEventListener('pointerdown', (event) => {
            const element = inBlock(event);
            suppressesNextClick = false;
            if (longPress) { clearTimeout(longPress.timer); longPress = null; }
            if (event.pointerType === 'mouse' || !element || !listener(element, 'menu')) return;
            const start = { clientX: event.clientX, clientY: event.clientY };
            longPress = { start, timer: setTimeout(() => {
                longPress = null;
                suppressesNextClick = true;
                send('contextmenu', element, start);
            }, 500) };
        }, true);
        function endLongPress(event) {
            if (!longPress) return;
            if (event.type === 'pointermove' && Math.hypot(event.clientX - longPress.start.clientX, event.clientY - longPress.start.clientY) < 10) return;
            clearTimeout(longPress.timer);
            longPress = null;
        }
        for (const type of ['pointermove', 'pointerup', 'pointercancel']) document.addEventListener(type, endLongPress, true);

        // Hovering with a mouse, trackpad or Pencil: the plugin hears the pointer move onto
        // an element and off it (link previews, buttons that show on hover).
        let hovered = null;
        let hoverFrame = 0;
        document.addEventListener('pointermove', (event) => {
            if (event.buttons !== 0 || event.pointerType === 'touch') return;
            const element = inBlock(event);
            const target = element && listener(element, 'hover') ? element : null;
            if (target === hovered) return;
            hovered = target;
            cancelAnimationFrame(hoverFrame);
            hoverFrame = requestAnimationFrame(() => send('hover', hovered, event));
        }, true);
        document.addEventListener('pointerleave', (event) => {
            if (!hovered) return;
            hovered = null;
            send('hover', null, event);
        }, true);

        // A press that moves: a drag the plugin follows (sortable lists, cards, and with a
        // mouse or trackpad sliders too). It reaches the plugin only once it moves, so a tap
        // stays a tap.
        let drag = null;
        document.addEventListener('pointerdown', (event) => {
            const element = inBlock(event);
            drag = null;
            if (!element || event.button !== 0) return;
            // On a touch screen only an element marked draggable is held (it does not scroll);
            // elsewhere a finger scrolls.
            const isDraggable = Boolean(element.closest('[draggable="true"]'));
            if (event.pointerType !== 'mouse' ? !isDraggable : !(isDraggable || listener(element, 'drag') || listener(element, 'press'))) return;
            drag = { element, start: { clientX: event.clientX, clientY: event.clientY }, pointerType: event.pointerType, isStarted: false, frame: 0 };
        }, true);
        document.addEventListener('pointermove', (event) => {
            if (!drag || event.buttons === 0) return;
            if (!drag.isStarted) {
                if (Math.hypot(event.clientX - drag.start.clientX, event.clientY - drag.start.clientY) < 6) return;
                drag.isStarted = true;
                suppressesNextClick = true;
                send('gesture', drag.element, drag.start, { phase: 'down', pointerType: drag.pointerType });
            }
            event.preventDefault();
            const lastEvent = { clientX: event.clientX, clientY: event.clientY };
            cancelAnimationFrame(drag.frame);
            const current = drag;
            drag.frame = requestAnimationFrame(() => {
                const over = document.elementFromPoint(lastEvent.clientX, lastEvent.clientY);
                send('gesture', current.element, lastEvent, { phase: 'move', overPath: over && blockElement().contains(over) ? pathTo(over) : null, pointerType: current.pointerType });
            });
        }, true);
        function endDrag(event) {
            if (!drag) return;
            const ended = drag;
            drag = null;
            cancelAnimationFrame(ended.frame);
            if (!ended.isStarted) return;
            const over = document.elementFromPoint(event.clientX, event.clientY);
            send('gesture', ended.element, event, { phase: event.type === 'pointercancel' ? 'cancel' : 'up',
                                                     overPath: over && blockElement().contains(over) ? pathTo(over) : null, pointerType: ended.pointerType });
        }
        document.addEventListener('pointerup', endDrag, true);
        document.addEventListener('pointercancel', endDrag, true);
        // The copy's own drag of a link or picture would carry it out of the block.
        document.addEventListener('dragstart', (event) => { if (inBlock(event)) event.preventDefault(); }, true);

        function forwardText(event) {
            const element = event.target instanceof Element ? event.target : null;
            if (!blockElement() || !element || !blockElement().contains(element) || !('value' in element)) return;
            if (element.type === 'checkbox' || element.type === 'radio') return;
            handler.postMessage({ kind: 'input', path: pathTo(element), value: String(element.value) });
        }
        document.addEventListener('input', forwardText, true);
        document.addEventListener('change', forwardText, true);
        // Keys that act on a field (Return in a search field, Escape, arrows in a list).
        document.addEventListener('keydown', (event) => {
            const element = event.target instanceof Element ? event.target : null;
            if (!blockElement() || !element || !blockElement().contains(element)) return;
            if (!['Enter', 'Escape', 'ArrowUp', 'ArrowDown', 'Tab'].includes(event.key)) return;
            handler.postMessage({ kind: 'key', path: pathTo(element), key: event.key });
        }, true);
    })();
    """
}

/// Receives a block page's messages. Separate from the view, because WebKit keeps its
/// message handlers strongly.
@MainActor
final class CommunityPluginCodeBlockDisplayCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    weak var block: CommunityPluginShownCodeBlock?
    var isLoaded = false
    /// What the page should show once it has loaded.
    var pendingPresentation: [String: Any]?
    weak var webView: WKWebView?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let kind = body["kind"] as? String else { return }
        switch kind {
        case "height":
            if let height = body["height"] as? Double { block?.heightDidChange(CGFloat(height)) }
        case "tap":
            if let path = body["path"] as? [Int] { block?.tap(elementPath: path) }
        case "input":
            if let path = body["path"] as? [Int], let value = body["value"] as? String { block?.enter(value, elementPath: path) }
        case "key":
            if let path = body["path"] as? [Int], let key = body["key"] as? String { block?.press(key, elementPath: path) }
        case "event":
            if let type = body["type"] as? String { block?.forward(type, details: body) }
        default:
            break
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        isLoaded = true
        if let pendingPresentation { present(pendingPresentation) }
    }

    /// Only the block's own page loads; links are followed by the plugin's block.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard !isLoaded, navigationAction.targetFrame?.isMainFrame == true else { return .cancel }
        return .allow
    }

    func present(_ presentation: [String: Any]) {
        pendingPresentation = presentation
        guard isLoaded, let webView else { return }
        webView.callAsyncJavaScript("GraphiteCodeBlock.show(html, styleSheets, isDark, textSize, accent, fillsSpace, bodyClasses, bodyStyle, hasTheme)", arguments: presentation,
                                    in: nil, in: .defaultClient) { _ in }
    }
}

/// The web view that shows a block's copy.
@MainActor
struct CommunityPluginCodeBlockDisplay {
    let block: CommunityPluginShownCodeBlock
    let html: String
    let styleSheets: String
    let isDark: Bool
    let textSize: Double
    let accentHex: String?
    /// A plugin view fills its tab or panel and scrolls inside; a block is as tall as its content.
    var fillsSpace = false
    /// The plugins' page body classes and inline style (`CommunityPluginHost.pluginBodyClasses`).
    var bodyClasses = ""
    var bodyStyle = ""
    /// Whether the vault's theme is among `styleSheets`, so the theme decides the accent's shades.
    var hasTheme = false

    /// One store for every block page: no page keeps anything, and sharing it lets WebKit
    /// share its processes between blocks.
    @MainActor static let dataStore = WKWebsiteDataStore.nonPersistent()

    func makeCoordinator() -> CommunityPluginCodeBlockDisplayCoordinator { CommunityPluginCodeBlockDisplayCoordinator() }

    @MainActor private func makeWebView(coordinator: CommunityPluginCodeBlockDisplayCoordinator, vaultRoot: URL?) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = Self.dataStore
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        if let vaultRoot {
            configuration.setURLSchemeHandler(CommunityPluginSchemeHandler(vaultRoot: vaultRoot), forURLScheme: CommunityPluginSchemeHandler.scheme)
        }
        let script = WKUserScript(source: CommunityPluginCodeBlockPage.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient)
        configuration.userContentController.addUserScript(script)
        configuration.userContentController.add(coordinator, contentWorld: .defaultClient, name: CommunityPluginCodeBlockPage.messageHandlerName)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        #if canImport(UIKit)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        // The note scrolls a block; a view scrolls inside, as the plugin's own view does.
        webView.scrollView.isScrollEnabled = fillsSpace
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        #else
        webView.setValue(false, forKey: "drawsBackground")
        #endif
        #if DEBUG
        webView.isInspectable = true
        #endif
        coordinator.webView = webView
        coordinator.block = block
        if let baseAddress = URL(string: CommunityPluginSchemeHandler.scheme + "://" + CommunityPluginSchemeHandler.runtimeHost + "/") {
            webView.loadHTMLString(CommunityPluginCodeBlockPage.shell, baseURL: baseAddress)
        }
        return webView
    }

    @MainActor private func update(_ coordinator: CommunityPluginCodeBlockDisplayCoordinator) {
        coordinator.block = block
        coordinator.present(["html": html, "styleSheets": styleSheets, "isDark": isDark, "textSize": textSize, "accent": accentHex ?? "", "fillsSpace": fillsSpace,
                             "bodyClasses": bodyClasses, "bodyStyle": bodyStyle, "hasTheme": hasTheme])
    }

    @MainActor private static func dismantle(_ webView: WKWebView) {
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.navigationDelegate = nil
        webView.stopLoading()
    }
}

#if canImport(UIKit)
extension CommunityPluginCodeBlockDisplay: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let webView = makeWebView(coordinator: context.coordinator, vaultRoot: block.vaultRoot)
        update(context.coordinator)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        update(context.coordinator)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: CommunityPluginCodeBlockDisplayCoordinator) {
        dismantle(webView)
    }
}
#elseif canImport(AppKit)
extension CommunityPluginCodeBlockDisplay: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let webView = makeWebView(coordinator: context.coordinator, vaultRoot: block.vaultRoot)
        update(context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        update(context.coordinator)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: CommunityPluginCodeBlockDisplayCoordinator) {
        dismantle(webView)
    }
}
#endif
