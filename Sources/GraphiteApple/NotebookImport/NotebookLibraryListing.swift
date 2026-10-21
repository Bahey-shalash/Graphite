import Foundation
import NotebookImport

/// The notebooks in a folder chosen for import, such as a Goodnotes or Notability library export: every `.goodnotes`
/// and `.note` file at any depth, with the names of the folders between the chosen folder and it, so the import makes
/// the same folders in the vault. Hidden files and folders (a Goodnotes export's `.goodnotesmeta`) are skipped, and
/// other files are counted, not listed.
public struct NotebookLibraryListing: Sendable, Equatable {
    public struct Notebook: Sendable, Equatable {
        public let location: URL
        public let format: NotebookFileFormat
        /// The folder names from the chosen folder down to the notebook's own folder; empty for a notebook directly in it.
        public let folderPath: [String]
    }

    /// Sorted by folder path, then by name, as Finder lists them.
    public let notebooks: [Notebook]
    /// Files of the folder that are not notebooks; they are left where they are.
    public let otherFileCount: Int

    /// Lists `folder`, which the caller can read (a security-scoped folder's access already started). The read is
    /// coordinated, so a file provider presents the folder's current contents.
    public static func list(_ folder: URL) throws -> NotebookLibraryListing {
        var coordinationError: NSError?
        var listing: Result<NotebookLibraryListing, any Error>?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: [], error: &coordinationError) { coordinatedFolder in
            listing = Result { try listContents(of: coordinatedFolder) }
        }
        if let coordinationError { throw coordinationError }
        guard let listing else { throw CocoaError(.fileReadUnknown) }
        return try listing.get()
    }

    private static func listContents(of folder: URL) throws -> NotebookLibraryListing {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey]
        guard try folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw CocoaError(.fileReadInvalidFileName) }
        // A folder inside that cannot be read fails the listing, so no notebook in it goes unmentioned.
        var enumerationError: (any Error)?
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys),
                                                              options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                              errorHandler: { _, error in
                                                                  enumerationError = enumerationError ?? error
                                                                  return false
                                                              }) else {
            throw CocoaError(.fileReadUnknown)
        }
        var notebooks: [Notebook] = []
        var otherFileCount = 0
        for case let location as URL in enumerator {
            let values = try location.resourceValues(forKeys: keys)
            if let format = NotebookFileFormat(fileExtension: location.pathExtension) {
                // A notebook the system presents as a package is still one file to import.
                if values.isDirectory == true { enumerator.skipDescendants() }
                // The enumerator's level is 1 for the chosen folder's own files, so the folders between are the last level − 1.
                let folderPath = Array(location.deletingLastPathComponent().pathComponents.suffix(enumerator.level - 1))
                notebooks.append(Notebook(location: location, format: format, folderPath: folderPath))
            } else if values.isDirectory != true {
                otherFileCount += 1
            }
        }
        if let enumerationError { throw enumerationError }
        notebooks.sort { first, second in
            let firstKey = first.folderPath + [first.location.lastPathComponent]
            let secondKey = second.folderPath + [second.location.lastPathComponent]
            return firstKey.lexicographicallyPrecedes(secondKey) { left, right in left.localizedStandardCompare(right) == .orderedAscending }
        }
        return NotebookLibraryListing(notebooks: notebooks, otherFileCount: otherFileCount)
    }
}
