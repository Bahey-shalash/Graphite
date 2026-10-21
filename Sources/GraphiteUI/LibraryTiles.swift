import SwiftUI
import GraphiteCore
import GraphiteApple

/// A folder as Files and the Finder draw one: the system's folder symbol in the folder's
/// color, with its symbol engraved on it, its emoji drawn in color, or its picture placed on it,
/// as the Finder shows them; a picture that is the whole icon is drawn alone.
struct LibraryFolderArtwork: View {
    let style: FolderStyle?
    /// The folder's picture, once read; nil draws the folder without it meanwhile.
    let picture: CGImage?
    /// The folder symbol's point size; the engraved symbol takes about a third of it.
    let symbolPointSize: CGFloat
    @Environment(\.displayScale) private var displayScale

    /// Where a mark sits: the middle of the folder's body, below its tab.
    private var markOffset: CGFloat { symbolPointSize * 0.06 }

    var body: some View {
        let tint = (style?.color).tileColor
        if style?.picture?.layout == .wholeIcon, let picture {
            Image(decorative: picture, scale: displayScale)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: symbolPointSize * 1.1, height: symbolPointSize * 1.1)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "folder.fill")
                .font(.system(size: symbolPointSize))
                .foregroundStyle(tint.gradient)
                .overlay { mark(tint: tint) }
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func mark(tint: Color) -> some View {
        switch style?.mark {
        case .symbol(let symbolName):
            // Engraved: a darker shade of the folder, lit from below as the Finder draws it.
            Image(systemName: symbolName)
                .font(.system(size: symbolPointSize * 0.3, weight: .semibold))
                .foregroundStyle(tint.mix(with: .black, by: 0.3))
                .shadow(color: .white.opacity(0.35), radius: 0, x: 0, y: max(symbolPointSize * 0.008, 0.5))
                .offset(y: markOffset)
        case .emoji(let emojiText):
            Text(emojiText)
                .font(.system(size: symbolPointSize * 0.4))
                .offset(y: markOffset)
        case .picture:
            if let picture {
                // Rounded in the middle of the folder's body, as Finder draws app folders.
                // The folder symbol is about 1.2 times its point size wide; the picture takes Finder's share of that.
                let side = symbolPointSize * 1.2 * FolderIconRenderer.pictureOnFolderSideFraction
                Image(decorative: picture, scale: displayScale)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: side * FolderIconRenderer.pictureOnFolderCornerFraction, style: .continuous))
                    .offset(y: markOffset)
            }
        case nil:
            EmptyView()
        }
    }
}

/// A folder tile's picture: Apple's own folder art wherever the system gives it (Finder's on
/// the Mac, the Files app's on iOS), with the folder's look; Graphite's drawing meanwhile.
struct LibraryFolderTileArtwork: View {
    let folder: VaultPath
    let looks: LibraryFolderLooks
    let symbolPointSize: CGFloat

    var body: some View {
        let look = looks.shownLook(of: folder)
        let image: FolderTileImage? = switch look {
        case .plain: looks.plainFolderIcon.map(FolderTileImage.appleArt)
        case .drawnByFinder, .drawnByGraphite: looks.tileImages[folder]
        }
        FolderArtView(style: look.style, image: image, symbolPointSize: symbolPointSize)
    }
}

/// A folder in Apple's art, with what the art could not carry drawn over it (the symbol or
/// emoji of a color no tag has), or in Graphite's drawing when there is no art.
struct FolderArtView: View {
    let style: FolderStyle?
    let image: FolderTileImage?
    /// The point size Graphite's drawing gives the folder symbol; Apple's art fills the same height.
    let symbolPointSize: CGFloat
    @Environment(\.displayScale) private var displayScale

    /// Apple's icons leave a margin around the folder; this fills the tile as the symbol does.
    private var artSide: CGFloat { symbolPointSize * 1.25 }

    var body: some View {
        switch image {
        case .appleArt(let art):
            Image(decorative: art, scale: displayScale)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: artSide, height: artSide)
                .overlay { markOverArt }
                .accessibilityHidden(true)
        case .picture(let picture):
            LibraryFolderArtwork(style: style, picture: picture, symbolPointSize: symbolPointSize)
        case nil:
            LibraryFolderArtwork(style: style, picture: nil, symbolPointSize: symbolPointSize)
        }
    }

    /// Engraved on the folder's front face as Finder engraves: a darker shade of its color, lit from below.
    @ViewBuilder private var markOverArt: some View {
        let frontFaceOffset = artSide * (FolderIconRenderer.pictureOnFolderCenterFromTopFraction - 0.5)
        switch style.flatMap({ style in AppleFolderArtPlan.plan(for: style).markDrawnOver }) {
        case .symbol(let symbolName):
            Image(systemName: symbolName)
                .font(.system(size: artSide * 0.24, weight: .semibold))
                .foregroundStyle((style?.color).tileColor.mix(with: .black, by: 0.3))
                .shadow(color: .white.opacity(0.35), radius: 0, x: 0, y: max(artSide * 0.006, 0.5))
                .offset(y: frontFaceOffset)
        case .emoji(let emojiText):
            Text(emojiText)
                .font(.system(size: artSide * 0.3))
                .offset(y: frontFaceOffset)
        case .picture, nil:
            EmptyView()
        }
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


extension Optional where Wrapped == FolderColor {
    /// A folder without a color is the system's blue, as in Files and the Finder.
    var tileColor: Color { self?.tileColor ?? .blue }
}

extension FolderColor {
    /// System colors, which adapt to dark mode and increased contrast; a custom color as chosen.
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
        case .custom(let red, let green, let blue):
            Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
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
        case .custom: "Custom Color"
        case .unknown(let rawValue): rawValue.capitalized
        }
    }
}

extension FolderStyle {
    /// The look as VoiceOver reads it after the folder's name: "green, flask".
    var spokenDescription: String {
        var parts: [String] = []
        if let color { parts.append(color.title.lowercased()) }
        switch mark {
        case .symbol(let symbolName): parts.append(FolderSymbolCatalog.spokenName(of: symbolName))
        case .emoji(let emojiText): parts.append(emojiText)
        case .picture: parts.append("picture")
        case nil: break
        }
        return parts.joined(separator: ", ")
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
