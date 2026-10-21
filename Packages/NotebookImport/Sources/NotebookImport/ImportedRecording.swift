import Foundation

/// A recording of the notebook, kept beside the imported PDF as an `.m4a` file whose bytes are the source's, unchanged:
/// Notability's recordings are `.m4a` files, and Goodnotes' are MP4 audio (AAC) without an extension. Where the file
/// goes follows the vault's attachment setting, which the import's caller applies.
public struct ImportedRecording: Sendable, Equatable {
    public static let fileExtension = "m4a"

    public let file: ImportedSourceFile
    /// A name for the file, without its extension, safe as a file name: the recording's own name, or "Recording 2".
    public let name: String
    public let durationSeconds: Double?

    public init(file: ImportedSourceFile, name: String, durationSeconds: Double?) {
        self.file = file
        self.name = name
        self.durationSeconds = durationSeconds
    }

    /// `proposedName` with path separators, colons and control characters as hyphens and without leading dots or
    /// surrounding spaces; `fallback` when nothing is left.
    static func fileName(from proposedName: String?, fallback: String) -> String {
        let unsafe = CharacterSet(charactersIn: "/\\:").union(.controlCharacters).union(.newlines)
        let scalars = (proposedName ?? "").unicodeScalars.map { scalar in unsafe.contains(scalar) ? "-" : Character(scalar) }
        let name = String(scalars).trimmingCharacters(in: .whitespaces).drop { character in character == "." }
        return name.isEmpty ? fallback : String(name)
    }
}

/// A notebook's recordings to keep, and what of them the import leaves out.
public struct ImportedRecordingsPlan: Sendable, Equatable {
    public let recordings: [ImportedRecording]
    /// `recordingFilesMissing` and `recordingTimingNotKept`, when they apply.
    public let report: [ImportReportEntry]

    public init(recordings: [ImportedRecording], report: [ImportReportEntry]) {
        self.recordings = recordings
        self.report = report
    }

    /// The report's entries for `missingFileCount` recordings without a file and `timedElementCount` elements timed
    /// against a recording (the owner's decision of 2026-10-20 leaves that timing out for now).
    static func report(missingFileCount: Int, timedElementCount: Int) -> [ImportReportEntry] {
        var report: [ImportReportEntry] = []
        if missingFileCount > 0 { report.append(.recordingFilesMissing(count: missingFileCount)) }
        if timedElementCount > 0 { report.append(.recordingTimingNotKept(timedElementCount: timedElementCount)) }
        return report
    }
}
