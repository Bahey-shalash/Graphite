import Foundation

/// Where Graphite keeps its own files outside any vault: the Caches folder (indexes, which
/// can be rebuilt) and the Application Support folder (File recovery copies and unfinished
/// recordings, which belong to the person). The app uses the system's folders; the hosted
/// tests use folders of their own below a temporary one, so a test run never touches what
/// is kept on the device or in the simulator.
public struct ApplicationFolders: Equatable, Sendable {
    /// The Caches folder to use, or nil for the system's (`FileManager` finds it when it is
    /// needed, as the code did before the folders could be chosen).
    public let cachesFolder: URL?
    /// The Application Support folder to use, or nil for the system's.
    public let applicationSupportFolder: URL?

    public init(cachesFolder: URL?, applicationSupportFolder: URL?) {
        self.cachesFolder = cachesFolder
        self.applicationSupportFolder = applicationSupportFolder
    }

    /// The system's Caches and Application Support folders.
    public static let system = ApplicationFolders(cachesFolder: nil, applicationSupportFolder: nil)

    /// A Caches and an Application Support folder below `parentFolder`. Nothing is created
    /// here: the code that writes into a folder makes the folders below it, as it does in
    /// the system's. The caller removes `parentFolder` when it is done with them.
    public static func temporary(below parentFolder: URL) -> ApplicationFolders {
        ApplicationFolders(cachesFolder: parentFolder.appendingPathComponent("Caches", isDirectory: true),
                           applicationSupportFolder: parentFolder.appendingPathComponent("Application Support", isDirectory: true))
    }
}
