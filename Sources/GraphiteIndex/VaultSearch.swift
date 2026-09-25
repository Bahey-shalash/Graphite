import Foundation
import GRDB
import GraphiteCore

public struct SearchResult: Identifiable, Sendable {
    public let path: VaultPath
    public let title: String
    /// Places in the note that matched, in order. Empty when only the name matched.
    public let matches: [SearchMatch]
    /// Lines that matched, including those beyond `matches`.
    public let matchCount: Int
    public var id: VaultPath { path }
    /// The first match's text, or nothing.
    public var excerpt: String { matches.first?.excerpt ?? "" }
}

/// Obsidian's search sort orders.
public enum SearchSortOrder: String, CaseIterable, Identifiable, Sendable {
    case fileNameAscending, fileNameDescending, modifiedNewestFirst, modifiedOldestFirst, createdNewestFirst, createdOldestFirst

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fileNameAscending: "File name (A to Z)"
        case .fileNameDescending: "File name (Z to A)"
        case .modifiedNewestFirst: "Modified time (new to old)"
        case .modifiedOldestFirst: "Modified time (old to new)"
        case .createdNewestFirst: "Created time (new to old)"
        case .createdOldestFirst: "Created time (old to new)"
        }
    }

    var sqlOrdering: String {
        switch self {
        case .fileNameAscending: "files.basename COLLATE NOCASE, files.path"
        case .fileNameDescending: "files.basename COLLATE NOCASE DESC, files.path DESC"
        case .modifiedNewestFirst: "files.modified DESC, files.path"
        case .modifiedOldestFirst: "files.modified, files.path"
        case .createdNewestFirst: "coalesce(files.created, files.modified) DESC, files.path"
        case .createdOldestFirst: "coalesce(files.created, files.modified), files.path"
        }
    }

    /// The value `sqlOrdering` sorts by before the path.
    var sqlSortValue: String {
        switch self {
        case .fileNameAscending, .fileNameDescending: "files.basename"
        case .modifiedNewestFirst, .modifiedOldestFirst: "files.modified"
        case .createdNewestFirst, .createdOldestFirst: "coalesce(files.created, files.modified)"
        }
    }

    /// Files after a position in `sqlOrdering`, given its sort value twice, then its path.
    var sqlRowsAfterPosition: String {
        let comparedValue = sqlSortValue + (self == .fileNameAscending || self == .fileNameDescending ? " COLLATE NOCASE" : "")
        let (valueComparison, pathComparison) = switch self {
        case .fileNameAscending, .modifiedOldestFirst, .createdOldestFirst: (">", ">")
        case .fileNameDescending: ("<", "<")
        case .modifiedNewestFirst, .createdNewestFirst: ("<", ">")
        }
        return "(\(comparedValue) \(valueComparison) ? OR (\(comparedValue) = ? AND files.path \(pathComparison) ?))"
    }
}

/// Where the next page of a search starts: after the last file checked, found by its
/// place in the sort order rather than by a count of rows, so files added, removed or
/// re-sorted between pages do not make the next page skip or repeat a file.
public struct SearchContinuation: Equatable, Sendable {
    /// The last file checked, or nil when the first page showed only name matches.
    let lastChecked: SearchSortPosition?
}

/// A file's place in a search's sort order: its sort value, then its path.
struct SearchSortPosition: Equatable, Sendable {
    let sortValue: DatabaseValue
    let path: String
}

public struct SearchPage: Sendable {
    public let results: [SearchResult]
    /// Pass to `search` for the following results; nil after the last page. A page is
    /// empty only when it is the last one.
    public let continuation: SearchContinuation?
}

/// A search that cannot run as written.
public enum SearchError: LocalizedError, Equatable {
    case invalidRegularExpression(String)
    case regularExpressionTooSlow

    public var errorDescription: String? {
        switch self {
        case .invalidRegularExpression(let pattern): "/\(pattern)/ is not a valid regular expression."
        case .regularExpressionTooSlow: "A regular expression in this search takes too long to run. Try a simpler pattern."
        }
    }
}

extension VaultIndex {
    /// File-name matches shown before the other results of a plain search.
    static let maximumNameMatches = 20
    /// One database read stops after checking this many candidates one by one (for searches
    /// the index cannot answer by itself, such as `line:`) or after this long, so a slow
    /// search shows what it has and does not hold the database for long.
    static let maximumCheckedCandidatesPerPage = 5_000
    static let maximumCheckingDurationPerPage: Duration = .milliseconds(250)
    private static let checkedCandidateBatchSize = 200
    /// Matching lines shown under each result.
    public static let maximumMatchesPerResult = 5

