import XCTest

/// What the iOS Simulator does to the Mac's audio output. A test run plays no sound and does not even open the audio output,
/// and the simulator opens the Mac's speaker device ("iOSSimulatorAudioDevice ... audio-out BuiltInSpeakerDevice" held by
/// coreaudiod) when an app in it writes, joins and exports a video's sound, as the recording tests do (measured by running one test alone
/// and with a watch on the assertion: it opens a moment after the test ends). The Mac suite runs such a test (macOS does not open the
/// output), and the nightly job runs it on the owner's iPad.
public enum SimulatorAudio {
    /// Skips the test in the iOS Simulator, saying what would open the output.
    public static func requireNoAudioOutput(whichIs cause: String) throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("\(cause) opens the iOS Simulator's audio output on the Mac, which a test run must not do; the Mac suite and the nightly iPad run cover it.")
        #endif
    }
}
