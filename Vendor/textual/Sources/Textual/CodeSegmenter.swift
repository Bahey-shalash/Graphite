import SwiftUI

extension StructuredText {
  /// A run of a code block's text with the token type that colors it.
  public struct CodeSegment: Hashable, Sendable {
    public let content: String
    public let type: HighlighterTheme.TokenType

    public init(content: String, type: HighlighterTheme.TokenType) {
      self.content = content
      self.type = type
    }
  }

  /// Splits a code block's text, in the language its info names, into segments whose
  /// contents join to the text; nil when it does not know the language, which leaves the
  /// block to Textual's own highlighter. Called synchronously while the block is laid out,
  /// so it must be fast, or cache its results.
  public typealias CodeSegmenter = @Sendable (_ code: String, _ language: String) -> [CodeSegment]?
}

extension EnvironmentValues {
  @Entry var codeSegmenter: StructuredText.CodeSegmenter? = nil
}

extension TextualNamespace where Base: View {
  /// Sets the tokenizer code blocks in ``StructuredText`` use before Textual's own.
  public func codeSegmenter(_ codeSegmenter: @escaping StructuredText.CodeSegmenter) -> some View {
    base.environment(\.codeSegmenter, codeSegmenter)
  }
}