    /// Files matching `query`, in Obsidian's search syntax, a page at a time.
    ///
    /// The page is read without holding the index actor, in bounded reads that leave the
    /// database to other work between them. Cancelling the calling task stops it with
    /// `CancellationError`: GRDB interrupts SQLite, a running regular expression gives up,
    /// and the candidates are no longer checked after the current note.
    public nonisolated func search(_ query: String, sortOrder: SearchSortOrder = .fileNameAscending, limit: Int = 50, after continuation: SearchContinuation? = nil) async throws -> SearchPage {
        let maximumResults = min(max(limit, 1), 200)
        let expression = SearchQueryParser.parse(query)
        if let expression { try Self.validateRegularExpressions(in: expression) }
        do {
            var page = try await databaseQueue.read { database in
                try Self.searchPage(for: expression, sortOrder: sortOrder, maximumResults: maximumResults, after: continuation, in: database)
            }
            // Callers read an empty page as "no matches", so a search with candidates left
            // keeps reading. Each read is bounded, so saves and other lookups get the
            // database between reads, and only cancellation stops a search with no results.
            while page.results.isEmpty, let nextContinuation = page.continuation {
                page = try await databaseQueue.read { database in
                    try Self.searchPage(for: expression, sortOrder: sortOrder, maximumResults: maximumResults, after: nextContinuation, in: database)
                }
            }
            return page
        } catch let error as DatabaseError where error.message == RegularExpressionFunction.timeLimitMessage {
            throw SearchError.regularExpressionTooSlow
        }
    }

    private static func searchPage(for expression: SearchExpression?, sortOrder: SearchSortOrder, maximumResults: Int,
                                   after continuation: SearchContinuation?, in database: Database) throws -> SearchPage {
        let condition = expression.map { expression in SearchSQLCompiler.condition(for: expression) } ?? SearchSQLCondition(sql: "1", arguments: [], isExact: true)
        var results: [(rowIdentifier: Int64, path: String, title: String)] = []
        var excludedPaths: [String] = []
        // As in Obsidian's quick search, files whose name contains every word lead. No more
        // lead than fit on the first page; the rest appear among the other results.
        // A term that could be part of `.md` would list every note by its extension alone.
        if let terms = expression?.plainTerms, !terms.isEmpty, !terms.contains(where: SearchMatcher.mayMatchNoteExtension) {
            let nameCondition = terms.map { _ in "folded_name LIKE ? ESCAPE '\\'" }.joined(separator: " AND ")
            let namePatterns = terms.map { term in "%" + escapedForLike(foldedKey(term.text)) + "%" }
            let nameRows = try Row.fetchAll(database, sql: "SELECT rowid, path, title FROM files WHERE \(nameCondition) ORDER BY length(basename), basename, path LIMIT ?",
                                            arguments: StatementArguments(namePatterns.map { pattern in pattern as any DatabaseValueConvertible } + [min(maximumNameMatches, maximumResults)]))
            excludedPaths = nameRows.map { row in row["path"] }
            if continuation == nil { results = nameRows.map { row in (row["rowid"], row["path"], row["title"]) } }
        }
        let exclusion = excludedPaths.isEmpty ? "" : " AND files.path NOT IN (\(excludedPaths.map { _ in "?" }.joined(separator: ", ")))"
        var matcher = expression.map(SearchMatcher.init(expression:))
        var lastChecked = continuation?.lastChecked
        var checkedCandidates = 0
        var hasMoreCandidates = true
        let clock = ContinuousClock()
        let startTime = clock.now
        collecting: while results.count < maximumResults {
            try Task.checkCancellation()
            let batchLimit = condition.isExact ? maximumResults - results.count : checkedCandidateBatchSize
            var arguments = condition.arguments + excludedPaths.map { path in path as (any DatabaseValueConvertible)? }
            var positionCondition = ""
            if let lastChecked {
                positionCondition = " AND " + sortOrder.sqlRowsAfterPosition
                arguments += [lastChecked.sortValue, lastChecked.sortValue, lastChecked.path]
            }
            arguments.append(batchLimit)
            let rows = try Row.fetchAll(database, sql: """
                SELECT files.rowid, files.path, files.title, files.contentIndexed, \(sortOrder.sqlSortValue) AS sortValue FROM files
                WHERE (\(condition.sql))\(exclusion)\(positionCondition) ORDER BY \(sortOrder.sqlOrdering) LIMIT ?
                """, arguments: StatementArguments(arguments))
            let filesToCheck = condition.isExact || matcher == nil ? nil : try searchableFiles(forRows: rows, in: database)
            for row in rows {
                lastChecked = SearchSortPosition(sortValue: row["sortValue"], path: row["path"])
                checkedCandidates += 1
                let rowIdentifier: Int64 = row["rowid"]
                var isAccepted = true
                if let filesToCheck {
                    // Checking a long note can take a while, so a stale search stops between notes.
                    try Task.checkCancellation()
                    isAccepted = filesToCheck[rowIdentifier].map { file in matcher?.matches(file) == true } ?? false
                    if matcher?.hasExceededRegularExpressionTimeLimit == true { throw SearchError.regularExpressionTooSlow }
                }
                if isAccepted {
                    results.append((rowIdentifier, row["path"], row["title"]))
                    if results.count == maximumResults { break collecting }
                }
                // A batch of long notes can take seconds to check, so the time limit applies
                // between notes; the next read starts after the last one checked.
                if filesToCheck != nil, clock.now - startTime >= maximumCheckingDurationPerPage { break collecting }
            }
            if rows.count < batchLimit { hasMoreCandidates = false; break }
            if checkedCandidates >= maximumCheckedCandidatesPerPage || clock.now - startTime >= maximumCheckingDurationPerPage { break }
        }
        let matchesByRow = try expression.map { expression in try matches(of: expression, forRows: results.map(\.rowIdentifier), in: database) } ?? [:]
        let searchResults = try results.map { result in
            let matches = matchesByRow[result.rowIdentifier]
            return SearchResult(path: try VaultPath(result.path), title: result.title, matches: matches?.matches ?? [], matchCount: matches?.totalCount ?? 0)
        }
        return SearchPage(results: searchResults, continuation: hasMoreCandidates ? SearchContinuation(lastChecked: lastChecked) : nil)
    }

