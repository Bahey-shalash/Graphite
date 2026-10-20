import XCTest
import GraphiteCore
@testable import GraphiteVoices
import GraphiteTestSupport

/// Answers every download request by never finishing, and tells the test what the request was
/// and how the downloader described its task.
private final class StalledDownloadProtocol: URLProtocol {
    struct Request: Equatable {
        let address: URL?
        let taskDescription: String?
    }

    nonisolated(unsafe) static var onRequest: (@Sendable (Request) -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.onRequest?(Request(address: request.url, taskDescription: task?.taskDescription))
    }

    override func stopLoading() {}
}

/// The background download session's name, how a download task names the voice and file it
/// belongs to (so tasks of an earlier launch can be matched again), and where resume data
/// is kept.
final class NeuralVoiceDownloaderTaskDescriptionTests: XCTestCase {
    private var voicesFolder: URL!
    private let reports = ReportLog()

    final class ReportLog: @unchecked Sendable {
        private let lock = NSLock()
        private var states: [(voice: String, state: NeuralVoiceDownloadState)] = []
        var onReport: (@Sendable (String, NeuralVoiceDownloadState) -> Void)?

        func record(_ voice: String, _ state: NeuralVoiceDownloadState) {
            lock.withLock { states.append((voice, state)) }
            onReport?(voice, state)
        }

        var all: [(voice: String, state: NeuralVoiceDownloadState)] { lock.withLock { states } }
    }

    override func setUpWithError() throws {
        voicesFolder = try TemporaryVault.make(prefix: "NeuralVoiceDownloads", for: self).root
    }

    override func tearDownWithError() throws {
        StalledDownloadProtocol.onRequest = nil
        try? FileManager.default.removeItem(at: voicesFolder) // Best-effort removal of a temporary folder.
    }

    private func makeVoice() -> NeuralVoiceDescription {
        NeuralVoiceDescription(
            id: "test-voice", name: "Test Voice", modelName: "Test model", modelFamily: .pocketTTS, speaker: nil, language: "en",
            qualityNote: "A test voice.", license: NeuralVoiceLicense(name: "Test", address: URL(string: "https://example.com/license")!),
            sources: [NeuralVoiceSource(repository: "owner/model", revision: "abc123", files: [
                NeuralVoiceFile(path: "weights/model.safetensors", byteCount: 1_000, sha256: String(repeating: "0", count: 64))
            ])],
            platforms: ["macOS", "iOS"], minimumPhysicalMemoryBytes: 0)
    }

