import XCTest
@testable import GraphiteCore

/// Which spelling and which occurrence of a link's parameter `VaultURI` reads.
final class VaultURIParameterPrecedenceTests: XCTestCase {
    private func uri(_ text: String) throws -> VaultURI? {
        VaultURI(url: try XCTUnwrap(URL(string: text)))
    }

    func testTheFirstOccurrenceOfAParameterWinsForGraphitesOwnActions() throws {
        XCTAssertEqual(try uri("graphite://open?vault=First&vault=Second&file=One&file=Two"),
                       VaultURI(vault: "First", action: .open(file: "One", path: nil)))
        XCTAssertEqual(try uri("graphite://search?query=first&query=second"), VaultURI(vault: nil, action: .search(query: "first")))
    }

    func testParameterNamesAreMatchedInLowercaseSoALaterCapitalisedRepeatDoesNotReplaceTheFirst() throws {
        XCTAssertEqual(try uri("graphite://open?file=One&FILE=Two"), VaultURI(vault: nil, action: .open(file: "One", path: nil)))
        XCTAssertEqual(try uri("graphite://open?File=One&file=Two"), VaultURI(vault: nil, action: .open(file: "One", path: nil)))
    }

    func testAnEmptyFirstOccurrenceStillWinsAndReadsAsMissing() throws {
        XCTAssertEqual(try uri("graphite://open?file=&file=Later"), VaultURI(vault: nil, action: .open(file: nil, path: nil)))
        XCTAssertNil(try uri("graphite://read?file=&file=Later"), "Reading needs a file, and the empty first one is the file.")
    }

    func testAPluginActionKeepsEachSpellingOfARepeatedNameAsItsOwnParameterAndTheFirstOfEachExactSpelling() throws {
        XCTAssertEqual(try uri("obsidian://advanced-uri?Key=1&key=2&Key=3"),
                       VaultURI(vault: nil, action: .plugin(action: "advanced-uri", parameters: ["Key": "1", "key": "2"])))
    }

    func testTheVaultOfAPluginActionIsReadFromTheLowercasedNameFirstOccurrence() throws {
        XCTAssertEqual(try uri("obsidian://advanced-uri?Vault=First&vault=Second"),
                       VaultURI(vault: "First", action: .plugin(action: "advanced-uri", parameters: ["Vault": "First", "vault": "Second"])))
    }

    func testTheActionNameInThePathOfALinkWithoutAHostIsTrimmedOfSlashesAndLowercased() throws {
        XCTAssertEqual(try uri("obsidian:/Open/?vault=V&file=N"), VaultURI(vault: "V", action: .open(file: "N", path: nil)))
    }
}