    /// Reports a malformed `/…/` pattern instead of letting it quietly match nothing.
    private static func validateRegularExpressions(in expression: SearchExpression) throws {
        for pattern in regularExpressionPatterns(in: expression) {
            do { _ = try NSRegularExpression(pattern: pattern) } catch { throw SearchError.invalidRegularExpression(pattern) }
        }
    }

    private static func regularExpressionPatterns(in expression: SearchExpression) -> [String] {
        switch expression {
        case .all(let items), .any(let items): items.flatMap(regularExpressionPatterns(in:))
        case .not(let item), .scoped(_, let item): regularExpressionPatterns(in: item)
        case .term(let term): term.kind == .regularExpression ? [term.text] : []
        case .property(_, let value): value.map(regularExpressionPatterns(in:)) ?? []
        }
    }

    static func escapedForLike(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
    }

    /// Matching lines of each note, found in its indexed text.
    private static func matches(of expression: SearchExpression, forRows rowIdentifiers: [Int64], in database: Database) throws -> [Int64: (matches: [SearchMatch], totalCount: Int)] {
        guard !rowIdentifiers.isEmpty else { return [:] }
        var matchesByRow: [Int64: (matches: [SearchMatch], totalCount: Int)] = [:]
        let rows = try Row.fetchAll(database, sql: "SELECT rowid, body FROM search WHERE rowid IN (\(rowIdentifiers.map { _ in "?" }.joined(separator: ", ")))",
                                    arguments: StatementArguments(rowIdentifiers))
        for row in rows {
            let body: String = row["body"] ?? ""
            guard !body.isEmpty else { continue }
            matchesByRow[row["rowid"]] = SearchExcerpts.matches(of: expression, in: body, limit: maximumMatchesPerResult)
        }
        return matchesByRow
    }

    /// Text, tags, and properties of candidate files, for checking them against a search.
    private static func searchableFiles(forRows rows: [Row], in database: Database) throws -> [Int64: SearchableFile] {
        guard !rows.isEmpty else { return [:] }
        let rowIdentifiers: [Int64] = rows.map { row in row["rowid"] }
        let paths: [String] = rows.map { row in row["path"] }
        let rowPlaceholders = rowIdentifiers.map { _ in "?" }.joined(separator: ", ")
        let pathPlaceholders = paths.map { _ in "?" }.joined(separator: ", ")
        var bodies: [Int64: String] = [:]
        for row in try Row.fetchAll(database, sql: "SELECT rowid, body FROM search WHERE rowid IN (\(rowPlaceholders))", arguments: StatementArguments(rowIdentifiers)) {
            bodies[row["rowid"]] = row["body"]
        }
        var tagsByPath: [String: [String]] = [:]
        for row in try Row.fetchAll(database, sql: "SELECT path, tag FROM tags WHERE path IN (\(pathPlaceholders))", arguments: StatementArguments(paths)) {
            tagsByPath[row["path"], default: []].append(row["tag"])
        }
        var propertiesByPath: [String: [BaseFrontmatterEntry]] = [:]
        let decoder = JSONDecoder()
        for row in try Row.fetchAll(database, sql: "SELECT path, key, node FROM properties WHERE path IN (\(pathPlaceholders)) ORDER BY path, position", arguments: StatementArguments(paths)) {
            let encodedNode: String = row["node"]
            guard let node = try? decoder.decode(BaseFrontmatterNode.self, from: Data(encodedNode.utf8)) else { continue }
            propertiesByPath[row["path"], default: []].append(BaseFrontmatterEntry(key: row["key"], node: node))
        }
        var files: [Int64: SearchableFile] = [:]
        for row in rows {
            let rowIdentifier: Int64 = row["rowid"]
            let pathText: String = row["path"]
            let path = try VaultPath(pathText)
            // A note that was not read (a cloud placeholder or an oversized note) has no
            // known text, like an attachment: its empty indexed body is not its content.
            let isContentIndexed: Bool = row["contentIndexed"]
            let content = DocumentKind(path: path) == .markdown && isContentIndexed ? bodies[rowIdentifier] ?? "" : nil
            files[rowIdentifier] = SearchableFile(path: path, content: content, tags: tagsByPath[pathText] ?? [], properties: propertiesByPath[pathText] ?? [])
        }
        return files
    }
}

/// A SQL condition on the `files` table for part of a search.
struct SearchSQLCondition {
    var sql: String
    var arguments: [(any DatabaseValueConvertible)?]
    /// True when the condition selects exactly the matching files. Otherwise it selects
    /// more, never fewer, and each candidate is checked by `SearchMatcher`.
    var isExact: Bool

    static var everything: SearchSQLCondition { SearchSQLCondition(sql: "1", arguments: [], isExact: false) }
}

/// Turns a search into SQL over the index. The full-text index and `SearchMatcher`
/// read words the same way, so conditions marked exact agree with the matcher. Terms the
/// word index cannot find are looked for as text (`SearchTextTokens.literalFragments`).
enum SearchSQLCompiler {
    enum Target {
        case note, fileName, filePath, content, tags
    }

    static let regularExpressionFunctionName = "graphite_regexp"

