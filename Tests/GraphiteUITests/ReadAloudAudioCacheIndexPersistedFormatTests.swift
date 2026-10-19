import XCTest
import GraphiteCore
import GraphiteVoices

/// The rendered-passage cache's `index.json`: a JSON array whose `lastUsed` dates are the
/// encoder's default, seconds since 2001-01-01 00:00:00 UTC. Folders written by earlier
/// builds are read by this one, so the number keeps its meaning.
final class ReadAloudAudioCacheIndexPersistedFormatTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("AudioCacheIndex-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func key(_ text: String) -> ReadAloudAudioCacheKey {
        ReadAloudAudioCacheKey(text: text, voiceIdentifier: "voice", voiceRevision: "r1")
    }

    private func storedIndex() throws -> [[String: Any]] {
        let data = try Data(contentsOf: folder.appendingPathComponent("index.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    func testACommittedPassageIsIndexedWithItsLastUseAsSecondsSince2001() async throws {
        let cache = ReadAloudAudioCache(folder: folder)
        let passageKey = key("committed")
        let before = Date.now.timeIntervalSinceReferenceDate
        try await cache.commit(passageKey, durationSeconds: 1, wordTimings: nil)
        let after = Date.now.timeIntervalSinceReferenceDate

        let entries = try storedIndex()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(Set(entries[0].keys), ["key", "byteCount", "lastUsed"])
        XCTAssertEqual((entries[0]["key"] as? [String: String])?["value"], passageKey.value)
        let lastUsed = try XCTUnwrap(entries[0]["lastUsed"] as? Double)
        XCTAssertGreaterThanOrEqual(lastUsed, before)
        XCTAssertLessThanOrEqual(lastUsed, after)
    }

    func testAnIndexWrittenByAnEarlierBuildOrdersPassagesByDatesCountedFrom2001() async throws {
        // The kept passage was last used in 2032 counted from 2001 (in 2001 counted from 1970),
        // so it is newer than the passage committed now, and the committed one makes way.
        let keptKey = key("kept")
        let committedKey = key("committed")
        let keptAudio = folder.appendingPathComponent("\(keptKey.value).m4a")
        try Data(count: 100).write(to: keptAudio)
        let index = #"[{"byteCount":100,"key":{"value":"\#(keptKey.value)"},"lastUsed":1000000000}]"#
        try Data(index.utf8).write(to: folder.appendingPathComponent("index.json"))

        let cache = ReadAloudAudioCache(folder: folder, capacityBytes: 100)
        let keptBefore = await cache.contains(keptKey)
        XCTAssertTrue(keptBefore)
        try await cache.commit(committedKey, durationSeconds: 1, wordTimings: nil)

        XCTAssertEqual(try storedIndex().compactMap { ($0["key"] as? [String: String])?["value"] }, [keptKey.value])
        let keptAfter = await cache.contains(keptKey)
        XCTAssertTrue(keptAfter)
    }
}
