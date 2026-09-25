import Foundation

/// A computed cell: a value, or the reason the expression failed for this row.
public enum BaseCellValue: Hashable, Sendable {
    case value(BaseValue)
    case error(String)

    public var value: BaseValue? {
        if case .value(let value) = self { return value }
        return nil
    }
}

public struct BaseColumn: Hashable, Sendable, Identifiable {
    public let property: BasePropertyIdentifier
    public let displayName: String
    public var id: BasePropertyIdentifier { property }
}

public struct BaseCoordinate: Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public init?(latitude: Double, longitude: Double) {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        self.latitude = latitude
        self.longitude = longitude
    }

    /// The Maps plugin's formats: `[lat, lng]` (numbers or numeric text) or `"lat, lng"`.
    /// Text with any other number of parts, such as decimal commas (`"48,85, 2,35"`),
    /// is not a coordinate: reading its first two parts would misplace the marker.
    public init?(value: BaseValue) {
        func number(_ element: BaseValue) -> Double? {
            switch element {
            case .number(let number): return number
            case .string(let text): return Double(text.trimmingCharacters(in: .whitespaces))
            default: return nil
            }
        }
        switch value {
        case .list(let elements):
            guard elements.count >= 2, let latitude = number(elements[0]), let longitude = number(elements[1]) else { return nil }
            self.init(latitude: latitude, longitude: longitude)
        case .string(let text):
            let parts = text.trimmingCharacters(in: CharacterSet(charactersIn: "[] ")).split(separator: ",")
            guard parts.count == 2, let latitude = Double(parts[0].trimmingCharacters(in: .whitespaces)),
                  let longitude = Double(parts[1].trimmingCharacters(in: .whitespaces)) else { return nil }
            self.init(latitude: latitude, longitude: longitude)
        default:
            return nil
        }
    }
}

/// Where a card's cover comes from.
public enum BaseImageReference: Hashable, Sendable {
    case vaultFile(VaultPath)
    case remote(URL)
    /// A CSS hex color such as `#F54927`, drawn as a solid cover.
    case color(String)
}

/// Values a view needs besides its columns: card covers and map markers.
public struct BaseRowPresentation: Hashable, Sendable {
    public var coverImage: BaseImageReference?
    public var coordinate: BaseCoordinate?
    public var markerIcon: String?
    public var markerColor: String?
    public init() {}
}

public struct BaseResultRow: Identifiable, Hashable, Sendable {
    public let path: VaultPath
    /// Aligned with `BaseQueryResult.columns`.
    public let cells: [BaseCellValue]
    public let presentation: BaseRowPresentation
    public var id: VaultPath { path }
}

public struct BaseSummaryCell: Hashable, Sendable {
    public let name: String
    public let value: BaseCellValue
}

public struct BaseResultGroup: Identifiable, Hashable, Sendable {
    public let id: Int
    /// The grouping value, or nil when the view is not grouped.
    public let key: BaseCellValue?
    public let rows: [BaseResultRow]
    /// Summaries for this group's rows, by column.
    public let summaries: [BasePropertyIdentifier: BaseSummaryCell]
}

public struct BaseQueryResult: Sendable {
    public let view: BaseView
    public let columns: [BaseColumn]
    public let groups: [BaseResultGroup]
    /// Summaries over every displayed row.
    public let summaries: [BasePropertyIdentifier: BaseSummaryCell]
    /// Rows that passed the filters, before `limit`.
    public let matchingCount: Int
    /// Problems with the base or its filters, for the user.
    public let problems: [String]
    /// The map view's configured center, evaluated against `this`.
    public let mapCenter: BaseCoordinate?
    public var rows: [BaseResultRow] { groups.flatMap(\.rows) }
    public var displayedCount: Int { groups.reduce(0) { count, group in count + group.rows.count } }
}

