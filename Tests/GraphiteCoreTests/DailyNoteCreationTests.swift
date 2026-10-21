import XCTest
import GraphiteTestSupport
@testable import GraphiteCore

final class DailyNoteCreationTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_792_000_000)
    private let zurich = TimeZone(identifier: "Europe/Zurich") ?? .gmt

    func testAnExistingDailyNoteIsLeftAsItIs() async throws {
        let vault = try TemporaryVault.make(files: ["2026-10-14.md": "Mine"], for: self)
        let isCreated = try await DailyNoteCreation.createIfMissing(try VaultPath("2026-10-14.md"), for: date, settings: DailyNoteSettings(template: "Template"),
                                                                    timeFormat: "HH:mm", maximumTemplateBytes: 1_024, timeZone: zurich, store: VaultStore(root: vault.root))
        XCTAssertFalse(isCreated)
        XCTAssertEqual(try vault.readText(at: "2026-10-14.md"), "Mine")
    }

    func testANoteWithoutATemplateIsEmpty() async throws {
        let vault = try TemporaryVault.make(for: self)
        let isCreated = try await DailyNoteCreation.createIfMissing(try VaultPath("Daily/2026-10-14.md"), for: date, settings: DailyNoteSettings(folder: "Daily"),
                                                                    timeFormat: "HH:mm", maximumTemplateBytes: 1_024, timeZone: zurich, store: VaultStore(root: vault.root))
        XCTAssertTrue(isCreated)
        XCTAssertEqual(try vault.readText(at: "Daily/2026-10-14.md"), "")
    }

    func testTheTemplateIsFilledInForTheNotesOwnDay() async throws {
        let vault = try TemporaryVault.make(files: ["Template.md": "{{title}} at {{time}}"], for: self)
        try await DailyNoteCreation.createIfMissing(try VaultPath("2026-10-14.md"), for: date, settings: DailyNoteSettings(template: "Template"),
                                                    timeFormat: "HH:mm", maximumTemplateBytes: 1_024, timeZone: zurich, store: VaultStore(root: vault.root))
        XCTAssertEqual(try vault.readText(at: "2026-10-14.md"), "2026-10-14 at 19:46")
    }

    func testAMissingTemplateIsNamedAndNothingIsCreated() async throws {
        let vault = try TemporaryVault.make(for: self)
        do {
            try await DailyNoteCreation.createIfMissing(try VaultPath("2026-10-14.md"), for: date, settings: DailyNoteSettings(template: "Gone"),
                                                        timeFormat: "HH:mm", maximumTemplateBytes: 1_024, timeZone: zurich, store: VaultStore(root: vault.root))
            XCTFail("A missing template is refused.")
        } catch DailyNoteCreation.Failure.templateMissing(let templatePath) {
            XCTAssertEqual(templatePath.rawValue, "Gone.md")
        }
        XCTAssertFalse(vault.fileExists(at: "2026-10-14.md"))
    }
}
