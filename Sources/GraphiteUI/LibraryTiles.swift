import SwiftUI
import GraphiteCore
import GraphiteApple

/// A folder as Files and the Finder draw one: the system's folder symbol in the folder's
/// color, with its own symbol engraved on it as the Finder shows a folder's symbol.
struct LibraryFolderArtwork: View {
    let style: FolderStyle?
    /// The folder symbol's point size; the engraved symbol takes a third of it.
    let symbolPointSize: CGFloat

    var body: some View {
        let tint = (style?.color ?? .blue).tileColor
        Image(systemName: "folder.fill")
            .font(.system(size: symbolPointSize))
            .foregroundStyle(tint.gradient)
            .overlay {
                if let symbolName = style?.symbolName {
                    Image(systemName: symbolName)
                        .font(.system(size: symbolPointSize * 0.3, weight: .semibold))
                        .foregroundStyle(tint.mix(with: .black, by: 0.35))
                        .offset(y: symbolPointSize * 0.06)
                }
            }
            .accessibilityHidden(true)
    }
}

/// The picture part of a file tile: the page, picture or note text, or the file's kind
/// while there is nothing to draw. Edged with a hairline, as Files edges its thumbnails.
struct LibraryFileArtwork: View {
    let entry: VaultEntry
    let preview: LibraryTilePreview?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            switch preview {
            case .picture(let image):
                Image(decorative: image, scale: displayScale)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
            case .note(let summary, let picture):
                LibraryNotePage(summary: summary, picture: picture, displayScale: displayScale)
            case .notDownloaded:
                kindIcon(systemImage: "icloud.and.arrow.down", caption: "In iCloud")
            case .kindIcon:
                kindIcon(systemImage: entry.kind.librarySymbol, caption: nil)
            case nil:
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.fill.quaternary)
                    .aspectRatio(0.77, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func kindIcon(systemImage: String, caption: String?) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            if let caption { Text(caption).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .aspectRatio(0.77, contentMode: .fit)
    }
}


extension FolderColor {
    /// System colors, which adapt to dark mode and increased contrast.
    var tileColor: Color {
        switch self {
        case .blue, .unknown: .blue
        case .green: .green
        case .yellow: .yellow
        case .orange: .orange
        case .red: .red
        case .pink: .pink
        case .purple: .purple
        case .indigo: .indigo
        case .teal: .teal
        case .gray: .gray
        }
    }

    var title: String {
        switch self {
        case .blue: "Blue"
        case .green: "Green"
        case .yellow: "Yellow"
        case .orange: "Orange"
        case .red: "Red"
        case .pink: "Pink"
        case .purple: "Purple"
        case .indigo: "Indigo"
        case .teal: "Teal"
        case .gray: "Gray"
        case .unknown(let rawValue): rawValue.capitalized
        }
    }
}

extension DocumentKind {
    /// The symbol a file of this kind shows when it has no preview.
    var librarySymbol: String {
        switch self {
        case .markdown: "doc.text"
        case .pdf: "book.closed"
        case .image: "photo"
        case .media: "waveform"
        case .base: "tablecells"
        case .canvas: "rectangle.3.group"
        case .other: "doc"
        }
    }
}
