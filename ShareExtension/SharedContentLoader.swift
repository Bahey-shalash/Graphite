import Foundation
import UniformTypeIdentifiers
import LinkPresentation
import ShareInbox

/// One thing another app shared: text, a web page, or a file now copied into the draft.
enum SharedContent: Sendable {
    case text(String)
    case link(URL, title: String?)
    case file(fileName: String, isImage: Bool)
}

/// Reads what the share sheet hands over (`NSItemProvider`s) into a draft of the share inbox:
/// text and web addresses as values, images and other files copied into the draft's folder
/// while the provider still holds them.
@MainActor
enum SharedContentLoader {
    /// How long a web page's title is waited for when the sharing app did not give one.
    static let pageTitleTimeoutSeconds: TimeInterval = 5

    /// The contents of one provider, or nil for a kind the share sheet offers nothing for.
    static func load(_ provider: NSItemProvider, into draft: SharedItemDraft, sharedAt date: Date) async throws -> SharedContent? {
        if let imageType = firstRegisteredType(of: provider, conformingTo: .image) {
            return try await loadFile(provider, type: imageType, isImage: true, into: draft, sharedAt: date)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier), !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return try await loadLink(provider)
        }
        let isNamedFile = provider.suggestedName != nil || provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        if !isNamedFile, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            return .text(try await loadObject(String.self, from: provider))
        }
        if let fileType = firstRegisteredType(of: provider, conformingTo: .data) ?? firstRegisteredType(of: provider, conformingTo: .content) {
            return try await loadFile(provider, type: fileType, isImage: false, into: draft, sharedAt: date)
        }
        return nil
    }

    /// The title of a shared web page: the one the sharing app gave, else the page's own,
    /// fetched for at most `pageTitleTimeoutSeconds`; nil when neither is known.
    static func pageTitle(of address: URL, givenTitle: String?) async -> String? {
        if let givenTitle = givenTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !givenTitle.isEmpty, givenTitle != address.absoluteString {
            return givenTitle
        }
        guard address.scheme == "http" || address.scheme == "https" else { return nil }
        let metadataProvider = LPMetadataProvider()
        metadataProvider.timeout = pageTitleTimeoutSeconds
        return try? await metadataProvider.startFetchingMetadata(for: address).title // no title is a link titled with the host
    }

    private static func firstRegisteredType(of provider: NSItemProvider, conformingTo type: UTType) -> UTType? {
        provider.registeredContentTypes.first { registeredType in registeredType.conforms(to: type) }
    }

    private static func loadLink(_ provider: NSItemProvider) async throws -> SharedContent {
        let address = try await loadObject(URL.self, from: provider)
        return .link(address, title: nil)
    }

    /// Copies the provider's file into the draft inside the completion handler, since the
    /// file the provider hands out is deleted once the handler returns.
    private static func loadFile(_ provider: NSItemProvider, type: UTType, isImage: Bool, into draft: SharedItemDraft, sharedAt date: Date) async throws -> SharedContent {
        let suggestedName = provider.suggestedName
        let calendar = Calendar.current
        let fileName: String = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(for: type, openInPlace: false) { location, _, error in
                guard let location else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                    return
                }
                let fileExtension = type.preferredFilenameExtension ?? location.pathExtension
                let preferredName = SharedAttachmentName.fileName(suggestedName: suggestedName ?? location.deletingPathExtension().lastPathComponent,
                                                                  fileExtension: fileExtension, unnamedStem: isImage ? "Shared image" : "Shared file",
                                                                  sharedAt: date, calendar: calendar)
                continuation.resume(with: Result { try draft.addAttachment(copying: location, preferredFileName: preferredName) })
            }
        }
        return .file(fileName: fileName, isImage: isImage)
    }

    private static func loadObject<Object: _ObjectiveCBridgeable & Sendable>(_ objectType: Object.Type, from provider: NSItemProvider) async throws -> Object
        where Object._ObjectiveCType: NSItemProviderReading {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadObject(ofClass: objectType) { object, error in
                guard let object else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                    return
                }
                continuation.resume(returning: object)
            }
        }
    }
}
