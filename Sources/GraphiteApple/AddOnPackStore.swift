import Foundation
import GraphiteCore

/// Where add-on packs live on the device and how they get there: each pack in a folder of its
/// own below Application Support (never in a vault), downloaded into a staging folder first
/// and moved into place only once every file's size and SHA-256 matched. A marker file names
/// the revision installed, so a folder left by an interrupted download, or the files of an
/// older revision, are never taken for the pack.
public struct AddOnPackStore: Sendable {
    /// The folder holding one folder per pack.
    public let packsFolder: URL

    public init(packsFolder: URL) {
        self.packsFolder = packsFolder
    }

    /// The store in `applicationSupportFolder`, or in the system's Application Support folder.
    public static func inApplicationSupport(_ applicationSupportFolder: URL?) throws -> AddOnPackStore {
        let base = try applicationSupportFolder
            ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return AddOnPackStore(packsFolder: base.appendingPathComponent("Graphite/Add-ons", isDirectory: true))
    }

    static let markerFileName = ".graphite-installed"

    public enum InstallError: Error, Equatable {
        /// The server answered with something other than the file.
        case unexpectedResponse(fileName: String, statusCode: Int)
        /// The file arrived, but its size or SHA-256 is not the pack's.
        case fileDoesNotMatch(fileName: String)
    }

    public func folder(of pack: AddOnPack) -> URL {
        packsFolder.appendingPathComponent(pack.id, isDirectory: true)
    }

    func stagingFolder(of pack: AddOnPack) -> URL {
        packsFolder.appendingPathComponent(pack.id + ".partial", isDirectory: true)
    }

    /// Whether the pack's current revision is complete on the device.
    public func isInstalled(_ pack: AddOnPack) -> Bool {
        let markerFile = folder(of: pack).appendingPathComponent(Self.markerFileName)
        guard let marker = try? String(contentsOf: markerFile, encoding: .utf8), marker == pack.revision else { return false }
        return pack.files.allSatisfy { file in FileManager.default.fileExists(atPath: folder(of: pack).appendingPathComponent(file.name).path) }
    }

    /// Where an installed pack keeps `file`, or nil while the pack is not installed.
    public func location(of file: AddOnFile, in pack: AddOnPack) -> URL? {
        isInstalled(pack) ? folder(of: pack).appendingPathComponent(file.name) : nil
    }

    /// Downloads every file of the pack with `session`, one at a time, checks each, and moves
    /// the whole pack into place. Nothing changes on the device if any file fails.
    public func install(_ pack: AddOnPack, using session: URLSession) async throws {
        let fileManager = FileManager.default
        let staging = stagingFolder(of: pack)
        try? fileManager.removeItem(at: staging) // what an earlier, interrupted download left
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            for file in pack.files {
                try Task.checkCancellation()
                let (downloadedFile, response) = try await session.download(from: pack.address(of: file))
                if let response = response as? HTTPURLResponse, response.statusCode != 200 {
                    throw InstallError.unexpectedResponse(fileName: file.name, statusCode: response.statusCode)
                }
                guard Self.verify(downloadedFile, against: file) else { throw InstallError.fileDoesNotMatch(fileName: file.name) }
                try fileManager.moveItem(at: downloadedFile, to: staging.appendingPathComponent(file.name))
            }
            try pack.revision.write(to: staging.appendingPathComponent(Self.markerFileName), atomically: true, encoding: .utf8)
            let destination = folder(of: pack)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
            } else {
                try fileManager.moveItem(at: staging, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: staging) // best effort: the pack stays as it was
            throw error
        }
    }

    /// Removes the pack's files from the device. It is downloaded again when next needed.
    public func remove(_ pack: AddOnPack) throws {
        let fileManager = FileManager.default
        for folder in [folder(of: pack), stagingFolder(of: pack)] where fileManager.fileExists(atPath: folder.path) {
            try fileManager.removeItem(at: folder)
        }
    }

    /// Whether a downloaded file is complete: the right size and the right SHA-256.
    static func verify(_ fileURL: URL, against file: AddOnFile) -> Bool {
        DownloadedFileCheck.matches(fileURL, byteCount: file.byteCount, sha256: file.sha256)
    }
}
