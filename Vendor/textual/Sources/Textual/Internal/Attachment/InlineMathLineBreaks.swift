/**
 * File: InlineMathLineBreaks.swift
 * --------------------------------
 * Layer: Vendor (Textual)
 * Description: Graphite patch: where a line may break inside inline math, as TeX and MathJax
 *              break it, so a formula is drawn in pieces that wrap like words.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/10/2026
 */

@_spi(Textual) private import SwiftUIMath

/// Where a line may break inside inline math, as TeX and MathJax break it: after a binary
/// operator or a relation at the formula's outer level, never inside a group, a `\left…\right`
/// pair, an environment, or a script.
///
/// A formula drawn as one attachment cannot break, so a table cell of
/// `$(C_{jb} \cdot L_A + C_{jsw})W + C_j \cdot W \cdot L/2$` kept its column as wide as the
/// whole formula and the table scrolled. Drawn in these pieces side by side, it wraps
/// between them.
enum InlineMathLineBreaks {
  /// The space TeX puts after a binary operator (4 mu) and after a relation (5 mu). A piece
  /// ends with it, because an operator at the end of a formula loses its spacing.
  private static let spaceAfterBinaryOperator = "\\>"
  private static let spaceAfterRelation = "\\;"

  /// The formula cut after each operator where a line may break, each piece ending with the
  /// space TeX puts after that operator; nil when it has no such place, or when cutting it
  /// could change how it is drawn (a style switch or an infix fraction at its outer level).
  static func pieces(of latex: String) -> [String]? {
    let characters = Array(latex)
    var scanner = Scanner(characters: characters)
    guard let breaks = scanner.lineBreaks(), !breaks.isEmpty else {
      return nil
    }
    var pieces: [String] = []
    var pieceStart = 0
    for lineBreak in breaks {
      let space = lineBreak.isAfterRelation ? spaceAfterRelation : spaceAfterBinaryOperator
      pieces.append(String(characters[pieceStart..<lineBreak.offset]) + space)
      pieceStart = lineBreak.offset
    }
    pieces.append(String(characters[pieceStart...]))
    return pieces
  }
}

private struct LineBreak {
  /// The offset of the first character after the operator.
  let offset: Int
  let isAfterRelation: Bool
}

/// Reads a formula once, following its outer level.
private struct Scanner {
  /// Commands that change how everything after them at their level is drawn: a piece cut
  /// after one would lose it, and an infix fraction takes everything before it.
  private static let commandsThatPreventBreaking: Set<String> = [
    "displaystyle", "textstyle", "scriptstyle", "scriptscriptstyle",
    "over", "atop", "choose", "brack", "brace",
  ]
  /// Spacing commands, which change no class.
  private static let spaceCommands: Set<String> = ["quad", "qquad"]
  /// Spaces, and a prime, which belongs to the symbol before it.
  private static let charactersWithoutClass: Set<Character> = [" ", "\t", "\n", "\r", "~", "'"]
  private static let spaceControlSymbols: Set<Character> = [",", ";", ":", ">", "!", " "]

  let characters: [Character]
  private var position = 0
  /// How many braces, `\left…\right` pairs and environments are open at `position`.
  private var nestingDepth = 0
  /// The class of the last symbol at the outer level; nil before the first.
  private var previousClass: Math.SymbolClass?
  /// A break after the last operator, made once the symbol after that operator allows it.
  private var pendingBreak: LineBreak?
  private var breaks: [LineBreak] = []

  init(characters: [Character]) {
    self.characters = characters
  }

  /// Every place a line may break, in order; nil when the formula must stay whole.
  mutating func lineBreaks() -> [LineBreak]? {
    while position < characters.count {
      let character = characters[position]
      position += 1
      switch character {
      case _ where Self.charactersWithoutClass.contains(character):
        continue
      case "{":
        if nestingDepth == 0 { outerSymbol(.ordinary) }
        nestingDepth += 1
      case "}":
        nestingDepth -= 1
        guard nestingDepth >= 0 else { return nil }
        if nestingDepth == 0 { previousClass = .ordinary }
      case "^", "_":
        skipScriptArgument()
      case "\\":
        guard command() else { return nil }
      case "%", "&", "$", "#":
        // A comment, an alignment outside an environment: leave the formula alone.
        if nestingDepth == 0 { return nil }
      default:
        if nestingDepth == 0 {
          outerSymbol(Math.symbolClass(ofCharacter: character) ?? .ordinary)
        }
      }
    }
    return nestingDepth == 0 ? breaks : nil
  }

