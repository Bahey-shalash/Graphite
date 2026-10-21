import Foundation
import CoreGraphics
import GraphiteCore
#if os(macOS)
import AppKit
#else
import QuickLookThumbnailing
#endif

/// Finder's look of the vault's folders, kept in their extended attributes: read and written
/// on every platform (the Files app reads the same attributes), and the folder's icon as the
/// system draws it.
public struct FinderFolderAttributes: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// Finder's look of a folder; a folder that cannot be read looks plain. Reads a few
    /// bytes of metadata and never downloads anything.
    public func look(of folder: VaultPath) -> FinderFolderLook {
        guard let location = try? folder.url(in: root) else { return .plain } // A path outside the vault has no look.
        let path = location.path
        return FinderFolderLook(
            tagsData: Self.attribute(FinderFolderLook.tagsAttributeName, of: path, maximumBytes: FinderFolderLook.maximumTagsBytes),
            iconData: Self.attribute(FinderFolderLook.iconAttributeName, of: path, maximumBytes: FinderFolderLook.maximumIconAttributeBytes),
            finderInformationData: Self.attribute(FinderFolderLook.finderInformationAttributeName, of: path,
                                                  maximumBytes: FinderFolderLook.finderInformationBytes),
            hasCustomIconFile: FileManager.default.fileExists(atPath: location.appendingPathComponent(FinderFolderLook.customIconFileName).path))
    }

    /// An extended attribute's bytes; nil when it is missing or larger than `maximumBytes`.
    static func attribute(_ name: String, of path: String, maximumBytes: Int) -> Data? {
        let length = getxattr(path, name, nil, 0, 0, 0)
        guard length > 0, length <= maximumBytes else { return nil }
        var bytes = [UInt8](repeating: 0, count: length)
        let readLength = getxattr(path, name, &bytes, length, 0, 0)
        guard readLength > 0 else { return nil }
        return Data(bytes.prefix(readLength))
    }

    /// The names the system gives the color tags, in the person's language on the Mac; the
    /// English names elsewhere, where the system offers no list.
    public static func colorTagNames() -> [FinderTagColor: String] {
        #if os(macOS)
        let labels = NSWorkspace.shared.fileLabels
        var names: [FinderTagColor: String] = [:]
        for tagColor in FinderTagColor.allCases where tagColor.rawValue < labels.count { names[tagColor] = labels[tagColor.rawValue] }
        return names
        #else
        return Dictionary(uniqueKeysWithValues: FinderTagColor.allCases.map { tagColor in (tagColor, tagColor.defaultTagName) })
        #endif
    }

    /// Writes a change so Finder and the Files app show it: the tags, the icon attribute, the
    /// custom-icon flag and the color label, as Finder writes them. The write is coordinated as
    /// a change of metadata only, so a file provider such as iCloud Drive syncs it. A picture
    /// becomes the custom icon file on the Mac only; elsewhere it stays Graphite's own.
    public func write(_ change: FinderFolderLookChange, to folder: VaultPath) throws {
        var location = try folder.url(in: root)
        // The system writes the custom icon file and its flag itself, so this comes first and
        // the flag is settled below.
        let hasCustomIconFile = try writeCustomIconFile(change.customIconFile, color: change.labelColor?.folderColor, at: location)
        let setsCustomIconFlag = change.setsCustomIconFlag && (change.iconAttributeData != nil || hasCustomIconFile)
        var coordinationError: NSError?
        var writeError: (any Error)?
        NSFileCoordinator().coordinate(writingItemAt: location, options: .contentIndependentMetadataOnly, error: &coordinationError) { coordinatedLocation in
            do {
                let path = coordinatedLocation.path
                try Self.replaceAttribute(FinderFolderLook.tagsAttributeName, with: FinderFolderLook.tagsAttributeData(for: change.tags), of: path)
                try Self.replaceAttribute(FinderFolderLook.iconAttributeName, with: change.iconAttributeData, of: path)
                let existingInformation = Self.attribute(FinderFolderLook.finderInformationAttributeName, of: path,
                                                         maximumBytes: FinderFolderLook.finderInformationBytes)
                let information = FinderFolderLook.finderInformation(existingInformation, settingCustomIconFlag: setsCustomIconFlag,
                                                                     labelColor: change.labelColor)
                try Self.replaceAttribute(FinderFolderLook.finderInformationAttributeName, with: information, of: path)
            } catch {
                writeError = error
            }
        }
        if let error = coordinationError ?? writeError { throw error }
        location.removeAllCachedResourceValues()
        #if os(macOS)
        // The system's icons of the folder are drawn again from what was written.
        NSWorkspace.shared.noteFileSystemChanged(location.path)
        #endif
    }

    /// Writes or removes Finder's custom icon file; returns whether the folder has one after.
    /// The picture is placed on Apple's folder art in the folder's color, as Graphite shows it.
    private func writeCustomIconFile(_ customIconFile: FinderFolderLookChange.CustomIconFileChange, color: FolderColor?, at location: URL) throws -> Bool {
        #if os(macOS)
        switch customIconFile {
        case .keep:
            return FileManager.default.fileExists(atPath: location.appendingPathComponent(FinderFolderLook.customIconFileName).path)
        case .remove:
            guard NSWorkspace.shared.setIcon(nil, forFile: location.path, options: []) else { throw Failure.iconNotWritten }
            return false
        case .write(let picture):
            let pictureLocation = try picture.path.url(in: root)
            guard let pictureData = try? Data(contentsOf: pictureLocation, options: .mappedIfSafe), // A missing picture is reported below.
                  let pictureImage = FolderIconRenderer.decodedPicture(from: pictureData),
                  let iconImage = FolderIconRenderer.finderIcon(picture: pictureImage, layout: picture.layout,
                                                                folderIcon: AppleFolderArt().folderArtNow(color: color, pixels: Self.finderIconPixels)) else {
                throw Failure.iconNotWritten
            }
            let icon = NSImage(cgImage: iconImage, size: NSSize(width: Self.finderIconPixels, height: Self.finderIconPixels))
            guard NSWorkspace.shared.setIcon(icon, forFile: location.path, options: []) else { throw Failure.iconNotWritten }
            return true
        }
        #else
        // The Files app's custom icon file cannot be written with a public API; it is left as it is.
        return FileManager.default.fileExists(atPath: location.appendingPathComponent(FinderFolderLook.customIconFileName).path)
        #endif
    }

    /// Whether a picture can become the folder's custom icon here: on the Mac only, where
    /// `NSWorkspace.setIcon` writes it.
    public static var canWriteCustomIcons: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    /// The side of the custom icon written for Finder, its largest icon view at 2x.
    static let finderIconPixels = 1_024
    /// Why Finder's icon of a folder was not written.
    public enum Failure: Error, Equatable {
        case iconNotWritten
    }

    /// The folder's icon as the system draws it, with its color, symbol, emoji or picture,
    /// `pixels` wide: Finder's on the Mac, the Files app's on iOS.
    public func systemIcon(of folder: VaultPath, pixels: Int) async -> CGImage? {
        guard let location = try? folder.url(in: root) else { return nil } // A path outside the vault has no icon.
        return await Self.systemIcon(at: location, pixels: pixels)
    }

    /// The system's plain folder, `pixels` wide.
    public static func plainFolderIcon(pixels: Int) async -> CGImage? {
        #if os(macOS)
        return drawPlainFolderIcon(pixels: pixels)
        #else
        // The Files app's folder comes from a folder without a look: an empty one Graphite keeps
        // in its temporary items.
        let plainFolder = FileManager.default.temporaryDirectory.appendingPathComponent(plainFolderName, isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: plainFolder, withIntermediateDirectories: true)) != nil else { return nil } // No folder: no art.
        return await systemIcon(at: plainFolder, pixels: pixels)
        #endif
    }

    /// The name of the empty folder whose icon is the plain folder, in the temporary items.
    static let plainFolderName = "Graphite Plain Folder"

    #if os(macOS)
    static func drawPlainFolderIcon(pixels: Int) -> CGImage? {
        var proposedRect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
        return NSWorkspace.shared.icon(for: .folder).cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }

    static func systemIcon(at location: URL, pixels: Int) async -> CGImage? {
        systemIconNow(at: location, pixels: pixels)
    }

    static func systemIconNow(at location: URL, pixels: Int) -> CGImage? {
        var proposedRect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
        return NSWorkspace.shared.icon(forFile: location.path).cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }
    #else
    /// The icon Quick Look gives for the folder: the Files app's own folder art, with the
    /// folder's color and symbol or emoji.
    static func systemIcon(at location: URL, pixels: Int) async -> CGImage? {
        let request = QLThumbnailGenerator.Request(fileAt: location, size: CGSize(width: pixels, height: pixels), scale: 1, representationTypes: .icon)
        let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) // No icon: Graphite draws the folder.
        return representation?.cgImage
    }
    #endif

    private static func replaceAttribute(_ name: String, with attributeData: Data?, of path: String) throws {
        guard let attributeData else {
            if removexattr(path, name, 0) != 0, errno != ENOATTR { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            return
        }
        let status = attributeData.withUnsafeBytes { buffer in setxattr(path, name, buffer.baseAddress, buffer.count, 0, 0) }
        if status != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
