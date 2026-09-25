import Foundation
import GRDB
import GraphiteCore

/// Records a base query loaded, each with the index row it was read from, so the next
/// query over the same index reads again only the files that changed.
///
/// Invariant: `update` rewrites a file's properties, tags and links together with its
/// `files` row, and every change to a file changes its size, modification date, creation
/// date or content state. An unchanged row therefore means an unchanged record.
public struct LoadedBaseRecords: Sendable {
    fileprivate struct RowRevision: Hashable, Sendable {
        let size: Int
        let modifiedInterval: Double
        let createdInterval: Double?
        let isContentIndexed: Bool
    }

    fileprivate struct RevisionedRecord: Sendable {
        let revision: RowRevision
        let record: BaseFileRecord
    }

    fileprivate var recordsByPath: [String: RevisionedRecord]
    /// Records the query that produced this read from the database rather than reused.
    let rereadRecordCount: Int

    /// Nothing loaded yet: the next query reads every record.
    public init() {
        recordsByPath = [:]
        rereadRecordCount = 0
    }

    fileprivate init(recordsByPath: [String: RevisionedRecord], rereadRecordCount: Int) {
        self.recordsByPath = recordsByPath
        self.rereadRecordCount = rereadRecordCount
    }
}

extension VaultIndex {
    /// The same batch as `baseRecords(matching:limit:)`, reusing the records in
    /// `previousRecords` whose files have not changed in the index since.
    /// - Returns: The batch, and the loaded records to pass to the next query.
    public func baseRecords(matching prefilter: BaseRecordPrefilter, limit: Int = VaultIndex.defaultBaseRecordLimit,
                            reusing previousRecords: LoadedBaseRecords) throws -> (batch: BaseRecordBatch, loadedRecords: LoadedBaseRecords) {
        let boundedLimit = min(max(limit, 1), Self.maximumBaseRecordLimit)
        return try databaseQueue.read { database in
            let (whereClause, arguments) = try Self.sqlCondition(for: prefilter, in: database)
            let rows = try Row.fetchAll(database, sql: "SELECT path, size, modified, created, contentIndexed FROM files WHERE \(whereClause) ORDER BY path LIMIT ?",
                                        arguments: arguments + [boundedLimit + 1])
            var candidateCount = rows.count
            if rows.count > boundedLimit {
                candidateCount = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM files WHERE \(whereClause)", arguments: arguments) ?? rows.count
            }
            var orderedPaths: [String] = []
            var revisionsByPath: [String: LoadedBaseRecords.RowRevision] = [:]
            var changedPaths: [String] = []
            for row in rows.prefix(boundedLimit) {
                let pathText: String = row["path"]
                let revision = LoadedBaseRecords.RowRevision(size: row["size"], modifiedInterval: row["modified"], createdInterval: row["created"],
                                                             isContentIndexed: row["contentIndexed"])
                orderedPaths.append(pathText)
                revisionsByPath[pathText] = revision
                if previousRecords.recordsByPath[pathText]?.revision != revision { changedPaths.append(pathText) }
            }
            var recordsByPath: [String: LoadedBaseRecords.RevisionedRecord] = [:]
            recordsByPath.reserveCapacity(orderedPaths.count)
            for record in try Self.records(forPaths: changedPaths, in: database) {
                guard let revision = revisionsByPath[record.path.rawValue] else { continue }
                recordsByPath[record.path.rawValue] = LoadedBaseRecords.RevisionedRecord(revision: revision, record: record)
            }
            var records: [BaseFileRecord] = []
            records.reserveCapacity(orderedPaths.count)
            for pathText in orderedPaths {
                if let reread = recordsByPath[pathText] {
                    records.append(reread.record)
                } else if let reused = previousRecords.recordsByPath[pathText], reused.revision == revisionsByPath[pathText] {
                    recordsByPath[pathText] = reused
                    records.append(reused.record)
                }
            }
            return (BaseRecordBatch(records: records, candidateCount: candidateCount),
                    LoadedBaseRecords(recordsByPath: recordsByPath, rereadRecordCount: changedPaths.count))
        }
    }
}
