import Foundation

/// A set of files Graphite downloads the first time they are needed instead of carrying them
/// inside the app, so the app stays small: pictures, sample content and other extras that a
/// feature can do without until they arrive. Every file is named with its size and SHA-256,
/// so a download that was cut short or changed on the way is never used, and the files come
/// from one fixed `revision`, so what a build downloads never changes under it.
public struct AddOnPack: Hashable, Sendable, Identifiable {
    /// A stable name for the pack, used as its folder's name on the device.
    public let id: String
    /// What the pack is, in the words Settings shows.
    public let title: String
    /// The version of the files, such as the commit they are downloaded from. A pack whose
    /// revision changes is downloaded again.
    public let revision: String
    /// The address each file's name is appended to.
    public let baseAddress: URL
    public let files: [AddOnFile]

    public init(id: String, title: String, revision: String, baseAddress: URL, files: [AddOnFile]) {
        self.id = id
        self.title = title
        self.revision = revision
        self.baseAddress = baseAddress
        self.files = files
    }

    /// The size of all the pack's files together, as downloaded and as kept on the device.
    public var byteCount: Int64 { files.reduce(0) { total, file in total + file.byteCount } }

    public func address(of file: AddOnFile) -> URL { baseAddress.appendingPathComponent(file.name) }

    public func file(named name: String) -> AddOnFile? { files.first { file in file.name == name } }
}

/// One file of an add-on pack: its name in the pack's folder, its size and its SHA-256.
public struct AddOnFile: Hashable, Sendable {
    public let name: String
    public let byteCount: Int64
    /// Lowercase hexadecimal.
    public let sha256: String

    public init(name: String, byteCount: Int64, sha256: String) {
        self.name = name
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}
