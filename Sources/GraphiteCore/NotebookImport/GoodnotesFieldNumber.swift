import Foundation

/// The field numbers of one protobuf layout of a Goodnotes file, one case per field, named by its role. The cases are
/// the only place a layout's numbers are written: the fields a reader accepts without a report, and the reads
/// themselves, both come from them.
protocol GoodnotesFieldNumber: RawRepresentable, CaseIterable, Sendable where RawValue == Int {}

extension GoodnotesFieldNumber {
    /// The numbers of every case: the fields of the layout that the format notes account for.
    static var knownFieldNumbers: Set<Int> { Set(allCases.map(\.rawValue)) }
}

/// Reads that take a layout's field case where the number-based reads take a number.
extension GoodnotesRecordFields {
    func contains(_ field: some GoodnotesFieldNumber) -> Bool { contains(field.rawValue) }

    func varint(_ field: some GoodnotesFieldNumber) throws(GoodnotesReadingError) -> UInt64? { try varint(field.rawValue) }

    func string(_ field: some GoodnotesFieldNumber) throws(GoodnotesReadingError) -> String { try string(field.rawValue) }

    func nonEmptyString(_ field: some GoodnotesFieldNumber) throws(GoodnotesReadingError) -> String? { try nonEmptyString(field.rawValue) }

    func hasNonEmptyBytes(_ field: some GoodnotesFieldNumber) throws(GoodnotesReadingError) -> Bool { try hasNonEmptyBytes(field.rawValue) }

    func fields(_ field: some GoodnotesFieldNumber) throws(GoodnotesReadingError) -> GoodnotesRecordFields { try fields(field.rawValue) }

    func repeatedFields(_ field: some GoodnotesFieldNumber) throws(GoodnotesReadingError) -> [GoodnotesRecordFields] {
        try repeatedFields(field.rawValue)
    }

    func float(_ field: some GoodnotesFieldNumber) throws(GoodnotesReadingError) -> Double { try float(field.rawValue) }

    func point(_ field: some GoodnotesFieldNumber) throws(GoodnotesReadingError) -> CGPoint { try point(field.rawValue) }

    func size(_ field: some GoodnotesFieldNumber) throws(GoodnotesReadingError) -> CGSize { try size(field.rawValue) }

    func vector(_ field: some GoodnotesFieldNumber) throws(GoodnotesReadingError) -> CGVector { try vector(field.rawValue) }

    func rectangle(_ field: some GoodnotesFieldNumber) throws(GoodnotesReadingError) -> CGRect { try rectangle(field.rawValue) }

    func color(_ field: some GoodnotesFieldNumber) throws(GoodnotesReadingError) -> NotebookImportColor { try color(field.rawValue) }

    func clock(_ field: some GoodnotesFieldNumber) throws(GoodnotesReadingError) -> GoodnotesClock { try clock(field.rawValue) }

    func compressedPayload(_ field: some GoodnotesFieldNumber, limits: NotebookImportLimits) throws(GoodnotesReadingError) -> [UInt8] {
        try compressedPayload(field.rawValue, limits: limits)
    }
}
