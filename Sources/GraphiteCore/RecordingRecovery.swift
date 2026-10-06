import Foundation

/// Where a recording belongs, written beside its audio or video when it starts, so a
/// recording that Graphite did not finish (the app was closed by the system, crashed, or
/// the iPad ran out of power) can be saved where it was meant to go.
public struct RecordingRecoveryManifest: Codable, Equatable, Sendable {
    /// The vault's identifier in Graphite's vault list.
    public var vaultIdentifier: UUID?
    /// The vault path of the `.m4a` or `.mp4` file the recording becomes.
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
    /// The recording's file; for a video recorded in several parts, the first of them.
    public let mediaLocation: URL
    /// The parts a video was recorded in after its first, in order. A video starts a new
    /// part each time the camera is taken away and given back; audio has none.
    public let laterPartLocations: [URL]
    public let manifest: RecordingRecoveryManifest?
    public let startedAt: Date
    /// The size of every part together.
    public let byteCount: Int
    public var id: URL { mediaLocation }

    public init(mediaLocation: URL, laterPartLocations: [URL] = [], manifest: RecordingRecoveryManifest?, startedAt: Date, byteCount: Int) {
        self.mediaLocation = mediaLocation; self.laterPartLocations = laterPartLocations
        self.manifest = manifest; self.startedAt = startedAt; self.byteCount = byteCount
    }

    public var destination: VaultPath? { manifest.flatMap { manifest in try? VaultPath(manifest.destinationPath) } }
    public var kind: RecordingKind { RecordingKind(recoveryFileExtension: mediaLocation.pathExtension) ?? .audio }
    /// Every part, in the order it was recorded.
    public var partLocations: [URL] { [mediaLocation] + laterPartLocations }
}

/// The folder of unfinished recordings, in Application Support: the recordings are the
/// user's, never a cache, and stay there until they are saved into a vault or deleted.
public enum RecordingRecoveryFolder {
    public static let mediaExtensions: Set<String> = ["caf", "m4a", "mp4"]

    public static func location() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = support.appendingPathComponent("Graphite/Recovery/Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    public static func manifestLocation(for mediaLocation: URL) -> URL {
        mediaLocation.deletingPathExtension().appendingPathExtension("json")
    }

