/**
 * File: BaseQueryResultRows.swift
 * -------------------------------
 * Layer: Core
 * Description: Part of a base's result: the rows a printed page shows, their groups kept with the count of the rows
 *              left out, so a group's heading and a numbered list read as they do with every row.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/10/2026
 */

/// Rows of a group left out before and after the rows a result keeps.
public struct BaseLeftOutRows: Hashable, Sendable {
    /// Before the kept rows: a numbered list counts on from them.
    public var before = 0
    public var after = 0
}

extension BaseResultGroup {
    /// The group's row count, rows left out included, which its heading shows.
    public var fullRowCount: Int { rows.count + leftOutRows.before + leftOutRows.after }
}

extension BaseQueryResult {
    /// The result with only the displayed rows at `positions`, counted across the groups in
    /// order, as a printed page shows part of a base. A group stays when any of its rows does,
    /// with the rows it lost counted (`leftOutRows`) and its summaries only where it starts;
    /// the whole result's summaries stay only with its last row.
    public func keepingRows(at positions: Range<Int>) -> BaseQueryResult {
        var keptGroups: [BaseResultGroup] = []
        var groupStart = 0
        for group in groups {
            let groupRange = groupStart..<(groupStart + group.rows.count)
            groupStart = groupRange.upperBound
            let kept = groupRange.clamped(to: positions)
            guard !kept.isEmpty || (group.rows.isEmpty && positions.contains(groupRange.lowerBound)) else { continue }
            let rowsBefore = kept.lowerBound - groupRange.lowerBound
            let keptRows = Array(group.rows[rowsBefore..<(kept.upperBound - groupRange.lowerBound)])
            var keptGroup = BaseResultGroup(id: group.id, key: group.key, rows: keptRows, summaries: rowsBefore == 0 ? group.summaries : [:])
            keptGroup.leftOutRows.before = group.leftOutRows.before + rowsBefore
            keptGroup.leftOutRows.after = group.leftOutRows.after + (groupRange.upperBound - kept.upperBound)
            keptGroups.append(keptGroup)
        }
        return BaseQueryResult(view: view, columns: columns, groupDisplayName: groupDisplayName, groups: keptGroups,
                               summaries: positions.upperBound >= displayedCount ? summaries : [:], matchingCount: matchingCount, problems: problems,
                               mapCenter: mapCenter)
    }
}