/// Runs one view of a base over a bounded set of records: filters, sorting, limit,
/// grouping, cells and summaries. Pure and synchronous; call it off the main actor.
public struct BaseQueryEngine {
    public let definition: BaseDefinition
    public let environment: BaseEvaluationEnvironment
    public let thisRecord: BaseFileRecord?
    public let provider: (any BaseRecordProvider)?

    public init(definition: BaseDefinition, environment: BaseEvaluationEnvironment, thisRecord: BaseFileRecord?, provider: (any BaseRecordProvider)? = nil) {
        self.definition = definition
        self.environment = environment
        self.thisRecord = thisRecord
        self.provider = provider
    }

    public func run(viewIndex: Int, records: [BaseFileRecord], sortOverride: [BaseSortKey]? = nil) -> BaseQueryResult {
        // Obsidian shows a table when a base defines no views.
        let view = definition.views.isEmpty ? BaseView(id: 0, type: .table, name: "Table") : definition.views[min(max(viewIndex, 0), definition.views.count - 1)]
        let evaluator = BaseEvaluator(formulas: definition.formulas, environment: environment, thisRecord: thisRecord, knownRecords: records, provider: provider)
        let columns = view.visibleProperties.map { property in BaseColumn(property: property, displayName: definition.displayName(for: property)) }
        var problems: [String] = []
        let filters = [definition.filters, view.filters].compactMap { filter in filter }
        let filterProblems = Self.syntaxProblems(in: filters, evaluator: evaluator)
        guard filterProblems.isEmpty else {
            return BaseQueryResult(view: view, columns: columns, groups: [], summaries: [:], matchingCount: 0, problems: filterProblems, mapCenter: nil)
        }

        var matchingRecords: [BaseFileRecord] = []
        var failedFilterCount = 0
        var firstFilterFailure: String?
        for record in records {
            do {
                if try filters.allSatisfy({ filter in try evaluator.matches(filter, record: record) }) { matchingRecords.append(record) }
            } catch {
                failedFilterCount += 1
                if firstFilterFailure == nil { firstFilterFailure = "\(record.path.name): \(error.localizedDescription)" }
            }
        }
        if let firstFilterFailure {
            problems.append("\(failedFilterCount) \(failedFilterCount == 1 ? "file was" : "files were") left out because a filter failed. \(firstFilterFailure)")
        }

        let sortKeys = sortOverride ?? view.sort
        let sortedRecords = sort(matchingRecords, by: sortKeys, evaluator: evaluator)
        let limitedRecords = view.limit.map { limit in Array(sortedRecords.prefix(limit)) } ?? sortedRecords
        let rows = limitedRecords.map { record in
            BaseResultRow(path: record.path,
                          cells: columns.map { column in cell(column.property, for: record, evaluator: evaluator) },
                          presentation: presentation(for: record, view: view, evaluator: evaluator))
        }
        let recordsByPath = Dictionary(limitedRecords.map { record in (record.path, record) }, uniquingKeysWith: { firstRecord, _ in firstRecord })
        let groups = group(rows, view: view, columns: columns, recordsByPath: recordsByPath, evaluator: evaluator)
        let summaries = summaryCells(for: rows, view: view, columns: columns, evaluator: evaluator)
        var mapCenter: BaseCoordinate?
        if view.type == .map, let centerText = view.map.center {
            mapCenter = evaluatedCoordinate(centerText, evaluator: evaluator)
            if mapCenter == nil { problems.append("The map center “\(centerText)” is not a latitude and longitude.") }
        }
        return BaseQueryResult(view: view, columns: columns, groups: groups, summaries: summaries, matchingCount: matchingRecords.count, problems: problems, mapCenter: mapCenter)
    }

    /// Every filter expression must parse before any row is shown: a typo must not
    /// silently widen or empty a view.
    static func syntaxProblems(in filters: [BaseFilter], evaluator: BaseEvaluator) -> [String] {
        var problems: [String] = []
        func visit(_ filter: BaseFilter) {
            switch filter {
            case .expression(let sourceText):
                if case .failure(let error) = evaluator.parsed(sourceText) { problems.append("Filter “\(sourceText)”: \(error.localizedDescription)") }
            case .and(let children), .or(let children), .not(let children):
                children.forEach(visit)
            }
        }
        filters.forEach(visit)
        return problems
    }

