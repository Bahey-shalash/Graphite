import Foundation
import GraphiteCore

/// Reads an image file chosen in the file picker.
enum PickedImageFiles {
    /// Bound on a picked image; the picture kept is far smaller.
    static let maximumImageBytes = 64 * 1_048_576

    static func imageData(at location: URL) throws -> Data {
        let hasAccess = location.startAccessingSecurityScopedResource()
        defer { if hasAccess { location.stopAccessingSecurityScopedResource() } }
        if let fileSize = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize, fileSize > maximumImageBytes {
            throw GraphiteError.oversized("This image is too large to add.")
        }
        return try Data(contentsOf: location)
    }
}
