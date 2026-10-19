import XCTest
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

/// How the places where Read Aloud stopped are kept on the device: the two keys, the key of
/// each place, and the 300 places kept.
@MainActor
final class ReadAloudNavigatorPlaceKeysTests: XCTestCase {
    private let vaultIdentifier = UUID(uuidString: "7F0A3C54-9B1E-4D7C-8E21-5A6B4C3D2E10")!
    private var preferences: UserDefaults!

    override func setUp() async throws {
        preferences = try IsolatedDeviceState.make(prefix: "ReadAloudNavigatorPlaceKeysTests", for: self).preferences
    }

    override func tearDown() async throws {
        preferences = nil
    }

    private func makeNavigator(openVault: UUID?) -> ReadAloudNavigator {
        let session = ReadAloudSession(speech: PenTestSpeech(), preferences: preferences)
        let navigator = ReadAloudNavigator(reader: ReadAloudController(session: session, preferences: preferences), preferences: preferences)
        navigator.vaultIdentifier = { openVault }
        return navigator
    }

    private var storedPositions: [String: Int]? { preferences.dictionary(forKey: "GraphiteReadAloudPositions") as? [String: Int] }
    private var storedOrder: [String]? { preferences.stringArray(forKey: "GraphiteReadAloudPositionsOrder") }

    func testANotePlaceIsKeptUnderTheVaultIdentifierAndThePathWithAUTF16Location() {
        let navigator = makeNavigator(openVault: vaultIdentifier)

        navigator.remember(1_234, for: "Notes/Lecture.md")

        XCTAssertEqual(storedPositions, ["7F0A3C54-9B1E-4D7C-8E21-5A6B4C3D2E10|Notes/Lecture.md": 1_234])
        XCTAssertEqual(storedOrder, ["7F0A3C54-9B1E-4D7C-8E21-5A6B4C3D2E10|Notes/Lecture.md"])
    }

    func testAPDFPlaceIsKeptUnderItsAbsoluteFilePathWithAPageIndexWhicheverVaultIsOpen() {
        let navigator = makeNavigator(openVault: vaultIdentifier)

        navigator.remember(7, for: "/Volumes/Vault/Slides.pdf")

        XCTAssertEqual(storedPositions, ["/Volumes/Vault/Slides.pdf": 7])
        XCTAssertEqual(ReadAloudNavigator.rememberedLocation(for: "/Volumes/Vault/Slides.pdf", preferences: preferences), 7)
    }

    func testWithNoVaultOpenANotePlaceIsKeptUnderItsBarePath() {
        let navigator = makeNavigator(openVault: nil)

        navigator.remember(5, for: "Notes/Lecture.md")

        XCTAssertEqual(storedPositions, ["Notes/Lecture.md": 5])
    }

    func testThePlaceKeyOfANoteNamesItsVaultAndTheKeyOfAPDFIsItsPath() {
        XCTAssertEqual(ReadAloudNavigator.placeKey(forIdentifier: "Notes/A.md", inVault: vaultIdentifier), "7F0A3C54-9B1E-4D7C-8E21-5A6B4C3D2E10|Notes/A.md")
        XCTAssertEqual(ReadAloudNavigator.placeKey(forIdentifier: "/Volumes/Vault/A.pdf", inVault: vaultIdentifier), "/Volumes/Vault/A.pdf")
        XCTAssertEqual(ReadAloudNavigator.placeKey(forIdentifier: "Notes/A.md", inVault: nil), "Notes/A.md")
    }

    func testAPlaceKeptBeforePlacesNamedTheirVaultIsNeverReadAsANotesPlace() {
        preferences.set(["Notes/Lecture.md": 99], forKey: "GraphiteReadAloudPositions")
        let navigator = makeNavigator(openVault: vaultIdentifier)

        XCTAssertNil(navigator.rememberedLocation(for: "Notes/Lecture.md"))
        XCTAssertNil(navigator.rememberedLocation(for: try! VaultPath("Notes/Lecture.md")))
    }

    func testAPlaceKeptBeforePlacesNamedTheirVaultStaysStoredUntilNewerPlacesPushItOut() {
        preferences.set(["Notes/Lecture.md": 99], forKey: "GraphiteReadAloudPositions")
        let navigator = makeNavigator(openVault: vaultIdentifier)

        navigator.remember(4, for: "Notes/Lecture.md")

        XCTAssertEqual(storedPositions, ["Notes/Lecture.md": 99, "7F0A3C54-9B1E-4D7C-8E21-5A6B4C3D2E10|Notes/Lecture.md": 4])
        XCTAssertEqual(storedOrder, ["Notes/Lecture.md", "7F0A3C54-9B1E-4D7C-8E21-5A6B4C3D2E10|Notes/Lecture.md"])
    }

    func testRememberingThreeHundredAndOnePlacesForgetsTheLeastRecentlyKeptOneAndKeepsTheOthersKeysUnchanged() {
        let navigator = makeNavigator(openVault: vaultIdentifier)

        for number in 0...300 { navigator.remember(number, for: "/Volumes/Vault/Slides \(number).pdf") }

        let positions = storedPositions ?? [:]
        XCTAssertEqual(positions.count, 300)
        XCTAssertNil(positions["/Volumes/Vault/Slides 0.pdf"], "The first place kept is the one forgotten.")
        XCTAssertEqual(positions["/Volumes/Vault/Slides 1.pdf"], 1)
        XCTAssertEqual(positions["/Volumes/Vault/Slides 300.pdf"], 300)
        XCTAssertEqual(storedOrder?.first, "/Volumes/Vault/Slides 1.pdf")
        XCTAssertEqual(storedOrder?.last, "/Volumes/Vault/Slides 300.pdf")
        XCTAssertEqual(storedOrder?.count, 300)
    }

    func testKeepingAnOldPlaceAgainMakesItTheMostRecentSoItOutlivesTheOneKeptAfterIt() {
        let navigator = makeNavigator(openVault: vaultIdentifier)
        for number in 0..<300 { navigator.remember(number, for: "/Volumes/Vault/Slides \(number).pdf") }

        navigator.remember(42, for: "/Volumes/Vault/Slides 0.pdf")
        navigator.remember(301, for: "/Volumes/Vault/Slides 300.pdf")

        let positions = storedPositions ?? [:]
        XCTAssertEqual(positions["/Volumes/Vault/Slides 0.pdf"], 42)
        XCTAssertNil(positions["/Volumes/Vault/Slides 1.pdf"], "The least recently kept place is now the second one.")
        XCTAssertEqual(positions.count, 300)
    }

    func testForgettingAPlaceRemovesOnlyThatKey() {
        let navigator = makeNavigator(openVault: vaultIdentifier)
        navigator.remember(1, for: "Notes/A.md")
        navigator.remember(2, for: "Notes/B.md")

        navigator.forgetLocation(for: "Notes/A.md")

        XCTAssertEqual(storedPositions, ["7F0A3C54-9B1E-4D7C-8E21-5A6B4C3D2E10|Notes/B.md": 2])
    }
}
