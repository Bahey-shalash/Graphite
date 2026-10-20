import Foundation

/// How the technical words of a lecture note are said. A voice guesses at all-caps words, unit
/// symbols and subscripts: it may spell RAM as "R A M", say CMOS as one odd syllable, or read
/// "10 nm" as "ten N M". Graphite replaces each with plain words the voice reads correctly:
/// "see moss", "ten nanometers", "V D D". Plain words work with every voice, including the
/// owner's Enhanced voice, where an IPA transcription was ignored or mangled; IPA is only handed
/// to a voice when `usesPhoneticNotation` is turned on for one verified to honor it. The
/// highlight always stays on the written word.
public struct ReadAloudPronunciations: Equatable, Sendable {
    public struct Pronunciation: Equatable, Sendable, Codable {
        /// Plain text the voice reads: "sim dee", letters apart ("C P U"), or words ("look-up table").
        public let say: String
        /// International Phonetic Alphabet, for voices verified to honor it.
        public let ipa: String?
        /// Said as what it stands for ("look-up table" for LUT) rather than as letters or a word;
        /// listed in Settings so the person can choose otherwise.
        public let isExpansion: Bool
        /// Words of which at least one must be near the term for it to be replaced: FF is a
        /// flip-flop next to "clock" or "register", not in other text. Empty means always.
        public let contextWords: [String]

        public init(say: String, ipa: String? = nil, isExpansion: Bool = false, contextWords: [String] = []) {
            self.say = say
            self.ipa = ipa
            self.isExpansion = isExpansion
            self.contextWords = contextWords
        }

        /// Letters said one by one; a plural adds "'s" rather than "s" ("G P U's").
        public var isSpelled: Bool { say.split(separator: " ").allSatisfy { letter in letter.count == 1 } }

        func plural() -> Pronunciation {
            Pronunciation(say: say + (isSpelled ? "'s" : "s"), ipa: ipa.map { ipa in ipa + "z" },
                          isExpansion: isExpansion, contextWords: contextWords)
        }
    }

    public private(set) var terms: [String: Pronunciation]
    /// Off by default: no voice has been verified to honor IPA, so plain respelling is used.
    public var usesPhoneticNotation = false

    public init(terms: [String: Pronunciation]) {
        self.terms = terms
    }

    /// The vault's file of extra or replaced pronunciations, relative to the vault folder.
    public static let vaultFilePath = ".graphite/pronunciations.json"
    /// A pronunciation file is a short list of terms; anything larger is ignored.
    public static let maximumFileBytes = 256 * 1_024

    /// Adds the vault's own terms over the built-in ones. Each entry is either a respelling,
    /// `"SIMDRAM": "sim dee ram"`, or `"SIMDRAM": {"say": "sim dee ram", "ipa": "ˈsɪmdiːɹæm"}`.
    /// A malformed file changes nothing.
    public func merging(vaultFile data: Data) -> ReadAloudPronunciations {
        var merged = self
        for entry in Self.vaultEntries(in: data) { merged.terms[entry.term] = entry.pronunciation }
        return merged
    }

    /// The most terms of a vault file that speech lookup and the Settings list use.
    public static let maximumVaultTerms = 2_000

    /// One term of a vault file with how it is said.
    public struct VaultEntry: Equatable, Sendable {
        public let term: String
        public let pronunciation: Pronunciation

        public init(term: String, pronunciation: Pronunciation) {
            self.term = term
            self.pronunciation = pronunciation
        }
    }

    /// Why a vault file that exists cannot be used.
    public enum VaultFileProblem: Equatable, Sendable {
        /// The bytes are not JSON, for example a file cut off before its closing brace.
        case notJSON
        /// The JSON is not an object of terms.
        case notAnObjectOfTerms
        /// The file is larger than `maximumFileBytes`.
        case overSizeLimit(byteCount: Int)
    }

    /// What reading the vault's pronunciation file found. Only `noFile` and a complete `loaded`
    /// leave the Settings editor knowing everything the file holds, so only they allow writing it.
    public enum VaultFileReading: Equatable, Sendable {
        /// There is no file yet; writing creates it.
        case noFile
        /// The file exists but its bytes could not be read, for example a cloud file that is not downloaded.
        case readFailed(errorDomain: String, errorCode: Int)
        case invalid(VaultFileProblem)
        /// `entries` are the usable terms (at most `maximumVaultTerms`); `termsInFile` is how many the file holds.
        case loaded(entries: [VaultEntry], termsInFile: Int)

        /// Writing a list built from this reading replaces the file without losing a term of it.
        public var allowsRewriting: Bool {
            switch self {
            case .noFile: true
            case .loaded(let entries, let termsInFile): entries.count == termsInFile
            case .readFailed, .invalid: false
            }
        }
    }

