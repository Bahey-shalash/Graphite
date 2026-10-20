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
    /// The most values one binary property list may expand to, shared members counted each time they appear.
    public var maximumPlainValueCount: Int

    public init(maximumEntryBytes: Int, maximumDecodedPayloadBytes: Int, maximumArchiveReferenceDepth: Int,
                maximumPropertyListNestingDepth: Int, maximumPlainValueCount: Int) {
        self.maximumEntryBytes = maximumEntryBytes
        self.maximumDecodedPayloadBytes = maximumDecodedPayloadBytes
        self.maximumArchiveReferenceDepth = maximumArchiveReferenceDepth
        self.maximumPropertyListNestingDepth = maximumPropertyListNestingDepth
        self.maximumPlainValueCount = maximumPlainValueCount
    }

    /// 512 MiB per entry on the Mac, the bound of the reference readers in `scripts/`, and half of it on the iPhone and
    /// iPad, where an app has less memory and a notebook's largest files (recordings, imported PDFs) are far smaller;
    /// 64 MiB per compressed payload; 64 levels of nesting; and 250,000 plain values (about 8 MiB of values).
    public static let standard = NotebookImportLimits(
        maximumEntryBytes: standardMaximumEntryBytes, maximumDecodedPayloadBytes: 64 * 1_048_576,
        maximumArchiveReferenceDepth: 64, maximumPropertyListNestingDepth: 64, maximumPlainValueCount: 250_000)

    #if os(macOS)
    private static let standardMaximumEntryBytes = 512 * 1_048_576
    #else
    private static let standardMaximumEntryBytes = 256 * 1_048_576
    #endif
}
