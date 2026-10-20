import Foundation
import Observation
import GraphiteCore

/// The vault's pronunciation file as Settings › Read Aloud › Pronunciations shows and changes it.
/// An edit is made to what the file holds when it is saved, never to the list shown when the
/// page opened, so a term that reached the file since (from another device, through iCloud)
/// is kept; and the file is replaced only while it is still what was just read.
@MainActor @Observable
final class ReadAloudPronunciationVaultFile {
    /// Why a save wrote nothing although the file could be read.
    enum SaveRefusal: Error {
        /// The file now holds something a rewrite would lose; `reading` says what.
        case fileCannotBeRewritten
    }

    /// What the file held when it was last read.
    private(set) var reading: ReadAloudPronunciations.VaultFileReading = .noFile
    @ObservationIgnored private let location: URL?
    @ObservationIgnored private let writer = AtomicFileWriter()

    init(vaultRoot: URL?) {
        location = vaultRoot?.appendingPathComponent(ReadAloudPronunciations.vaultFilePath)
    }

    /// Whether a vault is open, so there is a file to change.
    var hasVault: Bool { location != nil }

    /// The terms shown, from the last reading.
    var entries: [ReadAloudPronunciations.VaultEntry] {
        if case .loaded(let entries, _) = reading { entries } else { [] }
    }

    func reload() {
        reading = location.map(ReadAloudPronunciations.readVaultFile(at:)) ?? .noFile
    }

    /// Makes `edit` to the terms the file holds now and writes the file whole.
    /// - Throws: `SaveRefusal.fileCannotBeRewritten` when the file holds something a rewrite
    ///   would lose, `GraphiteError.conflict` when it changed while it was being saved, or the
    ///   write's own error. The file is then left as it was.
    func save(_ edit: ReadAloudPronunciations.VaultFileEdit) throws {
        guard let location else { return }
        let (currentReading, expectation) = readingForRewrite(at: location)
        reading = currentReading
        guard let expectation, let updatedEntries = ReadAloudPronunciations.vaultEntries(applying: edit, to: currentReading) else {
            throw SaveRefusal.fileCannotBeRewritten
        }
        let data = try ReadAloudPronunciations.vaultFileData(for: updatedEntries)
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writer.write(data, to: location, expecting: expectation)
        reload()
    }

    /// The file as it is now, with what a write must find to replace exactly this; no
    /// expectation when the file could not be read.
    private func readingForRewrite(at location: URL) -> (ReadAloudPronunciations.VaultFileReading, WriteExpectation?) {
        guard FileManager.default.fileExists(atPath: location.path) else { return (.noFile, .absent) }
        do {
            let snapshot = try writer.read(location)
            return (ReadAloudPronunciations.readVaultFile(data: snapshot.data), .revision(snapshot.revision))
        } catch {
            let readError = error as NSError
            return (.readFailed(errorDomain: readError.domain, errorCode: readError.code), nil)
        }
    }
}
