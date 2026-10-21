import Foundation
import Observation
import GraphiteCore
import GraphiteApple

/// Where an add-on pack stands on this device.
enum AddOnPackState: Equatable {
    case notDownloaded
    case downloading
    case downloaded
    /// The last download or removal failed, for this reason.
    case failed(AddOnFailure)
}

/// Why a pack could not be downloaded or removed, in terms the person can act on.
enum AddOnFailure: Equatable {
    case noConnection
    /// A file arrived, but not whole or not the one listed, so nothing was kept.
    case damagedFile
    case serverRefused
    case couldNotSave

    var explanation: String {
        switch self {
        case .noConnection: "Graphite could not connect to the internet."
        case .damagedFile: "A downloaded file was damaged, so nothing was kept."
        case .serverRefused: "The server did not send the files."
        case .couldNotSave: "The files could not be saved on this device."
        }
    }
}

/// The add-on packs on this device and their downloads: what Settings › General › Add-ons
/// lists and what a feature asks for when it needs its pack. One download of a pack runs at a
/// time; the files themselves are kept by `AddOnPackStore`, which is the truth on disk.
@MainActor @Observable
final class AddOnLibrary {
    /// Every pack this build knows, in the order Settings lists them.
    let packs: [AddOnPack]
    private(set) var states: [AddOnPack.ID: AddOnPackState] = [:]
    @ObservationIgnored private let store: AddOnPackStore?
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var downloads: [AddOnPack.ID: Task<Void, Never>] = [:]

    /// A library over the packs in `applicationFolders`, downloading with `session`.
    init(packs: [AddOnPack], applicationFolders: ApplicationFolders, session: URLSession) {
        self.packs = packs
        self.store = try? AddOnPackStore.inApplicationSupport(applicationFolders.applicationSupportFolder)
        self.session = session
        refresh()
    }

    /// The packs the app ships definitions of, with a download session that keeps no cookies
    /// or cache of its own.
    static func standard(applicationFolders: ApplicationFolders) -> AddOnLibrary {
        AddOnLibrary(packs: [WelcomeTourScreenshotPack.forThisPlatform].compactMap { pack in pack },
                     applicationFolders: applicationFolders, session: URLSession(configuration: .ephemeral))
    }

    func state(of pack: AddOnPack) -> AddOnPackState { states[pack.id] ?? .notDownloaded }

    /// Reads again which packs are complete on the device.
    func refresh() {
        for pack in packs where downloads[pack.id] == nil {
            states[pack.id] = store?.isInstalled(pack) == true ? .downloaded : (states[pack.id].flatMap(Self.keptFailure) ?? .notDownloaded)
        }
    }

    /// Where a downloaded pack keeps the file called `name`, or nil until the pack is here.
    func location(ofFileNamed name: String, in pack: AddOnPack) -> URL? {
        guard state(of: pack) == .downloaded, let file = pack.file(named: name) else { return nil }
        return store?.location(of: file, in: pack)
    }

    /// Starts downloading the pack unless it is here or already on its way.
    func download(_ pack: AddOnPack) {
        guard let store, downloads[pack.id] == nil, state(of: pack) != .downloaded else { return }
        states[pack.id] = .downloading
        let session = session
        downloads[pack.id] = Task { [weak self] in
            let outcome: AddOnPackState
            do {
                try await store.install(pack, using: session)
                outcome = .downloaded
            } catch is CancellationError {
                outcome = .notDownloaded
            } catch {
                outcome = .failed(Self.failure(for: error))
            }
            self?.finishDownload(of: pack, with: outcome)
        }
    }

    /// Removes the pack's files from the device; a feature that needs them downloads them again.
    func remove(_ pack: AddOnPack) {
        downloads[pack.id]?.cancel()
        downloads[pack.id] = nil
        do {
            try store?.remove(pack)
            states[pack.id] = .notDownloaded
        } catch {
            states[pack.id] = .failed(.couldNotSave)
        }
    }

    private func finishDownload(of pack: AddOnPack, with outcome: AddOnPackState) {
        downloads[pack.id] = nil
        states[pack.id] = outcome
    }

    private static func keptFailure(_ state: AddOnPackState) -> AddOnPackState? {
        if case .failed = state { return state }
        return nil
    }

    private static func failure(for error: Error) -> AddOnFailure {
        switch error {
        case let urlError as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost].contains(urlError.code):
            .noConnection
        case AddOnPackStore.InstallError.fileDoesNotMatch:
            .damagedFile
        case AddOnPackStore.InstallError.unexpectedResponse:
            .serverRefused
        default:
            .couldNotSave
        }
    }
}
