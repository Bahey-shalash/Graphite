import Foundation
import XCTest
@testable import GraphiteCore

/// Both notebooks' recordings planned as `.m4a` files: their files, names and durations, and the report of what is
/// left out (recordings without a file, and the timing of writing during a recording).
final class ImportedRecordingPlannerTests: XCTestCase {
    func testGoodnotesRecordingsAreNumberedInOrderAndOneWithoutAudioIsCounted() {
        let timing = GoodnotesRecording.ElementTiming(elementIdentifier: "stroke", secondsFromStart: 1.5, pageIdentifier: "page")
        let recordings = [
            GoodnotesRecording(identifier: "first", audio: Self.attachment("AUDIO-1"), durationSeconds: 47.2, elementTimings: [timing, timing]),
            GoodnotesRecording(identifier: "lost", audio: nil, durationSeconds: 3, elementTimings: []),
            GoodnotesRecording(identifier: "third", audio: Self.attachment("AUDIO-3"), durationSeconds: 9, elementTimings: [timing])
        ]
        let plan = GoodnotesRecordingPlanner.plan(recordings)
        XCTAssertEqual(plan.recordings, [
            ImportedRecording(file: ImportedSourceFile(path: .fixture("attachments/AUDIO-1")), name: "Recording 1", durationSeconds: 47.2),
            ImportedRecording(file: ImportedSourceFile(path: .fixture("attachments/AUDIO-3")), name: "Recording 3", durationSeconds: 9)
        ])
        XCTAssertEqual(plan.report, [.recordingFilesMissing(count: 1), .recordingTimingNotKept(timedElementCount: 3)])
    }

    func testNotabilityRecordingsKeepTheirLibraryNamesAsSafeFileNames() {
        let recordings = [
            NotabilityRecording(identifier: 1, file: .fixture("Recordings/Recording 1.m4a"), durationSeconds: 18.9, name: "Recording 1"),
            NotabilityRecording(identifier: 2, file: .fixture("Recordings/Lecture.m4a"), durationSeconds: nil, name: " ..Week 3/4: optics\n"),
            NotabilityRecording(identifier: 3, file: .fixture("Recordings/Unnamed.m4a"), durationSeconds: 2, name: nil),
            NotabilityRecording(identifier: 4, file: nil, durationSeconds: 5, name: "Unsafe path")
        ]
        let event = NotabilityPlaybackEvent(curveIndex: 0, curveUUID: UUID(), recordingIdentifier: 1, secondsFromRecordingStart: 10.8, durationSeconds: 0.5)
        let plan = NotabilityRecordingPlanner.plan(Self.note(recordings: recordings, playbackEvents: [event, event]))
        XCTAssertEqual(plan.recordings.map(\.name), ["Recording 1", "Week 3-4- optics-", "Recording 3"])
        XCTAssertEqual(plan.recordings.map(\.file.pathInSource), ["Recordings/Recording 1.m4a", "Recordings/Lecture.m4a", "Recordings/Unnamed.m4a"])
        XCTAssertEqual(plan.recordings.map(\.durationSeconds), [18.9, nil, 2])
        XCTAssertEqual(plan.report, [.recordingFilesMissing(count: 1), .recordingTimingNotKept(timedElementCount: 2)])
    }

    func testANotebookWithoutRecordingsHasAnEmptyPlan() {
        XCTAssertEqual(GoodnotesRecordingPlanner.plan([]), ImportedRecordingsPlan(recordings: [], report: []))
        XCTAssertEqual(NotabilityRecordingPlanner.plan(Self.note(recordings: [], playbackEvents: [])), ImportedRecordingsPlan(recordings: [], report: []))
    }

    func testANameWithNothingSafeLeftFallsBack() {
        XCTAssertEqual(ImportedRecording.fileName(from: " ... ", fallback: "Recording 2"), "Recording 2")
        XCTAssertEqual(ImportedRecording.fileName(from: "", fallback: "Recording 2"), "Recording 2")
        XCTAssertEqual(ImportedRecording.fileName(from: "Cours 10", fallback: "Recording 2"), "Cours 10")
    }

    private static func attachment(_ fileIdentifier: String) -> GoodnotesAttachment {
        GoodnotesAttachment(identifier: "attachment-" + fileIdentifier, fileIdentifier: fileIdentifier,
                            file: .fixture("attachments/" + fileIdentifier), byteCount: nil, pdfPageCount: nil)
    }

    private static func note(recordings: [NotabilityRecording], playbackEvents: [NotabilityPlaybackEvent]) -> NotabilityNote {
        let paper = NotabilityPaper(identifier: .legacyWhite, size: .letter, orientation: .portrait,
                                    sizingBehaviour: .lockedWidth(width: 572, device: "iPad"), lineStyle: .noLines)
        return NotabilityNote(name: nil, sessionFormatVersion: 9, applicationVersion: nil, paper: paper, reflowState: .locked(pageWidth: 572, device: nil),
                              pageGeometry: NotabilityPageGeometry(pageWidthInUnits: 572, paper: paper), shapes: [], pictures: [],
                              typedText: NotabilityTypedText(text: "", runs: []), importedPDFPages: [], recordings: recordings,
                              playbackEvents: playbackEvents)
    }
}