  /// Reads the command after a backslash; false when the formula must stay whole.
  private mutating func command() -> Bool {
    guard position < characters.count else { return false }
    let first = characters[position]
    guard first.isLetter, first.isASCII else {
      // A control symbol: `\{`, `\|`, `\,`, `\\`.
      position += 1
      return controlSymbol(first)
    }
    let nameStart = position
    while position < characters.count, characters[position].isLetter, characters[position].isASCII {
      position += 1
    }
    let name = String(characters[nameStart..<position])
    // `\operatorname*` and the like: the star belongs to the command.
    if position < characters.count, characters[position] == "*" { position += 1 }

    switch name {
    case "left":
      if nestingDepth == 0 { outerSymbol(.ordinary) }
      skipToken()
      nestingDepth += 1
    case "right":
      skipToken()
      nestingDepth -= 1
      guard nestingDepth >= 0 else { return false }
      if nestingDepth == 0 { previousClass = .close }
    case "begin":
      if nestingDepth == 0 { outerSymbol(.ordinary) }
      nestingDepth += 1
    case "end":
      nestingDepth -= 1
      guard nestingDepth >= 0 else { return false }
    case "sqrt":
      if nestingDepth == 0 { outerSymbol(.ordinary) }
      skipRootIndex()
    case _ where Self.spaceCommands.contains(name):
      break
    case _ where Self.commandsThatPreventBreaking.contains(name):
      if nestingDepth == 0 { return false }
    default:
      if nestingDepth == 0 { outerSymbol(Math.symbolClass(ofCommand: name) ?? .ordinary) }
    }
    return true
  }

  private mutating func controlSymbol(_ symbol: Character) -> Bool {
    guard nestingDepth == 0 else { return true }
    switch symbol {
    case "\\":
      // A line break of its own: leave the formula alone.
      return false
    case _ where Self.spaceControlSymbols.contains(symbol):
      break
    case "{":
      outerSymbol(.open)
    case "}":
      outerSymbol(.close)
    default:
      outerSymbol(.ordinary)
    }
    return true
  }

  /// A symbol at the outer level: it decides whether the line may break after the operator
  /// before it, and may itself be an operator to break after.
  private mutating func outerSymbol(_ symbolClass: Math.SymbolClass) {
    if let lineBreak = pendingBreak {
      pendingBreak = nil
      // TeX draws a binary operator before a relation, a closing bracket or punctuation as
      // a sign, and a line never breaks between two relations (`:=`).
      let keepsBreak = switch symbolClass {
      case .relation: false
      case .close, .punctuation: lineBreak.isAfterRelation
      case .ordinary, .largeOperator, .binaryOperator, .open: true
      }
      if keepsBreak { breaks.append(lineBreak) }
    }
    switch symbolClass {
    case .binaryOperator:
      // An operator with nothing before it to operate on is a sign (`-x`, `= -x`, `(-x`).
      if previousClass == .ordinary || previousClass == .close {
        pendingBreak = LineBreak(offset: position, isAfterRelation: false)
        previousClass = .binaryOperator
      } else {
        previousClass = .ordinary
      }
    case .relation:
      if previousClass != nil {
        pendingBreak = LineBreak(offset: position, isAfterRelation: true)
      }
      previousClass = .relation
    case .ordinary, .largeOperator, .open, .close, .punctuation:
      previousClass = symbolClass
    }
  }

  /// Steps over a superscript's or subscript's argument: a group, or one character or command.
  private mutating func skipScriptArgument() {
    skipSpaces()
    guard position < characters.count else { return }
    if characters[position] == "{" {
      position += 1
      nestingDepth += 1
    } else {
      skipToken()
    }
  }

  /// Steps over one character, or one command with its backslash.
  private mutating func skipToken() {
    skipSpaces()
    guard position < characters.count else { return }
    let character = characters[position]
    position += 1
    guard character == "\\", position < characters.count else { return }
    if characters[position].isLetter, characters[position].isASCII {
      while position < characters.count, characters[position].isLetter, characters[position].isASCII {
        position += 1
      }
    } else {
      position += 1
    }
  }

  /// Steps over the index of `\sqrt[n]{x}`, which is not part of the outer level.
  private mutating func skipRootIndex() {
    skipSpaces()
    guard position < characters.count, characters[position] == "[" else { return }
    var bracketDepth = 0
    while position < characters.count {
      let character = characters[position]
      position += 1
      if character == "\\" {
        position += 1
      } else if character == "[" || character == "{" {
        bracketDepth += 1
      } else if character == "]" || character == "}" {
        bracketDepth -= 1
        if bracketDepth == 0 { return }
      }
    }
  }

  private mutating func skipSpaces() {
    while position < characters.count, characters[position] == " " || characters[position] == "\t" {
      position += 1
    }
  }
}
