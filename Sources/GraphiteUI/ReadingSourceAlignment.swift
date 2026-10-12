import Foundation
import SwiftUI
import Textual
import GraphiteCore

enum ReadingSourceAlignment {
    /// Compare every word/equation in order. A missing or altered token disables
    /// the entire mapping; matching a repeated spelling alone is never sufficient.
    static func apply(_ sourceTokens: [ReadAloudSourceToken], to attributed: inout AttributedString) -> Bool {
        let visibleText = String(attributed.characters)
        let prose = NSMutableString(string: visibleText)
        var renderedTokens: [(text: String, range: NSRange, isEquation: Bool)] = []
        for run in attributed.runs {
            let range = NSRange(run.range, in: attributed)
            let isCodeBlock = run.presentationIntent?.components.contains { component in
                if case .codeBlock = component.kind { return true }
                return false
            } ?? false
            let isHTML = run.inlinePresentationIntent?.intersection([.inlineHTML, .blockHTML]).isEmpty == false
            let isFootnote = run.link.flatMap(GraphiteOpenLink.footnoteNumber(of:)) != nil
            if let attachment = run.textual.attachment {
                if attachment.isMathematics { renderedTokens.append(("\u{FFFC}", range, true)) }
                prose.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
            } else if isCodeBlock || isHTML || isFootnote {
                prose.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
            }
        }
        let proseText = prose as String
        // Foundation can concatenate adjacent table cells without a separating
        // character. Their presentation intents retain the semantic boundary.
        for (_, paragraphRange) in attributed.runs[\.presentationIntent] {
            guard let proseRange = Range(NSRange(paragraphRange, in: attributed), in: proseText) else { return false }
            proseText.enumerateSubstrings(in: proseRange, options: [.byWords, .substringNotRequired]) { _, range, _, _ in
                let renderedRange = NSRange(range, in: proseText)
                renderedTokens.append(((visibleText as NSString).substring(with: renderedRange), renderedRange, false))
            }
        }
        renderedTokens.sort { first, second in first.range.location < second.range.location }
        guard sourceTokens.count == renderedTokens.count,
              zip(sourceTokens, renderedTokens).allSatisfy({ source, rendered in
                  source.isEquation == rendered.isEquation && Array(source.text.utf16) == Array(rendered.text.utf16)
              }) else { return false }
        for (source, rendered) in zip(sourceTokens, renderedTokens) {
            guard let range = Range(rendered.range, in: attributed) else { return false }
            attributed[range][ReadingSourceRangeAttribute.self] = source.sourceRange
        }
        return true
    }
}

extension EnvironmentValues {
    @Entry var readingSourceTokensByBlock: [String: [ReadAloudSourceToken]] = [:]
    @Entry var readingActiveSourceRange: NSRange? = nil
    @Entry var readingFollowsSource = false
}
