import Foundation

/// Plans a Goodnotes notebook's live recordings (`GoodnotesNotebook.recordings`) as `.m4a` files, in the log's order,
/// named "Recording 1", "Recording 2" as Goodnotes shows them. A recording whose audio attachment is not in the log, or
/// names no safe file, is left out and counted.
public enum GoodnotesRecordingPlanner {
    public static func plan(_ recordings: [GoodnotesRecording]) -> ImportedRecordingsPlan {
        var planned: [ImportedRecording] = []
        var missingFileCount = 0
        for (recordingIndex, recording) in recordings.enumerated() {
            guard let file = recording.audio?.file else {
                missingFileCount += 1
                continue
            }
            planned.append(ImportedRecording(file: ImportedSourceFile(path: file), name: "Recording \(recordingIndex + 1)",
                                             durationSeconds: recording.durationSeconds))
        }
        let timedElementCount = recordings.reduce(0) { total, recording in total + recording.elementTimings.count }
        return ImportedRecordingsPlan(recordings: planned,
                                      report: ImportedRecordingsPlan.report(missingFileCount: missingFileCount, timedElementCount: timedElementCount))
    }
}
