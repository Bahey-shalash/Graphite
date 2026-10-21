import Foundation
import GraphiteCore
import GraphiteApple

/// Where a voice's files live on disk and whether they are complete. A voice is installed
/// only once every file was downloaded and its checksum matched, which is recorded in a
/// marker file naming the revisions; a folder left by an interrupted download is never
/// mistaken for a voice.
public struct NeuralVoiceInstallation: Sendable {
    public let voicesFolder: URL

    public init(voicesFolder: URL) {
        self.voicesFolder = voicesFolder
    }

    static let markerFileName = ".graphite-installed"

    public func folder(of voice: NeuralVoiceDescription) -> URL {
        voicesFolder.appendingPathComponent(voice.id, isDirectory: true)
    }

    /// Files of a download in progress, kept apart until all of them are verified.
    public func stagingFolder(of voice: NeuralVoiceDescription) -> URL {
        voicesFolder.appendingPathComponent(voice.id + ".partial", isDirectory: true)
    }

    private static func marker(of voice: NeuralVoiceDescription) -> String {
        voice.sources.map { source in "\(source.repository)@\(source.revision)" }.joined(separator: "\n")
    }

    public func isInstalled(_ voice: NeuralVoiceDescription) -> Bool {
        let markerFile = folder(of: voice).appendingPathComponent(Self.markerFileName)
        guard let marker = try? String(contentsOf: markerFile, encoding: .utf8), marker == Self.marker(of: voice) else { return false }
        return voice.files.allSatisfy { file in
            FileManager.default.fileExists(atPath: folder(of: voice).appendingPathComponent(file.localPath).path)
        }
    }

    /// Whether a staged file is complete: the right size and the right SHA-256.
    public static func verify(_ fileURL: URL, against file: NeuralVoiceFile) -> Bool {
        DownloadedFileCheck.matches(fileURL, byteCount: file.byteCount, sha256: file.sha256)
    }

    /// Moves a fully verified staging folder into place and marks the voice installed.
    public func finishInstalling(_ voice: NeuralVoiceDescription) throws {
        let staging = stagingFolder(of: voice)
        for file in voice.files where !FileManager.default.fileExists(atPath: staging.appendingPathComponent(file.localPath).path) {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: file.localPath])
        }
        try Self.marker(of: voice).write(to: staging.appendingPathComponent(Self.markerFileName), atomically: true, encoding: .utf8)
        let destination = folder(of: voice)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: staging, to: destination)
    }

    /// Removes the voice and anything left of a download.
    public func remove(_ voice: NeuralVoiceDescription) throws {
        for folder in [folder(of: voice), stagingFolder(of: voice)] where FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    /// Space the voice's files take on disk, installed or partly downloaded.
    public func bytesOnDisk(of voice: NeuralVoiceDescription) -> Int64 {
        [folder(of: voice), stagingFolder(of: voice)].reduce(Int64(0)) { total, folder in
            guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return total }
            var sum = total
            for case let file as URL in enumerator {
                sum += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            return sum
        }
    }
}
