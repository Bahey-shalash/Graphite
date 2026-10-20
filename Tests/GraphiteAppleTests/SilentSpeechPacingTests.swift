import XCTest
import Foundation
import GraphiteCore
@testable import GraphiteApple
import GraphiteTestSupport

/// A silent reading (`AudioOutputRoute.silent`, what every test run uses) gives the events of speech at the
/// pace of speech, by the clock, and never reaches the synthesizer or the audio output.
@MainActor
final class SilentSpeechPacingTests: XCTestCase {
    private static let tenWords = "The controller schedules every refresh, then reads the row. Done!"

    private func makeSpeech(clock: ManualClock) throws -> (speech: AppleReadAloudSpeech, voiceIdentifier: String) {
        let speech = AppleReadAloudSpeech(output: .silent, clock: clock)
        let voice = try XCTUnwrap(speech.voices.first, "This machine lists no Apple voice.")
        return (speech, voice.id)
    }

    /// Lets the reading run and moves the clock past every wait it makes, until it has none.
    private func readToTheEnd(_ clock: ManualClock) async {
        for _ in 0..<64 {
            await ManualClock.letResumedTasksRun()
            if clock.pendingSleepCount == 0 { return }
            clock.advance(by: .seconds(60))
        }
    }

    /// Names of the events so far, with a word's text.
    private func summary(_ events: [ReadAloudSpeechEvent], text: String) -> [String] {
        events.map { event in
            switch event {
            case .started: "started"
            case .spoken(_, let range): (text as NSString).substring(with: range)
            case .finished: "finished"
            case .paused: "paused"
            case .continued: "continued"
            default: "other"
            }
        }
    }

    func testAReadingGivesItsWordsInOrderAtTheTimesTheScheduleSaysAndFinishesAtTheEnd() async throws {
        let clock = ManualClock()
        let (speech, voiceIdentifier) = try makeSpeech(clock: clock)
        var events: [ReadAloudSpeechEvent] = []
        speech.eventHandler = { events.append($0) }
        let requestIdentifier = UUID()

        try speech.speak(Self.tenWords, voiceIdentifier: voiceIdentifier, speed: 1, requestIdentifier: requestIdentifier)
        let steps = SilentSpeechPacing.schedule(for: Self.tenWords, speed: 1, leadingPauseSeconds: 0)
        func name(of step: SilentSpeechPacing.Step) -> String {
            switch step.event {
            case .started: "started"
            case .word(let range): (Self.tenWords as NSString).substring(with: range)
            case .finished: "finished"
            }
        }
        // A step with no wait happens as soon as the one before it did; each other step waits its delay on the clock.
        var happened: [String] = []
        for step in steps {
            if step.delaySeconds > 0 {
                try await clock.awaitPendingSleepers()
                clock.advance(by: .seconds(step.delaySeconds - 0.01))
                await ManualClock.letResumedTasksRun()
                XCTAssertEqual(summary(events, text: Self.tenWords), happened, "\(name(of: step)) came too early.")
                clock.advance(by: .seconds(0.02))
            }
            await ManualClock.letResumedTasksRun()
            happened.append(name(of: step))
            // The steps with no wait of their own come together with the one before; the next wait checks them.
            if step.delaySeconds > 0 { XCTAssertEqual(summary(events, text: Self.tenWords), happened) }
        }
        XCTAssertEqual(summary(events, text: Self.tenWords), happened)
        XCTAssertEqual(happened.count, 12, "Started, ten words, finished.")
        XCTAssertEqual(happened.dropFirst().first, "The")
        XCTAssertEqual(happened.last, "finished")
        for event in events {
            switch event {
            case .started(let identifier), .finished(let identifier), .spoken(let identifier, _): XCTAssertEqual(identifier, requestIdentifier)
            default: XCTFail("Unexpected \(event)")
            }
        }
    }

    func testTenWordsTakeAboutAsLongAsAnEvenVoiceReadsThem() {
        // Independent of the pacing numbers: an even voice reads 140 to 200 words a minute, so ten words take 3 to 4.3 seconds
        // at speed 1; punctuation here adds a little.
        let seconds = SilentSpeechPacing.durationSeconds(of: Self.tenWords, speed: 1)
        XCTAssertGreaterThan(seconds, 3)
        XCTAssertLessThan(seconds, 6)
        XCTAssertEqual(SilentSpeechPacing.durationSeconds(of: Self.tenWords, speed: 2), seconds / 2, accuracy: 0.001, "Twice the speed, half the time.")
    }

