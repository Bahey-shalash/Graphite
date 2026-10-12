import Foundation
import GraphiteCore

/// Where a voice's download stands.
public enum NeuralVoiceDownloadState: Equatable, Sendable {
    case notInstalled
    /// Bytes received so far out of the voice's total.
    case downloading(receivedBytes: Int64, totalBytes: Int64)
    /// Stopped by the person or by a lost connection; what arrived is kept and continues.
    case paused(receivedBytes: Int64, totalBytes: Int64)
    case verifying
    case installed
    case failed(String)
}

/// Downloads voices file by file with a background `URLSession`, so a download of several
/// gigabytes continues while Graphite is in the background or closed, and a lost connection
/// resumes where it stopped instead of starting over. Each file goes into the voice's staging
/// folder and is checked against its size and SHA-256 before the voice is installed.
public final class NeuralVoiceDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    // `@unchecked Sendable`: URLSession calls the delegate methods on `delegateQueue`, a serial
    // queue, and every mutable property below is touched only from that queue (public methods
    // hop onto it with `delegateQueue.addOperation`).
    public static let sessionIdentifier = "com.graphite.study.voice-downloads"
    /// A lost connection is retried from where it stopped this many times before the download
    /// pauses and waits for the person.
    private static let automaticRetryLimit = 3

    private let manifest: NeuralVoiceManifest
    private let installation: NeuralVoiceInstallation
    private let delegateQueue: OperationQueue
    private let report: @Sendable (String, NeuralVoiceDownloadState) -> Void
    private var session: URLSession!
    /// Bytes received per file of each voice being downloaded, by voice identifier then file path.
    private var receivedBytes: [String: [String: Int64]] = [:]
    private var retryCounts: [String: Int] = [:]
    private var pausedVoices: Set<String> = []

    /// `report` receives every state change, on a background queue.
    public init(manifest: NeuralVoiceManifest, installation: NeuralVoiceInstallation,
                configuration: URLSessionConfiguration? = nil,
                report: @escaping @Sendable (String, NeuralVoiceDownloadState) -> Void) {
        self.manifest = manifest
        self.installation = installation
        self.report = report
        delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.name = "graphite.voice-downloads"
        super.init()
        let sessionConfiguration = configuration ?? {
            let background = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
            background.isDiscretionary = false
            background.allowsExpensiveNetworkAccess = true
            #if os(iOS)
            background.sessionSendsLaunchEvents = true
            #endif
            return background
        }()
        session = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: delegateQueue)
        // Downloads started before the app was closed continue in the same session; find them.
        session.getAllTasks { [weak self] tasks in
            guard let self else { return }
            self.delegateQueue.addOperation {
                for task in tasks {
                    guard let target = self.target(of: task) else { continue }
                    self.receivedBytes[target.voice.id, default: [:]][target.file.localPath] = task.countOfBytesReceived
                }
                for voiceIdentifier in Set(tasks.compactMap { task in self.target(of: task)?.voice.id }) { self.reportProgress(of: voiceIdentifier) }
            }
        }
    }

    // MARK: Requests

    /// Downloads every file of the voice that is not already staged and verified, resuming
    /// partial files from where they stopped.
    public func download(_ voice: NeuralVoiceDescription) {
        delegateQueue.addOperation { [self] in
            pausedVoices.remove(voice.id)
            let staging = installation.stagingFolder(of: voice)
            try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            excludeFromBackup(installation.voicesFolder)
            session.getAllTasks { tasks in
                self.delegateQueue.addOperation {
                    let running = Set(tasks.filter { task in task.state == .running || task.state == .suspended }
                        .compactMap { task in self.target(of: task) }.filter { target in target.voice.id == voice.id }.map(\.file.localPath))
                    var startedAny = false
                    for source in voice.sources {
                        for file in source.files where !running.contains(file.localPath) {
                            let stagedFile = staging.appendingPathComponent(file.localPath)
                            if FileManager.default.fileExists(atPath: stagedFile.path), NeuralVoiceInstallation.verify(stagedFile, against: file) {
                                self.receivedBytes[voice.id, default: [:]][file.localPath] = file.byteCount
                                continue
                            }
                            let task: URLSessionDownloadTask
                            if let resumeData = try? Data(contentsOf: self.resumeDataFile(for: file, of: voice)) {
                                task = self.session.downloadTask(withResumeData: resumeData)
                            } else {
                                task = self.session.downloadTask(with: self.manifest.downloadAddress(of: file, in: source))
                            }
                            task.taskDescription = Self.taskDescription(voice: voice, file: file)
                            task.countOfBytesClientExpectsToReceive = file.byteCount
                            task.resume()
                            startedAny = true
                        }
                    }
                    if startedAny || !running.isEmpty { self.reportProgress(of: voice.id) } else { self.installIfComplete(voice) }
                }
            }
        }
    }

    /// Stops the voice's downloads, keeping what arrived so `download` continues from there.
    public func pause(_ voice: NeuralVoiceDescription) {
        delegateQueue.addOperation { [self] in
            pausedVoices.insert(voice.id)
            session.getAllTasks { tasks in
                for task in tasks {
                    guard let downloadTask = task as? URLSessionDownloadTask, self.target(of: task)?.voice.id == voice.id else { continue }
                    downloadTask.cancel { resumeData in
                        self.delegateQueue.addOperation {
                            if let resumeData, let target = self.target(of: task) { self.saveResumeData(resumeData, for: target.file, of: voice) }
                        }
                    }
                }
                self.delegateQueue.addOperation { self.reportPaused(voice.id) }
            }
        }
    }

    /// Cancels any download of the voice and deletes its files.
    public func remove(_ voice: NeuralVoiceDescription) {
        delegateQueue.addOperation { [self] in
            pausedVoices.insert(voice.id)
            session.getAllTasks { tasks in
                for task in tasks where self.target(of: task)?.voice.id == voice.id { task.cancel() }
                self.delegateQueue.addOperation {
                    self.receivedBytes[voice.id] = nil
                    do {
                        try self.installation.remove(voice)
                        self.report(voice.id, .notInstalled)
                    } catch {
                        self.report(voice.id, .failed("The voice could not be deleted: \(error.localizedDescription)"))
                    }
                    self.pausedVoices.remove(voice.id)
                }
            }
        }
    }

    // MARK: URLSession delegate

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                           totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let target = target(of: downloadTask) else { return }
        receivedBytes[target.voice.id, default: [:]][target.file.localPath] = totalBytesWritten
        reportProgress(of: target.voice.id)
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let target = target(of: downloadTask) else { return }
        if let response = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            report(target.voice.id, .failed("The download server answered \(response.statusCode). Try again later."))
            return
        }
        // The temporary file disappears when this method returns, so it is moved first and
        // checked afterwards.
        let stagedFile = installation.stagingFolder(of: target.voice).appendingPathComponent(target.file.localPath)
        do {
            try FileManager.default.createDirectory(at: stagedFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: stagedFile.path) { try FileManager.default.removeItem(at: stagedFile) }
            try FileManager.default.moveItem(at: location, to: stagedFile)
        } catch {
            report(target.voice.id, .failed("The downloaded file could not be saved: \(error.localizedDescription)"))
            return
        }
        try? FileManager.default.removeItem(at: resumeDataFile(for: target.file, of: target.voice))
        guard NeuralVoiceInstallation.verify(stagedFile, against: target.file) else {
            try? FileManager.default.removeItem(at: stagedFile)
            receivedBytes[target.voice.id]?[target.file.localPath] = 0
            report(target.voice.id, .failed("\(target.file.path) did not match its published checksum, so it was discarded. Download again."))
            return
        }
        receivedBytes[target.voice.id, default: [:]][target.file.localPath] = target.file.byteCount
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let target = target(of: task) else { return }
        guard let error else {
            installIfCompleteWhenIdle(target.voice)
            return
        }
        let nsError = error as NSError
        if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            saveResumeData(resumeData, for: target.file, of: target.voice)
        }
        guard !pausedVoices.contains(target.voice.id), nsError.code != NSURLErrorCancelled else { return }
        let retryKey = target.voice.id + "/" + target.file.localPath
        let retries = retryCounts[retryKey, default: 0]
        if retries < Self.automaticRetryLimit {
            retryCounts[retryKey] = retries + 1
            download(target.voice)
        } else {
            retryCounts[retryKey] = 0
            reportPaused(target.voice.id)
        }
    }

    #if os(iOS)
    /// The system woke Graphite to deliver finished downloads; once they are handled, the
    /// stored completion handler tells the system it may suspend the app again.
    private var backgroundEventsCompletion: (@Sendable () -> Void)?

    public func setBackgroundEventsCompletion(_ completion: @escaping @Sendable () -> Void) {
        delegateQueue.addOperation { [self] in backgroundEventsCompletion = completion }
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completion = backgroundEventsCompletion
        backgroundEventsCompletion = nil
        DispatchQueue.main.async { completion?() }
    }
    #endif

    // MARK: Helpers

    private static func taskDescription(voice: NeuralVoiceDescription, file: NeuralVoiceFile) -> String {
        voice.id + "\n" + file.localPath
    }

    private func target(of task: URLSessionTask) -> (voice: NeuralVoiceDescription, file: NeuralVoiceFile)? {
        let parts = (task.taskDescription ?? "").split(separator: "\n", maxSplits: 1).map(String.init)
        guard parts.count == 2, let voice = manifest.voice(identifier: parts[0]),
              let file = voice.files.first(where: { file in file.localPath == parts[1] }) else { return nil }
        return (voice, file)
    }

    private func resumeDataFile(for file: NeuralVoiceFile, of voice: NeuralVoiceDescription) -> URL {
        installation.stagingFolder(of: voice).appendingPathComponent(file.localPath + ".resume")
    }

    private func saveResumeData(_ resumeData: Data, for file: NeuralVoiceFile, of voice: NeuralVoiceDescription) {
        let destination = resumeDataFile(for: file, of: voice)
        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? resumeData.write(to: destination, options: .atomic)
    }

    private func totals(of voiceIdentifier: String) -> (received: Int64, total: Int64)? {
        guard let voice = manifest.voice(identifier: voiceIdentifier) else { return nil }
        let received = voice.files.reduce(Int64(0)) { sum, file in sum + min(file.byteCount, receivedBytes[voiceIdentifier]?[file.localPath] ?? 0) }
        return (received, voice.byteCount)
    }

    private func reportProgress(of voiceIdentifier: String) {
        guard let totals = totals(of: voiceIdentifier) else { return }
        report(voiceIdentifier, .downloading(receivedBytes: totals.received, totalBytes: totals.total))
    }

    private func reportPaused(_ voiceIdentifier: String) {
        guard let totals = totals(of: voiceIdentifier) else { return }
        report(voiceIdentifier, .paused(receivedBytes: totals.received, totalBytes: totals.total))
    }

    private func installIfCompleteWhenIdle(_ voice: NeuralVoiceDescription) {
        session.getAllTasks { tasks in
            self.delegateQueue.addOperation {
                let stillRunning = tasks.contains { task in self.target(of: task)?.voice.id == voice.id && task.state == .running }
                if !stillRunning { self.installIfComplete(voice) }
            }
        }
    }

    /// Installs the voice when every file is staged and verified.
    private func installIfComplete(_ voice: NeuralVoiceDescription) {
        let staging = installation.stagingFolder(of: voice)
        let complete = voice.files.allSatisfy { file in
            (receivedBytes[voice.id]?[file.localPath] ?? 0) == file.byteCount
                && FileManager.default.fileExists(atPath: staging.appendingPathComponent(file.localPath).path)
        }
        guard complete else {
            if !pausedVoices.contains(voice.id) { reportPaused(voice.id) }
            return
        }
        report(voice.id, .verifying)
        do {
            try installation.finishInstalling(voice)
            receivedBytes[voice.id] = nil
            report(voice.id, .installed)
        } catch {
            report(voice.id, .failed("The voice could not be installed: \(error.localizedDescription)"))
        }
    }

    private func excludeFromBackup(_ folder: URL) {
        var folder = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
    }
}
