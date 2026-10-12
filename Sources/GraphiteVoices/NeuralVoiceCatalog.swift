import Foundation
import GraphiteCore
import MLXAudioTTS

/// The voices Graphite knows how to download, and where downloaded voices live.
public enum NeuralVoiceCatalog {
    /// The manifest shipped with the app: `Resources/NeuralVoices.json`.
    public static func bundledManifest() throws -> NeuralVoiceManifest {
        guard let address = Bundle.module.url(forResource: "NeuralVoices", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try NeuralVoiceManifest.decode(Data(contentsOf: address))
    }

    /// Dia's fixed voice: the codec codes of a clip Dia itself generated in the owner's blind
    /// test (voice E, the expressive passage), never a recording of a real person.
    public static func diaVoicePrompt() -> DiaVoicePrompt? {
        guard let address = Bundle.module.url(forResource: "DiaVoicePrompt", withExtension: "json"),
              let data = try? Data(contentsOf: address) else { return nil }
        return try? JSONDecoder().decode(DiaVoicePrompt.self, from: data)
    }

    /// Downloaded voices, one folder per voice identifier, in Application Support rather than
    /// Caches: the system may empty Caches whenever it likes, and a voice is a download of up
    /// to a few gigabytes the person chose to keep. The folder is excluded from backups.
    public static func voicesFolder() throws -> URL {
        var folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)
            .appendingPathComponent("Voices", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? folder.setResourceValues(resourceValues)
        return folder
    }
}
