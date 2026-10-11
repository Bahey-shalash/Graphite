import Foundation

/// A deliberately bounded subset of LaTeX, interpreted before speech synthesis.
/// Unknown commands fail the whole expression instead of changing its meaning.
public enum MathSpeech {
    public static func expression(_ source: String) -> String? {
        guard source.utf16.count <= 8_192 else { return nil }
        var delimiters: [Character] = []
        for character in source {
            if character == "(" || character == "[" { delimiters.append(character) }
            if character == ")" || character == "]" {
                guard delimiters.popLast() == (character == ")" ? "(" : "[") else { return nil }
            }
        }
        guard delimiters.isEmpty else { return nil }
        var parser = Parser(characters: Array(source))
        guard let speech = parser.sequence(depth: 0, closesGroup: false), parser.position == parser.characters.count,
              !speech.isEmpty else { return nil }
        return speech
    }

    private struct Parser {
        let characters: [Character]
        var position = 0
        static let commandSpeech = [
            "alpha": "alpha", "beta": "beta", "gamma": "gamma", "delta": "delta", "epsilon": "epsilon",
            "theta": "theta", "lambda": "lambda", "mu": "mu", "nu": "nu", "pi": "pi", "rho": "rho",
            "sigma": "sigma", "tau": "tau", "phi": "phi", "psi": "psi", "omega": "omega",
            "Gamma": "capital gamma", "Delta": "capital delta", "Theta": "capital theta", "Sigma": "capital sigma",
            "Phi": "capital phi", "Omega": "capital omega", "infty": "infinity", "times": "times", "cdot": "times",
            "leq": "less than or equal to", "geq": "greater than or equal to", "neq": "not equal to", "approx": "approximately equals",
            "pm": "plus or minus", "in": "belongs to", "to": "tends to", "sin": "sine", "cos": "cosine", "tan": "tangent",
            "log": "log", "ln": "natural log", "exp": "exponential"
        ]

        mutating func skipWhitespace() {
            while position < characters.count, characters[position].isWhitespace { position += 1 }
        }

        mutating func sequence(depth: Int, closesGroup: Bool) -> String? {
            guard depth <= 32 else { return nil }
            var terms: [String] = []
            var hasBase = false
            var hasPower = false
            var hasSubscript = false
            while true {
                skipWhitespace()
                guard position < characters.count else { return closesGroup ? nil : terms.joined(separator: " ") }
                if characters[position] == "}" {
                    guard closesGroup else { return nil }
                    position += 1
                    return terms.isEmpty ? nil : terms.joined(separator: " ")
                }
                let character = characters[position]
                if character == "^" || character == "_" {
                    guard hasBase, character == "^" ? !hasPower : !hasSubscript else { return nil }
                    if character == "^" { hasPower = true } else { hasSubscript = true }
                } else {
                    hasBase = character.isLetter || character.isNumber || character == "\\" || character == "{" || character == ")" || character == "]"
                    hasPower = false; hasSubscript = false
                }
                guard let term = atom(depth: depth) else { return nil }
                terms.append(term)
            }
        }

        mutating func requiredGroup(depth: Int) -> String? {
            skipWhitespace()
            guard position < characters.count, characters[position] == "{" else { return nil }
            position += 1
            return sequence(depth: depth + 1, closesGroup: true)
        }

        mutating func atom(depth: Int) -> String? {
            guard depth <= 32, position < characters.count else { return nil }
            let character = characters[position]
            position += 1
            if character == "{" {
                return sequence(depth: depth + 1, closesGroup: true).map { speech in "open group \(speech) close group" }
            }
            if character == "\\" {
                var command = ""
                while position < characters.count, characters[position].isASCII, characters[position].isLetter {
                    command.append(characters[position]); position += 1
                }
                if command == "frac" {
                    guard let numerator = requiredGroup(depth: depth), let denominator = requiredGroup(depth: depth) else { return nil }
                    return "fraction, numerator \(numerator), denominator \(denominator), end fraction"
                }
                if command == "sqrt" {
                    return requiredGroup(depth: depth).map { radicand in "square root of \(radicand), end root" }
                }
                return Self.commandSpeech[command]
            }
            if character == "^" || character == "_" {
                skipWhitespace()
                let argument: String?
                if position < characters.count, characters[position] == "{" { argument = requiredGroup(depth: depth) }
                else if position < characters.count, characters[position].isASCII, characters[position].isNumber {
                    argument = String(characters[position]); position += 1
                } else if position < characters.count, characters[position].isLetter || characters[position] == "\\" {
                    argument = atom(depth: depth + 1)
                } else { return nil }
                guard let argument else { return nil }
                if character == "_" { return "subscript \(argument), end subscript" }
                if argument == "2" { return "squared" }
                if argument == "3" { return "cubed" }
                return "to the power \(argument), end power"
            }
            if character.isASCII, character.isNumber || character == "." {
                var number = String(character)
                while position < characters.count, characters[position].isASCII,
                      characters[position].isNumber || characters[position] == "." {
                    number.append(characters[position]); position += 1
                }
                guard Double(number) != nil else { return nil }
                return number
            }
            if character.isASCII, character.isLetter { return String(character) }
            return ["+": "plus", "-": "minus", "=": "equals", "<": "less than", ">": "greater than",
                    "(": "open parenthesis", ")": "close parenthesis", "[": "open bracket", "]": "close bracket",
                    ",": "comma", "!": "factorial", "/": "divided by", "*": "times", "|": "vertical bar"][character]
        }
    }
}