    public static func write(_ manifest: RecordingRecoveryManifest, for mediaLocation: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: manifestLocation(for: mediaLocation), options: .atomic)
    }

    public static func manifest(for mediaLocation: URL) -> RecordingRecoveryManifest? {
        guard let data = try? Data(contentsOf: manifestLocation(for: mediaLocation)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RecordingRecoveryManifest.self, from: data)
    }

    /// Files this size or smaller hold a header and no audio (a CAF's header takes 4 KiB).
    public static let largestFileWithoutAudio = 4_096

    private static let laterPartMarker = ".part-"

    /// Where part `partNumber` of the video whose first part is `firstPartLocation` is
    /// written: "Name.part-2.mp4" beside "Name.mp4". Part 1 is the first part itself.
    public static func partLocation(_ partNumber: Int, ofRecordingAt firstPartLocation: URL) -> URL {
        guard partNumber > 1 else { return firstPartLocation }
        return firstPartLocation.deletingPathExtension()
            .appendingPathExtension("part-\(partNumber)")
            .appendingPathExtension(firstPartLocation.pathExtension)
    }

    /// Where the parts of a video are joined into one file before it is saved into the
    /// vault: a hidden file, so a join that was cut short is never offered as a recording.
    public static func combinedMovieLocation(forRecordingAt firstPartLocation: URL) -> URL {
        firstPartLocation.deletingLastPathComponent()
            .appendingPathComponent("." + firstPartLocation.deletingPathExtension().lastPathComponent + ".joined." + firstPartLocation.pathExtension)
    }

    /// The parts after the first of the video at `firstPartLocation`, in order.
    public static func laterPartLocations(ofRecordingAt firstPartLocation: URL) -> [URL] {
        let folder = firstPartLocation.deletingLastPathComponent()
        guard let locations = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        return locations.compactMap { location -> (partNumber: Int, location: URL)? in
            guard let part = laterPart(location), part.firstPartName == firstPartLocation.lastPathComponent else { return nil }
            return (part.partNumber, location)
        }
        .sorted { first, second in first.partNumber < second.partNumber }.map(\.location)
    }

    /// The first part's name and this file's part number, for a file `partLocation` names.
    private static func laterPart(_ location: URL) -> (firstPartName: String, partNumber: Int)? {
        let stem = location.deletingPathExtension().lastPathComponent
        guard let markerRange = stem.range(of: laterPartMarker, options: .backwards),
              let partNumber = Int(stem[markerRange.upperBound...]), partNumber > 1 else { return nil }
        return (String(stem[..<markerRange.lowerBound]) + "." + location.pathExtension, partNumber)
    }

    /// Recordings in `folder` other than the one being made, oldest first. Files with no
    /// audio, which hold nothing to recover, are left out. The later parts of a video are
    /// listed with its first part, and on their own only when that part is gone.
    public static func recordings(in folder: URL, excluding activeLocation: URL? = nil) -> [RecoverableRecording] {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .creationDateKey, .isRegularFileKey]
        guard let locations = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return [] }
        let active = activeLocation?.standardizedFileURL.resolvingSymlinksInPath().path
        var byteCounts: [URL: Int] = [:]
        var creationDates: [URL: Date] = [:]
        for location in locations {
            guard mediaExtensions.contains(location.pathExtension.lowercased()),
                  let values = try? location.resourceValues(forKeys: keys), values.isRegularFile == true,
                  let byteCount = values.fileSize, byteCount > largestFileWithoutAudio else { continue }
            byteCounts[location] = byteCount
            creationDates[location] = values.creationDate
        }
        let namesWithMedia = Set(byteCounts.keys.map(\.lastPathComponent))
        var laterParts: [String: [(partNumber: Int, location: URL)]] = [:]
        var firstParts: [URL] = []
        for location in byteCounts.keys {
            if let part = laterPart(location), namesWithMedia.contains(part.firstPartName) || part.firstPartName == activeLocation?.lastPathComponent {
                laterParts[part.firstPartName, default: []].append((part.partNumber, location))
            } else {
                firstParts.append(location)
            }
        }
        return firstParts.compactMap { location -> RecoverableRecording? in
            guard location.standardizedFileURL.resolvingSymlinksInPath().path != active else { return nil }
            let parts = (laterParts[location.lastPathComponent] ?? []).sorted { first, second in first.partNumber < second.partNumber }.map(\.location)
            // A later part whose first part is gone still belongs where that part was going.
            let manifest = manifest(for: laterPart(location).map { part in folder.appendingPathComponent(part.firstPartName) } ?? location)
            let byteCount = ([location] + parts).reduce(0) { total, part in total + (byteCounts[part] ?? 0) }
            return RecoverableRecording(mediaLocation: location, laterPartLocations: parts, manifest: manifest,
                                        startedAt: manifest?.startedAt ?? creationDates[location] ?? .distantPast, byteCount: byteCount)
        }
        .sorted { first, second in first.startedAt < second.startedAt }
    }

    /// Deletes a recording, with its later parts and its manifest, once it is saved or the
    /// person discards it.
    public static func remove(_ recording: RecoverableRecording) throws {
        try FileManager.default.removeItem(at: recording.mediaLocation)
        for partLocation in recording.laterPartLocations { try? FileManager.default.removeItem(at: partLocation) }
        try? FileManager.default.removeItem(at: combinedMovieLocation(forRecordingAt: recording.mediaLocation))
        try? FileManager.default.removeItem(at: manifestLocation(for: recording.mediaLocation))
    }
}
