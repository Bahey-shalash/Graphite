import Foundation
import CoreGraphics
import GraphiteCore
#if os(macOS)
import AppKit
#endif

/// Reads Finder's look of the vault's folders from their extended attributes, on every
/// platform; on the Mac also writes it, and draws a folder's icon as Finder does.
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

    #if os(macOS)
    /// The names the system gives the color tags, in the person's language.
    public static func colorTagNames() -> [FinderTagColor: String] {
        let labels = NSWorkspace.shared.fileLabels
        var names: [FinderTagColor: String] = [:]
        for tagColor in FinderTagColor.allCases where tagColor.rawValue < labels.count { names[tagColor] = labels[tagColor.rawValue] }
        return names
    }

    /// Writes a change so Finder shows it: the tags, the icon attribute, the custom-icon flag
    /// and the color label, as Finder writes them. The write is coordinated as
    /// a change of metadata only, so a file provider such as iCloud Drive syncs it.
    public func write(_ change: FinderFolderLookChange, to folder: VaultPath) throws {
        var location = try folder.url(in: root)
        // The system writes the custom icon file and its flag itself, so this comes first and
        // the flag is settled below.
        try writeCustomIconFile(change.customIconFile, at: location)
        var coordinationError: NSError?
        var writeError: (any Error)?
        NSFileCoordinator().coordinate(writingItemAt: location, options: .contentIndependentMetadataOnly, error: &coordinationError) { coordinatedLocation in
            do {
                let path = coordinatedLocation.path
                if let tagsData = FinderFolderLook.tagsAttributeData(for: change.tags) {
                    try Self.setAttribute(FinderFolderLook.tagsAttributeName, to: tagsData, of: path)
                } else {
                    try Self.removeAttribute(FinderFolderLook.tagsAttributeName, of: path)
                }
                if let iconAttributeData = change.iconAttributeData {
                    try Self.setAttribute(FinderFolderLook.iconAttributeName, to: iconAttributeData, of: path)
                } else {
                    try Self.removeAttribute(FinderFolderLook.iconAttributeName, of: path)
                }
                let existingInformation = Self.attribute(FinderFolderLook.finderInformationAttributeName, of: path,
                                                         maximumBytes: FinderFolderLook.finderInformationBytes)
                if let information = FinderFolderLook.finderInformation(existingInformation, settingCustomIconFlag: change.setsCustomIconFlag,
                                                                         labelColor: change.labelColor) {
                    try Self.setAttribute(FinderFolderLook.finderInformationAttributeName, to: information, of: path)
                } else {
                    try Self.removeAttribute(FinderFolderLook.finderInformationAttributeName, of: path)
                }
            } catch {
                writeError = error
            }
        }
        if let error = coordinationError ?? writeError { throw error }
        location.removeAllCachedResourceValues()
        // The system's icons of the folder are drawn again from what was written.
        NSWorkspace.shared.noteFileSystemChanged(location.path)
    }

    private func writeCustomIconFile(_ customIconFile: FinderFolderLookChange.CustomIconFileChange, at location: URL) throws {
        switch customIconFile {
        case .keep:
            return
        case .remove:
            guard NSWorkspace.shared.setIcon(nil, forFile: location.path, options: []) else { throw Self.iconNotWritten }
        case .write(let picture):
            let pictureLocation = try picture.path.url(in: root)
            guard let pictureData = try? Data(contentsOf: pictureLocation, options: .mappedIfSafe), // A missing picture is reported below.
                  let pictureImage = FolderIconRenderer.decodedPicture(from: pictureData),
                  let iconImage = FolderIconRenderer.finderIcon(picture: pictureImage, layout: picture.layout,
                                                                folderIcon: systemIcon(of: nil, pixels: Self.finderIconPixels)) else {
                throw Self.iconNotWritten
            }
            let icon = NSImage(cgImage: iconImage, size: NSSize(width: Self.finderIconPixels, height: Self.finderIconPixels))
            guard NSWorkspace.shared.setIcon(icon, forFile: location.path, options: []) else { throw Self.iconNotWritten }
        }
    }

    /// The side of the custom icon written for Finder, its largest icon view at 2x.
    static let finderIconPixels = 1_024
    /// Why Finder's icon of a folder was not written.
    public enum Failure: Error, Equatable {
        case iconNotWritten
    }

    private static let iconNotWritten = Failure.iconNotWritten

    /// The folder's icon as Finder draws it, `pixels` wide; the generic folder for nil.
    public func systemIcon(of folder: VaultPath?, pixels: Int) -> CGImage? {
        let icon: NSImage
        if let folder {
            guard let location = try? folder.url(in: root) else { return nil } // A path outside the vault has no icon.
            icon = NSWorkspace.shared.icon(forFile: location.path)
        } else {
            icon = NSWorkspace.shared.icon(for: .folder)
        }
        var proposedRect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
        return icon.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }

    private static func setAttribute(_ name: String, to attributeData: Data, of path: String) throws {
        let status = attributeData.withUnsafeBytes { buffer in setxattr(path, name, buffer.baseAddress, buffer.count, 0, 0) }
        if status != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    private static func removeAttribute(_ name: String, of path: String) throws {
        if removexattr(path, name, 0) != 0, errno != ENOATTR { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
    #endif
}
