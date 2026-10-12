import Foundation
import Observation
import GraphiteCore

/// The downloadable voices on this device: which are offered, downloaded or downloading, the
/// one chosen for High Quality reading, and the reading mode. Settings shows it; the
/// High Quality speech reads from it.
@MainActor @Observable
public final class NeuralVoiceLibrary {
    public let manifest: NeuralVoiceManifest
    public let installation: NeuralVoiceInstallation
    public private(set) var states: [String: NeuralVoiceDownloadState] = [:]
    /// The voice High Quality mode reads with; nil until a voice is downloaded.
    public private(set) var selectedVoiceIdentifier: String?
    /// The mode the person chose, or nil to use High Quality whenever a voice is downloaded.
    public private(set) var chosenMode: ReadAloudQualityMode?
    /// Whether passages that are not rendered yet are read by the system voice instead of
    /// waiting. Off by default: the person asked for the good voice and is willing to wait.
    public var readsUnpreparedPassagesQuickly: Bool {
        didSet { preferences.set(readsUnpreparedPassagesQuickly, forKey: Self.quickFillKey) }
    }
    public private(set) var cacheBytes: Int64 = 0

    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let platform: String
    @ObservationIgnored private let physicalMemoryBytes: UInt64
    @ObservationIgnored private var downloader: NeuralVoiceDownloader?
    @ObservationIgnored public let audioCache: ReadAloudAudioCache

    private static let selectedVoiceKey = "GraphiteReadAloudNeuralVoice"
    private static let modeKey = "GraphiteReadAloudQualityMode"
    private static let quickFillKey = "GraphiteReadAloudReadsUnpreparedPassagesQuickly"

    public static var currentPlatform: String {
        #if os(macOS)
        "macOS"
        #else
        "iOS"
        #endif
    }

    /// `startsDownloader` is false in tests, which never touch the shared background session.
    public init(manifest: NeuralVoiceManifest, installation: NeuralVoiceInstallation, audioCache: ReadAloudAudioCache,
                preferences: UserDefaults = .standard, platform: String = NeuralVoiceLibrary.currentPlatform,
                physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory, startsDownloader: Bool = true) {
        self.manifest = manifest
        self.installation = installation
        self.audioCache = audioCache
        self.preferences = preferences
        self.platform = platform
        self.physicalMemoryBytes = physicalMemoryBytes
        readsUnpreparedPassagesQuickly = preferences.bool(forKey: Self.quickFillKey)
        chosenMode = preferences.string(forKey: Self.modeKey).flatMap(ReadAloudQualityMode.init(rawValue:))
        selectedVoiceIdentifier = preferences.string(forKey: Self.selectedVoiceKey)
        refreshInstalledVoices()
        if startsDownloader {
            downloader = NeuralVoiceDownloader(manifest: manifest, installation: installation) { [weak self] identifier, state in
                Task { @MainActor in self?.receive(state, for: identifier) }
            }
        }
        Task { await refreshCacheSize() }
    }

    /// The library the app uses: the shipped manifest, voices in Application Support and the
    /// audio cache in Caches.
    public static func standard() throws -> NeuralVoiceLibrary {
        NeuralVoiceLibrary(manifest: try NeuralVoiceCatalog.bundledManifest(),
                           installation: NeuralVoiceInstallation(voicesFolder: try NeuralVoiceCatalog.voicesFolder()),
                           audioCache: ReadAloudAudioCache(folder: try ReadAloudAudioCache.defaultFolder()))
    }

    /// Voices this device can run, in the manifest's order (best first).
    public var offeredVoices: [NeuralVoiceDescription] {
        manifest.voices.filter { voice in voice.isOffered(onPlatform: platform, physicalMemoryBytes: physicalMemoryBytes) }
    }

    /// Voices in the manifest this device cannot run, listed so their absence is explained.
    public var unavailableVoices: [NeuralVoiceDescription] {
        manifest.voices.filter { voice in !voice.isOffered(onPlatform: platform, physicalMemoryBytes: physicalMemoryBytes) }
    }

    /// Why a voice is not offered here, in words for the person.
    public func unavailabilityReason(of voice: NeuralVoiceDescription) -> String {
        let device = platform == "macOS" ? "this Mac" : "this device"
        if !voice.platforms.contains(platform) {
            return platform == "iOS" ? "Mac only: it needs more memory than this iPad has, and is too slow here to prepare a note." : "Not available on \(device)."
        }
        return "Needs more memory than \(device) has."
    }