    static func condition(for expression: SearchExpression, target: Target = .note) -> SearchSQLCondition {
        switch expression {
        case .all(let items):
            return combined(items.map { item in condition(for: item, target: target) }, with: "AND")
        case .any(let items):
            return combined(items.map { item in condition(for: item, target: target) }, with: "OR")
        case .not(let item):
            let inner = condition(for: item, target: target)
            // The complement of a superset is not a superset: every file is a candidate.
            return inner.isExact ? SearchSQLCondition(sql: "NOT (\(inner.sql))", arguments: inner.arguments, isExact: true) : .everything
        case .term(let term):
            return termCondition(term, target: target)
        case .scoped(let scope, let operand):
            switch scope {
            case .file: return condition(for: operand, target: .fileName)
            case .path: return condition(for: operand, target: .filePath)
            case .content: return condition(for: operand, target: .content)
            case .tag: return condition(for: operand, target: .tags)
            case .ignoreCase: return condition(for: operand, target: target)
            case .matchCase:
                var inner = operand.containsNegation ? .everything : condition(for: operand, target: target)
                inner.isExact = false
                return inner
            case .line, .block, .section, .task, .taskTodo, .taskDone:
                // Whatever matches one line or task matches the whole content.
                var inner = operand.containsNegation ? .everything : condition(for: operand, target: .content)
                inner.isExact = false
                return inner
            }
        case .property(let name, let value):
            guard name.unicodeScalars.allSatisfy(\.isASCII) else { return .everything }
            return SearchSQLCondition(sql: "files.path IN (SELECT path FROM properties WHERE key = ? COLLATE NOCASE)", arguments: [name], isExact: value == nil)
        }
    }

    private static func combined(_ conditions: [SearchSQLCondition], with joiner: String) -> SearchSQLCondition {
        SearchSQLCondition(sql: conditions.map { condition in "(\(condition.sql))" }.joined(separator: " \(joiner) "),
                           arguments: conditions.flatMap(\.arguments), isExact: conditions.allSatisfy(\.isExact))
    }

    private static func termCondition(_ term: SearchTerm, target: Target) -> SearchSQLCondition {
        if term.kind == .regularExpression {
            let pattern = RegularExpressionFunction.argument(pattern: term.text, isCaseSensitive: false)
            let function = regularExpressionFunctionName
            // Attachments and unread notes are indexed with an empty body, which is not their
            // text: a pattern that matches empty text must not find them.
            let contentCondition = "files.contentIndexed = 1 AND files.rowid IN (SELECT rowid FROM search WHERE \(function)(?, body))"
            switch target {
            case .note:
                return SearchSQLCondition(sql: "\(function)(?, files.basename) OR \(function)(?, files.path) OR (\(contentCondition))",
                                          arguments: [pattern, pattern, pattern], isExact: true)
            case .content:
                return SearchSQLCondition(sql: contentCondition, arguments: [pattern], isExact: true)
            case .fileName:
                return SearchSQLCondition(sql: "\(function)(?, files.basename)", arguments: [pattern], isExact: true)
            case .filePath:
                return SearchSQLCondition(sql: "\(function)(?, files.path)", arguments: [pattern], isExact: true)
            case .tags:
                return SearchSQLCondition(sql: "files.path IN (SELECT path FROM tags WHERE \(function)(?, tag))", arguments: [pattern], isExact: true)
            }
        }
        let isASCII = term.text.unicodeScalars.allSatisfy(\.isASCII)
        switch target {
        case .note, .content:
            // Whitespace alone asks for nothing (see `SearchMatcher`).
            guard !term.text.allSatisfy(\.isWhitespace) else { return SearchSQLCondition(sql: "1", arguments: [], isExact: true) }
            let namePattern = "%" + VaultIndex.escapedForLike(VaultIndex.foldedKey(term.text)) + "%"
            let nameCondition = "files.folded_name LIKE ? ESCAPE '\\'"
            // Names and the path column hold `.md`, which plain search does not look in, so
            // the matcher decides terms that could reach into it.
            let isExactForNote = !SearchMatcher.mayMatchNoteExtension(term)
            let fragments = SearchTextTokens.literalFragments(of: term.text)
            if !fragments.isEmpty {
                // `unicode61` reads a run of Chinese or Thai as one word, so a word inside it
                // is not the start of any indexed word, and symbols make no words at all.
                // Every note the matcher accepts contains each fragment as written, so these
                // conditions select more notes, never fewer, and the matcher decides.
                let fragmentArguments = fragments.map { fragment in fragment as (any DatabaseValueConvertible)? }
                let bodyCondition = fragments.map { _ in "instr(body, ?) > 0" }.joined(separator: " AND ")
                let contentCondition = "files.rowid IN (SELECT rowid FROM search WHERE \(bodyCondition))"
                if target == .content { return SearchSQLCondition(sql: contentCondition, arguments: fragmentArguments, isExact: false) }
                let pathCondition = fragments.map { _ in "instr(files.path, ?) > 0" }.joined(separator: " AND ")
                return SearchSQLCondition(sql: "\(contentCondition) OR \(nameCondition) OR (\(pathCondition))",
                                          arguments: fragmentArguments + [namePattern] + fragmentArguments, isExact: false)
            }
            let words = SearchTextTokens(term.text).tokens.map { token in (term.text as NSString).substring(with: token.range) }
            // A term of variation selectors alone has nothing to look for either.
            guard !words.isEmpty else { return SearchSQLCondition(sql: "1", arguments: [], isExact: true) }
            // The words go to FTS5 as written: its `unicode61` tokenizer folds them exactly as
            // it folded the notes, which Foundation's folding does not (it turns "ß" into "ss").
            let phrase = "\"" + words.joined(separator: " ") + "\"" + (term.kind == .word ? "*" : "")
            if target == .content {
                return SearchSQLCondition(sql: "files.rowid IN (SELECT rowid FROM search WHERE search MATCH ?)", arguments: ["body : " + phrase], isExact: true)
            }
            return SearchSQLCondition(sql: "files.rowid IN (SELECT rowid FROM search WHERE search MATCH ?) OR \(nameCondition)",
                                      arguments: [phrase, namePattern], isExact: isExactForNote)
        case .fileName, .filePath:
            // The folded columns ignore case for every letter, as the matcher does; LIKE on
            // the names as written would ignore it for ASCII letters only.
            let column = target == .fileName ? "files.folded_name" : "files.folded_path"
            return SearchSQLCondition(sql: "\(column) LIKE ? ESCAPE '\\'", arguments: ["%" + VaultIndex.escapedForLike(VaultIndex.foldedKey(term.text)) + "%"], isExact: true)
        case .tags:
            let tag = term.text.hasPrefix("#") ? String(term.text.dropFirst()) : term.text
            guard isASCII else { return .everything }
            return SearchSQLCondition(sql: "files.path IN (SELECT path FROM tags WHERE tag = ? COLLATE NOCASE OR tag LIKE ? ESCAPE '\\')",
                                      arguments: [tag, VaultIndex.escapedForLike(tag) + "/%"], isExact: true)
        }
    }
}

