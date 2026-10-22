import Foundation
import GraphiteCore

/// What a preview card shows: what the reading view shows for an embed of the same link.
struct LinkPreviewContent: Sendable {
    /// The file the link names.
    let path: VaultPath
    /// The heading or `^block` the link names; nil for the whole note.
    let subpath: String?
    /// The note, or its section or block, or the image, as reading-view blocks; for a
    /// heading or block the note does not have, the message saying so.
    let blocks: [RenderedBlock]

    /// The card's title: the note's name, and the heading or block the link names.
    var title: String {
        path.stem + (subpath.map { subpath in " › " + subpath } ?? "")
    }

    /// The card for what an embed of the link shows; nil when it shows no note or image: a
    /// link nothing answers, another kind of file, or a note too large to embed.
    init?(embedPreview block: RenderedBlock) {
        switch block {
        case .transclusion(_, let path, let heading, let body):
            self.init(path: path, subpath: heading, blocks: body)
        case .missingSection(_, let path, let subpath):
            self.init(path: path, subpath: subpath, blocks: [block])
        case .image(_, let path, _, _, _):
            self.init(path: path, subpath: nil, blocks: [block])
        case .properties, .markdown, .displayMath, .heading, .callout, .video, .audio, .pdf, .base, .baseFile, .missingEmbed, .footnotes,
             .pluginCodeBlock, .pluginSection, .diagram:
            return nil
        }
    }

    private init(path: VaultPath, subpath: String?, blocks: [RenderedBlock]) {
        self.path = path
        self.subpath = subpath
        self.blocks = blocks
    }
}

/// What preview cards read notes with: the open vault, and how its notes read in a card
/// (as an embedded note reads, without properties).
struct LinkPreviewReading: Equatable {
    let vault: ReadingVault
    let configuration: ReadingConfiguration

    /// The card for `request`'s link, built off the main actor; nil when the link shows none.
    func content(for request: LinkPreviewRequest) async -> LinkPreviewContent? {
        // A link to a heading or block of its own note (`[[#Heading]]`) names that note.
        let target = request.target.hasPrefix("#") ? request.sourceNote.rawValue + request.target : request.target
        let isWiki = request.isWiki, source = request.sourceNote
        let block = try? await vault.embedPreview(of: target, isWiki: isWiki, from: source, configuration: configuration) // Unreadable: no card.
        return block.flatMap(LinkPreviewContent.init(embedPreview:))
    }

    static func == (leftReading: LinkPreviewReading, rightReading: LinkPreviewReading) -> Bool {
        leftReading.vault.root == rightReading.vault.root && leftReading.vault.index === rightReading.vault.index
            && leftReading.vault.store === rightReading.vault.store && leftReading.configuration == rightReading.configuration
    }
}
