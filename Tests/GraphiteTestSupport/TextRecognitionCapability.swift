import CoreGraphics
import CoreText
import Foundation
import Vision
import XCTest

/// Whether this machine can run Vision's on-device text recognition. A virtual Mac without
/// a GPU (GitHub's macOS runners) loads the framework but fails every request with
/// `CRImageReaderError` 9, so tests that recognize text skip there and say why; a Mac with
/// the models runs them. Production code does not consult this: a failed recognition is
/// reported to the person, never read as a page without words.
public enum TextRecognitionCapability {
    private static let probe = Task<String?, Never> { await probeFailureDescription() }

    /// Skips the calling test, naming the missing capability, when recognition does not work
    /// here. The probe runs once per test process; later calls await its stored result.
    public static func requireOnDeviceTextRecognition() async throws {
        if let failureDescription = await probe.value {
            throw XCTSkip("On-device text recognition does not work on this machine (\(failureDescription)).")
        }
    }

    /// Returns `nil` when a rendered line of text is recognized, else what went wrong.
    private static func probeFailureDescription() async -> String? {
        guard let image = renderedLine("Graphite reads text") else { return "the probe image could not be drawn" }
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        do {
            let lines = try await request.perform(on: image)
            return lines.isEmpty ? "it found no text in an image of one line" : nil
        } catch {
            return "\(error)"
        }
    }

    private static func renderedLine(_ text: String) -> CGImage? {
        let width = 480, height = 96
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 40, nil),
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.textPosition = CGPoint(x: 16, y: 34)
        CTLineDraw(line, context)
        return context.makeImage()
    }
}
