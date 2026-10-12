import XCTest
@testable import GraphiteCore

/// Acronyms and technical terms are said the way people in computing and VLSI say them, and
/// the highlight still lands on the word as written.
final class ReadAloudPronunciationTests: XCTestCase {
    func testDictionaryRulesAndPlurals() {
        let pronunciations = ReadAloudPronunciations.standard
        XCTAssertEqual(pronunciations.pronunciation(of: "RAM"), .init(say: "ram", ipa: "ɹæm"))
        XCTAssertEqual(pronunciations.pronunciation(of: "SIMDRAM")?.say, "sim dee ram")
        XCTAssertEqual(pronunciations.pronunciation(of: "CMOS")?.say, "see moss")
        XCTAssertEqual(pronunciations.pronunciation(of: "nMOS")?.say, "en moss")
        XCTAssertEqual(pronunciations.pronunciation(of: "CPU")?.say, "C P U")
        XCTAssertEqual(pronunciations.pronunciation(of: "GPUs")?.say, "G P U's")
        XCTAssertEqual(pronunciations.pronunciation(of: "ASICs")?.say, "ay sicks")
        XCTAssertEqual(pronunciations.pronunciation(of: "ASICs")?.ipa, "ˈeɪsɪkz")
        // Unknown all-caps words without a vowel are spelled; others are left to the voice.
        XCTAssertEqual(pronunciations.pronunciation(of: "LSB")?.say, "L S B")
        XCTAssertNil(pronunciations.pronunciation(of: "AND"))
        XCTAssertNil(pronunciations.pronunciation(of: "NOTE"))
    }

    func testVaultFileAddsAndReplacesTermsAndIgnoresMalformedFiles() throws {
        let file = Data(#"{"SIMDRAM": "simdram", "HBM": {"say": "H B M"}, "": "x", "Bad": 3}"#.utf8)
        let merged = ReadAloudPronunciations.standard.merging(vaultFile: file)
        XCTAssertEqual(merged.pronunciation(of: "SIMDRAM"), .init(say: "simdram"))
        XCTAssertEqual(merged.pronunciation(of: "HBM")?.say, "H B M")
        XCTAssertEqual(ReadAloudPronunciations.standard.merging(vaultFile: Data("not json".utf8)), .standard)
    }

    func testRespelledTermsCarryIPAAndHighlightTheWrittenWord() throws {
        let source = "SIMD and MIMD machines use SRAM, DRAM and GPUs."
        let document = try ReadAloudDocument.markdown(source)
        let passage = try XCTUnwrap(document.passages.first)
        XCTAssertEqual(passage.text, "sim dee and mim dee machines use ess ram, dee ram and G P U's.")
        let spoken = (passage.text as NSString).range(of: "mim dee")
        XCTAssertEqual((source as NSString).substring(with: try XCTUnwrap(passage.sourceRange(for: spoken))), "MIMD")
        XCTAssertEqual(passage.spans.first { span in span.writtenText == "SIMD" }?.phoneticNotation, "ˈsɪmdiː")
        XCTAssertNil(passage.spans.first { span in span.writtenText == "GPUs" }?.phoneticNotation, "Spelled letters need no IPA.")
        // The rendered note still finds its written words.
        XCTAssertTrue(ReadAloudSourceToken.tokens(in: document).map(\.text).contains("MIMD"))
        let page = try ReadAloudDocument.pageText("The ALU and the FPGA\nuse RISC.")
        XCTAssertEqual(page.passages.first?.text, "The A L U and the F P G A use risk.")
    }
}