/// `graphite_regexp(pattern, text)` for SQLite: whether an ICU regular expression, as
/// Obsidian's `/…/` search, finds a match in the text.
enum RegularExpressionFunction {
    /// A pattern with nested repetition, such as `(a+)+$`, can take minutes on one line.
    /// SQLite cannot interrupt a function while it runs, so the function stops itself.
    static let maximumMatchDuration = TimeLimitedRegularExpression.maximumMatchDuration
    static let timeLimitMessage = "graphite_regexp: the regular expression took too long"
    static let invalidPatternMessage = "graphite_regexp: invalid regular expression"

    /// Case sensitivity travels with the pattern, so one function serves both.
    static func argument(pattern: String, isCaseSensitive: Bool) -> String {
        (isCaseSensitive ? "c:" : "i:") + pattern
    }

    static let function = DatabaseFunction(SearchSQLCompiler.regularExpressionFunctionName, argumentCount: 2, pure: true) { values in
        guard let argument = String.fromDatabaseValue(values[0]), let text = String.fromDatabaseValue(values[1]) else { return false }
        guard let regularExpression = cache.regularExpression(for: argument) else {
            throw DatabaseError(resultCode: .SQLITE_ERROR, message: invalidPatternMessage)
        }
        return try containsMatch(regularExpression, in: text)
    }

    /// Whether `text` has a match, giving up after `maximumMatchDuration` with an error, or
    /// early when the searching task is cancelled (GRDB then fails the statement).
    static func containsMatch(_ regularExpression: NSRegularExpression, in text: String) throws -> Bool {
        do {
            return try TimeLimitedRegularExpression.firstMatch(of: regularExpression, in: text, maximumDuration: maximumMatchDuration) != nil
        } catch TimeLimitedRegularExpression.Interruption.timeLimitExceeded {
            throw DatabaseError(resultCode: .SQLITE_ERROR, message: timeLimitMessage)
        } catch {
            return false
        }
    }

    private static let cache = RegularExpressionCache()
}

/// Compiled patterns shared by every database connection.
/// `NSCache` is thread-safe and `NSRegularExpression` is immutable, so the cache can be
/// used from SQLite's threads without further locking.
private final class RegularExpressionCache: @unchecked Sendable {
    private let compiled = NSCache<NSString, NSRegularExpression>()

    init() { compiled.countLimit = 64 }

    /// Nil for a malformed pattern; `VaultIndex.search` reports those before any SQL runs.
    func regularExpression(for argument: String) -> NSRegularExpression? {
        if let cached = compiled.object(forKey: argument as NSString) { return cached }
        let isCaseSensitive = argument.hasPrefix("c:")
        guard let regularExpression = try? NSRegularExpression(pattern: String(argument.dropFirst(2)), options: isCaseSensitive ? [] : [.caseInsensitive]) else { return nil }
        compiled.setObject(regularExpression, forKey: argument as NSString)
        return regularExpression
    }
}

/// A file the quick switcher offers, ranked by `FuzzyMatcher`.
public struct QuickSwitcherMatch: Identifiable, Sendable {
    public let path: VaultPath
    /// The alias that matched, when the file was found through one.
    public let alias: String?
    public let score: Double
    /// Matched characters in the text that matched: the alias, the path (for a query with
    /// `/`), or otherwise the name without `.md`.
    public let matchedRanges: [Range<Int>]
    public var id: String { path.rawValue + "|" + (alias ?? "") }
}

extension VaultIndex {
    /// Candidates read from the index per query before ranking.
    static let maximumQuickSwitcherCandidates = 3_000
    /// Candidates ranked between checks for cancellation.
    private static let cancellationCheckInterval = 256

