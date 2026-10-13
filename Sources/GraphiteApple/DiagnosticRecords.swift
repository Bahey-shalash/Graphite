import Foundation
import os

/// Evidence of freezes, kept on the device for the developer: the system's hang and crash
/// reports (`MetricKitDiagnostics`), Graphite's own record of a main thread that stopped
/// answering (`MainThreadWatchdog`), and of a page that stopped taking touches. Each is a
/// small JSON file in `Library/Diagnostics` of the app's container, which is outside the
/// vault and never synced. `~/.graphite-tools/fetch-diagnostics.sh` copies the folder off an
/// iPad. Only the newest `maximumFileCount` files are kept.
public enum DiagnosticRecords {
    public static let folderName = "Diagnostics"
    public static let maximumFileCount = 80

    /// Writes happen in order, away from the thread that asks: the watchdog asks from its own
    /// thread while the main thread is stuck, and views ask from the main thread.
    private static let writeQueue = DispatchQueue(label: "com.graphite.study.diagnostic-records", qos: .utility)
    private static let log = Logger(subsystem: "com.graphite.study", category: "Diagnostics")

    public static var folder: URL? {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent(folderName, isDirectory: true)
    }

    /// Writes a record named after its kind and the time, such as
    /// `MainThreadStall-2026-10-13T13-43-02.512Z.json`.
    /// - Parameter fields: Values `JSONSerialization` accepts: strings, numbers, booleans,
    ///   arrays and dictionaries of them.
    public static func write(kind: String, fields: [String: Any], date: Date = Date()) {
        var record = fields
        record["kind"] = kind
        record["date"] = timestamp(date)
        record["context"] = DiagnosticContext.snapshot()
        guard JSONSerialization.isValidJSONObject(record),
              let data = try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]) else {
            log.error("A \(kind, privacy: .public) record could not be encoded")
            return
        }
        write(data, named: "\(kind)-\(fileTimestamp(date)).json")
        log.notice("Recorded \(kind, privacy: .public)")
    }

    /// Writes data already encoded, such as a MetricKit payload. A file of the same name is
    /// left as it is, so a payload delivered twice is kept once.
    public static func write(_ data: Data, named fileName: String) {
        writeQueue.async {
            guard let folder else { return }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let location = folder.appendingPathComponent(fileName)
                guard !FileManager.default.fileExists(atPath: location.path) else { return }
                try data.write(to: location, options: .atomic)
                removeOldestFiles(in: folder)
            } catch {
                log.error("A diagnostic record could not be written: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Waits until the records asked for so far are on disk; for tests.
    public static func waitForPendingWrites() {
        writeQueue.sync {}
    }

    private static func removeOldestFiles(in folder: URL) {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys),
              files.count > maximumFileCount else { return }
        let oldestFirst = files.sorted { leftFile, rightFile in
            let leftDate = (try? leftFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rightDate = (try? rightFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return leftDate < rightDate
        }
        for file in oldestFirst.prefix(files.count - maximumFileCount) { try? FileManager.default.removeItem(at: file) }
    }

    /// Coordinated universal time, with milliseconds, as `2026-10-13T11:43:02.512Z`.
    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// A timestamp a file name can hold on every file system: no colons.
    static func fileTimestamp(_ date: Date) -> String {
        timestamp(date).replacingOccurrences(of: ":", with: "-")
    }
}

/// What Graphite was showing and doing, for the records: values views keep up to date (the
/// document open, the window's size, the mode) and the last few things that happened. It is
/// read from the watchdog's thread while the main thread may be stuck, so it is guarded by a
/// lock and holds plain strings only.
public enum DiagnosticContext {
    public static let maximumEventCount = 30

    private struct State {
        var values: [String: String] = [:]
        var recentEvents: [String] = []
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    /// Sets a value, such as `"document": "PDF, writing"`; nil removes it.
    public static func set(_ value: String?, for key: String) {
        state.withLock { state in state.values[key] = value }
    }

    /// Notes something that happened, with the time; the oldest events are dropped.
    public static func note(_ event: String, date: Date = Date()) {
        let line = DiagnosticRecords.timestamp(date) + " " + event
        state.withLock { state in
            state.recentEvents.append(line)
            if state.recentEvents.count > maximumEventCount { state.recentEvents.removeFirst(state.recentEvents.count - maximumEventCount) }
        }
    }

    public static func snapshot() -> [String: Any] {
        let (values, recentEvents) = state.withLock { state in (state.values, state.recentEvents) }
        return ["values": values, "recentEvents": recentEvents]
    }
}
