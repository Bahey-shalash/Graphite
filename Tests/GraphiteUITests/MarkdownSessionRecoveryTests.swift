import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class MarkdownSessionRecoveryTests: XCTestCase {
    /// File recovery copies the text a save or a reload is about to replace, and nothing
    /// when nothing is replaced.
    func testReportsTheSavedTextBeforeASaveOrAReloadReplacesIt() async throws {
        let vault = try TemporaryVault.make(prefix: "Vault", for: self).root
        let notePath = try VaultPath("Note.md")
        let noteLocation = vault.appendingPathComponent("Note.md")
        try Data("first".utf8).write(to: noteLocation)
        let store = VaultStore(root: vault)
        let session = try MarkdownSession(path: notePath, snapshot: try await store.read(notePath), store: store, didSave: { _ in })
        var replacedTexts: [String] = []
        session.willReplaceSavedText = { replacedText in replacedTexts.append(replacedText) }

        try await session.save()
        XCTAssertEqual(replacedTexts, [], "Nothing changed, so nothing is replaced.")

        session.text = "second"
        try await session.save()
        XCTAssertEqual(replacedTexts, ["first"])

        // Another app rewrites the note.
        try Data("third, from elsewhere".utf8).write(to: noteLocation)
        try await session.reload()
        XCTAssertEqual(replacedTexts, ["first", "second"])
        try await session.reload()
        XCTAssertEqual(replacedTexts, ["first", "second"], "Reading the same text again replaces nothing.")
    }
}