    /// Files whose name, path, or alias contains the query's characters in order, best first.
    public nonisolated func quickSwitcherMatches(for query: String, limit: Int = 60) async throws -> [QuickSwitcherMatch] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        guard !trimmedQuery.isEmpty, limit > 0 else { return [] }
        let matchesPath = trimmedQuery.contains("/")
        let candidatePattern = FuzzyCandidatePattern(query: trimmedQuery)
        return try await databaseQueue.read { database in
            let column = matchesPath ? "coalesce(path_key, path)" : "coalesce(name_key, basename)"
            let rows = try Row.fetchAll(database, sql: "SELECT path, basename FROM files WHERE \(candidatePattern.sql(on: column)) ORDER BY length(path) LIMIT ?",
                                        arguments: StatementArguments(candidatePattern.arguments.map { argument in argument as any DatabaseValueConvertible } + [Self.maximumQuickSwitcherCandidates]))
            // Stored paths and names are already normalized, so candidates are ranked by
            // their text, and only those shown become `VaultPath`s.
            var candidates: [(pathText: String, alias: String?, score: Double, matchedRanges: [Range<Int>])] = []
            for (rowPosition, row) in rows.enumerated() {
                // Ranking thousands of candidates takes a while, so a query replaced by the next keystroke stops early.
                if rowPosition.isMultiple(of: Self.cancellationCheckInterval) { try Task.checkCancellation() }
                let pathText: String = row["path"]
                let text = matchesPath ? Self.switcherPathText(pathText) : Self.switcherName(fileName: row["basename"])
                guard let match = FuzzyMatcher.match(trimmedQuery, in: text) else { continue }
                candidates.append((pathText, nil, match.score, match.matchedRanges))
            }
            if !matchesPath {
                let rows = try Row.fetchAll(database, sql: "SELECT path, alias FROM aliases WHERE \(candidatePattern.sql(on: "alias")) LIMIT ?",
                                            arguments: StatementArguments(candidatePattern.arguments.map { argument in argument as any DatabaseValueConvertible } + [Self.maximumQuickSwitcherCandidates]))
                for (rowPosition, row) in rows.enumerated() {
                    if rowPosition.isMultiple(of: Self.cancellationCheckInterval) { try Task.checkCancellation() }
                    let alias: String = row["alias"]
                    guard let match = FuzzyMatcher.match(trimmedQuery, in: alias) else { continue }
                    // An alias ranks just below the same match on a name.
                    candidates.append((row["path"], alias, match.score - 0.5, match.matchedRanges))
                }
            }
            let shown = candidates.sorted { leftCandidate, rightCandidate in
                leftCandidate.score != rightCandidate.score ? leftCandidate.score > rightCandidate.score : leftCandidate.pathText < rightCandidate.pathText
            }.prefix(limit)
            return try shown.map { candidate in
                QuickSwitcherMatch(path: try VaultPath(candidate.pathText), alias: candidate.alias, score: candidate.score, matchedRanges: candidate.matchedRanges)
            }
        }
    }

    /// A note's name without `.md`, or another file's full name, as the switcher shows it.
    public static func switcherName(_ path: VaultPath) -> String {
        switcherName(fileName: path.name)
    }

    static func switcherName(fileName: String) -> String {
        DocumentKind(fileExtension: (fileName as NSString).pathExtension) == .markdown ? (fileName as NSString).deletingPathExtension : fileName
    }

    static func switcherPathText(_ pathText: String) -> String {
        DocumentKind(fileExtension: (pathText as NSString).pathExtension) == .markdown ? (pathText as NSString).deletingPathExtension : pathText
    }
}

/// A SQL condition keeping every name `FuzzyMatcher` can accept for a query: the query's
/// folded characters in order. LIKE ignores case for ASCII letters only, so on its own
/// `élan` would miss `Élan vital`, and so would `elan`, although `FuzzyMatcher` accepts
/// both. LIKE decides names written in ASCII exactly, and quickly; names with other
/// characters are checked with a slower GLOB pattern that writes each query character as
/// the set of characters whose folded form contains it.
struct FuzzyCandidatePattern {
    let arguments: [String]

    init(query: String) {
        let queryCharacters = Self.folded(query).filter { character in !character.isWhitespace }
        let likePattern = "%" + queryCharacters.map { character in VaultIndex.escapedForLike(String(character)) }.joined(separator: "%") + "%"
        arguments = [likePattern, Self.glob(for: query)]
    }

    /// The condition on `column`, taking `arguments` in order. Text has a character outside
    /// ASCII when it has more bytes (a BLOB's length) than characters (a TEXT's length).
    func sql(on column: String) -> String {
        "(\(column) LIKE ? ESCAPE '\\' OR (length(CAST(\(column) AS BLOB)) > length(\(column)) AND \(column) GLOB ?))"
    }

    static func glob(for query: String) -> String {
        let queryCharacters = Array(folded(query).filter { character in !character.isWhitespace })
        var characterClasses: [String] = []
        for (queryIndex, queryCharacter) in queryCharacters.enumerated() {
            // `FuzzyMatcher` lets one name character stand for several query characters (`ﬁ`
            // for `fi`, `ß` for `ss`), but a GLOB set matches one. A query character that may
            // come from the same name character as the one before it is left out, which only
            // widens the pattern.
            if queryIndex > 0, Self.mayComeFromOneCharacter(queryCharacters[queryIndex - 1], then: queryCharacter) { continue }
            characterClasses.append(characterClass(for: queryCharacter))
        }
        return "*" + characterClasses.joined(separator: "*") + "*"
    }

