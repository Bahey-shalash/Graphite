import XCTest
import GraphiteCore
import GraphiteApple
import NotebookImport
import GraphiteFixtures
import GraphiteTestSupport
@testable import GraphiteUI

/// An import of notebooks into a vault, run as the workspace runs it but on a temporary vault: a chosen notebook goes
/// into the destination folder, a chosen folder becomes a folder of its name with its subfolders kept, every file takes
/// a free name, recordings go beside their PDF, and a source is never changed.
final class NotebookImportRunTests: XCTestCase {
    private let lecture = FixtureFolders.syntheticNotebooks.appendingPathComponent("Synthetic lecture.goodnotes")
    private let note = FixtureFolders.syntheticNotebooks.appendingPathComponent("Synthetic note.note")

    /// The files the run said it wrote, as the workspace hears them on the main actor.
    @MainActor private final class WrittenFiles {
        var paths: [VaultPath] = []
    }

    private static func run(_ sources: [URL], into destination: VaultPath, vault: TemporaryVault, written: WrittenFiles) async -> NotebookImportSummary {
        let store = VaultStore(root: vault.root)
        let importVault = NotebookImportVault(freePath: { folder, stem, fileExtension in
                                                  try await store.uniquePath(directory: folder, stem: stem, extension: fileExtension)
                                              },
                                              makeFolder: { folder in try await store.createDirectory(folder) },
                                              location: { path in try path.url(in: vault.root) },
                                              fileWriter: store.writer,
                                              filesDidChange: { paths in written.paths += paths })
        let run = NotebookImportRun(vault: importVault, conversion: NotebookConversion(fileWriter: store.writer), limits: .standard,
                                    strokeCreationDate: Date(timeIntervalSinceReferenceDate: 0))
        let (progress, continuation) = AsyncStream.makeStream(of: NotebookImportProgress.self)
        let summary = await run.run(sources: sources, into: destination, progress: continuation)
        continuation.finish()
        var lastProgress: NotebookImportProgress?
        for await update in progress { lastProgress = update }
        XCTAssertEqual(lastProgress?.notebookCount, summary.outcomes.count)
        return summary
    }

    func testChosenNotebooksGoIntoTheFolderUnderFreeNamesWithTheirRecordingsBeside() async throws {
        let vault = try TemporaryVault.make(prefix: "NotebookImportRun", files: ["Courses/Synthetic lecture.pdf": "taken"], for: self)
        let written = WrittenFiles()
        let summary = await Self.run([lecture, note], into: try VaultPath("Courses"), vault: vault, written: written)
        XCTAssertEqual(summary.importedCount, 2)
        XCTAssertEqual(summary.outcomes.map(\.sourceName), ["Synthetic lecture.goodnotes", "Synthetic note.note"])
        XCTAssertEqual(summary.outcomes.compactMap(\.importedNotebook?.pdf.rawValue), ["Courses/Synthetic lecture 1.pdf", "Courses/Synthetic note.pdf"])
        XCTAssertEqual(summary.outcomes.compactMap(\.importedNotebook).flatMap(\.recordings).map(\.rawValue),
                       ["Courses/Synthetic lecture 1 - Recording 1.m4a", "Courses/Synthetic note - Lecture.m4a"])
        let writtenCount = await written.paths.count
        XCTAssertEqual(writtenCount, 4)
        XCTAssertEqual(try String(contentsOf: vault.location(of: "Courses/Synthetic lecture.pdf"), encoding: .utf8), "taken")
        XCTAssertFalse(summary.wasCancelled)
    }

    func testAChosenFolderKeepsItsFoldersAndReportsWhatItHeldBesidesNotebooks() async throws {
        let export = try TemporaryVault.make(prefix: "NotebookLibraryExport", for: self)
        try export.writeFile("Semester/Physics/Week 1/Lecture.goodnotes", data: Data(contentsOf: lecture))
        try export.writeFile("Semester/Physics/Broken.goodnotes", text: "not a notebook")
        try export.writeFile("Semester/Syllabus.pdf", text: "%PDF")
        try export.writeFile("Empty/Readme.txt", text: "nothing")
        let vault = try TemporaryVault.make(prefix: "NotebookImportRun", files: ["Semester/Kept.md": "an existing folder"], for: self)
        let sources = [export.location(of: "Semester/"), export.location(of: "Empty/")]
        let summary = await Self.run(sources, into: .root, vault: vault, written: WrittenFiles())
        XCTAssertEqual(summary.outcomes.map(\.sourceName), ["Broken.goodnotes", "Lecture.goodnotes"])
        XCTAssertEqual(summary.outcomes.first?.result, .failed(.notANotebook(.goodnotes)))
        XCTAssertEqual(summary.outcomes.last?.importedNotebook?.pdf.rawValue, "Semester 1/Physics/Week 1/Lecture.pdf",
                       "The folder takes a free name, so an import never mixes with a folder already there.")
        XCTAssertEqual(summary.otherFileCount, 2)
        XCTAssertEqual(summary.foldersWithoutNotebooks, ["Empty"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.location(of: "Empty").path), "Nothing is made for a folder without notebooks.")
    }

    func testACancelledImportStartsNoFurtherNotebook() async throws {
        let vault = try TemporaryVault.make(prefix: "NotebookImportRun", for: self)
        let written = WrittenFiles()
        let task = Task.detached { [lecture, note] in
            withUnsafeCurrentTask { task in task?.cancel() }
            return await Self.run([lecture, note], into: .root, vault: vault, written: written)
        }
        let summary = await task.value
        XCTAssertTrue(summary.wasCancelled)
        XCTAssertEqual(summary.outcomes.map(\.result), [.notStarted, .notStarted])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: vault.root.path), [])
    }
}
