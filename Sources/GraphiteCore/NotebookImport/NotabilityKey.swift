import Foundation

/// The keys of one part of a Notability note, one case per key, named by its role and raw-valued by the key the note
/// stores. The cases are the only place a key is written: the keys a reader accepts without a report
/// (`NotabilityKnownKeys`) and the reads themselves both come from them.
protocol NotabilityKey: RawRepresentable, CaseIterable, Sendable where RawValue == String {}

extension NotabilityKey {
    /// The keys of every case: the keys of this part that the format description accounts for.
    static var knownKeys: Set<String> { Set(allCases.map(\.rawValue)) }
}
