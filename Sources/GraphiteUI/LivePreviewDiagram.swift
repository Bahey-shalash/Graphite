import SwiftUI
import GraphiteCore
import MermaidDiagrams

/// A ```` ```mermaid ```` block in Live Preview, over its concealed fence: the diagram the reading view draws for the same
/// code (`ReadingDiagramView`), read and laid out away from the main actor in the note's text font and size, so that the
/// main actor only draws it. A diagram that cannot be read shows its source and why, and a type not drawn natively yet
/// shows its code, as in the reading view. A tap shows the source, with the cursor at the fence, as a formula's does.
struct LivePreviewDiagramView: View {
    let source: String
    let environment: LivePreviewEnvironment
    let revealSource: () -> Void
    @State private var preparation: LivePreviewDiagramPreparation?

    var body: some View {
        let request = LivePreviewDiagramRequest(source: source, environment: environment)
        // One made for another font is drawn in proportion to the text size until the new one is laid out
        // (`ReadingDiagramView`); one made for other code is never drawn.
        let shownPreparation = preparation.flatMap { prepared in prepared.request.source == source ? prepared : nil }
        content(shownPreparation)
            .contentShape(Rectangle())
            .onTapGesture(perform: revealSource)
            // Until the diagram is laid out, the empty space's height is not reported as the block's.
            .transformPreference(LivePreviewEmbedLoadingKey.self) { isLoading in isLoading = isLoading || shownPreparation == nil }
            .task(id: request) {
                let prepared = await LivePreviewDiagramPreparation.prepared(for: request)
                guard !Task.isCancelled else { return }
                preparation = prepared
            }
    }

    @ViewBuilder private func content(_ shownPreparation: LivePreviewDiagramPreparation?) -> some View {
        switch shownPreparation?.content {
        case .diagram(let diagram):
            ReadingDiagramView(diagram: diagram, textSize: environment.textSize, root: environment.root, navigate: environment.follow,
                               // `follow` scrolls the note to a heading written as `#heading`.
                               scrollToHeading: { anchor in environment.follow("#" + anchor, true) })
        case .code:
            RenderedMarkdownBlock(markdown: "```mermaid\n" + source + "\n```", environment: environment)
        case nil:
            Color.clear.frame(height: 0)
        }
    }
}

/// The code a diagram block is prepared from, and the font it is laid out in: the note's text font at its size, as the
/// reading view lays diagrams out.
struct LivePreviewDiagramRequest: Equatable, Sendable {
    let source: String
    let font: DiagramFont

    init(source: String, font: DiagramFont) {
        self.source = source
        self.font = font
    }

    init(source: String, environment: LivePreviewEnvironment) {
        self.init(source: source, font: DiagramFont(postScriptName: environment.typography.diagramFontPostScriptName, size: CGFloat(environment.textSize)))
    }
}

/// What a diagram block shows, decided as the reading view decides it (`ReadingDiagram`).
enum LivePreviewDiagramContent: Sendable {
    /// A diagram of a type drawn natively, laid out; or its source with why it could not be read or laid out.
    case diagram(ReadingDiagram)
    /// A type not drawn natively yet, or a diagram holding what its type does not lay out yet: shown as code.
    case code
}

/// A diagram block's code read and laid out for one request.
struct LivePreviewDiagramPreparation: Sendable {
    let request: LivePreviewDiagramRequest
    let content: LivePreviewDiagramContent

    /// Reads and lays the code out away from the main actor, as the reading view's builder does. Each block makes the
    /// measurers of its font (`DiagramTypography`, about 40 µs in `Coverage.md`), less than its hosted view costs to make;
    /// the view is made once while the block stays concealed and kept off screen after (`DetachedWidgetPool`).
    static func prepared(for request: LivePreviewDiagramRequest) async -> LivePreviewDiagramPreparation {
        await Task.detached(priority: .userInitiated) {
            LivePreviewDiagramPreparation(request: request, content: content(of: request))
        }.value
    }

    static func content(of request: LivePreviewDiagramRequest) -> LivePreviewDiagramContent {
        guard let diagram = ReadingDiagram(source: request.source, typography: DiagramTypography(font: request.font)) else { return .code }
        return .diagram(diagram)
    }
}
