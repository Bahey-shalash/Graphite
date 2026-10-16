import SwiftUI

// MARK: - Overview
//
// HighlightedTextFragment displays syntax-highlighted code using a two-phase approach.
// Tokenization runs asynchronously and is keyed by content, while highlighting runs
// synchronously on token or environment changes (theme, color scheme, dynamic type).
//
// The presentationIntent is preserved after highlighting so pasteboard formatters can
// reconstruct the block structure when copying code.

struct HighlightedTextFragment: View {
  @Environment(\.textEnvironment) private var textEnvironment
  @Environment(\.codeSegmenter) private var codeSegmenter

  @State private var model = Model()

  private let content: AttributedSubstring
  private let languageHint: String?
  private let theme: StructuredText.HighlighterTheme

  init(
    _ content: AttributedSubstring,
    languageHint: String?,
    theme: StructuredText.HighlighterTheme
  ) {
    self.content = content
    self.languageHint = languageHint
    self.theme = theme
  }

  var body: some View {
    if let codeSegmenter, let languageHint,
      let highlightedCode = model.segmentedCode(
        content: content, languageHint: languageHint, segmenter: codeSegmenter, theme: theme,
        environment: textEnvironment)
    {
      // The host's tokenizer runs synchronously: the block never shows uncolored first.
      TextFragment(highlightedCode)
        .foregroundStyle(theme.foregroundColor)
    } else {
      asynchronouslyHighlighted
    }
  }

  private var asynchronouslyHighlighted: some View {
    TextFragment(model.highlightedCode ?? AttributedString(content))
      .foregroundStyle(theme.foregroundColor)
      .task(id: content) {
        await model.tokenize(
          content: content,
          languageHint: languageHint
        )
      }
      .onChange(of: Tuple(model.tokens, textEnvironment)) { _, newValue in
        model.highlight(
          tokens: newValue.values.0,
          presentationIntent: content.presentationIntent,
          using: theme,
          environment: newValue.values.1
        )
      }
  }
}

extension HighlightedTextFragment {
  @MainActor @Observable final class Model {
    var tokens: [CodeToken] = []
    var highlightedCode: AttributedString?
    /// The host's highlighting of the last content, kept while the view's inputs stay the same.
    @ObservationIgnored private var lastSegmented:
      (key: SegmentedCodeKey, highlightedCode: AttributedString?)?

    struct SegmentedCodeKey: Equatable {
      let content: AttributedSubstring
      let languageHint: String
      let theme: StructuredText.HighlighterTheme
      let environment: TextEnvironmentValues
    }

    func segmentedCode(
      content: AttributedSubstring,
      languageHint: String,
      segmenter: StructuredText.CodeSegmenter,
      theme: StructuredText.HighlighterTheme,
      environment: TextEnvironmentValues
    ) -> AttributedString? {
      let key = SegmentedCodeKey(
        content: content, languageHint: languageHint, theme: theme, environment: environment)
      if let lastSegmented, lastSegmented.key == key { return lastSegmented.highlightedCode }
      let segments = segmenter(String(content.characters[...]), languageHint)
      let highlightedCode = segments.map { segments in
        highlighted(
          tokens: segments.map { segment in CodeToken(content: segment.content, type: segment.type) },
          presentationIntent: content.presentationIntent,
          using: theme,
          environment: environment)
      }
      lastSegmented = (key, highlightedCode)
      return highlightedCode
    }

    func tokenize(content: AttributedSubstring, languageHint: String?) async {
      let code = String(content.characters[...])
      tokens = [CodeToken(content: code, type: .plain)]

      if let tokenizer = CodeTokenizer.shared, let languageHint {
        tokens = await tokenizer.tokenize(code: code, language: languageHint)
      }
    }

    func highlight(
      tokens: [CodeToken],
      presentationIntent: PresentationIntent?,
      using theme: StructuredText.HighlighterTheme,
      environment: TextEnvironmentValues
    ) {
      highlightedCode = highlighted(
        tokens: tokens, presentationIntent: presentationIntent, using: theme,
        environment: environment)
    }

    private func highlighted(
      tokens: [CodeToken],
      presentationIntent: PresentationIntent?,
      using theme: StructuredText.HighlighterTheme,
      environment: TextEnvironmentValues
    ) -> AttributedString {
      var attributes = AttributeContainer()
      // Re-apply the presentation intent for pasteboard formatters
      attributes.presentationIntent = presentationIntent
      ForegroundColorProperty(theme.foregroundColor)
        .apply(in: &attributes, environment: environment)
      var highlightedCode = AttributedString()

      for token in tokens {
        var content = AttributedString(token.content)
        var tokenAttributes = attributes

        if let tokenProperties = theme.tokenProperties[token.type] {
          tokenProperties.apply(in: &tokenAttributes, environment: environment)
        }

        content.mergeAttributes(tokenAttributes)
        highlightedCode.append(content)
      }

      return highlightedCode
    }
  }
}
