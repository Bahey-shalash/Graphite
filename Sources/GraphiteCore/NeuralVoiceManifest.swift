import Foundation

/// The speech models Graphite can run on the device. Each family needs its own loader;
/// the voices of one family differ only in the speaker they ask the model for.
public enum NeuralVoiceModelFamily: String, Codable, Sendable, CaseIterable {
    /// Kyutai Pocket TTS: about 100 million parameters, a fixed speaker embedding per voice.
    case pocketTTS = "pocket-tts"
    /// Alibaba Qwen3-TTS CustomVoice: named speakers, 0.6 or 1.7 billion parameters.
    case qwen3TTS = "qwen3-tts"
    /// Resemble AI Chatterbox Turbo with its built-in speaker.
    case chatterboxTurbo = "chatterbox-turbo"
    /// Nari Labs Dia 1.6B, kept to one speaker by a short audio prompt it generated itself.
    case dia
}

/// One file a voice needs, as published in its model repository. The checksum is the SHA-256
/// Hugging Face lists for the file at the pinned revision, so a download can be verified
/// before the voice is offered.
public struct NeuralVoiceFile: Codable, Equatable, Sendable {
    /// The path inside the repository, also the path inside the voice's folder on the device
    /// unless `destinationPath` says otherwise.
    public let path: String
    public let byteCount: Int64
    public let sha256: String
    /// Where the file goes inside the voice's folder when it differs from `path`, such as a
    /// codec from another repository that the loader expects in a subfolder.
    public let destinationPath: String?

    public init(path: String, byteCount: Int64, sha256: String, destinationPath: String? = nil) {
        self.path = path
        self.byteCount = byteCount
        self.sha256 = sha256
        self.destinationPath = destinationPath
    }

    public var localPath: String { destinationPath ?? path }
}

/// A repository at a fixed revision and the files taken from it. Pinning the revision keeps
/// the checksums valid when the repository changes later.
public struct NeuralVoiceSource: Codable, Equatable, Sendable {
    /// "owner/name" on the download host, such as "mlx-community/pocket-tts".
    public let repository: String
    /// The commit the files and checksums belong to.
    public let revision: String
    public let files: [NeuralVoiceFile]

    public init(repository: String, revision: String, files: [NeuralVoiceFile]) {
        self.repository = repository
        self.revision = revision
        self.files = files
    }
}

/// The license a voice's model weights are published under, and the credit its terms ask for.
public struct NeuralVoiceLicense: Codable, Equatable, Sendable {
    /// The license's short name, such as "CC BY 4.0" or "Apache 2.0".
    public let name: String
    public let address: URL
    /// The credit shown in Settings and About when the license requires attribution.
    public let attribution: String?

    public init(name: String, address: URL, attribution: String? = nil) {
        self.name = name
        self.address = address
        self.attribution = attribution
    }
}

/// A voice that can be downloaded and run on the device.
public struct NeuralVoiceDescription: Codable, Equatable, Sendable, Identifiable {
    /// Stable identifier used for the folder, the preference and the audio cache key.
    public let id: String
    /// The name people see, such as "Alba".
    public let name: String
    /// Who made the model and which one, such as "Kyutai Pocket TTS".
    public let modelName: String
    public let modelFamily: NeuralVoiceModelFamily
    /// The speaker the model is asked for ("alba", "Ryan"); nil for the model's built-in voice.
    public let speaker: String?
    /// BCP 47 language the voice reads, such as "en".
    public let language: String
    /// One sentence on how it sounds and how long it takes, measured on an iPad Pro M1.
    public let qualityNote: String
    public let license: NeuralVoiceLicense
    public let sources: [NeuralVoiceSource]
    /// Platforms the voice is offered on: "iOS", "macOS". A voice too slow or too large for
    /// an iPad is offered only on the Mac.
    public let platforms: [String]
    /// The device memory below which the voice is not offered, because loading it would end
    /// the app. Devices report less than their marketed size (an 8 GB iPad Pro M1 reports
    /// 7.36 GiB), so the manifest's limits sit below the marketed sizes.
    public let minimumPhysicalMemoryBytes: UInt64

