import XCTest
@testable import GraphiteCore

/// The name of a cached rendered passage: the lowercase hexadecimal SHA-256 of
/// `"graphite-read-aloud"`, the render settings version, the voice, the voice revision and the
/// text, separated by U+0000. Folders written by earlier builds are looked up by these names,
/// so the recipe never changes without raising `renderSettingsVersion`.
final class ReadAloudAudioCacheKeyTests: XCTestCase {
    func testTheKeyOfAFixedTextVoiceAndRevisionIsTheRecordedDigest() {
        let key = ReadAloudAudioCacheKey(text: "Hello, world.", voiceIdentifier: "voice-id", voiceRevision: "r1+r2")

        // printf 'graphite-read-aloud\0001\000voice-id\000r1+r2\000Hello, world.' | shasum -a 256
        XCTAssertEqual(key.value, "8e9c14b8ce9458158c90d47a56bcf6a914502dbece48583bc76800d4af656d73")
        XCTAssertEqual(key.description, key.value)
    }

    func testTheRenderSettingsVersionIsOneAndIsPartOfTheKey() {
        XCTAssertEqual(ReadAloudAudioCacheKey.renderSettingsVersion, 1)

        let defaultVersion = ReadAloudAudioCacheKey(text: "Hello, world.", voiceIdentifier: "voice-id", voiceRevision: "r1+r2")
        let explicitFirstVersion = ReadAloudAudioCacheKey(text: "Hello, world.", voiceIdentifier: "voice-id", voiceRevision: "r1+r2", renderSettingsVersion: 1)
        let secondVersion = ReadAloudAudioCacheKey(text: "Hello, world.", voiceIdentifier: "voice-id", voiceRevision: "r1+r2", renderSettingsVersion: 2)

        XCTAssertEqual(defaultVersion, explicitFirstVersion)
        // printf 'graphite-read-aloud\0002\000voice-id\000r1+r2\000Hello, world.' | shasum -a 256
        XCTAssertEqual(secondVersion.value, "3e62405222548cce28ab62987fbe999ae4114dc8964b7b75b52f8e1bf82cfeca")
    }

    func testTheKeyIs64LowercaseHexadecimalDigits() {
        let key = ReadAloudAudioCacheKey(text: "Ünïcode ∑ text 😀", voiceIdentifier: "Voice", voiceRevision: "REV")

        XCTAssertEqual(key.value.count, 64)
        XCTAssertTrue(key.value.allSatisfy { character in "0123456789abcdef".contains(character) })
    }

    func testFieldsAreSeparatedSoNeighbouringFieldsCannotShareAKey() {
        let first = ReadAloudAudioCacheKey(text: "c", voiceIdentifier: "a", voiceRevision: "b")
        let second = ReadAloudAudioCacheKey(text: "bc", voiceIdentifier: "a", voiceRevision: "")
        let third = ReadAloudAudioCacheKey(text: "c", voiceIdentifier: "ab", voiceRevision: "")

        XCTAssertEqual(Set([first, second, third]).count, 3)
    }

    func testEveryFieldChangesTheKey() {
        let base = ReadAloudAudioCacheKey(text: "Hello", voiceIdentifier: "voice", voiceRevision: "r1")

        XCTAssertNotEqual(base, ReadAloudAudioCacheKey(text: "Hello.", voiceIdentifier: "voice", voiceRevision: "r1"))
        XCTAssertNotEqual(base, ReadAloudAudioCacheKey(text: "Hello", voiceIdentifier: "voice2", voiceRevision: "r1"))
        XCTAssertNotEqual(base, ReadAloudAudioCacheKey(text: "Hello", voiceIdentifier: "voice", voiceRevision: "r2"))
    }

    func testAKeyIsReadBackFromTheFileNameOfItsAudioAndDetails() throws {
        let key = ReadAloudAudioCacheKey(text: "Hello", voiceIdentifier: "voice", voiceRevision: "r1")

        XCTAssertEqual(ReadAloudAudioCacheKey(fileName: "\(key.value).m4a"), key)
        XCTAssertEqual(ReadAloudAudioCacheKey(fileName: "\(key.value).json"), key)
        XCTAssertNil(ReadAloudAudioCacheKey(fileName: "index.json"))
    }
}
