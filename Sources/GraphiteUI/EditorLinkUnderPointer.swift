import Foundation
import GraphiteCore

/// The link to a note under the pointer in the editor, the same on the iPad and the Mac,
/// whose preview card shows while the pointer rests there.
struct EditorLinkUnderPointer: Equatable {
    let target: String
    let isWiki: Bool
    /// The whole link in the note, brackets included, in UTF-16 code units.
    let range: NSRange

    /// The note link around `characterIndex` of `source`, in Live Preview and in source mode,
    /// whether its markup shows or not; nil for a web link, an embed, or a link written in
    /// code, math or frontmatter, which are text.
    static func link(at characterIndex: Int, in source: NSString) -> EditorLinkUnderPointer? {
        guard characterIndex >= 0, characterIndex < source.length else { return nil }
        let lineRange = source.lineRange(for: NSRange(location: characterIndex, length: 0))
        guard let located = LinkLocator.locatedLink(in: source.substring(with: lineRange), at: characterIndex - lineRange.location, includesEnd: false),
              case .note(let target, let isWiki) = located.link,
              !LivePreviewTapTargets.isInsideCode(characterIndex, in: source) else { return nil }
        return EditorLinkUnderPointer(target: target, isWiki: isWiki,
                                      range: NSRange(location: lineRange.location + located.range.location, length: located.range.length))
    }
}
