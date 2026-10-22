import SwiftUI
import GraphiteCore

/// A link's preview card: the note's name, which opens the link, and the note, its section or
/// block, or the image, as the reading view draws an embed of the link, scrolling inside.
struct LinkPreviewCard: View {
    let request: LinkPreviewRequest
    let content: LinkPreviewContent
    let root: URL
    let textSize: Double
    let actions: LinkPreviewActions
    let model: LinkPreviewModel
    /// The card's height with nothing cut, which places it.
    let naturalHeightDidChange: (CGFloat) -> Void
    @Environment(\.noteTheme) private var theme
    @State private var headerHeight: CGFloat = 0
    @State private var bodyHeight: CGFloat = 0

    private static let cornerRadiusPoints: CGFloat = 12
    private static let bodyPaddingPoints: CGFloat = 16
    private static let dividerThicknessPoints: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .onGeometryChange(for: CGFloat.self) { geometry in geometry.size.height } action: { height in
                    headerHeight = height
                    naturalHeightDidChange(headerHeight + Self.dividerThicknessPoints + bodyHeight)
                }
            Divider()
            ScrollView {
                ReadingBlocksView(blocks: content.blocks, root: root, textSize: textSize,
                                  navigate: { target, isWiki in follow(target, isWiki: isWiki, from: content.path) },
                                  // The card shows part of the note; its own headings are found in the note itself.
                                  scrollToHeading: { _ in follow(request.target, isWiki: request.isWiki, from: request.sourceNote) },
                                  openPDF: { path, pageIndex in
                                      model.close()
                                      actions.openPDF(path, pageIndex)
                                  },
                                  updateProperties: nil)
                    .padding(Self.bodyPaddingPoints)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .onGeometryChange(for: CGFloat.self) { geometry in geometry.size.height } action: { height in
                        bodyHeight = height
                        naturalHeightDidChange(headerHeight + Self.dividerThicknessPoints + bodyHeight)
                    }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(theme?.background.map { color in AnyShapeStyle(Color(color)) } ?? AnyShapeStyle(.background),
                    in: RoundedRectangle(cornerRadius: Self.cornerRadiusPoints))
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadiusPoints))
        .overlay(RoundedRectangle(cornerRadius: Self.cornerRadiusPoints).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
        .onHover { isInside in
            if isInside { model.pointerEnteredCard() } else { model.pointerLeftCard() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Preview of \(content.title)")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                follow(request.target, isWiki: request.isWiki, from: request.sourceNote)
            } label: {
                Label(content.title, systemImage: "doc.text")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .font(.headline)
            .accessibilityHint("Opens the note")
            Button("Close", systemImage: "xmark") { model.close() }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Follows a link of the card, which closes it.
    private func follow(_ target: String, isWiki: Bool, from source: VaultPath) {
        model.close()
        actions.follow(target, isWiki, source)
    }
}
