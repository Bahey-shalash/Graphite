import Foundation

/// The bounds a Goodnotes or Notability reader applies to every size it reads from a file, so that a damaged or
/// hostile notebook fails with a typed error instead of exhausting memory or time. Each size is checked before
/// anything of that size is allocated.
public struct NotebookImportLimits: Sendable, Equatable {
    /// The largest uncompressed size of one archive entry that is read.
    public var maximumEntryBytes: Int
    /// The largest decoded size of one compressed payload inside an entry: a Goodnotes ink path or rich text.
    public var maximumDecodedPayloadBytes: Int
    /// The longest chain of references followed from one keyed-archive value to the object it names.
    public var maximumArchiveReferenceDepth: Int
    /// The most nested arrays and dictionaries decoded inside one property list value.
    public var maximumPropertyListNestingDepth: Int

    public init(maximumEntryBytes: Int, maximumDecodedPayloadBytes: Int, maximumArchiveReferenceDepth: Int,
                maximumPropertyListNestingDepth: Int) {
        self.maximumEntryBytes = maximumEntryBytes
        self.maximumDecodedPayloadBytes = maximumDecodedPayloadBytes
        self.maximumArchiveReferenceDepth = maximumArchiveReferenceDepth
        self.maximumPropertyListNestingDepth = maximumPropertyListNestingDepth
    }

    /// The bounds of the reference readers in `scripts/`: 512 MiB per entry, 64 MiB per compressed payload and 64
    /// levels of nesting.
    public static let standard = NotebookImportLimits(
        maximumEntryBytes: 512 * 1_048_576, maximumDecodedPayloadBytes: 64 * 1_048_576,
        maximumArchiveReferenceDepth: 64, maximumPropertyListNestingDepth: 64)
}