    public init(id: String, name: String, modelName: String, modelFamily: NeuralVoiceModelFamily, speaker: String?,
                language: String, qualityNote: String, license: NeuralVoiceLicense, sources: [NeuralVoiceSource],
                platforms: [String], minimumPhysicalMemoryBytes: UInt64) {
        self.id = id
        self.name = name
        self.modelName = modelName
        self.modelFamily = modelFamily
        self.speaker = speaker
        self.language = language
        self.qualityNote = qualityNote
        self.license = license
        self.sources = sources
        self.platforms = platforms
        self.minimumPhysicalMemoryBytes = minimumPhysicalMemoryBytes
    }

    /// Every file the voice needs, from all of its sources.
    public var files: [NeuralVoiceFile] { sources.flatMap(\.files) }

    /// The download size in bytes, which is also the space the voice takes once installed.
    public var byteCount: Int64 { files.reduce(0) { total, file in total + file.byteCount } }

    public func isOffered(onPlatform platform: String, physicalMemoryBytes: UInt64) -> Bool {
        platforms.contains(platform) && physicalMemoryBytes >= minimumPhysicalMemoryBytes
    }
}

/// The list of downloadable voices, kept in the repository as `NeuralVoices.json`. Addresses
/// are built from the host, repository, revision and path, so a mirror only changes the host.
public struct NeuralVoiceManifest: Codable, Equatable, Sendable {
    public static let supportedFormatVersion = 1
    /// A manifest is a short list of voices; anything larger is not read.
    public static let maximumFileBytes = 512 * 1_024

    public let formatVersion: Int
    /// The host that serves "<repository>/resolve/<revision>/<path>", such as https://huggingface.co.
    public let downloadHost: URL
    public let voices: [NeuralVoiceDescription]

    public init(formatVersion: Int = supportedFormatVersion, downloadHost: URL, voices: [NeuralVoiceDescription]) {
        self.formatVersion = formatVersion
        self.downloadHost = downloadHost
        self.voices = voices
    }

    public enum ManifestError: Error, Equatable {
        case tooLarge
        case unsupportedFormatVersion(Int)
        case duplicateVoiceIdentifier(String)
        case unsafeFilePath(String)
        case malformedChecksum(String)
    }

    /// Reads and checks a manifest: known format, unique voice identifiers, file paths that
    /// stay inside the voice folder and checksums that are 64 hexadecimal digits.
    public static func decode(_ data: Data) throws -> NeuralVoiceManifest {
        guard data.count <= maximumFileBytes else { throw ManifestError.tooLarge }
        let manifest = try JSONDecoder().decode(NeuralVoiceManifest.self, from: data)
        guard manifest.formatVersion == supportedFormatVersion else {
            throw ManifestError.unsupportedFormatVersion(manifest.formatVersion)
        }
        var seenIdentifiers = Set<String>()
        for voice in manifest.voices {
            guard seenIdentifiers.insert(voice.id).inserted, isSafeRelativePath(voice.id) else {
                throw ManifestError.duplicateVoiceIdentifier(voice.id)
            }
            for file in voice.files {
                guard isSafeRelativePath(file.path), isSafeRelativePath(file.localPath) else {
                    throw ManifestError.unsafeFilePath(file.localPath)
                }
                guard file.sha256.count == 64, file.sha256.allSatisfy(\.isHexDigit) else {
                    throw ManifestError.malformedChecksum(file.path)
                }
            }
        }
        return manifest
    }

    /// The address a file is downloaded from.
    public func downloadAddress(of file: NeuralVoiceFile, in source: NeuralVoiceSource) -> URL {
        var address = downloadHost
        for component in source.repository.split(separator: "/") { address.appendPathComponent(String(component)) }
        address.appendPathComponent("resolve")
        address.appendPathComponent(source.revision)
        for component in file.path.split(separator: "/") { address.appendPathComponent(String(component)) }
        return address
    }

    public func voice(identifier: String) -> NeuralVoiceDescription? {
        voices.first { voice in voice.id == identifier }
    }

    /// A relative path with no empty, "." or ".." components and no leading slash, so joining
    /// it to the voice folder can never leave that folder.
    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { component in
            !component.isEmpty && component != "." && component != ".."
        }
    }
}
