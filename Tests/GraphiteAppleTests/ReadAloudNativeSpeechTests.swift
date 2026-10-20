import XCTest
import Foundation
import GraphiteCore
@testable import GraphiteApple

/// This test uses the installed voice and the real synthesizer, rendered to buffers that are
/// dropped (`AudioOutputRoute.silent`): nothing is heard while the test runs. It establishes
/// callback delivery, not subjective naturalness or device drift.
@MainActor
final class ReadAloudNativeSpeechTests: XCTestCase {
    func testInstalledAppleVoiceDeliversActualWordRangesAndCompletion() async throws {
        let speech = AppleReadAloudSpeech(output: .silent, clock: LiveApplicationClock(), rendersToDroppedBuffers: true)
        guard let voice = ReadAloudVoice.preferred(in: speech.voices, language: "en-US") else {
            throw XCTSkip("Install an English Apple voice to run native speech integration.")
        }
        let identifier = UUID()
        let text = "Read this sentence."
        let source = text as NSString
        var ranges: [NSRange] = []
        var completed = false
        speech.eventHandler = { event in
            switch event {
            case .spoken(let requestIdentifier, let range):
                XCTAssertEqual(requestIdentifier, identifier)
                XCTAssertGreaterThan(range.length, 0)
                XCTAssertLessThanOrEqual(NSMaxRange(range), source.length)
                if range.location >= 0, range.location <= source.length, range.length <= source.length - range.location { ranges.append(range) }
            case .finished(let requestIdentifier):
                XCTAssertEqual(requestIdentifier, identifier)
                completed = true
            default: break
            }
        }
        defer { speech.stop(); speech.eventHandler = nil }
        try speech.speak(text, voiceIdentifier: voice.id, speed: 1, requestIdentifier: identifier)
        let deadline = ContinuousClock.now + .seconds(25)
        while !completed, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(completed, "The real speech engine did not finish within the integration-test deadline.")
        XCTAssertFalse(ranges.isEmpty, "The production adapter must deliver actual spoken-word positions.")
        let words = ranges.map { source.substring(with: $0).trimmingCharacters(in: .punctuationCharacters) }
        XCTAssertEqual(words, ["Read", "this", "sentence"])
    }
}
