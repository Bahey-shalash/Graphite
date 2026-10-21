import Foundation

/// Plans a Notability note's recordings (`Recordings/library.plist`) as `.m4a` files, in the library's order, each named
/// by its name in the library ("Recording 1"). A recording whose library entry names no safe file is left out and
/// counted.
public enum NotabilityRecordingPlanner {
    public static func plan(_ note: NotabilityNote) -> ImportedRecordingsPlan {
        var planned: [ImportedRecording] = []
        var missingFileCount = 0
        for (recordingIndex, recording) in note.recordings.enumerated() {
            guard let file = recording.file else {
                missingFileCount += 1
                continue
            }
            let name = ImportedRecording.fileName(from: recording.name, fallback: "Recording \(recordingIndex + 1)")
            planned.append(ImportedRecording(file: ImportedSourceFile(path: file), name: name, durationSeconds: recording.durationSeconds))
        }
        return ImportedRecordingsPlan(recordings: planned,
                                      report: ImportedRecordingsPlan.report(missingFileCount: missingFileCount,
                                                                            timedElementCount: note.playbackEvents.count))
    }
}