    private func cell(_ property: BasePropertyIdentifier, for record: BaseFileRecord, evaluator: BaseEvaluator) -> BaseCellValue {
        do {
            let value = try evaluator.value(of: property, for: record)
            // `image()` may hold a link; resolve it here, where the index is at hand, so
            // views receive a vault path, a URL or a color.
            if case .image(let target) = value, case .vaultFile(let path)? = imageReference(for: .string(target), source: record.path, evaluator: evaluator) {
                return .value(.image(path.rawValue))
            }
            return .value(value)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    // MARK: Sorting

    private func sort(_ records: [BaseFileRecord], by sortKeys: [BaseSortKey], evaluator: BaseEvaluator) -> [BaseFileRecord] {
        // Normalized once per value, so text is read as a number or date consistently.
        let keyValues: [[BaseValue?]] = records.map { record in
            sortKeys.map { sortKey in (try? evaluator.value(of: sortKey.property, for: record))?.normalizedForSorting }
        }
        let names = records.map(\.path.name)
        let orderedIndices = records.indices.sorted { leftIndex, rightIndex in
            for (keyIndex, sortKey) in sortKeys.enumerated() {
                let ordering = Self.compareForSorting(keyValues[leftIndex][keyIndex], keyValues[rightIndex][keyIndex], direction: sortKey.direction)
                if ordering != .orderedSame { return ordering == .orderedAscending }
            }
            // Without sort keys, and for ties, files are in natural name order.
            let nameOrdering = names[leftIndex].localizedStandardCompare(names[rightIndex])
            if nameOrdering != .orderedSame { return nameOrdering == .orderedAscending }
            return records[leftIndex].path < records[rightIndex].path
        }
        return orderedIndices.map { index in records[index] }
    }

    /// Empty values and errors sort last in both directions, as in Obsidian.
    static func compareForSorting(_ leftValue: BaseValue?, _ rightValue: BaseValue?, direction: BaseSortDirection) -> ComparisonResult {
        let isLeftEmpty = leftValue?.isEmptyValue ?? true
        let isRightEmpty = rightValue?.isEmptyValue ?? true
        if isLeftEmpty || isRightEmpty {
            if isLeftEmpty && isRightEmpty { return .orderedSame }
            return isLeftEmpty ? .orderedDescending : .orderedAscending
        }
        guard let leftValue, let rightValue else { return .orderedSame }
        // Values of different kinds order by kind alone, and within the text kind one rule
        // applies to every pair. Mixing rules makes cycles (5 < "3a" < [[4]] < 5), which
        // leave the row order undefined. Rows compare text by `<`, as
        // `BaseValue.orderedComparison` does; a formula's `sort()` uses `sortOrder`.
        let leftKind = sortingKind(leftValue), rightKind = sortingKind(rightValue)
        let ordering: ComparisonResult
        if leftKind != rightKind {
            ordering = leftKind < rightKind ? .orderedAscending : .orderedDescending
        } else if leftKind == textSortingKind {
            let leftText = leftValue.displayText, rightText = rightValue.displayText
            ordering = leftText < rightText ? .orderedAscending : (leftText > rightText ? .orderedDescending : .orderedSame)
        } else {
            ordering = BaseValue.sortOrder(leftValue, rightValue)
        }
        guard direction == .descending else { return ordering }
        switch ordering {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }

    /// Text, links, files, images and icons: they compare by their text, as
    /// `BaseValue.orderedComparison` compares text with links and files.
    private static let textSortingKind = 4

    /// The order kinds sort in, matching `BaseValue.sortOrder`'s rank for values of
    /// different types.
    private static func sortingKind(_ value: BaseValue) -> Int {
        switch value {
        case .boolean: 0
        case .number: 1
        case .date: 2
        case .duration: 3
        case .string, .link, .file, .image, .icon: textSortingKind
        case .list: 5
        case .object: 6
        case .regularExpression: 7
        case .null: 8
        }
    }

    // MARK: Grouping and summaries

    private func group(_ rows: [BaseResultRow], view: BaseView, columns: [BaseColumn], recordsByPath: [VaultPath: BaseFileRecord], evaluator: BaseEvaluator) -> [BaseResultGroup] {
        guard let groupBy = view.groupBy else {
            return [BaseResultGroup(id: 0, key: nil, rows: rows, summaries: [:])]
        }
        var groupOrder: [String] = []
        var rowsByGroup: [String: [BaseResultRow]] = [:]
        var keysByGroup: [String: BaseCellValue] = [:]
        // Normalized as for sorting rows, so groups of "10", "9" and "2" follow the same
        // numeric order that sorting by the property gives.
        var sortingValuesByGroup: [String: BaseValue] = [:]
        for row in rows {
            guard let record = recordsByPath[row.path] else { continue }
            let key = cell(groupBy.property, for: record, evaluator: evaluator)
            let identity = groupIdentity(key, source: record.path, evaluator: evaluator)
            if rowsByGroup[identity] == nil {
                groupOrder.append(identity)
                keysByGroup[identity] = key
                sortingValuesByGroup[identity] = key.value?.normalizedForSorting
            }
            rowsByGroup[identity, default: []].append(row)
        }
        let sortedIdentities = groupOrder.sorted { leftIdentity, rightIdentity in
            let ordering = Self.compareForSorting(sortingValuesByGroup[leftIdentity], sortingValuesByGroup[rightIdentity], direction: groupBy.direction)
            if ordering != .orderedSame { return ordering == .orderedAscending }
            return leftIdentity < rightIdentity
        }
        return sortedIdentities.enumerated().map { position, identity in
            let groupRows = rowsByGroup[identity] ?? []
            return BaseResultGroup(id: position, key: keysByGroup[identity], rows: groupRows, summaries: summaryCells(for: groupRows, view: view, columns: columns, evaluator: evaluator))
        }
    }

    /// Rows with equal grouping values share a group. Links group by the file they
    /// resolve to, so `[[Ann]]` and `[[People/Ann]]` share one; a link that resolves to
    /// no single file groups by its written target.
    private func groupIdentity(_ key: BaseCellValue, source: VaultPath, evaluator: BaseEvaluator) -> String {
        switch key {
        case .error(let message): return "error:" + message
        case .value(let value):
            switch value {
            case .null: return "empty"
            case .link(let link):
                if !link.isExternal, let path = evaluator.resolveLink(link.target, from: link.source ?? source) { return "file:" + path.rawValue }
                return "text:" + BaseEvaluator.normalizedLinkText(link.pathPart)
            case .file(let path): return "file:" + path.rawValue
            case .list(let elements) where elements.isEmpty: return "empty"
            case .string(let text) where text.isEmpty: return "empty"
            default: return value.typeName + ":" + value.displayText
            }
        }
    }

    private func summaryCells(for rows: [BaseResultRow], view: BaseView, columns: [BaseColumn], evaluator: BaseEvaluator) -> [BasePropertyIdentifier: BaseSummaryCell] {
        var summaries: [BasePropertyIdentifier: BaseSummaryCell] = [:]
        for (columnIndex, column) in columns.enumerated() {
            guard let summaryName = view.summaries[column.property] else { continue }
            let values = rows.compactMap { row in row.cells[columnIndex].value }
            let summaryValue: BaseCellValue
            if let formulaText = definition.summaryFormulas[summaryName] {
                do { summaryValue = .value(try evaluator.evaluateSummary(sourceText: formulaText, values: values)) }
                catch { summaryValue = .error(error.localizedDescription) }
            } else if let defaultValue = BaseSummaryCalculator.summarize(summaryName, values: values, linkedFile: { link in
                link.isExternal ? nil : evaluator.resolveLink(link.target, from: link.source)
            }) {
                summaryValue = .value(defaultValue)
            } else {
                summaryValue = .error("There is no summary named “\(summaryName)”.")
            }
            summaries[column.property] = BaseSummaryCell(name: summaryName, value: summaryValue)
        }
        return summaries
    }

    // MARK: Presentation

    private func presentation(for record: BaseFileRecord, view: BaseView, evaluator: BaseEvaluator) -> BaseRowPresentation {
        var presentation = BaseRowPresentation()
        switch view.type {
        case .cards:
            if let imageProperty = view.cards.imageProperty, let value = try? evaluator.value(of: imageProperty, for: record) {
                presentation.coverImage = imageReference(for: value, source: record.path, evaluator: evaluator)
            }
        case .map:
            if let coordinatesProperty = view.map.coordinatesProperty, let value = try? evaluator.value(of: coordinatesProperty, for: record) {
                presentation.coordinate = BaseCoordinate(value: value)
            }
            if let iconProperty = view.map.markerIconProperty, let value = try? evaluator.value(of: iconProperty, for: record), value.isTruthy {
                presentation.markerIcon = value.displayText
            }
            if let colorProperty = view.map.markerColorProperty, let value = try? evaluator.value(of: colorProperty, for: record), value.isTruthy {
                presentation.markerColor = value.displayText
            }
        default:
            break
        }
        return presentation
    }

    /// Obsidian's cover sources: a vault image (link or path), a URL, or a hex color.
    func imageReference(for value: BaseValue, source: VaultPath, evaluator: BaseEvaluator) -> BaseImageReference? {
        func vaultImage(_ path: VaultPath?) -> BaseImageReference? {
            guard let path, DocumentKind(path: path) == .image else { return nil }
            return .vaultFile(path)
        }
        switch value {
        case .list(let elements):
            return elements.lazy.compactMap { element in imageReference(for: element, source: source, evaluator: evaluator) }.first
        case .file(let path):
            return vaultImage(path)
        case .link(let link):
            if link.isExternal { return Self.webURL(link.target).map(BaseImageReference.remote) }
            return vaultImage(evaluator.resolveLink(link.target, from: link.source ?? source))
        case .string(let text), .image(let text):
            let trimmedText = text.trimmingCharacters(in: .whitespaces)
            if Self.hexColorPattern?.firstMatch(in: trimmedText, range: NSRange(trimmedText.startIndex..., in: trimmedText)) != nil { return .color(trimmedText) }
            if let url = Self.webURL(trimmedText) { return .remote(url) }
            if let link = BaseLink.parse(trimmedText) { return imageReference(for: .link(link), source: source, evaluator: evaluator) }
            if let path = try? VaultPath(trimmedText), !path.rawValue.isEmpty, evaluator.record(at: path) != nil { return vaultImage(path) }
            return vaultImage(evaluator.resolveLink(trimmedText, from: source))
        default:
            return nil
        }
    }

    /// Compiled once: it runs for every card. `\z` rather than `$`, which would also
    /// match before a final line break.
    private static let hexColorPattern = try? NSRegularExpression(pattern: "^#([0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})\\z")

    /// Covers load only from the web. A note must not make a card show a local file
    /// from outside the vault (`file://`) or send other kinds of requests.
    private static func webURL(_ text: String) -> URL? {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        return url
    }

    private func evaluatedCoordinate(_ centerText: String, evaluator: BaseEvaluator) -> BaseCoordinate? {
        if let value = try? evaluator.evaluate(sourceText: centerText, for: thisRecord), let coordinate = BaseCoordinate(value: value) {
            return coordinate
        }
        return BaseCoordinate(value: .string(centerText))
    }
}

/// Obsidian's built-in summaries.
public enum BaseSummaryCalculator {
    public static let numberSummaryNames = ["Average", "Min", "Max", "Sum", "Range", "Median", "Stddev"]
    public static let dateSummaryNames = ["Earliest", "Latest", "Range"]
    public static let checkboxSummaryNames = ["Checked", "Unchecked"]
    public static let anySummaryNames = ["Empty", "Filled", "Unique"]

    /// The summary value, or nil for a name that is not a built-in summary.
    /// - Parameter linkedFile: The file a link resolves to, so that Unique counts links
    ///   to one note once however they are written.
    public static func summarize(_ name: String, values: [BaseValue], linkedFile: (BaseLink) -> VaultPath? = { _ in nil }) -> BaseValue? {
        let numbers = values.compactMap { value -> Double? in if case .number(let number) = value { return number } else { return nil } }
        let dates = values.compactMap { value -> BaseDate? in if case .date(let date) = value { return date } else { return nil } }
        func count(_ predicate: (BaseValue) -> Bool) -> BaseValue { .number(Double(values.filter(predicate).count)) }
        switch name.lowercased() {
        case "average", "mean": return numbers.isEmpty ? .null : .number(numbers.reduce(0, +) / Double(numbers.count))
        case "min": return numbers.min().map(BaseValue.number) ?? .null
        case "max": return numbers.max().map(BaseValue.number) ?? .null
        case "sum": return .number(numbers.reduce(0, +))
        case "median": return median(numbers).map(BaseValue.number) ?? .null
        case "stddev":
            guard !numbers.isEmpty else { return .null }
            // Population standard deviation over the column's numbers.
            let mean = numbers.reduce(0, +) / Double(numbers.count)
            return .number((numbers.map { number in (number - mean) * (number - mean) }.reduce(0, +) / Double(numbers.count)).squareRoot())
        case "range":
            if let minimum = numbers.min(), let maximum = numbers.max() { return .number(maximum - minimum) }
            guard let earliest = dates.min(by: { leftDate, rightDate in leftDate.date < rightDate.date }),
                  let latest = dates.max(by: { leftDate, rightDate in leftDate.date < rightDate.date }) else { return .null }
            return .duration(BaseDuration(milliseconds: latest.date.timeIntervalSince(earliest.date) * 1_000))
        case "earliest": return dates.min { leftDate, rightDate in leftDate.date < rightDate.date }.map(BaseValue.date) ?? .null
        case "latest": return dates.max { leftDate, rightDate in leftDate.date < rightDate.date }.map(BaseValue.date) ?? .null
        case "checked": return count { value in value == .boolean(true) }
        case "unchecked": return count { value in value == .boolean(false) }
        case "empty": return count(\.isEmptyValue)
        case "filled": return count { value in !value.isEmptyValue }
        case "unique":
            let distinctIdentities = Set(values.filter { value in !value.isEmptyValue }.map { value in uniqueIdentity(of: value, linkedFile: linkedFile) })
            return .number(Double(distinctIdentities.count))
        default: return nil
        }
    }

    /// A link's label is not part of what it points to: `[[Ann]]` and `[[Ann|Annie]]` are one value.
    private static func uniqueIdentity(of value: BaseValue, linkedFile: (BaseLink) -> VaultPath?) -> String {
        switch value {
        case .link(let link):
            if let path = linkedFile(link) { return "file:" + path.rawValue }
            return link.isExternal ? "link:" + link.target : "link:" + BaseEvaluator.normalizedLinkText(link.pathPart)
        case .file(let path):
            return "file:" + path.rawValue
        default:
            return value.typeName + ":" + value.displayText
        }
    }

    static func median(_ numbers: [Double]) -> Double? {
        guard !numbers.isEmpty else { return nil }
        let sortedNumbers = numbers.sorted()
        let middle = sortedNumbers.count / 2
        return sortedNumbers.count % 2 == 0 ? (sortedNumbers[middle - 1] + sortedNumbers[middle]) / 2 : sortedNumbers[middle]
    }
}
