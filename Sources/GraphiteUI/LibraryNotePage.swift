import SwiftUI
import GraphiteCore

/// A note's tile drawn as a page of its reading view: the start of the note laid out at a
/// document's width, in its real type sizes and wrapping, then scaled down to the tile, as
/// the Files app shows a document's first page. The page is light whatever the appearance,
/// as paper is.
struct LibraryNotePage: View {
    let summary: NotePreviewSummary
    let picture: CGImage?
    let displayScale: CGFloat
    /// Width over height: a portrait page in the library, the card's shape in the tab overview.
    var pageAspectRatio: CGFloat = Self.portraitAspectRatio

    /// The width the note is laid out at before scaling, in points: about a phone's reading
    /// width, so lines wrap as they would on a page.
    private static let pageWidthPoints: CGFloat = 300
    private static let portraitAspectRatio: CGFloat = 0.77
    private static let pageMarginPoints: CGFloat = 20

    var body: some View {
        Color.white
            .aspectRatio(pageAspectRatio, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                GeometryReader { geometry in
                    page
                        .frame(width: Self.pageWidthPoints, height: Self.pageWidthPoints / pageAspectRatio, alignment: .topLeading)
                        .scaleEffect(geometry.size.width / Self.pageWidthPoints, anchor: .topLeading)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
            .environment(\.colorScheme, .light)
            .accessibilityHidden(true)
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(summary.blocks.enumerated()), id: \.offset) { _, block in blockView(block) }
        }
        .padding(Self.pageMarginPoints)
        .foregroundStyle(Color.black)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Every line wraps to its full height, as on a page; what passes the page's bottom
        // edge is cut there rather than squeezing each line to one.
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func blockView(_ block: NotePreviewSummary.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(.system(size: Self.headingPointSize(level: level), weight: level <= 2 ? .bold : .semibold))
                .padding(.top, level <= 2 ? 4 : 2)
        case .paragraph(let text):
            Text(text).font(.system(size: 12))
        case .listItem(let marker, let depth, let text):
            listRow(depth: depth) { Text(marker).font(.system(size: 12)).foregroundStyle(.secondary) } text: { Text(text) }
        case .task(let isDone, let depth, let text):
            taskRow(isDone: isDone, depth: depth, text: text)
        case .quote(let text):
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) { Rectangle().fill(.quaternary).frame(width: 3) }
        case .callout(let type, let title):
            calloutHeader(type: type, title: title)
        case .code(let code):
            Text(code)
                .font(.system(size: 10, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 0.95), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        case .rule:
            Rectangle().fill(.quaternary).frame(height: 1).padding(.vertical, 3)
        case .picture:
            if let picture {
                Image(decorative: picture, scale: displayScale)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 140, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
    }

    private func taskRow(isDone: Bool, depth: Int, text: AttributedString) -> some View {
        listRow(depth: depth) {
            Image(systemName: isDone ? "checkmark.square.fill" : "square")
                .font(.system(size: 11))
                .foregroundStyle(isDone ? Color.accentColor : Color.secondary)
        } text: {
            Text(text).strikethrough(isDone).foregroundStyle(isDone ? .secondary : .primary)
        }
    }

    private func calloutHeader(type: String, title: AttributedString) -> some View {
        let tint = Self.calloutColor(type: type)
        return Label { Text(title).font(.system(size: 12, weight: .semibold)) } icon: {
            Image(systemName: Self.calloutSymbol(type: type)).font(.system(size: 11))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func listRow<Marker: View, Content: View>(depth: Int, @ViewBuilder marker: () -> Marker, @ViewBuilder text: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            marker()
            text().font(.system(size: 12))
        }
        .padding(.leading, CGFloat(depth) * 16)
    }

    private static func headingPointSize(level: Int) -> CGFloat {
        switch level {
        case 1: 22
        case 2: 18
        case 3: 15
        default: 13
        }
    }

    /// Obsidian's callout families, by the type as written.
    private static func calloutSymbol(type: String) -> String {
        switch type.lowercased() {
        case "tip", "hint", "important": "flame"
        case "success", "check", "done": "checkmark.circle"
        case "question", "help", "faq": "questionmark.circle"
        case "warning", "caution", "attention": "exclamationmark.triangle"
        case "failure", "fail", "missing", "danger", "error", "bug": "xmark.octagon"
        case "example": "list.bullet"
        case "quote", "cite": "quote.opening"
        default: "info.circle"
        }
    }

    private static func calloutColor(type: String) -> Color {
        switch type.lowercased() {
        case "tip", "hint", "important": .teal
        case "success", "check", "done": .green
        case "question", "help", "faq", "warning", "caution", "attention": .orange
        case "failure", "fail", "missing", "danger", "error", "bug": .red
        case "example": .purple
        case "quote", "cite": .gray
        default: .blue
        }
    }
}
