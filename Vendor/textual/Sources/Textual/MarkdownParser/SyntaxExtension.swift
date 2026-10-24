import Foundation

extension AttributedStringMarkdownParser {
  /// A syntax extension that replaces matched tokens after Markdown parsing.
  public struct SyntaxExtension {
    let patterns: [PatternTokenizer.Pattern]
    let replace:
      (
        _ token: PatternTokenizer.Token,
        _ attributes: AttributeContainer
      ) -> AttributedString?
  }
}

extension AttributedStringMarkdownParser.SyntaxExtension {
  /// Replaces `:shortcode:` sequences using the provided custom emoji definitions.
  public static func emoji(_ emoji: Set<Emoji>) -> Self {
    guard !emoji.isEmpty else {
      return Self(patterns: [], replace: { _, _ in nil })
    }

    let emojiMap = Dictionary(
      uniqueKeysWithValues: emoji.map { emoji in
        (emoji.shortcode, emoji)
      }
    )

    return Self(patterns: [.emoji]) { token, attributes in
      guard let shortcode = token.capturedContent, let emoji = emojiMap[shortcode] else {
        return nil
      }

      return AttributedString(
        shortcode,
        attributes: attributes.emojiURL(emoji.url)
      )
    }
  }

  /// Replaces inline and block math expressions with attachments.
  public static var math: Self {
    .init(patterns: [.mathBlock, .mathInline]) { token, attributes in
      guard let latex = token.capturedContent else {
        return nil
      }
      // Graphite patch: inline math is drawn in pieces a line may break between, as TeX and
      // MathJax break it, so a long formula wraps and a table column holding one can shrink.
      if token.type == .mathInline, let pieces = MathAttachment.inlinePieces(of: latex) {
        return pieces.reduce(into: AttributedString()) { output, piece in
          output.append(AttributedString("\u{FFFC}", attributes: attributes.attachment(.init(piece))))
        }
      }
      // Graphite patch: a formula the typesetter cannot parse stays as its source text.
      // As an attachment it would measure zero and show only a placeholder glyph.
      guard MathAttachment.canTypeset(latex) else {
        return nil
      }

      let attachment = MathAttachment(
        latex: latex,
        style: token.type == .mathBlock ? .block : .inline
      )
      return AttributedString("\u{FFFC}", attributes: attributes.attachment(.init(attachment)))
    }
  }
}
