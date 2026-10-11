import XCTest
@testable import GraphiteCore

final class ReadAloudAudioTimingTests: XCTestCase {
    func testMediaClockFollowsWordsAndLeavesSilenceUnhighlighted() throws {
        let timing = try ReadAloudAudioTiming(sourceText: "Read this.", characters: "Read this.".map(String.init),
                                             startTimesSeconds: [0.1, 0.15, 0.2, 0.3, 0.5, 0.8, 0.85, 0.9, 1, 1.2],
                                             endTimesSeconds: [0.15, 0.2, 0.3, 0.4, 0.6, 0.85, 0.9, 1, 1.1, 1.3], durationSeconds: 1.5)
        XCTAssertNil(timing.wordRange(atPlaybackSeconds: 0))
        XCTAssertEqual(timing.wordRange(atPlaybackSeconds: 0.2), NSRange(location: 0, length: 4))
        XCTAssertNil(timing.wordRange(atPlaybackSeconds: 0.7))
        XCTAssertEqual(timing.wordRange(atPlaybackSeconds: 0.9), NSRange(location: 5, length: 4))
        XCTAssertNil(timing.wordRange(atPlaybackSeconds: 1.3))
        XCTAssertNil(timing.wordRange(atPlaybackSeconds: .nan))
        XCTAssertNil(timing.wordRange(atPlaybackSeconds: -.infinity))
        XCTAssertNil(timing.wordRange(atPlaybackSeconds: 1.5))
        // A seek backwards queries the same immutable timeline.
        XCTAssertEqual(timing.wordRange(atPlaybackSeconds: 0.2), NSRange(location: 0, length: 4))
    }

    func testUnicodeProviderEntriesBecomeExactUTF16SourceRanges() throws {
        let sourceText = "😀 cafe\u{301} again"
        let characters = sourceText.unicodeScalars.map(String.init)
        let starts = characters.indices.map { Double($0) * 0.1 }
        let ends = starts.map { $0 + 0.1 }
        let timing = try ReadAloudAudioTiming(sourceText: sourceText, characters: characters,
                                             startTimesSeconds: starts, endTimesSeconds: ends, durationSeconds: 3)
        XCTAssertEqual(timing.words.map(\.range), [(sourceText as NSString).range(of: "cafe\u{301}"),
                                                   (sourceText as NSString).range(of: "again")])
        let document = try ReadAloudDocument.plainText(sourceText)
        let range = try XCTUnwrap(timing.wordRange(atPlaybackSeconds: 0.35))
        XCTAssertEqual(document.passages.first?.sourceRange(for: range), (sourceText as NSString).range(of: "cafe\u{301}"))
    }

    func testAlteredNumbersNormalizationAndCanonicalChangesAreRejected() {
        for (sourceText, providerText) in [("12", "twelve"), ("12", "13"), ("cafe\u{301}", "café")] {
            XCTAssertThrowsError(try ReadAloudAudioTiming(sourceText: sourceText, characters: [providerText],
                                                        startTimesSeconds: [0], endTimesSeconds: [1], durationSeconds: 2))
        }
    }

    func testMalformedAndOutOfBoundsTimingIsRejected() {
        for (starts, ends) in [([0.0], [0.2, 0.4]), ([0.3, 0.1], [0.4, 0.5]),
                               ([0.0, 0.3], [0.4, 0.2]), ([-0.1, 0.3], [0.2, 0.4]),
                               ([0.0, .nan], [0.2, 0.4]), ([0.0, 0.3], [0.2, .infinity]),
                               ([0.0, 0.3], [0.2, 3.0])] {
            XCTAssertThrowsError(try ReadAloudAudioTiming(sourceText: "ab", characters: ["a", "b"],
                                                        startTimesSeconds: starts, endTimesSeconds: ends, durationSeconds: 2))
        }
        XCTAssertThrowsError(try ReadAloudAudioTiming(sourceText: "ab", characters: ["", "ab"],
                                                    startTimesSeconds: [0, 1], endTimesSeconds: [1, 2], durationSeconds: 2))
        XCTAssertThrowsError(try ReadAloudAudioTiming(sourceText: "two words", characters: ["two words"],
                                                    startTimesSeconds: [0], endTimesSeconds: [1], durationSeconds: 2))
    }
}