    /// Reads the vault file at `location` and tells apart a missing file, a failed read, a file
    /// that cannot be used and a (possibly partial) load. A failure is never an empty list.
    public static func readVaultFile(at location: URL) -> VaultFileReading {
        let data: Data
        do {
            data = try Data(contentsOf: location)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return .noFile
        } catch {
            let nsError = error as NSError
            return .readFailed(errorDomain: nsError.domain, errorCode: nsError.code)
        }
        return readVaultFile(data: data)
    }

    /// The same as `readVaultFile(at:)` for bytes already read.
    public static func readVaultFile(data: Data) -> VaultFileReading {
        guard data.count <= maximumFileBytes else { return .invalid(.overSizeLimit(byteCount: data.count)) }
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            return .invalid(.notJSON)
        }
        guard let object = json as? [String: Any] else { return .invalid(.notAnObjectOfTerms) }
        return .loaded(entries: usableEntries(of: object), termsInFile: object.count)
    }

    /// The entries of a vault file, sorted by term, for speech lookup. A file that cannot be used
    /// adds nothing; use `readVaultFile` where the reason matters.
    public static func vaultEntries(in data: Data) -> [(term: String, pronunciation: Pronunciation)] {
        guard case .loaded(let entries, _) = readVaultFile(data: data) else { return [] }
        return entries.map { entry in (entry.term, entry.pronunciation) }
    }

    private static func usableEntries(of object: [String: Any]) -> [VaultEntry] {
        var result: [VaultEntry] = []
        for (term, entry) in object.sorted(by: { first, second in first.key < second.key }).prefix(maximumVaultTerms) {
            let trimmedTerm = term.trimmingCharacters(in: .whitespaces)
            guard !trimmedTerm.isEmpty, trimmedTerm.count <= 64 else { continue }
            if let say = entry as? String, !say.isEmpty, say.count <= 200 {
                result.append(VaultEntry(term: trimmedTerm, pronunciation: Pronunciation(say: say)))
            } else if let fields = entry as? [String: Any], let say = fields["say"] as? String, !say.isEmpty, say.count <= 200 {
                let ipa = (fields["ipa"] as? String).flatMap { ipa in ipa.isEmpty || ipa.count > 200 ? nil : ipa }
                result.append(VaultEntry(term: trimmedTerm, pronunciation: Pronunciation(say: say, ipa: ipa)))
            }
        }
        return result.sorted { first, second in first.term.localizedStandardCompare(second.term) == .orderedAscending }
    }

    /// The JSON a vault file holds for these entries, sorted, readable in any text editor. An entry
    /// with hand-written `ipa` is written in the object form, the others as a plain respelling.
    public static func vaultFileData(for entries: [VaultEntry]) throws -> Data {
        var object: [String: Any] = [:]
        for entry in entries {
            let term = entry.term.trimmingCharacters(in: .whitespaces)
            let say = entry.pronunciation.say.trimmingCharacters(in: .whitespaces)
            guard !term.isEmpty, !say.isEmpty else { continue }
            if let ipa = entry.pronunciation.ipa {
                object[term] = ["say": say, "ipa": ipa]
            } else {
                object[term] = say
            }
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// `entries` after the person saves `term` said as `say`, in place of `originalTerm` (nil for
    /// a new term). Every other entry is returned as it was. The edited entry keeps its `ipa` while
    /// its term stays the same; a renamed term starts without the old term's `ipa`.
    public static func updatingVaultEntries(
        _ entries: [VaultEntry], replacing originalTerm: String?, with term: String, say: String
    ) -> [VaultEntry] {
        let newTerm = term.trimmingCharacters(in: .whitespaces)
        let replacedTerm = originalTerm ?? newTerm
        let keptPhoneticNotation = entries.first { entry in entry.term == newTerm && entry.term == replacedTerm }?.pronunciation.ipa
        var updated = entries.filter { entry in entry.term != replacedTerm && entry.term != newTerm }
        updated.append(VaultEntry(term: newTerm, pronunciation: Pronunciation(say: say.trimmingCharacters(in: .whitespaces), ipa: keptPhoneticNotation)))
        return updated
    }

    /// One change the person makes to the vault's terms in Settings.
    public enum VaultFileEdit: Equatable, Sendable {
        /// `term` said as `say`, in place of `originalTerm` (nil for a new term).
        case saving(term: String, say: String, replacing: String?)
        /// These terms are taken out.
        case removing(terms: Set<String>)
    }

    /// The entries to write once `edit` is made to the file as `reading` found it, or nil when
    /// the file holds something a rewrite would lose. Every entry the edit does not name is kept.
    public static func vaultEntries(applying edit: VaultFileEdit, to reading: VaultFileReading) -> [VaultEntry]? {
        guard reading.allowsRewriting else { return nil }
        let currentEntries: [VaultEntry] = if case .loaded(let entries, _) = reading { entries } else { [] }
        switch edit {
        case .saving(let term, let say, let originalTerm):
            return updatingVaultEntries(currentEntries, replacing: originalTerm, with: term, say: say)
        case .removing(let terms):
            return currentEntries.filter { entry in !terms.contains(entry.term) }
        }
    }

    // MARK: Words

    /// What to say for a word as written, or nil to leave it to the voice. Looks up the word,
    /// then its singular ("GPUs"), then a letters-and-number form ("DDR4", "NAND2"). An unknown
    /// all-caps word without a vowel ("PLL", "JSSC") is spelled; one with a vowel is the voice's
    /// call, so AND, NOTE or FIGURE are not spelled out.
    public func pronunciation(of word: String, context: String = "") -> Pronunciation? {
        if let known = applicable(terms[word], context: context) { return known }
        let characters = Array(word)
        let isPlural = characters.count > 2 && characters.last == "s"
            && (characters[characters.count - 2].isUppercase || characters[characters.count - 2].isNumber)
        if isPlural, let singular = pronunciation(of: String(word.dropLast()), context: context) { return singular.plural() }
        let length = (word as NSString).length
        if let match = Self.lettersAndNumber?.firstMatch(in: word, range: NSRange(location: 0, length: length)) {
            let letters = (word as NSString).substring(with: match.range(at: 1))
            let number = (word as NSString).substring(with: match.range(at: 2))
            let lettersSaid = pronunciation(of: letters, context: context)?.say ?? letters
            return Pronunciation(say: lettersSaid + " " + number)
        }
        guard characters.count >= 2, characters.allSatisfy({ character in character.isUppercase && character.isLetter }),
              !characters.contains(where: { character in "AEIOU".contains(character) }) else { return nil }
        return Pronunciation(say: characters.map(String.init).joined(separator: " "))
    }

    private func applicable(_ pronunciation: Pronunciation?, context: String) -> Pronunciation? {
        guard let pronunciation else { return nil }
        guard !pronunciation.contextWords.isEmpty else { return pronunciation }
        let lowercasedContext = context.lowercased()
        return pronunciation.contextWords.contains { word in lowercasedContext.contains(word) } ? pronunciation : nil
    }

    /// "DDR4", "NAND2", "L2", "FO4": capitals followed by a number.
    private static let lettersAndNumber = try? NSRegularExpression(pattern: #"^([A-Z]{1,8})([0-9]{1,3})$"#)

    // MARK: Replacements

    /// One stretch of written text and what is said for it.
    public struct Replacement: Equatable, Sendable {
        public let range: NSRange
        public let speech: String
        public let phoneticNotation: String?
    }

    /// Everything in `text` said differently from how it is written: a number with its unit, a
    /// subscript written in prose, technical words, and symbols. Ranges are UTF-16 offsets.
    public func replacements(in text: String) -> [Replacement] {
        let source = text as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        var found: [Replacement] = []
        func add(_ range: NSRange, _ speech: String, phonetic: String? = nil) {
            guard !found.contains(where: { existing in NSIntersectionRange(existing.range, range).length > 0 }) else { return }
            found.append(Replacement(range: range, speech: speech, phoneticNotation: usesPhoneticNotation ? phonetic : nil))
        }
        // Units first, so "5 mA" is milliamps rather than a word "mA".
        for match in Self.numberWithUnit?.matches(in: text, range: fullRange) ?? [] {
            let number = source.substring(with: match.range(at: 1))
            let unitRange = match.range(at: 3)
            guard let unit = Self.units[source.substring(with: unitRange)] else { continue }
            let spacing = match.range(at: 2).length == 0 ? " " : ""
            add(unitRange, spacing + (number == "1" ? unit.singular : unit.plural))
        }
        for match in Self.proseSubscript?.matches(in: text, range: fullRange) ?? [] {
            let base = source.substring(with: match.range(at: 1))
            let subscriptRange = match.range(at: 2).location != NSNotFound ? match.range(at: 2) : match.range(at: 3)
            let subscriptText = source.substring(with: subscriptRange)
            // A lowercase base needs a known subscript: m_axi is a name, not a quantity.
            guard base.first?.isUppercase == true || Self.subscriptWords[subscriptText] != nil,
                  let said = Self.subscriptSpeech(subscriptText) else { continue }
            add(match.range, base + " " + said)
        }
        for match in Self.word?.matches(in: text, range: fullRange) ?? [] {
            let word = source.substring(with: match.range)
            let contextStart = max(0, match.range.location - 80)
            let contextRange = NSRange(location: contextStart, length: min(source.length, NSMaxRange(match.range) + 80) - contextStart)
            guard let pronunciation = pronunciation(of: word, context: source.substring(with: contextRange)),
                  pronunciation.say != word else { continue }
            add(match.range, pronunciation.say, phonetic: pronunciation.ipa)
        }
        for match in Self.symbol?.matches(in: text, range: fullRange) ?? [] {
            let before = match.range.location == 0 || Self.isSpace(source.character(at: match.range.location - 1))
            let after = NSMaxRange(match.range) >= source.length || Self.isSpace(source.character(at: NSMaxRange(match.range)))
            guard let said = Self.symbolSpeech(source.substring(with: match.range), isSurroundedBySpace: before && after) else { continue }
            add(match.range, said)
        }
        return found.sorted { first, second in first.range.location < second.range.location }
    }

    /// Words, including "RISC-V", "x86-64", "SoC", "nMOS" and "DDR4".
    private static let word = try? NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_])(?:RISC-V|x86(?:-64)?|[A-Za-z][A-Za-z0-9]*)(?![\p{L}\p{N}_])"#)

    private static func isSpace(_ unit: unichar) -> Bool { unit == 32 || unit == 9 || unit == 10 || unit == 160 }

    // MARK: Units

    struct UnitName: Sendable {
        let singular: String
        let plural: String
    }

    private static func unit(_ singular: String, _ plural: String? = nil) -> UnitName {
        UnitName(singular: singular, plural: plural ?? singular + "s")
    }

    /// A unit symbol after a number. Only after a number: "A" alone is a letter, "5 A" amps.
    static let units: [String: UnitName] = [
        "nm": unit("nanometer"), "µm": unit("micrometer"), "μm": unit("micrometer"), "um": unit("micrometer"),
        "mm": unit("millimeter"), "cm": unit("centimeter"), "km": unit("kilometer"), "pm": unit("picometer"),
        "V": unit("volt"), "mV": unit("millivolt"), "kV": unit("kilovolt"), "µV": unit("microvolt"), "μV": unit("microvolt"),
        "fF": unit("femtofarad"), "pF": unit("picofarad"), "nF": unit("nanofarad"), "µF": unit("microfarad"),
        "μF": unit("microfarad"), "aF": unit("attofarad"), "F": unit("farad"),
        "THz": unit("terahertz", "terahertz"), "GHz": unit("gigahertz", "gigahertz"), "MHz": unit("megahertz", "megahertz"),
        "kHz": unit("kilohertz", "kilohertz"), "Hz": unit("hertz", "hertz"),
        "fs": unit("femtosecond"), "ps": unit("picosecond"), "ns": unit("nanosecond"), "µs": unit("microsecond"),
        "μs": unit("microsecond"), "us": unit("microsecond"), "ms": unit("millisecond"), "s": unit("second"),
        "Ω": unit("ohm"), "kΩ": unit("kilohm"), "MΩ": unit("megohm"), "GΩ": unit("gigohm"),
        "A": unit("amp"), "mA": unit("milliamp"), "µA": unit("microamp"), "μA": unit("microamp"), "nA": unit("nanoamp"), "pA": unit("picoamp"),
        "W": unit("watt"), "mW": unit("milliwatt"), "µW": unit("microwatt"), "μW": unit("microwatt"), "nW": unit("nanowatt"), "kW": unit("kilowatt"),
        "J": unit("joule"), "pJ": unit("picojoule"), "fJ": unit("femtojoule"), "nJ": unit("nanojoule"), "µJ": unit("microjoule"), "aJ": unit("attojoule"),
        "eV": unit("electron volt"), "meV": unit("millielectron volt"),
        "K": unit("kelvin", "kelvin"), "°C": unit("degree Celsius", "degrees Celsius"), "dB": unit("decibel"),
        "dBm": UnitName(singular: "D B M", plural: "D B M"),
        "bit": unit("bit"), "bits": unit("bit"), "B": unit("byte"),
        "kb": unit("kilobit"), "Kb": unit("kilobit"), "Mb": unit("megabit"), "Gb": unit("gigabit"),
        "kB": unit("kilobyte"), "KB": unit("kilobyte"), "MB": unit("megabyte"), "GB": unit("gigabyte"), "TB": unit("terabyte"),
        "KiB": unit("kibibyte"), "MiB": unit("mebibyte"), "GiB": unit("gibibyte"),
        "Gb/s": unit("gigabit per second", "gigabits per second"), "GB/s": unit("gigabyte per second", "gigabytes per second"),
        "MB/s": unit("megabyte per second", "megabytes per second"),
        "mm²": unit("square millimeter"), "µm²": unit("square micrometer"), "μm²": unit("square micrometer"), "nm²": unit("square nanometer")
    ]

    private static let numberWithUnit: NSRegularExpression? = {
        let symbols = units.keys.sorted { first, second in first.count > second.count }
            .map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        return try? NSRegularExpression(pattern: #"(?<![\p{L}\p{N}.])([0-9]+(?:[.,][0-9]+)?)(\s?)("# + symbols + #")(?![\p{L}\p{N}])"#)
    }()

    // MARK: Subscripts

    /// "V_DD", "V_{th}", "t_pd", "I_D" in prose, outside $…$.
    private static let proseSubscript = try? NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_\\])([A-Za-z])_(?:\{([A-Za-z0-9]{1,5})\}|([A-Za-z0-9]{1,5}))(?![\p{L}\p{N}_])"#)

    /// Subscripts said as words; other subscripts of capitals, or of up to two lowercase letters,
    /// are spelled ("D D", "G S", "p d"), and digits are said as numbers.
    static let subscriptWords: [String: String] = [
        "th": "threshold", "TH": "threshold", "T": "T", "t": "T", "sat": "saturation", "eff": "effective", "ox": "ox",
        "in": "in", "out": "out", "max": "max", "min": "min", "dd": "D D", "ss": "S S", "on": "on", "off": "off",
        "ref": "ref", "load": "load", "tot": "total", "clk": "clock", "leak": "leakage", "pd": "P D", "cd": "C D",
        "pHL": "P H L", "pLH": "P L H", "m": "m", "mb": "M B", "ds": "D S", "gs": "G S"
    ]

    /// How a subscript is said, or nil to leave the text alone.
    static func subscriptSpeech(_ subscriptText: String) -> String? {
        if let word = subscriptWords[subscriptText] { return word }
        if subscriptText.allSatisfy(\.isNumber) { return subscriptText }
        if subscriptText.allSatisfy({ character in character.isUppercase || character.isNumber }) {
            return subscriptText.map(String.init).joined(separator: " ")
        }
        if subscriptText.count <= 2, subscriptText.allSatisfy(\.isLetter) {
            return subscriptText.map(String.init).joined(separator: " ")
        }
        return nil
    }

    /// The speech for a lone subscripted symbol written as an equation, such as $V_{DD}$ or
    /// $V_{th}$, as an engineer says it ("V D D", "V threshold"); nil for anything else, which
    /// the math interpreter reads.
    public static func singleSubscriptedSymbol(_ expression: String) -> String? {
        let trimmed = expression.trimmingCharacters(in: .whitespaces)
        let source = trimmed as NSString
        guard let match = singleSymbol?.firstMatch(in: trimmed, range: NSRange(location: 0, length: source.length)) else { return nil }
        let base = source.substring(with: match.range(at: 1))
        let subscriptRange = match.range(at: 2).location != NSNotFound ? match.range(at: 2) : match.range(at: 3)
        let subscriptText = source.substring(with: subscriptRange)
        guard subscriptText.contains(where: \.isLetter), let said = subscriptSpeech(subscriptText) else { return nil }
        return base + " " + said
    }

    private static let singleSymbol = try? NSRegularExpression(pattern: #"^([A-Za-z])_(?:\{(?:\\(?:mathrm|text|rm)\{)?([A-Za-z0-9]{1,5})\}?\}|([A-Za-z0-9]))$"#)

    // MARK: Symbols

    private static let symbol = try? NSRegularExpression(pattern: #"[→←⇒⇐↔≈≤≥≠×±∝∞·√Δ∆]"#)

    static func symbolSpeech(_ symbol: String, isSurroundedBySpace: Bool) -> String? {
        switch symbol {
        case "→": " to "
        case "←": " gets "
        case "⇒": " implies "
        case "⇐": " is implied by "
        case "↔": " corresponds to "
        case "≈": " approximately "
        case "≤": " less than or equal to "
        case "≥": " greater than or equal to "
        case "≠": " not equal to "
        case "×": " times "
        case "±": " plus or minus "
        case "∝": " proportional to "
        case "∞": " infinity "
        case "√": " square root of "
        case "Δ", "∆": " delta "
        // A middle dot between the items of a list is a pause; between symbols it multiplies.
        case "·": isSurroundedBySpace ? ", " : " times "
        default: nil
        }
    }
}
