import XCTest
@testable import GraphiteCore

/// The owner's field's words are said the way engineers say them, with plain respellings every
/// voice reads, and the highlight stays on the word as written.
final class ReadAloudPronunciationTests: XCTestCase {
    private let pronunciations = ReadAloudPronunciations.standard

    private func spoken(_ text: String) throws -> String {
        try XCTUnwrap(ReadAloudDocument.markdown(text).passages.first).text
    }

    func testTheMostFrequentTermsOfTheOwnersNotes() throws {
        let expected: [String: String] = [
            "DRAM": "dee ram", "CMOS": "see moss", "VHDL": "V H D L", "FPGA": "F P G A", "IEEE": "I triple E",
            "MOSFET": "moss fet", "NMOS": "en moss", "PMOS": "pee moss", "nMOS": "en moss", "pMOS": "pee moss",
            "NAND": "nand", "CPU": "C P U", "SRAM": "ess ram", "PIM": "pim", "VDD": "V D D", "RISC-V": "risk five",
            "SoC": "S O C", "DDR": "D D R", "LUT": "look-up table", "FinFET": "fin fet", "x86": "x eighty-six",
            "RowHammer": "row hammer", "SystemVerilog": "system verilog", "XOR": "ex-or", "GND": "ground"
        ]
        for (term, say) in expected { XCTAssertEqual(pronunciations.pronunciation(of: term)?.say, say, term) }
        XCTAssertGreaterThanOrEqual(pronunciations.terms.count, 200)
    }

    func testPluralsPossessivesNumbersAndTheRuleForUnknownCapitals() throws {
        XCTAssertEqual(pronunciations.pronunciation(of: "GPUs")?.say, "G P U's")
        XCTAssertEqual(pronunciations.pronunciation(of: "LUTs")?.say, "look-up tables")
        XCTAssertEqual(pronunciations.pronunciation(of: "FPGAs")?.say, "F P G A's")
        XCTAssertEqual(pronunciations.pronunciation(of: "DDR4")?.say, "D D R 4")
        XCTAssertEqual(pronunciations.pronunciation(of: "NAND2")?.say, "nand 2")
        XCTAssertEqual(pronunciations.pronunciation(of: "L2")?.say, "L 2")
        XCTAssertEqual(pronunciations.pronunciation(of: "PLL")?.say, "P L L", "No vowel: spelled by rule.")
        XCTAssertNil(pronunciations.pronunciation(of: "AND"), "Ordinary capitalized words are the voice's call.")
        XCTAssertNil(pronunciations.pronunciation(of: "FIGURE"))
        XCTAssertEqual(try spoken("The CMOS's inputs and two DFFs."), "The see moss’s inputs and two D flip-flops.")
    }

    func testFlipFlopIsExpandedOnlyNearCircuitWords() throws {
        XCTAssertEqual(try spoken("Each FF samples on the clock edge."), "Each flip-flop samples on the clock edge.")
        XCTAssertEqual(try spoken("Press FF to skip ahead."), "Press F F to skip ahead.")
        XCTAssertTrue(pronunciations.terms["LUT"]?.isExpansion ?? false)
        XCTAssertFalse(pronunciations.terms["CMOS"]?.isExpansion ?? true)
    }

    func testNumbersWithUnitsSubscriptsAndSymbols() throws {
        XCTAssertEqual(try spoken("A 10 nm node at 1.2 V draws 5 mA and 2 fF, 1 ps per gate."),
                       "A 10 nanometers node at 1.2 volts draws 5 milliamps and 2 femtofarads, 1 picosecond per gate.")
        XCTAssertEqual(try spoken("It runs at 3GHz with 1.2 kΩ and 0.5 µm wires."),
                       "It runs at 3 gigahertz with 1.2 kilohms and 0.5 micrometers wires.")
        XCTAssertEqual(try spoken("Raise V_DD above V_{th} and keep t_pd low; m_axi stays."),
                       "Raise V D D above V threshold and keep t P D low; m_axi stays.")
        XCTAssertEqual(try spoken("Delay ≈ 2× the FO4 → faster."), "Delay  approximately  2 times  the fan-out of 4  to  faster.")
        XCTAssertEqual(try spoken("Inverter · NAND gate"), "Inverter ,  nand gate")
        XCTAssertEqual(try spoken("Use $V_{DD}$ and $V_{th}$ here."), "Use V D D and V threshold here.")
    }

    /// Plain respelling is the default; IPA is handed over only when turned on for a voice
    /// verified to honor it (none yet: the owner's Enhanced voice mangled it).
    func testRespellingIsTheDefaultAndIPAIsOptIn() throws {
        let passage = try XCTUnwrap(ReadAloudDocument.markdown("The SIMD unit.").passages.first)
        XCTAssertEqual(passage.text, "The sim dee unit.")
        XCTAssertNil(passage.spans.first { span in span.writtenText == "SIMD" }?.phoneticNotation)
        var withIPA = ReadAloudPronunciations(terms: ["SIMD": .init(say: "sim dee", ipa: "ˈsɪmdiː")])
        withIPA.usesPhoneticNotation = true
        XCTAssertEqual(withIPA.replacements(in: "SIMD").first?.phoneticNotation, "ˈsɪmdiː")
    }

    func testHighlightStaysOnTheWrittenWordAfterRespelling() throws {
        let source = "The CMOS gate at 10 nm with V_DD and LUTs."
        let document = try ReadAloudDocument.markdown(source)
        let passage = try XCTUnwrap(document.passages.first)
        for (said, written) in [("see moss", "CMOS"), ("nanometers", "nm"), ("V D D", "V_DD"), ("look-up tables", "LUTs")] {
            let range = (passage.text as NSString).range(of: said)
            XCTAssertNotEqual(range.location, NSNotFound, said)
            XCTAssertEqual((source as NSString).substring(with: try XCTUnwrap(passage.sourceRange(for: range))), written)
        }
        let tokens = ReadAloudSourceToken.tokens(in: document).map(\.text)
        XCTAssertTrue(tokens.contains("CMOS") && tokens.contains("LUTs"), "\(tokens)")
        let page = try ReadAloudDocument.pageText("The ALU and the FPGA\nuse RISC-V at 3 GHz.")
        XCTAssertEqual(page.passages.first?.text, "The A L U and the F P G A use risk five at 3 gigahertz.")
    }

    func testVaultFileAddsAndReplacesTermsAndIgnoresMalformedFiles() throws {
        let file = Data(#"{"SIMDRAM": "simdram", "HBM": {"say": "H B M"}, "": "x", "Bad": 3}"#.utf8)
        let merged = ReadAloudPronunciations.standard.merging(vaultFile: file)
        XCTAssertEqual(merged.pronunciation(of: "SIMDRAM")?.say, "simdram")
        XCTAssertEqual(merged.pronunciation(of: "HBM")?.say, "H B M")
        XCTAssertEqual(ReadAloudPronunciations.standard.merging(vaultFile: Data("not json".utf8)), .standard)
        let written = try ReadAloudPronunciations.vaultFileData(for: [
            .init(term: "LUT", pronunciation: .init(say: "L U T")), .init(term: "", pronunciation: .init(say: "x"))
        ])
        XCTAssertEqual(ReadAloudPronunciations.vaultEntries(in: written).map(\.term), ["LUT"])
    }
}
