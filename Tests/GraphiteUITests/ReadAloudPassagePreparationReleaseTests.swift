import XCTest
import GraphiteCore
@testable import GraphiteVoices

/// A render that never finishes by itself, standing in for a model busy on a long passage. It
/// ends only when its task is cancelled.
private final class EndlessRenderer: NeuralPassageRendering, @unchecked Sendable {
    let renderStarted = XCTestExpectation(description: "A render started")
    let modelReleased = XCTestExpectation(description: "The model was released")

    func render(_ text: String, voice: NeuralVoiceDescription, voiceFolder: URL, seed: UInt64?) async throws -> RenderedSpeech {
        renderStarted.fulfill()
        try await Task.sleep(for: .seconds(3_600))
        throw CocoaError(.featureUnsupported)
    }

    func releaseResources() async {
        modelReleased.fulfill()
    }
}

@MainActor
final class ReadAloudPassagePreparationReleaseTests: XCTestCase {
    private func startRendering(with renderer: EndlessRenderer) async throws -> ReadAloudPassagePreparation {
        let fixture = try InstalledNeuralVoiceFixture(renderer: renderer, testCase: self)
        fixture.preparation.prepare([ReadAloudPassagePreparation.Item(voiceText: "One passage.", passageText: "One passage.")],
                                    from: 0, voice: fixture.voice, language: "en")
        await fulfillment(of: [renderer.renderStarted], timeout: 30)
        return fixture.preparation
    }

    func testCancellingWhileAPassageRendersReleasesTheModel() async throws {
        let renderer = EndlessRenderer()
        let preparation = try await startRendering(with: renderer)

        preparation.cancel()

        await fulfillment(of: [renderer.modelReleased], timeout: 30)
    }

    func testSuspendingWhileAPassageRendersReleasesTheModel() async throws {
        let renderer = EndlessRenderer()
        let preparation = try await startRendering(with: renderer)

        preparation.suspend()

        await fulfillment(of: [renderer.modelReleased], timeout: 30)
    }
}
