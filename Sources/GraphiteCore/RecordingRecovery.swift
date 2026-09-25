import Foundation

/// Where a recording belongs, written beside its audio when it starts, so a recording that
/// Graphite did not finish (the app was closed by the system, crashed, or the iPad ran out
/// of power) can be saved where it was meant to go.
public struct RecordingRecoveryManifest: Codable, Equatable, Sendable {
    /// The vault's identifier in Graphite's vault list.
    public var vaultIdentifier: UUID?
    /// The vault path of the `.m4a` file the recording becomes.
    public var destinationPath: String
    /// The note the recording was started from.
    public var notePath: String?
    public var startedAt: Date

    public init(vaultIdentifier: UUID?, destinationPath: String, notePath: String?, startedAt: Date) {
        self.vaultIdentifier = vaultIdentifier
        self.destinationPath = destinationPath
        self.notePath = notePath
        self.startedAt = startedAt
    }
}

/// A recording left in the recovery folder, with where it belongs when that is known.
public struct RecoverableRecording: Identifiable, Equatable, Sendable {
    public let audioLocation: URL
    public let manifest: RecordingRecoveryManifest?
    public let startedAt: Date
    public let byteCount: Int
    public var id: URL { audioLocation }

    public var destination: VaultPath? { manifest.flatMap { manifest in try? VaultPath(manifest.destinationPath) } }
}

/// The folder of unfinished recordings, in Application Support: the audio is the user's,
/// never a cache, and stays there until it is saved into a vault or deleted.
public enum RecordingRecoveryFolder {
    public static let audioExtensions: Set<String> = ["caf", "m4a"]

    public static func location() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = support.appendingPathComponent("Graphite/Recovery/Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    public static func manifestLocation(for audioLocation: URL) -> URL {
        audioLocation.deletingPathExtension().appendingPathExtension("json")
    }

    public static func write(_ manifest: RecordingRecoveryManifest, for audioLocation: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: manifestLocation(for: audioLocation), options: .atomic)
    }

    public static func manifest(for audioLocation: URL) -> RecordingRecoveryManifest? {
        guard let data = try? Data(contentsOf: manifestLocation(for: audioLocation)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RecordingRecoveryManifest.self, from: data)
    }

    /// Files this size or smaller hold a header and no audio (a CAF's header takes 4 KiB).
    public static let largestFileWithoutAudio = 4_096

    /// Recordings in `folder` other than the one being made, oldest first. Files with no
    /// audio, which hold nothing to recover, are left out.
    public static func recordings(in folder: URL, excluding activeLocation: URL? = nil) -> [RecoverableRecording] {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .creationDateKey, .isRegularFileKey]
        guard let locations = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return [] }
        let active = activeLocation?.standardizedFileURL.resolvingSymlinksInPath().path
        return locations.compactMap { location -> RecoverableRecording? in
            guard audioExtensions.contains(location.pathExtension.lowercased()),
                  location.standardizedFileURL.resolvingSymlinksInPath().path != active,
                  let values = try? location.resourceValues(forKeys: keys), values.isRegularFile == true,
                  let byteCount = values.fileSize, byteCount > largestFileWithoutAudio else { return nil }
            let manifest = manifest(for: location)
            return RecoverableRecording(audioLocation: location, manifest: manifest, startedAt: manifest?.startedAt ?? values.creationDate ?? .distantPast, byteCount: byteCount)
        }
        .sorted { first, second in first.startedAt < second.startedAt }
    }

    /// Deletes a recording and its manifest, once it is saved or the person discards it.
    public static func remove(_ recording: RecoverableRecording) throws {
        try FileManager.default.removeItem(at: recording.audioLocation)
        try? FileManager.default.removeItem(at: manifestLocation(for: recording.audioLocation))
    }
}
