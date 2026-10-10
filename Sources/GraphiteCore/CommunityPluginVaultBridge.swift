import Foundation

/// The vault as Obsidian community plugins reach it: the file operations of the plugin
/// runtime's `Vault` and `DataAdapter`, answered from the open vault. Every read and write
/// goes through `VaultStore`, so paths stay inside the vault (symbolic links included),
/// writes are coordinated and atomic, and a write is refused when the file is not at the
/// revision the plugin read. Plugins write like another app would: Graphite's own vault
/// presenter hears of their changes and updates open notes, the index and the sidebar.
///
/// Messages and answers are JSON. The Node tests of the runtime answer the same messages
/// from a folder on disk (`Tests/CommunityPluginRuntimeTests/support/test-vault-host.js`);
/// the two must keep the same operations, answers and failure kinds.
public struct CommunityPluginVaultBridge: Sendable {
    public let store: VaultStore
    /// The vault's "Deleted files" setting, read when a plugin trashes a file.
    private let deletionMethod: @Sendable () async -> DeletionMethod

    /// The most entries `vault.list` returns. Beyond it the runtime's file list is partial,
    /// and it is told so.
    public static let maximumListedEntries = 250_000
    /// The largest file a plugin can read or write in one message.
    public static let maximumTransferredBytes = 64 * 1_048_576

    public init(store: VaultStore, deletionMethod: @escaping @Sendable () async -> DeletionMethod) {
        self.store = store
        self.deletionMethod = deletionMethod
    }

    /// The vault operations this bridge answers; the plugin host answers the others.
    public static func handles(_ operation: String) -> Bool { operation.hasPrefix("vault.") }

    /// Answers one message from the runtime. Failures are answers too
    /// (`{"failure": {"kind", "message"}}`), so a plugin's promise is rejected with them.
    public func respond(to messageData: Data) async -> Data {
        do {
            let envelope = try JSONDecoder().decode(MessageEnvelope.self, from: messageData)
            let answer = try await respond(to: envelope.operation, messageData: messageData)
            return try JSONSerialization.data(withJSONObject: answer, options: [.withoutEscapingSlashes])
        } catch {
            return Self.failureData(for: error)
        }
    }

    private struct MessageEnvelope: Decodable { let operation: String }

    // The answers are built as JSON objects, since they are handed straight to the web view.
    private func respond(to operation: String, messageData: Data) async throws -> [String: Any] {
        let decoder = JSONDecoder()
        switch operation {
        case "vault.list":
            let request = try decoder.decode(ListRequest.self, from: messageData)
            return try await listVault(under: VaultPath(request.folder ?? ""))
        case "vault.listFolder":
            return try listFolder(VaultPath(try decoder.decode(PathRequest.self, from: messageData).path))
        case "vault.stat":
            let path = try VaultPath(try decoder.decode(PathRequest.self, from: messageData).path)
            return ["stat": try Self.stat(of: path.url(in: store.root)) ?? NSNull()]
        case "vault.read":
            return try await read(try decoder.decode(ReadRequest.self, from: messageData))
        case "vault.write":
            return try await write(try decoder.decode(WriteRequest.self, from: messageData))
        case "vault.createFolder":
            let path = try VaultPath(try decoder.decode(PathRequest.self, from: messageData).path)
            try await store.createDirectory(path)
            return ["stat": try Self.stat(of: path.url(in: store.root)) ?? NSNull()]
        case "vault.remove":
            return try await remove(try decoder.decode(RemoveRequest.self, from: messageData))
        case "vault.rename":
            let request = try decoder.decode(MoveRequest.self, from: messageData)
            let destination = try VaultPath(request.destinationPath)
            try await store.move(try VaultPath(request.path), to: destination)
            return ["stat": try Self.stat(of: destination.url(in: store.root)) ?? NSNull()]
        case "vault.copy":
            return try await copy(try decoder.decode(MoveRequest.self, from: messageData))
        default:
            throw BridgeFailure(kind: "unknownOperation", message: "Graphite does not know the vault operation “\(operation)”.")
        }
    }

    // MARK: Requests