    /// `FuzzyMatcher`'s folding. The two must stay the same, or the pattern drops names
    /// the matcher would accept.
    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }

    /// Characters whose folded form contains a given character, other than itself: `É`, `è`
    /// and `E` for `e`, `ß` and `ſ` for `s`, `ﬁ` for both `f` and `i`. `FuzzyMatcher`
    /// compares a name's characters by every character of their folded form. Scripts with
    /// case or accents lie in these ranges; for any other character, its case forms are
    /// added directly.
    private static let foldingVariants: [Character: [Unicode.Scalar]] = foldingTables.variants

    /// Pairs of characters that appear in this order in the folded form of one character,
    /// such as `f` then `i` for `ﬁ`, each pair written as a two-character string.
    private static let orderedPairsInOneFoldedCharacter: Set<String> = foldingTables.orderedPairs

    private static let foldingTables: (variants: [Character: [Unicode.Scalar]], orderedPairs: Set<String>) = {
        var variants: [Character: [Unicode.Scalar]] = [:]
        var orderedPairs: Set<String> = []
        let foldableRanges: [ClosedRange<UInt32>] = [0x0041...0x33FF, 0xA640...0xABFF, 0xFB00...0xFFEF, 0x10400...0x104FF]
        for range in foldableRanges {
            for value in range {
                guard let scalar = Unicode.Scalar(value) else { continue }
                let character = Character(scalar)
                let foldedCharacters = Array(folded(String(character)))
                guard !foldedCharacters.isEmpty, foldedCharacters != [character] else { continue }
                var seenCharacters: Set<Character> = []
                for foldedCharacter in foldedCharacters where foldedCharacter != character && seenCharacters.insert(foldedCharacter).inserted {
                    variants[foldedCharacter, default: []].append(scalar)
                }
                for firstIndex in foldedCharacters.indices {
                    for secondIndex in foldedCharacters.indices where secondIndex > firstIndex {
                        orderedPairs.insert(String([foldedCharacters[firstIndex], foldedCharacters[secondIndex]]))
                    }
                }
            }
        }
        return (variants, orderedPairs)
    }()

    /// Whether `firstCharacter` then `secondCharacter` may both come from one name character's folded form.
    private static func mayComeFromOneCharacter(_ firstCharacter: Character, then secondCharacter: Character) -> Bool {
        orderedPairsInOneFoldedCharacter.contains(String([firstCharacter, secondCharacter]))
    }

    /// One pattern position matching any character whose folded form contains `queryCharacter`. A GLOB
    /// set matches one Unicode scalar; the rest of a longer character falls to the `*` after it.
    private static func characterClass(for queryCharacter: Character) -> String {
        var members: Set<Unicode.Scalar> = []
        members.formUnion(queryCharacter.unicodeScalars.prefix(1))
        members.formUnion(foldingVariants[queryCharacter] ?? [])
        members.formUnion(String(queryCharacter).uppercased().unicodeScalars.prefix(1))
        guard members.count > 1 else {
            let text = members.first.map(String.init) ?? ""
            // `*`, `?` and `[` are GLOB syntax; inside a set they stand for themselves.
            return ["*", "?", "["].contains(text) ? "[" + text + "]" : text
        }
        // SQLite reads a whole set for every character it compares, so runs of consecutive
        // characters, common among accented letters, are written as ranges.
        let syntaxCharacters: [Unicode.Scalar] = ["]", "-", "^"]
        var set = members.contains("]") ? "]" : ""
        var runs: [ClosedRange<UInt32>] = []
        for value in members.filter({ scalar in !syntaxCharacters.contains(scalar) }).map(\.value).sorted() {
            if let lastRun = runs.last, lastRun.upperBound + 1 == value { runs[runs.count - 1] = lastRun.lowerBound...value } else { runs.append(value...value) }
        }
        for run in runs {
            guard let lowerBound = Unicode.Scalar(run.lowerBound), let upperBound = Unicode.Scalar(run.upperBound) else { continue }
            set += run.count > 2 ? "\(lowerBound)-\(upperBound)" : String(String.UnicodeScalarView(run.compactMap(Unicode.Scalar.init)))
        }
        // In a set, `]` is literal only first, `-` only last, and `^` anywhere but first.
        if members.contains("^") { set += "^" }
        if members.contains("-") { set += "-" }
        return "[" + set + "]"
    }
}

/// A tag and how many files use it.
public struct TagCount: Hashable, Sendable {
    public let tag: String
    public let fileCount: Int
}

