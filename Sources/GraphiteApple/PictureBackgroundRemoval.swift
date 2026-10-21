import Foundation
import CoreGraphics
import CoreImage
import Vision

/// Takes the background out of a picture on the device, as the system's Remove Background
/// does: Vision finds the foreground (people, animals, objects) and the rest becomes transparent.
public enum PictureBackgroundRemoval {
    /// Why the background was left in.
    public enum Failure: Error, Equatable {
        /// Vision found nothing in front of a background.
        case noForeground
        /// Vision could not run here, as in a simulator without its models.
        case unavailable
    }

    public static func removingBackground(from picture: CGImage) throws -> CGImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: picture, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw Failure.unavailable
        }
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else { throw Failure.noForeground }
        let maskedBuffer: CVPixelBuffer
        do {
            maskedBuffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false)
        } catch {
            throw Failure.unavailable
        }
        let maskedImage = CIImage(cvPixelBuffer: maskedBuffer)
        guard let result = CIContext().createCGImage(maskedImage, from: maskedImage.extent) else { throw Failure.unavailable }
        return result
    }
}
