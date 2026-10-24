/**
 * File: ReadingSourceAlignment.swift
 * ----------------------------------
 * Layer: UI
 * Description: Matches the reading view's rendered words and formulas to the read-aloud voice's source
 *              tokens, so the spoken word is highlighted where it is drawn.
 *
 * Authors: Bahey Shalash
 * Version: 0.6
 * Date: 24/10/2026
 */

import Foundation
import SwiftUI
import Textual
import GraphiteCore

enum ReadingSourceAlignment {
    /// The voice's text has the parser's typographic marks ("gate’s"), the rendered note may
    /// show what was typed ("gate's"). They are the same word; any other difference still
    /// disables the block's mapping. Before, one apostrophe left a whole paragraph unlit.
    static func comparable(_ word: String) -> [UInt16] {
        var units: [UInt16] = []
        for scalar in word.unicodeScalars {
            switch scalar {
            case "\u{2018}", "\u{2019}", "\u{02BC}": units.append(39)
            case "\u{201C}", "\u{201D}": units.append(34)
            case "\u{2013}", "\u{2014}": units.append(45)
            default: units.append(contentsOf: String(scalar).utf16)
            }
        }
        return units
    }

    /// Compare every word/equation in order. A missing or altered token disables
    /// the entire mapping; matching a repeated spelling alone is never sufficient.
    private typealias RenderedToken = (text: String, range: NSRange, isEquation: Bool)

    /// A formula a line may break inside is drawn in pieces (Textual patch 21), but is one
    /// equation in the source: a later piece widens the equation before it.
    private static func appendEquation(_ range: NSRange, continuesFormula: Bool, to renderedTokens: inout [RenderedToken]) {
        if continuesFormula, let formula = renderedTokens.last, formula.isEquation {
            renderedTokens[renderedTokens.count - 1].range = NSUnionRange(formula.range, range)
        } else {
            renderedTokens.append(("\u{FFFC}", range, true))
        }
    }

    static func apply(_ sourceTokens: [ReadAloudSourceToken], to attributed: inout AttributedString) -> Bool {
        let visibleText = String(attributed.characters)
        let prose = NSMutableString(string: visibleText)
        var renderedTokens: [RenderedToken] = []
        for run in attributed.runs {
            let range = NSRange(run.range, in: attributed)
            let isCodeBlock = run.presentationIntent?.components.contains { component in
                if case .codeBlock = component.kind { return true }
                return false
            } ?? false
            let isHTML = run.inlinePresentationIntent?.intersection([.inlineHTML, .blockHTML]).isEmpty == false
            let isFootnote = run.link.flatMap(GraphiteOpenLink.footnoteNumber(of:)) != nil
            if let attachment = run.textual.attachment {
                if attachment.isMathematics { appendEquation(range, continuesFormula: attachment.continuesFormula, to: &renderedTokens) }
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
                  source.isEquation == rendered.isEquation && comparable(source.text) == comparable(rendered.text)
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
    /// The keys the reading view folds headings and remembers callouts by (`ReadingFoldKeys`).
    @Entry var readingFoldKeys = ReadingFoldKeys()
    @Entry var readingActiveSourceRange: NSRange? = nil
    @Entry var readingFollowsSource = false
    /// The reading view's word read, one cell per text (`ReadingWordCells`); nil elsewhere.
    @Entry var readingWordCells: ReadingWordCells? = nil
    /// The fill behind the word read aloud in rendered text (`ObsidianMarkdownText`).
    @Entry var readingHighlightFill: Color = ReadAloudHighlightStyle.color
}
