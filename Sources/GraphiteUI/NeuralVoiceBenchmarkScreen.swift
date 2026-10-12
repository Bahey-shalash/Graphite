import SwiftUI
import AVFoundation
import GraphiteCore
import GraphiteVoices
#if os(iOS)
import UIKit
#endif

/// A measuring screen for on-device voices, shown instead of the workspace only when the app
/// is launched with `-GraphiteVoiceBenchmark`. People never see it; it exists so speed,
/// memory and heat can be measured on a real iPad from the command line.
public struct NeuralVoiceBenchmarkScreen: View {
    public static var isRequested: Bool {
        NeuralVoiceBenchmarkConfiguration(arguments: ProcessInfo.processInfo.arguments) != nil
    }

    @State private var lines: [String] = []
    @State private var silentPlayer: AVAudioPlayer?

    public init() {}

    public var body: some View {
        List(Array(lines.enumerated()), id: \.offset) { _, line in
            Text(line).font(.callout.monospaced())
        }
        .navigationTitle("Voice Benchmark")
        .task { await start() }
    }

    private func start() async {
        guard let configuration = NeuralVoiceBenchmarkConfiguration(arguments: ProcessInfo.processInfo.arguments) else { return }
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = true
        #endif
        if configuration.mode == .background { keepRunningInBackground() }
        do {
            let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let benchmark = NeuralVoiceBenchmark(
                configuration: configuration, manifest: try NeuralVoiceCatalog.bundledManifest(),
                voicesFolder: try NeuralVoiceCatalog.voicesFolder(),
                outputFolder: documents.appendingPathComponent("VoiceBenchmark", isDirectory: true),
                deviceModel: Self.deviceModelIdentifier(),
                applicationState: { await Self.applicationStateName() })
            lines.append("Physical memory \(ProcessResources.physicalMemoryBytes / 1_048_576) MB, available \((ProcessResources.availableBytesBeforeTermination() ?? 0) / 1_048_576) MB")
            await benchmark.run { line in Task { @MainActor in lines.append(line) } }
        } catch {
            lines.append("Could not start: \(error)")
        }
    }

    /// Plays silence on a loop so iOS keeps the app running after it leaves the screen, as
    /// Read Aloud's own playback does, to see whether rendering continues there.
    private func keepRunningInBackground() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let silence = PCMWaveFile.encode(samples: [Float](repeating: 0, count: 24_000), sampleRate: 24_000)
        silentPlayer = try? AVAudioPlayer(data: silence)
        silentPlayer?.numberOfLoops = -1
        silentPlayer?.play()
    }

    @MainActor
    private static func applicationStateName() -> String {
        #if os(iOS)
        switch UIApplication.shared.applicationState {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
        #else
        return "active"
        #endif
    }

    private static func deviceModelIdentifier() -> String {
        var systemInformation = utsname()
        uname(&systemInformation)
        return withUnsafeBytes(of: &systemInformation.machine) { bytes in
            String(decoding: bytes.prefix { byte in byte != 0 }, as: UTF8.self)
        }
    }
}
