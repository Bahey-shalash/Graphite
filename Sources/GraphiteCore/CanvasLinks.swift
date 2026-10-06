import Foundation

/// Something in a canvas that names another file of the vault: a file card's `file`, a
/// group's background image, or the Markdown of a text card, which may hold links.
public struct CanvasLinkSource: Sendable {
    public enum Kind: Sendable {
        /// A whole path from the vault's root, as file cards and backgrounds write it.
        case filePath
        case groupBackground
        /// A text card's Markdown.
        case text
    }

    public let kind: Kind
    public let value: String
    /// The card's place in the file's `nodes` list.
    let elementIndex: Int
}

extension CanvasFile {
    /// Everything in the canvas that may name another file, in file order. Cards Graphite
    /// cannot show (without a position, say) are included: they still name their files.
    public var linkSources: [CanvasLinkSource] {
        var sources: [CanvasLinkSource] = []
        for (elementIndex, value) in nodeValues.enumerated() {
            switch value.member("type")?.value.string {
            case "file":
                if let path = value.member("file")?.value.string, !path.isEmpty {
                    sources.append(CanvasLinkSource(kind: .filePath, value: path, elementIndex: elementIndex))
                }
            case "group":
                if let background = value.member("background")?.value.string, !background.isEmpty {
                    sources.append(CanvasLinkSource(kind: .groupBackground, value: background, elementIndex: elementIndex))
                }
            case "text":
                if let text = value.member("text")?.value.string, !text.isEmpty {
                    sources.append(CanvasLinkSource(kind: .text, value: text, elementIndex: elementIndex))
                }
            default:
                break
            }
        }
        return sources
    }

    /// The canvas with new values for some of its `linkSources`, as after a file they
    /// name moved. Only those values change; every other byte stays as written.
    public func replacing(_ replacements: [(source: CanvasLinkSource, newValue: String)]) throws -> CanvasFile {
        let values = nodeValues
        var splices: [CanvasSplice] = []
        for replacement in replacements {
            guard values.indices.contains(replacement.source.elementIndex) else { throw CanvasFileError.missingItem }
            var edit = CanvasObjectEdit(object: values[replacement.source.elementIndex], bytes: bytes)
            switch replacement.source.kind {
            case .filePath: edit.setString("file", to: replacement.newValue)
            case .groupBackground: edit.setString("background", to: replacement.newValue)
            case .text: edit.setString("text", to: replacement.newValue)
            }
            splices += edit.splices()
        }
        guard !splices.isEmpty else { return self }
        let orderedSplices = splices.sorted { firstSplice, secondSplice in firstSplice.range.lowerBound < secondSplice.range.lowerBound }
        guard let result = CanvasPatch(steps: [orderedSplices]).applying(to: bytes) else { throw CanvasFileError.editNotApplied }
        do { return try CanvasFile(validatedBytes: result.bytes) } catch { throw CanvasFileError.editNotApplied }
    }
}

/// A canvas's links for the vault index, so a note shown on a canvas lists the canvas
/// among its backlinks, as in Obsidian, and a rename finds the canvases to update.
public enum CanvasLinks {
    /// The links of a canvas as the index stores a note's: each file card and group
    /// background as an embed of its file, and the links written in text cards. A canvas
    /// that cannot be read has none.
    public static func semantics(ofCanvasText canvasText: String) -> NoteSemantics {
        var links: [NoteLink] = []
        if let file = try? CanvasFile(data: Data(canvasText.utf8)) {
            for source in file.linkSources {
                switch source.kind {
                case .filePath, .groupBackground:
                    links.append(NoteLink(target: markdownLinkTarget(forFilePath: source.value), label: nil, isEmbed: true, isWiki: false, location: 0, length: 0))
                case .text:
                    links += (try? NoteLinkScanner.links(in: source.value)) ?? []
                }
            }
        }
        return NoteSemantics(links: links, headings: [], tags: [], aliases: [], body: "", frontmatter: nil)
    }

    /// A file card's path as a Markdown link destination that names exactly that file.
    /// The index decodes percent escapes in such a destination and ends its path at `#`,
    /// so both are escaped; the leading `/` says the path starts at the vault's root, as
    /// a file card's always does, where a bare path would first be looked for beside the
    /// canvas.
    static func markdownLinkTarget(forFilePath path: String) -> String {
        "/" + path.replacingOccurrences(of: "%", with: "%25").replacingOccurrences(of: "#", with: "%23")
    }
}