    private func makeDownloader(for voice: NeuralVoiceDescription) -> (NeuralVoiceDownloader, NeuralVoiceInstallation) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StalledDownloadProtocol.self]
        let installation = NeuralVoiceInstallation(voicesFolder: voicesFolder)
        let manifest = NeuralVoiceManifest(downloadHost: URL(string: "https://voices.example.com")!, voices: [voice])
        let reports = reports
        let downloader = NeuralVoiceDownloader(manifest: manifest, installation: installation, configuration: configuration) { voiceIdentifier, state in
            reports.record(voiceIdentifier, state)
        }
        return (downloader, installation)
    }

    private func makeTask(described description: String?) -> URLSessionTask {
        let task = URLSession(configuration: .ephemeral).downloadTask(with: URL(string: "https://voices.example.com/unused")!)
        task.taskDescription = description
        return task
    }

    func testTheBackgroundSessionIsIdentifiedByTheAppsVoiceDownloadsName() {
        XCTAssertEqual(NeuralVoiceDownloader.sessionIdentifier, "com.graphite.study.voice-downloads")
    }

    func testADownloadTaskIsDescribedByTheVoiceIdentifierAndTheFilesLocalPathOnTwoLines() async throws {
        let voice = makeVoice()
        let (downloader, installation) = makeDownloader(for: voice)
        let requested = expectation(description: "The file is requested")
        nonisolated(unsafe) var request: StalledDownloadProtocol.Request?
        StalledDownloadProtocol.onRequest = { received in request = received; requested.fulfill() }

        downloader.download(voice)
        await fulfillment(of: [requested], timeout: 30)

        XCTAssertEqual(request?.taskDescription, "test-voice\nweights/model.safetensors")
        XCTAssertEqual(request?.address?.absoluteString, "https://voices.example.com/owner/model/resolve/abc123/weights/model.safetensors")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installation.stagingFolder(of: voice).path), "Files arrive in the voice's .partial folder.")
        downloader.remove(voice)
    }

    func testATaskOfAnEarlierLaunchIsMatchedByItsDescriptionAndAnUnknownVoiceIsIgnored() async throws {
        let voice = makeVoice()
        let (downloader, _) = makeDownloader(for: voice)
        let session = URLSession(configuration: .ephemeral)

        downloader.urlSession(session, task: makeTask(described: "other-voice\nweights/model.safetensors"), didCompleteWithError: nil)
        downloader.urlSession(session, task: makeTask(described: "test-voice"), didCompleteWithError: nil)
        downloader.urlSession(session, task: makeTask(described: "test-voice\nunknown/file.bin"), didCompleteWithError: nil)
        downloader.urlSession(session, task: makeTask(described: nil), didCompleteWithError: nil)
        XCTAssertTrue(reports.all.isEmpty, "A task that names no known voice and file changes nothing.")

        let reported = expectation(description: "The known task is matched")
        reports.onReport = { _, _ in reported.fulfill() }
        downloader.urlSession(session, task: makeTask(described: "test-voice\nweights/model.safetensors"), didCompleteWithError: nil)
        await fulfillment(of: [reported], timeout: 30)

        XCTAssertEqual(reports.all.map(\.voice), ["test-voice"])
        XCTAssertEqual(reports.all.first?.state, .paused(receivedBytes: 0, totalBytes: 1_000), "The voice is incomplete, so it waits.")
    }

    /// BUG-VOICE-06: A file that fails its checksum keeps the voice's failure reason after URLSession reports
    /// the task complete; the completion must not replace it with Paused.
    func testAFileThatFailsItsChecksumKeepsItsFailureReasonAfterItsTaskCompletes() async throws {
        let voice = makeVoice()
        let (downloader, installation) = makeDownloader(for: voice)
        let session = URLSession(configuration: .ephemeral)
        let task = session.downloadTask(with: URL(string: "https://voices.example.com/unused")!)
        task.taskDescription = "test-voice\nweights/model.safetensors"
        let downloadedFile = voicesFolder.appendingPathComponent("downloaded-file")
        try Data(repeating: 7, count: 1_000).write(to: downloadedFile)

        downloader.urlSession(session, downloadTask: task, didFinishDownloadingTo: downloadedFile)
        guard case .failed(let reason)? = reports.all.last?.state else { return XCTFail("Expected the checksum failure, got \(reports.all)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: installation.stagingFolder(of: voice).appendingPathComponent("weights/model.safetensors").path),
                       "The file that failed its checksum is discarded.")

        let completed = expectation(description: "The completed task is handled")
        reports.onReport = { _, _ in completed.fulfill() }
        downloader.urlSession(session, task: task, didCompleteWithError: nil)
        await fulfillment(of: [completed], timeout: 30)

        XCTAssertEqual(reports.all.last?.state, .failed(reason), "The failure reason stays shown; it must not turn into Paused.")
    }

    func testResumeDataOfAStoppedFileIsKeptBesideItInTheStagingFolderWithADotResumeSuffix() async throws {
        let voice = makeVoice()
        let (downloader, installation) = makeDownloader(for: voice)
        let paused = expectation(description: "The voice is paused")
        reports.onReport = { _, state in if case .paused = state { paused.fulfill() } }
        downloader.pause(voice)
        await fulfillment(of: [paused], timeout: 30)
        let resumeData = Data("resume".utf8)
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost,
                            userInfo: [NSURLSessionDownloadTaskResumeData: resumeData])

        downloader.urlSession(URLSession(configuration: .ephemeral), task: makeTask(described: "test-voice\nweights/model.safetensors"), didCompleteWithError: error)

        let location = installation.stagingFolder(of: voice).appendingPathComponent("weights/model.safetensors.resume")
        XCTAssertEqual(try Data(contentsOf: location), resumeData)
    }
}