    private struct PathRequest: Decodable { let path: String }
    private struct ListRequest: Decodable { let folder: String? }
    private struct ReadRequest: Decodable {
        let path: String
        let encoding: String
        let isSkippingCloudFiles: Bool?
        let maximumBytes: Int?
    }
    private struct WriteRequest: Decodable {
        struct Expectation: Decodable {
            let kind: String
            let revision: FileRevision?
        }
        let path: String
        let text: String?
        let base64: String?
        let expectation: Expectation
    }
    private struct RemoveRequest: Decodable {
        let path: String
        let method: String
        let isRecursive: Bool?
        let isFolderExpected: Bool?
    }
    private struct MoveRequest: Decodable {
        let path: String
        let destinationPath: String
    }

    // MARK: Listing

    /// Every file and folder under `folder` that the vault shows: hidden items (`.obsidian`,
    /// `.trash`) and symbolic links are left out, as the index leaves them out.
    private func listVault(under folder: VaultPath) async throws -> [String: Any] {
        let root = store.root
        let folderLocation = try folder.url(in: root)
        let listing = try await Task.detached(priority: .utility) { () throws -> (entries: [ListedEntry], isTruncated: Bool) in
            let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey]
            guard let enumerator = FileManager.default.enumerator(at: folderLocation, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
                throw GraphiteError.unavailable("Graphite could not list “\(folder.rawValue)”.")
            }
            var entries: [ListedEntry] = []
            for case let location as URL in enumerator {
                try Task.checkCancellation()
                guard let values = try? location.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true,
                      let path = Self.vaultPath(of: location, under: folderLocation, folder: folder) else { continue }
                if entries.count == Self.maximumListedEntries { return (entries, true) }
                entries.append(ListedEntry(path: path, values: values))
            }
            return (entries, false)
        }.value
        let entries = listing.entries.map { entry -> [String: Any] in
            var dictionary = Self.statDictionary(isFolder: entry.isFolder, size: entry.size, modified: entry.modified, created: entry.created)
            dictionary["path"] = entry.path.rawValue
            return dictionary
        }
        return ["entries": entries, "isTruncated": listing.isTruncated]
    }

    /// One listed item, made off the main thread and turned into JSON afterwards.
    private struct ListedEntry: Sendable {
        let path: VaultPath
        let isFolder: Bool
        let size: Int
        let modified: Date
        let created: Date

        init(path: VaultPath, values: URLResourceValues) {
            self.path = path
            isFolder = values.isDirectory == true
            size = values.fileSize ?? 0
            modified = values.contentModificationDate ?? .distantPast
            created = values.creationDate ?? modified
        }
    }

    /// The direct children of `folder`, hidden ones included, as Obsidian's adapter lists them.
    private func listFolder(_ folder: VaultPath) throws -> [String: Any] {
        let folderLocation = try folder.url(in: store.root)
        let children = try FileManager.default.contentsOfDirectory(at: folderLocation, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        var files: [String] = []
        var folders: [String] = []
        for child in children {
            guard let childPath = try? folder.appending(child.lastPathComponent) else { continue }
            let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory { folders.append(childPath.rawValue) } else { files.append(childPath.rawValue) }
        }
        return ["files": files.sorted(), "folders": folders.sorted()]
    }

    private static func vaultPath(of location: URL, under folderLocation: URL, folder: VaultPath) -> VaultPath? {
        let folderComponents = folderLocation.standardizedFileURL.pathComponents
        let components = location.standardizedFileURL.pathComponents
        guard components.count > folderComponents.count, Array(components.prefix(folderComponents.count)) == folderComponents else { return nil }
        return try? folder.appending(components.dropFirst(folderComponents.count).joined(separator: "/"))
    }

    // MARK: Reading and writing

    private func read(_ request: ReadRequest) async throws -> [String: Any] {
        let path = try VaultPath(request.path)
        let location = try path.url(in: store.root)
        guard let stat = try Self.stat(of: location) else { throw BridgeFailure(kind: "missing", message: "“\(path.rawValue)” does not exist.") }
        guard stat["isFolder"] as? Bool != true else { throw BridgeFailure(kind: "isFolder", message: "“\(path.rawValue)” is a folder.") }
        // Reading a file the provider keeps only in the cloud would download it; the
        // runtime's background reading skips such files instead.
        if request.isSkippingCloudFiles == true, Self.isNotDownloaded(location) { return ["isNotDownloaded": true] }
        let limit = min(request.maximumBytes ?? Self.maximumTransferredBytes, Self.maximumTransferredBytes)
        let snapshot: FileSnapshot
        do {
            snapshot = try await store.read(path, maximumBytes: limit)
        } catch GraphiteError.oversized {
            if request.maximumBytes != nil { return ["isTooLarge": true] }
            throw BridgeFailure(kind: "tooLarge", message: "“\(path.rawValue)” is larger than a plugin can read at once.")
        }
        var answer: [String: Any] = ["revision": Self.revisionDictionary(snapshot.revision), "stat": stat]
        if request.encoding == "binary" {
            answer["base64"] = snapshot.data.base64EncodedString()
        } else {
            answer["text"] = Self.decodedText(snapshot.data)
        }
        return answer
    }

    private func write(_ request: WriteRequest) async throws -> [String: Any] {
        let path = try VaultPath(request.path)
        let location = try path.url(in: store.root)
        let exists = FileManager.default.fileExists(atPath: location.path)
        var data: Data
        if let text = request.text {
            // A note that starts with a byte order mark keeps it, as Graphite's own saves do.
            let keepsByteOrderMark = exists && (try? Self.startsWithByteOrderMark(location)) == true
            data = keepsByteOrderMark && !text.hasPrefix("\u{FEFF}") ? Self.byteOrderMark + Data(text.utf8) : Data(text.utf8)
        } else if let base64 = request.base64, let decoded = Data(base64Encoded: base64) {
            data = decoded
        } else {
            throw BridgeFailure(kind: "invalidData", message: "The plugin sent nothing to write to “\(path.rawValue)”.")
        }
        guard data.count <= Self.maximumTransferredBytes else { throw BridgeFailure(kind: "tooLarge", message: "The plugin tried to write more than Graphite accepts in one file.") }
        let expectation: WriteExpectation
        switch request.expectation.kind {
        case "absent": expectation = .absent
        case "revision":
            guard let revision = request.expectation.revision else { throw BridgeFailure(kind: "invalidData", message: "A revision-checked write named no revision.") }
            expectation = .revision(revision)
        case "replace":
            // Whatever is there now: the plugin asked to replace the file outright.
            expectation = exists ? .revision(try await store.read(path, maximumBytes: nil).revision) : .absent
        default:
            throw BridgeFailure(kind: "invalidData", message: "Unknown write expectation “\(request.expectation.kind)”.")
        }
        try await store.createDirectory(path.parent)
        let revision = try await store.save(data, at: path, expecting: expectation)
        return ["revision": Self.revisionDictionary(revision), "stat": try Self.stat(of: location) ?? NSNull()]
    }

    private static let byteOrderMark = Data([0xEF, 0xBB, 0xBF])

    private static func startsWithByteOrderMark(_ location: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: location)
        defer { try? handle.close() }
        return try handle.read(upToCount: 3) == byteOrderMark
    }

    /// Text as the browser's decoder reads it (`TextDecoder`): UTF-8 with invalid bytes
    /// replaced, and a leading byte order mark left out.
    static func decodedText(_ data: Data) -> String {
        String(decoding: data.starts(with: byteOrderMark) ? data.dropFirst(byteOrderMark.count) : data[...], as: UTF8.self)
    }

    // MARK: Removing and copying

    private func remove(_ request: RemoveRequest) async throws -> [String: Any] {
        let path = try VaultPath(request.path)
        let location = try path.url(in: store.root)
        guard let stat = try Self.stat(of: location) else { throw BridgeFailure(kind: "missing", message: "“\(path.rawValue)” is no longer in the vault.") }
        let isFolder = stat["isFolder"] as? Bool == true
        if let isFolderExpected = request.isFolderExpected, isFolderExpected != isFolder {
            throw BridgeFailure(kind: isFolder ? "isFolder" : "notFolder", message: isFolder ? "“\(path.rawValue)” is a folder." : "“\(path.rawValue)” is not a folder.")
        }
        if isFolder, request.isRecursive == false, !((try? FileManager.default.contentsOfDirectory(atPath: location.path)) ?? []).isEmpty {
            throw BridgeFailure(kind: "notEmpty", message: "“\(path.rawValue)” is not empty.")
        }
        let method: DeletionMethod
        switch request.method {
        case "system": method = .systemTrash
        case "local": method = .vaultTrash
        case "permanent": method = .permanent
        case "vaultSetting": method = await deletionMethod()
        default: throw BridgeFailure(kind: "invalidData", message: "Unknown way to remove a file: “\(request.method)”.")
        }
        let outcome = try await store.delete(path, method: method)
        switch outcome {
        case .movedToSystemTrash: return ["outcome": "systemTrash"]
        case .movedToVaultTrash(let trashPath): return ["outcome": "vaultTrash", "trashPath": trashPath.rawValue]
        case .deleted: return ["outcome": "deleted"]
        }
    }

    private func copy(_ request: MoveRequest) async throws -> [String: Any] {
        let source = try VaultPath(request.path)
        let destination = try VaultPath(request.destinationPath)
        let sourceLocation = try source.url(in: store.root)
        let destinationLocation = try destination.url(in: store.root)
        guard let sourceStat = try Self.stat(of: sourceLocation) else { throw BridgeFailure(kind: "missing", message: "“\(source.rawValue)” is no longer in the vault.") }
        guard !FileManager.default.fileExists(atPath: destinationLocation.path) else { throw BridgeFailure(kind: "exists", message: "“\(destination.rawValue)” already exists.") }
        try await store.createDirectory(destination.parent)
        if sourceStat["isFolder"] as? Bool == true {
            let writer = store.writer
            var coordinationError: NSError?
            var copyResult: Result<Void, Error>?
            writer.makeCoordinator().coordinate(readingItemAt: sourceLocation, options: [], writingItemAt: destinationLocation, options: .forReplacing, error: &coordinationError) { coordinatedSource, coordinatedDestination in
                copyResult = Result { try FileManager.default.copyItem(at: coordinatedSource, to: coordinatedDestination) }
            }
            if let coordinationError { throw coordinationError }
            guard let copyResult else { throw GraphiteError.unavailable("The file provider did not allow the copy.") }
            try copyResult.get()
        } else {
            try store.writer.copy(from: sourceLocation, to: destinationLocation, expecting: .absent)
        }
        return ["stat": try Self.stat(of: destinationLocation) ?? NSNull()]
    }

    // MARK: Values

    /// Sizes and times as Obsidian's `Stat` has them, times in milliseconds since 1970.
    static func stat(of location: URL) throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: location.path) else { return nil }
        let values = try location.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey])
        return statDictionary(values)
    }

    private static func statDictionary(_ values: URLResourceValues) -> [String: Any] {
        let modified = values.contentModificationDate ?? .distantPast
        return statDictionary(isFolder: values.isDirectory == true, size: values.fileSize ?? 0, modified: modified, created: values.creationDate ?? modified)
    }

    private static func statDictionary(isFolder: Bool, size: Int, modified: Date, created: Date) -> [String: Any] {
        [
            "isFolder": isFolder,
            "size": isFolder ? 0 : size,
            "modified": (modified.timeIntervalSince1970 * 1000).rounded(),
            "created": (created.timeIntervalSince1970 * 1000).rounded(),
        ]
    }

    static func revisionDictionary(_ revision: FileRevision) -> [String: Any] {
        ["digest": revision.digest, "size": revision.size]
    }

    private static func isNotDownloaded(_ location: URL) -> Bool {
        guard let values = try? location.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
              values.isUbiquitousItem == true else { return false }
        return values.ubiquitousItemDownloadingStatus != .current
    }

    // MARK: Failures

    /// A failure with a kind the runtime understands (`conflict`, `missing`, `exists`…).
    public struct BridgeFailure: Error, LocalizedError {
        public let kind: String
        public let message: String
        public init(kind: String, message: String) { self.kind = kind; self.message = message }
        public var errorDescription: String? { message }
    }

    public static func failureData(for error: Error) -> Data {
        let kind: String
        switch error {
        case let failure as BridgeFailure: kind = failure.kind
        case GraphiteError.conflict: kind = "conflict"
        case GraphiteError.outsideVault: kind = "outsideVault"
        case GraphiteError.invalidPath: kind = "invalidPath"
        case GraphiteError.oversized: kind = "tooLarge"
        case GraphiteError.unavailable(let reason) where reason.hasSuffix("already exists."): kind = "exists"
        case GraphiteError.unavailable(let reason) where reason.hasSuffix("is no longer in the vault."): kind = "missing"
        case is DecodingError: kind = "invalidData"
        default: kind = "failed"
        }
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let answer: [String: Any] = ["failure": ["kind": kind, "message": message]]
        return (try? JSONSerialization.data(withJSONObject: answer)) ?? Data(#"{"failure":{"kind":"failed","message":"Graphite could not answer."}}"#.utf8)
    }
}