    func testTheLeadingPauseComesBeforeTheStart() async throws {
        let clock = ManualClock()
        let (speech, voiceIdentifier) = try makeSpeech(clock: clock)
        var events: [ReadAloudSpeechEvent] = []
        speech.eventHandler = { events.append($0) }

        try speech.speak("Heading", voiceIdentifier: voiceIdentifier, speed: 1, leadingPauseSeconds: 1.5, usesSystemSettings: false, requestIdentifier: UUID())
        try await clock.awaitPendingSleepers()
        clock.advance(by: .seconds(1.4))
        await ManualClock.letResumedTasksRun()
        XCTAssertTrue(events.isEmpty)
        clock.advance(by: .seconds(0.2))
        await ManualClock.letResumedTasksRun()
        XCTAssertEqual(summary(events, text: "Heading").first, "started")
    }

    func testPausingHoldsTheReadingAndResumingGoesOnFromTheNextWord() async throws {
        let clock = ManualClock()
        let (speech, voiceIdentifier) = try makeSpeech(clock: clock)
        var events: [ReadAloudSpeechEvent] = []
        speech.eventHandler = { events.append($0) }
        try speech.speak("one two three", voiceIdentifier: voiceIdentifier, speed: 1, requestIdentifier: UUID())
        await ManualClock.letResumedTasksRun()
        XCTAssertEqual(summary(events, text: "one two three"), ["started", "one"], "The steps with no wait have happened.")

        XCTAssertTrue(speech.pause())
        clock.advance(by: .seconds(60))
        await ManualClock.letResumedTasksRun()
        XCTAssertEqual(summary(events, text: "one two three"), ["started", "one", "paused"], "Paused, nothing moves on.")
        XCTAssertFalse(speech.pause(), "Already paused.")

        XCTAssertTrue(speech.resume())
        await readToTheEnd(clock)
        XCTAssertEqual(summary(events, text: "one two three"), ["started", "one", "paused", "continued", "two", "three", "finished"])
    }

    func testStoppingEndsTheReadingWithoutFurtherEvents() async throws {
        let clock = ManualClock()
        let (speech, voiceIdentifier) = try makeSpeech(clock: clock)
        var events: [ReadAloudSpeechEvent] = []
        speech.eventHandler = { events.append($0) }
        try speech.speak("one two three", voiceIdentifier: voiceIdentifier, speed: 1, requestIdentifier: UUID())
        await ManualClock.letResumedTasksRun()
        let eventsBeforeStopping = events.count

        speech.stop()
        await readToTheEnd(clock)

        XCTAssertEqual(events.count, eventsBeforeStopping)
        XCTAssertFalse(speech.pause())
        XCTAssertFalse(speech.resume())
    }

    func testASilentReadingNeverMakesTheSynthesizer() async throws {
        let clock = ManualClock()
        let (speech, voiceIdentifier) = try makeSpeech(clock: clock)
        speech.eventHandler = { _ in }
        try speech.speak(Self.tenWords, voiceIdentifier: voiceIdentifier, speed: 1, requestIdentifier: UUID())
        await readToTheEnd(clock)
        _ = speech.pause()
        _ = speech.resume()
        speech.stop()
        speech.releaseAudio()

        XCTAssertFalse(speech.hasCreatedSynthesizer, "Speech and the audio output are reached only through the synthesizer.")
    }

    func testAReplacementReadingEndsTheOneBefore() async throws {
        let clock = ManualClock()
        let (speech, voiceIdentifier) = try makeSpeech(clock: clock)
        var events: [ReadAloudSpeechEvent] = []
        speech.eventHandler = { events.append($0) }
        let first = UUID(), second = UUID()
        try speech.speak("old words here", voiceIdentifier: voiceIdentifier, speed: 1, requestIdentifier: first)
        await ManualClock.letResumedTasksRun()
        let eventsOfTheFirst = events.count
        try speech.speak("new", voiceIdentifier: voiceIdentifier, speed: 1, requestIdentifier: second)
        await readToTheEnd(clock)

        XCTAssertEqual(summary(Array(events.dropFirst(eventsOfTheFirst)), text: "new"), ["started", "new", "finished"])
        for event in events.dropFirst(eventsOfTheFirst) {
            switch event {
            case .started(let identifier), .finished(let identifier), .spoken(let identifier, _): XCTAssertEqual(identifier, second)
            default: break
            }
        }
    }
}
