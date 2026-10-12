import Foundation

/// How acronyms and technical terms are said. A voice guesses at all-caps words: it spells
/// RAM as "R A M" or says CPU as one syllable. A built-in dictionary for computing and
/// electrical engineering terms gives each a respelling the voice reads correctly, and an
/// IPA transcription for voices that accept one; the vault can add or replace terms.
public struct ReadAloudPronunciations: Equatable, Sendable {
    public struct Pronunciation: Equatable, Sendable, Codable {
        /// Plain text the voice reads: "sim dee", or letters apart, "C P U".
        public let say: String
        /// International Phonetic Alphabet, used by voices that support it; nil to spell.
        public let ipa: String?
        /// Letters said one by one; a plural adds "'s" rather than "s" ("G P U's").
        public var isSpelled: Bool { ipa == nil && say.split(separator: " ").allSatisfy { letter in letter.count == 1 } }

        public init(say: String, ipa: String? = nil) {
            self.say = say
            self.ipa = ipa
        }
    }

    public private(set) var terms: [String: Pronunciation]

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
        guard data.count <= Self.maximumFileBytes,
              let entries = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return self }
        var merged = self
        for (term, entry) in entries.prefix(2_000) {
            let trimmedTerm = term.trimmingCharacters(in: .whitespaces)
            guard !trimmedTerm.isEmpty, trimmedTerm.count <= 64 else { continue }
            if let say = entry as? String, !say.isEmpty, say.count <= 200 {
                merged.terms[trimmedTerm] = Pronunciation(say: say)
            } else if let fields = entry as? [String: Any], let say = fields["say"] as? String, !say.isEmpty, say.count <= 200 {
                merged.terms[trimmedTerm] = Pronunciation(say: say, ipa: (fields["ipa"] as? String).flatMap { ipa in ipa.isEmpty || ipa.count > 200 ? nil : ipa })
            }
        }
        return merged
    }

    /// What to say for a word as written, or nil to leave it to the voice. Unknown all-caps
    /// words without a vowel ("DDR", "PCB", "FSM") are spelled; others are the voice's call,
    /// so ordinary capitalized words such as AND or NOT are not spelled out.
    public func pronunciation(of word: String) -> Pronunciation? {
        if let known = terms[word] { return known }
        var base = Substring(word)
        let isPlural = word.count > 2 && word.hasSuffix("s") && word.dropLast().last?.isUppercase == true
        if isPlural { base = base.dropLast() }
        let pronunciation: Pronunciation
        if let known = terms[String(base)] {
            pronunciation = known
        } else if base.count >= 2, base.allSatisfy({ character in character.isUppercase && character.isLetter }),
                  !base.contains(where: { character in "AEIOU".contains(character) }) {
            pronunciation = Pronunciation(say: base.map(String.init).joined(separator: " "))
        } else {
            return nil
        }
        guard isPlural else { return pronunciation }
        return Pronunciation(say: pronunciation.say + (pronunciation.isSpelled ? "'s" : "s"),
                             ipa: pronunciation.ipa.map { ipa in ipa + "z" })
    }

    /// Words with at least two capitals (CMOS, SoC, FinFET), nMOS and pMOS, with a plural "s".
    static let candidateWord = try? NSRegularExpression(pattern: #"\b(?:[A-Za-z]*[A-Z][A-Za-z]*[A-Z][A-Za-z]*|[np]MOS)\b"#)

    private static func spelled(_ letters: String) -> Pronunciation {
        Pronunciation(say: letters.map(String.init).joined(separator: " "))
    }

    /// Terms from computer architecture, VLSI and digital design said as words, and the
    /// common ones that are spelled although they contain a vowel.
    public static let standard = ReadAloudPronunciations(terms: [
        "RAM": Pronunciation(say: "ram", ipa: "ɹæm"),
        "ROM": Pronunciation(say: "rom", ipa: "ɹɑm"),
        "SRAM": Pronunciation(say: "ess ram", ipa: "ˈɛsɹæm"),
        "DRAM": Pronunciation(say: "dee ram", ipa: "ˈdiːɹæm"),
        "eDRAM": Pronunciation(say: "ee dee ram", ipa: "ˈiːdiːɹæm"),
        "SIMDRAM": Pronunciation(say: "sim dee ram", ipa: "ˈsɪmdiːɹæm"),
        "SIMD": Pronunciation(say: "sim dee", ipa: "ˈsɪmdiː"),
        "MIMD": Pronunciation(say: "mim dee", ipa: "ˈmɪmdiː"),
        "SISD": Pronunciation(say: "sis dee", ipa: "ˈsɪsdiː"),
        "MISD": Pronunciation(say: "mis dee", ipa: "ˈmɪsdiː"),
        "SIMT": Pronunciation(say: "sim tee", ipa: "ˈsɪmtiː"),
        "NASA": Pronunciation(say: "nassa", ipa: "ˈnæsə"),
        "RISC": Pronunciation(say: "risk", ipa: "ɹɪsk"),
        "CISC": Pronunciation(say: "sisk", ipa: "sɪsk"),
        "ASIC": Pronunciation(say: "ay sick", ipa: "ˈeɪsɪk"),
        "CMOS": Pronunciation(say: "see moss", ipa: "ˈsiːmɑs"),
        "NMOS": Pronunciation(say: "en moss", ipa: "ˈɛnmɑs"),
        "PMOS": Pronunciation(say: "pee moss", ipa: "ˈpiːmɑs"),
        "nMOS": Pronunciation(say: "en moss", ipa: "ˈɛnmɑs"),
        "pMOS": Pronunciation(say: "pee moss", ipa: "ˈpiːmɑs"),
        "MOSFET": Pronunciation(say: "moss fet", ipa: "ˈmɑsfɛt"),
        "FinFET": Pronunciation(say: "fin fet", ipa: "ˈfɪnfɛt"),
        "NAND": Pronunciation(say: "nand", ipa: "nænd"),
        "XOR": Pronunciation(say: "ex or", ipa: "ˈɛksɔɹ"),
        "XNOR": Pronunciation(say: "ex nor", ipa: "ˈɛksnɔɹ"),
        "NOR": Pronunciation(say: "nor", ipa: "nɔɹ"),
        "MAC": Pronunciation(say: "mack", ipa: "mæk"),
        "LUT": Pronunciation(say: "lut", ipa: "lʌt"),
        "CUDA": Pronunciation(say: "cooda", ipa: "ˈkuːdə"),
        "JEDEC": Pronunciation(say: "jedeck", ipa: "ˈdʒɛdɛk"),
        "SPICE": Pronunciation(say: "spice", ipa: "spaɪs"),
        "CPU": spelled("CPU"), "GPU": spelled("GPU"), "TPU": spelled("TPU"), "NPU": spelled("NPU"),
        "ALU": spelled("ALU"), "FPU": spelled("FPU"), "MMU": spelled("MMU"), "MCU": spelled("MCU"),
        "VLSI": spelled("VLSI"), "FPGA": spelled("FPGA"), "SoC": spelled("SOC"), "IC": spelled("IC"),
        "IO": spelled("IO"), "API": spelled("API"), "ISA": spelled("ISA"), "EDA": spelled("EDA"),
        "USB": spelled("USB"), "OS": spelled("OS"), "UI": spelled("UI"), "IoT": spelled("IOT"),
        "ECC": spelled("ECC"), "DMA": spelled("DMA"), "PIM": spelled("PIM"), "PUM": spelled("PUM"),
        "GPGPU": spelled("GPGPU"), "VHDL": spelled("VHDL"), "RTL": spelled("RTL"), "HDL": spelled("HDL"),
        "TLB": spelled("TLB"), "DDR": spelled("DDR"), "PCB": spelled("PCB"), "FSM": spelled("FSM"),
        "PUN": spelled("PUN"), "PDN": spelled("PDN"), "CVSL": spelled("CVSL"), "CPL": spelled("CPL"),
        "DPL": spelled("DPL"), "SSD": spelled("SSD"), "HDD": spelled("HDD"), "BJT": spelled("BJT"),
        "EPFL": spelled("EPFL"), "ETH": spelled("ETH")
    ])
}