extension VaultIndex {
    /// Tags containing `query` (all tags when it is empty), most used first; a tag written
    /// with different capitals counts once, as Obsidian counts it.
    public nonisolated func tags(matching query: String, limit: Int = 30) async throws -> [TagCount] {
        guard limit > 0 else { return [] }
        let foldedQuery = query.lowercased()
        // LIKE ignores case for ASCII letters only, so any other character of the query
        // matches any text here, and the comparison below decides.
        let pattern = "%" + query.map { character in character.isASCII ? Self.escapedForLike(String(character)) : "%" }.joined() + "%"
        return try await databaseQueue.read { database in
            // SQLite groups spellings that differ in ASCII capitals; other capitals, such
            // as `#Été` and `#été`, are grouped here.
            let rows = try Row.fetchAll(database, sql: "SELECT tag, COUNT(DISTINCT path) AS fileCount FROM tags WHERE tag LIKE ? ESCAPE '\\' GROUP BY tag COLLATE NOCASE",
                                        arguments: [pattern])
            var spellingsByKey: [String: [TagCount]] = [:]
            for row in rows {
                let tag: String = row["tag"]
                let key = tag.lowercased()
                guard foldedQuery.isEmpty || key.contains(foldedQuery) else { continue }
                spellingsByKey[key, default: []].append(TagCount(tag: tag, fileCount: row["fileCount"]))
            }
            var counts: [TagCount] = []
            for spellings in spellingsByKey.values {
                // The most used spelling names the tag.
                guard let mostUsed = spellings.max(by: { leftSpelling, rightSpelling in leftSpelling.fileCount < rightSpelling.fileCount }) else { continue }
                guard spellings.count > 1 else { counts.append(mostUsed); continue }
                // One file may use several spellings, so their counts cannot be added.
                let placeholders = spellings.map { _ in "?" }.joined(separator: ", ")
                let fileCount = try Int.fetchOne(database, sql: "SELECT COUNT(DISTINCT path) FROM tags WHERE tag COLLATE NOCASE IN (\(placeholders))",
                                                 arguments: StatementArguments(spellings.map(\.tag))) ?? mostUsed.fileCount
                counts.append(TagCount(tag: mostUsed.tag, fileCount: fileCount))
            }
            return Array(counts.sorted { leftCount, rightCount in
                if leftCount.fileCount != rightCount.fileCount { return leftCount.fileCount > rightCount.fileCount }
                let comparison = leftCount.tag.caseInsensitiveCompare(rightCount.tag)
                return comparison == .orderedSame ? leftCount.tag < rightCount.tag : comparison == .orderedAscending
            }.prefix(limit))
        }
    }

    /// Every level of every tag (`course` and `course/math` for `#course/math`), each with
    /// the notes that have it or a tag nested under it, for the Tags view's nested list.
    public func nestedTagCounts() throws -> [TagCount] {
        try databaseQueue.read { database in
            let rows = try Row.fetchAll(database, sql: """
                WITH RECURSIVE levels(tag, rest, path) AS (
                  SELECT CASE WHEN instr(tag, '/') > 0 THEN substr(tag, 1, instr(tag, '/') - 1) ELSE tag END,
                         CASE WHEN instr(tag, '/') > 0 THEN substr(tag, instr(tag, '/') + 1) ELSE '' END, path FROM tags
                  UNION ALL
                  SELECT tag || '/' || CASE WHEN instr(rest, '/') > 0 THEN substr(rest, 1, instr(rest, '/') - 1) ELSE rest END,
                         CASE WHEN instr(rest, '/') > 0 THEN substr(rest, instr(rest, '/') + 1) ELSE '' END, path
                  FROM levels WHERE rest != ''
                )
                SELECT tag, COUNT(DISTINCT path) AS fileCount FROM levels WHERE tag != '' GROUP BY tag COLLATE NOCASE
                """)
            return rows.map { row in TagCount(tag: row["tag"], fileCount: row["fileCount"]) }
        }
    }
}

/// A property name used in the vault, how many notes use it, and a few of its values, from
/// which its type is inferred when `types.json` does not assign one.
public struct PropertyUsage: Sendable {
    public let key: String
    public let fileCount: Int
    public let sampleValues: [BaseFrontmatterNode]
}

extension VaultIndex {
    /// Every property name in the vault, names differing only in capitals counted once, as
    /// Obsidian counts them.
    public func propertyUsages(sampleCount: Int = 5) throws -> [PropertyUsage] {
        try databaseQueue.read { database in
            let counts = try Row.fetchAll(database, sql: """
                SELECT key, COUNT(DISTINCT path) AS fileCount FROM properties GROUP BY key COLLATE NOCASE
                """)
            let sampleRows = try Row.fetchAll(database, sql: """
                SELECT key, node FROM (
                  SELECT key, node, ROW_NUMBER() OVER (PARTITION BY key COLLATE NOCASE ORDER BY rowid) AS sampleNumber FROM properties
                ) WHERE sampleNumber <= ?
                """, arguments: [sampleCount])
            let decoder = JSONDecoder()
            var samplesByKey: [String: [BaseFrontmatterNode]] = [:]
            for row in sampleRows {
                let key: String = row["key"]
                let encodedNode: String = row["node"]
                guard let node = try? decoder.decode(BaseFrontmatterNode.self, from: Data(encodedNode.utf8)) else { continue }
                samplesByKey[key.lowercased(), default: []].append(node)
            }
            return counts.map { row in
                let key: String = row["key"]
                return PropertyUsage(key: key, fileCount: row["fileCount"], sampleValues: samplesByKey[key.lowercased()] ?? [])
            }
        }
    }

    /// Notes with a property named `key`, ignoring capitals.
    public func paths(withPropertyKey key: String) throws -> [VaultPath] {
        try databaseQueue.read { database in
            try String.fetchAll(database, sql: "SELECT DISTINCT path FROM properties WHERE key = ? COLLATE NOCASE ORDER BY path", arguments: [key])
                .compactMap { rawPath in try? VaultPath(rawPath) }
        }
    }
}