    public func state(of voice: NeuralVoiceDescription) -> NeuralVoiceDownloadState { states[voice.id] ?? .notInstalled }

    public var installedVoices: [NeuralVoiceDescription] {
        offeredVoices.filter { voice in states[voice.id] == .installed }
    }

    public var hasDownloadedVoice: Bool { !installedVoices.isEmpty }

    public var mode: ReadAloudQualityMode { ReadAloudQualityMode.effective(chosen: chosenMode, hasDownloadedVoice: hasDownloadedVoice) }

    public func chooseMode(_ mode: ReadAloudQualityMode) {
        chosenMode = mode
        preferences.set(mode.rawValue, forKey: Self.modeKey)
    }

    /// The installed voice to read with: the chosen one, or the first installed one.
    public var selectedVoice: ReadAloudPassagePreparation.Voice? {
        let installed = installedVoices
        guard let voice = installed.first(where: { voice in voice.id == selectedVoiceIdentifier }) ?? installed.first else { return nil }
        return ReadAloudPassagePreparation.Voice(description: voice, folder: installation.folder(of: voice))
    }

    public func selectVoice(_ voice: NeuralVoiceDescription) {
        guard states[voice.id] == .installed else { return }
        selectedVoiceIdentifier = voice.id
        preferences.set(voice.id, forKey: Self.selectedVoiceKey)
    }

    public func download(_ voice: NeuralVoiceDescription) {
        guard voice.isOffered(onPlatform: platform, physicalMemoryBytes: physicalMemoryBytes) else { return }
        states[voice.id] = .downloading(receivedBytes: 0, totalBytes: voice.byteCount)
        downloader?.download(voice)
    }

    public func pauseDownload(_ voice: NeuralVoiceDescription) { downloader?.pause(voice) }

    public func delete(_ voice: NeuralVoiceDescription) {
        if let downloader { downloader.remove(voice) } else {
            try? installation.remove(voice)
            states[voice.id] = .notInstalled
        }
        if selectedVoiceIdentifier == voice.id {
            selectedVoiceIdentifier = nil
            preferences.removeObject(forKey: Self.selectedVoiceKey)
        }
    }

    /// Deletes every downloaded voice and all rendered audio, for when Read Aloud is turned off.
    public func deleteEverything() async {
        for voice in manifest.voices where states[voice.id] != nil && states[voice.id] != .notInstalled { delete(voice) }
        await deleteRenderedAudio()
    }

    public func deleteRenderedAudio() async {
        await audioCache.removeAll()
        await refreshCacheSize()
    }

    public func refreshCacheSize() async {
        cacheBytes = await audioCache.totalBytes
    }

    /// Space taken by downloaded and partly downloaded voices.
    public var voiceBytesOnDisk: Int64 {
        manifest.voices.reduce(0) { total, voice in total + installation.bytesOnDisk(of: voice) }
    }

    /// Re-reads which voices are installed, for after files changed outside the downloader.
    public func refreshInstalledVoices() {
        for voice in manifest.voices {
            if installation.isInstalled(voice) {
                states[voice.id] = .installed
            } else if states[voice.id] == .installed {
                states[voice.id] = .notInstalled
            } else if states[voice.id] == nil, FileManager.default.fileExists(atPath: installation.stagingFolder(of: voice).path) {
                // A download left unfinished when the app last closed: what arrived is kept.
                states[voice.id] = .paused(receivedBytes: installation.bytesOnDisk(of: voice), totalBytes: voice.byteCount)
            }
        }
    }

    #if os(iOS)
    /// Called when iOS wakes Graphite to deliver finished voice downloads.
    public func handleBackgroundDownloadEvents(completion: @escaping @Sendable () -> Void) {
        downloader?.setBackgroundEventsCompletion(completion)
    }
    #endif

    private func receive(_ state: NeuralVoiceDownloadState, for identifier: String) {
        states[identifier] = state
        if state == .installed, selectedVoiceIdentifier == nil, let voice = manifest.voice(identifier: identifier) {
            selectVoice(voice)
        }
    }
}
