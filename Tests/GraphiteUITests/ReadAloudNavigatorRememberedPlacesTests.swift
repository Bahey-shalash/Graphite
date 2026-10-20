import XCTest
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

/// Where reading stopped in a note is remembered for the note of the vault it was read in.
@MainActor
final class ReadAloudNavigatorRememberedPlacesTests: XCTestCase {
    private let firstVaultIdentifier = UUID()
    private let secondVaultIdentifier = UUID()

    private func makeNavigator(openVault: @escaping () -> UUID?) throws -> ReadAloudNavigator {
        let preferences = try IsolatedDeviceState.make(prefix: "ReadAloudNavigatorRememberedPlacesTests", for: self).preferences
        let session = ReadAloudSession(speech: PenTestSpeech(), preferences: preferences)
        let navigator = ReadAloudNavigator(reader: ReadAloudController(session: session, preferences: preferences), preferences: preferences)
        navigator.vaultIdentifier = openVault
        return navigator
    }

    func testANotePlaceRememberedInOneVaultIsNotUsedForTheSameNamedNoteOfAnotherVault() throws {
        var openVault: UUID? = firstVaultIdentifier
        let navigator = try makeNavigator { openVault }
        navigator.remember(1_234, for: "Lecture.md")

        openVault = secondVaultIdentifier

        XCTAssertNil(navigator.rememberedLocation(for: "Lecture.md"))
        XCTAssertNil(navigator.rememberedLocation(for: try VaultPath("Lecture.md")))
    }

    func testANotePlaceIsFoundAgainWhenItsVaultIsOpenAgain() throws {
        var openVault: UUID? = firstVaultIdentifier
        let navigator = try makeNavigator { openVault }
        navigator.remember(1_234, for: "Lecture.md")
        openVault = secondVaultIdentifier
        navigator.remember(55, for: "Lecture.md")

        openVault = firstVaultIdentifier
        XCTAssertEqual(navigator.rememberedLocation(for: "Lecture.md"), 1_234)
        XCTAssertEqual(navigator.rememberedLocation(for: try VaultPath("Lecture.md")), 1_234)
        openVault = secondVaultIdentifier
        XCTAssertEqual(navigator.rememberedLocation(for: "Lecture.md"), 55)
    }

    func testForgettingANotePlaceLeavesTheSameNamedNoteOfAnotherVaultRemembered() throws {
        var openVault: UUID? = firstVaultIdentifier
        let navigator = try makeNavigator { openVault }
        navigator.remember(1_234, for: "Lecture.md")
        openVault = secondVaultIdentifier
        navigator.remember(55, for: "Lecture.md")

        navigator.forgetLocation(for: "Lecture.md")

        XCTAssertNil(navigator.rememberedLocation(for: "Lecture.md"))
        openVault = firstVaultIdentifier
        XCTAssertEqual(navigator.rememberedLocation(for: "Lecture.md"), 1_234)
    }

    func testAPDFPlaceIsKeptByItsFileLocationWhicheverVaultIsOpen() throws {
        var openVault: UUID? = firstVaultIdentifier
        let navigator = try makeNavigator { openVault }
        navigator.remember(7, for: "/Volumes/Vault/Slides.pdf")

        openVault = secondVaultIdentifier

        XCTAssertEqual(navigator.rememberedLocation(for: "/Volumes/Vault/Slides.pdf"), 7)
    }
}
