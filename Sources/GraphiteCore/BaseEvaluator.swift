import Foundation

/// Time, calendar and property typing used while evaluating a base.
public struct BaseEvaluationEnvironment: Sendable {
    public var now: Date
    public var calendar: Calendar
    /// `.obsidian/types.json` assignments.
    public var declaredTypes: [String: PropertyType]

    public init(now: Date = .now, calendar: Calendar = BaseDateFormatting.displayCalendar, declaredTypes: [String: PropertyType] = [:]) {
        self.now = now
        self.calendar = calendar
        self.declaredTypes = declaredTypes
    }

    func declaredType(for key: String) -> PropertyType? {
        declaredTypes[key] ?? declaredTypes.first { entry in entry.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }
}

/// Evaluates formulas and filters for the rows of one query. Not thread-safe: create
/// one per query run, off the main actor. It memoizes formula values, link
/// resolutions and record lookups for the lifetime of that run.
public final class BaseEvaluator {
    public let environment: BaseEvaluationEnvironment
    public let thisRecord: BaseFileRecord?
    private let provider: any BaseRecordProvider
    private let parsedFormulas: [String: Result<BaseExpression, BaseExpressionError>]
    private var recordsByPath: [VaultPath: BaseFileRecord]
    private var missingRecordPaths: Set<VaultPath> = []
    private var parsedSources: [String: Result<BaseExpression, BaseExpressionError>] = [:]
    private var formulaResults: [FormulaKey: Result<BaseValue, BaseExpressionError>] = [:]
    private var formulasInProgress: Set<FormulaKey> = []
    private var resolvedLinks: [LinkKey: VaultPath?] = [:]
    private var backlinksByPath: [VaultPath: [VaultPath]] = [:]
    /// `.obsidian/types.json` lookups by property key. A key that is not written exactly
    /// as in types.json falls back to a case-insensitive scan of every declared type.
    private var declaredTypesByKey: [String: PropertyType?] = [:]
    /// A `/pattern/` in a filter or formula is evaluated once per row; compiling it once
    /// per run keeps a regex filter over thousands of rows from recompiling each time.
    private var compiledRegularExpressions: [BaseRegularExpression: Result<NSRegularExpression, BaseExpressionError>] = [:]
    /// How deeply `evaluate` is currently nested, across formula references and callbacks.
    private var evaluationDepth = 0
    /// Bounds work inside `filter`, `map` and `reduce` on very long lists.
    private static let maximumListOperationLength = 100_000
    /// `unique()` compares values that have no hashable identity (links, files, lists, and
    /// text mixed with numbers or dates) pairwise, so its work grows with the square of
    /// the length. 10,000 such values are 50 million comparisons at most.
    private static let maximumPairwiseUniqueLength = 10_000
    /// Nesting shallower than this never checks the stack: every ordinary formula stays
    /// below it, and even an unoptimized build needs only about 8 KiB per level.
    private static let unconditionalEvaluationDepth = 16
    /// Stack left unused when a deeply nested evaluation stops. Covers one more level in
    /// an unoptimized build plus the Foundation and ICU work (dates, regular expressions)
    /// a single level can reach.
    private static let minimumStackHeadroomBytes = 128 * 1_024

    private struct FormulaKey: Hashable {
        let path: VaultPath?
        let name: String
    }

    /// A written link target and the folder of the note it is written in, or nil for a
    /// link with no note (a formula's text).
    private struct LinkKey: Hashable {
        let target: String
        let sourceFolder: VaultPath?
    }

    private struct Scope {
        let record: BaseFileRecord?
        var variables: [String: BaseValue] = [:]
    }

    /// - Parameters:
    ///   - knownRecords: Records already loaded (the query's rows), used before asking the provider.
    ///   - provider: Lookups for files outside `knownRecords`. Defaults to the known records only.
    public init(formulas: [BaseFormula], environment: BaseEvaluationEnvironment, thisRecord: BaseFileRecord?, knownRecords: [BaseFileRecord] = [], provider: (any BaseRecordProvider)? = nil) {
        self.environment = environment
        self.thisRecord = thisRecord
        var records = knownRecords
        if let thisRecord { records.append(thisRecord) }
        self.provider = provider ?? BaseInMemoryRecordProvider(records: records)
        recordsByPath = Dictionary(records.map { record in (record.path, record) }, uniquingKeysWith: { firstRecord, _ in firstRecord })
        var formulasByName: [String: Result<BaseExpression, BaseExpressionError>] = [:]
        for formula in formulas {
            formulasByName[formula.name] = Result { try BaseExpression.parse(formula.sourceText) }.mapError { error in
                (error as? BaseExpressionError) ?? .evaluation(error.localizedDescription)
            }
        }
        parsedFormulas = formulasByName
    }

    // MARK: Public entry points

    /// Parses expression text once per evaluator.
    public func parsed(_ sourceText: String) -> Result<BaseExpression, BaseExpressionError> {
        if let cached = parsedSources[sourceText] { return cached }
        let result = Result { try BaseExpression.parse(sourceText) }.mapError { error in (error as? BaseExpressionError) ?? .evaluation(error.localizedDescription) }
        parsedSources[sourceText] = result
        return result
    }

    public func evaluate(_ expression: BaseExpression, for record: BaseFileRecord?) throws -> BaseValue {
        try evaluate(expression, in: Scope(record: record))
    }

    public func evaluate(sourceText: String, for record: BaseFileRecord?) throws -> BaseValue {
        try evaluate(parsed(sourceText).get(), for: record)
    }

    /// The value of a column for a row.
    public func value(of property: BasePropertyIdentifier, for record: BaseFileRecord) throws -> BaseValue {
        switch property {
        case .note(let name): return noteProperty(name, of: record)
        case .file(let name): return try fileField(name, of: record.path)
        case .formula(let name): return try formulaValue(name, for: record)
        }
    }

    /// Whether a row passes a filter tree. Throws for a filter that cannot be parsed
    /// or evaluated for this row.
    public func matches(_ filter: BaseFilter, record: BaseFileRecord) throws -> Bool {
        switch filter {
        case .expression(let sourceText):
            return try evaluate(parsed(sourceText).get(), in: Scope(record: record)).isTruthy
        case .and(let children):
            for child in children where try !matches(child, record: record) { return false }
            return true
        case .or(let children):
            if children.isEmpty { return true }
            for child in children where try matches(child, record: record) { return true }
            return false
        case .not(let children):
            for child in children where try matches(child, record: record) { return false }
            return true
        }
    }

    /// Evaluates a custom summary formula; `values` holds the column's values.
    public func evaluateSummary(sourceText: String, values: [BaseValue]) throws -> BaseValue {
        try evaluate(parsed(sourceText).get(), in: Scope(record: nil, variables: ["values": .list(values)]))
    }

    /// The single file a link target resolves to from `source`, if any.
    public func resolveLink(_ target: String, from source: VaultPath?) -> VaultPath? {
        let pathPart = WikiLinkResolver.pathPart(target)
        // `[[#Heading]]` names the note it is written in.
        if pathPart.isEmpty { return source }
        // A provider resolves a link from its note's folder only (see
        // `BaseRecordProvider.resolveLinkTarget`), so every row in one folder shares one
        // resolution instead of each row asking the index again.
        let key = LinkKey(target: target, sourceFolder: source?.parent)
        if let cached = resolvedLinks[key] { return cached }
        var resolvedPath: VaultPath?
        if let source {
            resolvedPath = provider.resolveLinkTarget(target, from: source)
        } else if let rootedPath = try? VaultPath(pathPart), record(at: rootedPath) != nil {
            resolvedPath = rootedPath
        } else {
            resolvedPath = provider.resolveLinkTarget(target, from: .root)
        }
        resolvedLinks[key] = resolvedPath
        return resolvedPath
    }

    public func record(at path: VaultPath) -> BaseFileRecord? {
        if let record = recordsByPath[path] { return record }
        if missingRecordPaths.contains(path) { return nil }
        guard let record = provider.record(at: path) else {
            missingRecordPaths.insert(path)
            return nil
        }
        recordsByPath[path] = record
        return record
    }

    // MARK: Expressions

    private func evaluate(_ expression: BaseExpression, in scope: Scope) throws -> BaseValue {
        // Formulas that read other formulas, long method chains and nested callbacks all
        // recurse through here. A base query runs on a Swift concurrency thread whose
        // stack is only 512 KiB, and exhausting it ends the app, so a pathological .base
        // file becomes an error in its cells instead.
        evaluationDepth += 1
        defer { evaluationDepth -= 1 }
        if evaluationDepth > Self.unconditionalEvaluationDepth, !Self.currentThreadHasStackHeadroom() {
            throw BaseExpressionError.evaluation("The formula is nested too deeply to evaluate.")
        }
        switch expression {
        case .literal(let value):
            return value
        case .identifier(let name):
            return try identifierValue(name, in: scope)
        case .member(let base, let name):
            return try memberValue(base: base, name: name, in: scope)
        case .subscripted(let base, let subscriptExpression):
            let key = try evaluate(subscriptExpression, in: scope)
            if case .identifier(let baseName) = base, scope.variables[baseName] == nil, case .string(let keyText) = key {
                switch baseName {
                case "note": return noteProperty(keyText, of: scope.record)
                case "formula": return try formulaValue(keyText, for: scope.record)
                case "this": return try thisMember(keyText)
                default: break
                }
            }
            return try subscriptValue(evaluate(base, in: scope), key: key)
        case .functionCall(let name, let arguments):
            return try callFunction(name, arguments: arguments, in: scope)
        case .methodCall(let receiverExpression, let name, let arguments):
            return try callMethod(name, on: receiverExpression, arguments: arguments, in: scope)
        case .unary(let unaryOperator, let operand):
            let operandValue = try evaluate(operand, in: scope)
            switch unaryOperator {
            case .not: return .boolean(!operandValue.isTruthy)
            case .plus: return try numberValue(operandValue, context: "+")
            case .negate:
                switch operandValue {
                case .number(let number): return .number(-number)
                case .duration(let duration): return .duration(duration.negated())
                case .null: return .null
                default: throw BaseExpressionError.evaluation("Cannot negate \(Self.describe(operandValue)).")
                }
            }
        case .binary(let binaryOperator, let leftExpression, let rightExpression):
            switch binaryOperator {
            case .and:
                guard try evaluate(leftExpression, in: scope).isTruthy else { return .boolean(false) }
                return .boolean(try evaluate(rightExpression, in: scope).isTruthy)
            case .or:
                if try evaluate(leftExpression, in: scope).isTruthy { return .boolean(true) }
                return .boolean(try evaluate(rightExpression, in: scope).isTruthy)
            default:
                return try binaryValue(binaryOperator, try evaluate(leftExpression, in: scope), try evaluate(rightExpression, in: scope))
            }
        case .listLiteral(let elements):
            return .list(try elements.map { element in try evaluate(element, in: scope) })
        }
    }

    /// Whether the calling thread has at least `minimumStackHeadroomBytes` of stack left.
    /// The stack grows down from `pthread_get_stackaddr_np`, and the address of a local
    /// variable marks how far it has grown.
    private static func currentThreadHasStackHeadroom() -> Bool {
        let thread = pthread_self()
        let stackTopAddress = UInt(bitPattern: pthread_get_stackaddr_np(thread))
        let stackSizeBytes = UInt(pthread_get_stacksize_np(thread))
        guard stackTopAddress > stackSizeBytes else { return true }
        var stackMarker: UInt8 = 0
        let currentAddress = withUnsafeMutablePointer(to: &stackMarker) { pointer in UInt(bitPattern: pointer) }
        let stackBottomAddress = stackTopAddress - stackSizeBytes
        return currentAddress > stackBottomAddress && currentAddress - stackBottomAddress > UInt(minimumStackHeadroomBytes)
    }

    private func identifierValue(_ name: String, in scope: Scope) throws -> BaseValue {
        if let variable = scope.variables[name] { return variable }
        switch name {
        case "this": return thisRecord.map { record in .file(record.path) } ?? .null
        case "file": return scope.record.map { record in .file(record.path) } ?? .null
        case "note": return noteObject(of: scope.record)
        case "formula": throw BaseExpressionError.evaluation("Use formula.name to read a formula.")
        default: return noteProperty(name, of: scope.record)
        }
    }

    private func memberValue(base: BaseExpression, name: String, in scope: Scope) throws -> BaseValue {
        if case .identifier(let baseName) = base, scope.variables[baseName] == nil {
            switch baseName {
            case "formula": return try formulaValue(name, for: scope.record)
            case "note": return noteProperty(name, of: scope.record)
            case "this": return try thisMember(name)
            default: break
            }
        }
        if case .member(.identifier("this"), let group) = base, scope.variables["this"] == nil {
            if group == "formula" { return try formulaValue(name, for: thisRecord) }
            if group == "note" { return noteProperty(name, of: thisRecord) }
        }
        return try field(name, of: evaluate(base, in: scope))
    }

    /// `this.name` and `this["name"]`: the embedding note's file, properties, or one property.
    private func thisMember(_ name: String) throws -> BaseValue {
        switch name {
        case "file": return thisRecord.map { record in .file(record.path) } ?? .null
        case "note": return noteObject(of: thisRecord)
        case "formula": throw BaseExpressionError.evaluation("Use this.formula.name to read a formula.")
        default: return noteProperty(name, of: thisRecord)
        }
    }

    private func field(_ name: String, of value: BaseValue) throws -> BaseValue {
        switch value {
        case .null:
            return .null
        case .file(let path):
            return try fileField(name, of: path)
        case .link(let link):
            guard let path = resolveLink(link.target, from: link.source) else { return .null }
            return try fileField(name, of: path)
        case .date(let date):
            let parts = environment.calendar.dateComponents([.era, .year, .month, .day, .hour, .minute, .second], from: date.date)
            switch name {
            case "year": return .number(Double(Self.astronomicalYear(era: parts.era, year: parts.year ?? 0)))
            case "month": return .number(Double(parts.month ?? 0))
            case "day": return .number(Double(parts.day ?? 0))
            case "hour": return .number(Double(parts.hour ?? 0))
            case "minute": return .number(Double(parts.minute ?? 0))
            case "second": return .number(Double(parts.second ?? 0))
            case "millisecond": return .number(Self.millisecondOfSecond(date.date))
            default: break
            }
        case .duration(let duration):
            let total = duration.totalMilliseconds
            switch name {
            case "years": return .number(total / (365.2425 * BaseDuration.millisecondsPerDay))
            case "months": return .number(total / (BaseDuration.averageDaysPerMonth * BaseDuration.millisecondsPerDay))
            case "weeks": return .number(total / (7 * BaseDuration.millisecondsPerDay))
            case "days": return .number(total / BaseDuration.millisecondsPerDay)
            case "hours": return .number(total / 3_600_000)
            case "minutes": return .number(total / 60_000)
            case "seconds": return .number(total / 1_000)
            case "milliseconds": return .number(total)
            default: break
            }
        case .string(let text):
            if name == "length" { return .number(Double(text.count)) }
        case .list(let elements):
            if name == "length" { return .number(Double(elements.count)) }
        case .object(let object):
            return object[name] ?? .null
        default:
            break
        }
        throw BaseExpressionError.evaluation("\(Self.describe(value).capitalizedFirstLetter) has no field “\(name)”.")
    }

    /// The year as JavaScript's `getFullYear()` and moment's `YYYY` count it: 1 BCE is 0,
    /// 2 BCE is -1. The Gregorian calendar numbers years before the common era upward
    /// from 1 in era 0.
    private static func astronomicalYear(era: Int?, year: Int) -> Int {
        era == 0 ? 1 - year : year
    }

    /// The millisecond within the second, 0 to 999, like JavaScript's `getMilliseconds()`.
    /// Calendar nanoseconds come from a binary time interval, so 0.123 s reads back as
    /// 122,999,999 ns. Truncating with half a microsecond of tolerance recovers the whole
    /// millisecond: a time interval near today is off by at most a fraction of that.
    private static func millisecondOfSecond(_ date: Date) -> Double {
        let totalMilliseconds = (date.timeIntervalSince1970 * 1_000 + 0.000_5).rounded(.down)
        let millisecond = totalMilliseconds.truncatingRemainder(dividingBy: 1_000)
        // abs turns the -0 of a negative whole second into 0.
        return millisecond < 0 ? millisecond + 1_000 : abs(millisecond)
    }

    private func subscriptValue(_ value: BaseValue, key: BaseValue) throws -> BaseValue {
        switch (value, key) {
        case (.null, _): return .null
        // Like JavaScript, only a whole number that is a valid position indexes; a
        // fractional, non-finite or out-of-range number gives an empty value.
        case (.list(let elements), .number(let number)):
            guard let index = Int(exactly: number) else { return .null }
            return elements.indices.contains(index) ? elements[index] : .null
        case (.string(let text), .number(let number)):
            guard let index = Int(exactly: number), index >= 0, index < text.count else { return .null }
            return .string(String(text[text.index(text.startIndex, offsetBy: index)]))
        case (.object(let object), .string(let keyText)):
            return object[keyText] ?? .null
        case (_, .string(let keyText)):
            return try field(keyText, of: value)
        default:
            throw BaseExpressionError.evaluation("Cannot index \(Self.describe(value)) with \(Self.describe(key)).")
        }
    }

    // MARK: Properties, files and formulas

    private func noteProperty(_ name: String, of record: BaseFileRecord?) -> BaseValue {
        guard let record, let entry = record.propertyEntry(named: name) else { return .null }
        return BaseFrontmatter.value(of: entry.node, declaredType: declaredType(for: entry.key), source: record.path, calendar: environment.calendar)
    }

    private func noteObject(of record: BaseFileRecord?) -> BaseValue {
        guard let record else { return .null }
        return .object(BaseObject(entries: record.properties.map { entry in
            BaseObjectEntry(key: entry.key, value: BaseFrontmatter.value(of: entry.node, declaredType: declaredType(for: entry.key), source: record.path, calendar: environment.calendar))
        }))
    }

    private func declaredType(for key: String) -> PropertyType? {
        if let cachedType = declaredTypesByKey[key] { return cachedType }
        let declaredType = environment.declaredType(for: key)
        declaredTypesByKey[key] = declaredType
        return declaredType
    }

    private func formulaValue(_ name: String, for record: BaseFileRecord?) throws -> BaseValue {
        let key = FormulaKey(path: record?.path, name: name)
        if let cached = formulaResults[key] { return try cached.get() }
        guard let parsedFormula = parsedFormulas[name] else { throw BaseExpressionError.evaluation("There is no formula named “\(name)”.") }
        guard !formulasInProgress.contains(key) else { throw BaseExpressionError.evaluation("Formula “\(name)” refers to itself.") }
        formulasInProgress.insert(key)
        defer { formulasInProgress.remove(key) }
        let result: Result<BaseValue, BaseExpressionError> = Result {
            let expression: BaseExpression
            do { expression = try parsedFormula.get() }
            catch { throw BaseExpressionError.evaluation("Formula “\(name)”: \(error.localizedDescription)") }
            return try evaluate(expression, in: Scope(record: record))
        }.mapError { error in (error as? BaseExpressionError) ?? .evaluation(error.localizedDescription) }
        formulaResults[key] = result
        return try result.get()
    }

    private func fileField(_ name: String, of path: VaultPath) throws -> BaseValue {
        let record = record(at: path)
        switch name {
        case "name": return .string(path.name)
        case "basename": return .string(path.stem)
        case "path": return .string(path.rawValue)
        case "folder": return .string(path.parent.rawValue.isEmpty ? "/" : path.parent.rawValue)
        case "ext": return .string((path.name as NSString).pathExtension)
        case "file": return .file(path)
        case "size": return record.map { record in .number(Double(record.size)) } ?? .null
        case "ctime": return record.map { record in .date(BaseDate(date: record.createdDate, hasTime: true)) } ?? .null
        case "mtime": return record.map { record in .date(BaseDate(date: record.modifiedDate, hasTime: true)) } ?? .null
        case "tags": return .list((record?.tags ?? []).map { tag in .string("#" + tag) })
        case "links": return .list(linkTargets(of: record, includesEmbeds: false).map { target in .link(BaseLink(target: target, source: path)) })
        case "embeds": return .list(internalBodyLinks(of: record).filter(\.isEmbed).map { link in .link(BaseLink(target: link.target, source: path)) })
        case "backlinks": return .list(backlinks(to: path).map(BaseValue.file))
        case "properties": return noteObject(of: record)
        default: return noteProperty(name, of: record)
        }
    }

    /// Body links, then links written in properties, as Obsidian's `file.links` lists them.
    private func linkTargets(of record: BaseFileRecord?, includesEmbeds: Bool) -> [String] {
        guard let record else { return [] }
        let bodyTargets = internalBodyLinks(of: record).filter { link in includesEmbeds || !link.isEmbed }.map(\.target)
        return bodyTargets + BaseFrontmatter.links(in: record.properties).map(\.target)
    }

    /// The index keeps every Markdown link destination, web pages and `mailto:` included;
    /// Obsidian's link lists hold only links to vault files, as property links already do.
    private func internalBodyLinks(of record: BaseFileRecord?) -> [BaseRecordLink] {
        (record?.links ?? []).filter { link in link.isWiki || !BaseLink(target: link.target).isExternal }
    }

    private func backlinks(to path: VaultPath) -> [VaultPath] {
        if let cached = backlinksByPath[path] { return cached }
        let sources = provider.backlinks(to: path)
        backlinksByPath[path] = sources
        return sources
    }

    /// Whether a link target written in `source` points at `destination`. Unresolvable
    /// targets fall back to comparing names, so a link to a note that is missing from
    /// the index still matches by its written name.
    func link(_ target: String, from source: VaultPath?, pointsTo destination: VaultPath) -> Bool {
        if let resolvedPath = resolveLink(target, from: source) { return resolvedPath == destination }
        let normalizedTarget = Self.normalizedLinkText(WikiLinkResolver.pathPart(target))
        let destinationWithoutExtension = Self.normalizedLinkText(destination.rawValue)
        if normalizedTarget == destinationWithoutExtension { return true }
        return !normalizedTarget.contains("/") && normalizedTarget == Self.normalizedLinkText(destination.name)
    }

    /// Lowercased and Unicode-normalized, without a trailing `.md` and surrounding slashes.
    static func normalizedLinkText(_ text: String) -> String {
        var normalizedText = WikiLinkResolver.comparisonKey(text.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))).lowercased()
        if normalizedText.hasSuffix(".md") { normalizedText.removeLast(3) }
        return normalizedText
    }

    /// The file a value refers to: a file, a link, or text naming a path or link target.
    private func filePath(of value: BaseValue, from source: VaultPath?) -> VaultPath? {
        switch value {
        case .file(let path): return path
        case .link(let link): return resolveLink(link.target, from: link.source ?? source)
        case .string(let text):
            // Empty text names no file. resolveLink would read it as a link to the note itself.
            if text.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
            if let link = BaseLink.parse(text) { return resolveLink(link.target, from: source) }
            if let path = try? VaultPath(text), !path.rawValue.isEmpty, record(at: path) != nil { return path }
            return resolveLink(text, from: source)
        default: return nil
        }
    }

    // MARK: Equality

    /// `==` semantics: links and files are equal when they point at the same file;
    /// numbers and numeric text, dates and date text compare by value.
    func isEqual(_ leftValue: BaseValue, _ rightValue: BaseValue) -> Bool {
        switch (leftValue, rightValue) {
        case (.null, .null): return true
        case (.null, _), (_, .null): return false
        case (.number(let leftNumber), .number(let rightNumber)): return leftNumber == rightNumber
        case (.string(let leftText), .string(let rightText)): return leftText == rightText
        case (.boolean(let leftFlag), .boolean(let rightFlag)): return leftFlag == rightFlag
        case (.date(let leftDate), .date(let rightDate)): return leftDate.date == rightDate.date
        case (.duration(let leftDuration), .duration(let rightDuration)): return leftDuration.totalMilliseconds == rightDuration.totalMilliseconds
        case (.file(let leftPath), .file(let rightPath)): return leftPath == rightPath
        case (.link(let link), .file(let path)), (.file(let path), .link(let link)):
            return self.link(link.target, from: link.source, pointsTo: path)
        case (.link(let leftLink), .link(let rightLink)):
            if let leftPath = resolveLink(leftLink.target, from: leftLink.source), let rightPath = resolveLink(rightLink.target, from: rightLink.source) {
                return leftPath == rightPath
            }
            return Self.normalizedLinkText(leftLink.pathPart) == Self.normalizedLinkText(rightLink.pathPart)
        case (.link(let link), .string(let text)), (.string(let text), .link(let link)):
            if let textLink = BaseLink.parse(text) { return isEqual(.link(link), .link(textLink)) }
            return Self.normalizedLinkText(link.pathPart) == Self.normalizedLinkText(text)
        case (.file(let path), .string(let text)), (.string(let text), .file(let path)):
            if let textPath = filePath(of: .string(text), from: nil) { return textPath == path }
            return Self.normalizedLinkText(text) == Self.normalizedLinkText(path.rawValue)
        case (.list(let leftElements), .list(let rightElements)):
            return leftElements.count == rightElements.count && zip(leftElements, rightElements).allSatisfy { pair in isEqual(pair.0, pair.1) }
        case (.duration(let duration), .number(let milliseconds)), (.number(let milliseconds), .duration(let duration)):
            return duration.totalMilliseconds == milliseconds
        case (.number, .string), (.string, .number), (.date, .string), (.string, .date):
            return BaseValue.orderedComparison(leftValue, rightValue) == .orderedSame
        default:
            return leftValue == rightValue
        }
    }

    // MARK: Operators

    private func binaryValue(_ binaryOperator: BaseBinaryOperator, _ leftValue: BaseValue, _ rightValue: BaseValue) throws -> BaseValue {
        switch binaryOperator {
        case .equal: return .boolean(isEqual(leftValue, rightValue))
        case .notEqual: return .boolean(!isEqual(leftValue, rightValue))
        case .less, .lessOrEqual, .greater, .greaterOrEqual:
            guard let ordering = BaseValue.orderedComparison(Self.millisecondsIfComparedWithNumber(leftValue, rightValue),
                                                             Self.millisecondsIfComparedWithNumber(rightValue, leftValue)) else { return .boolean(false) }
            switch binaryOperator {
            case .less: return .boolean(ordering == .orderedAscending)
            case .lessOrEqual: return .boolean(ordering != .orderedDescending)
            case .greater: return .boolean(ordering == .orderedDescending)
            default: return .boolean(ordering != .orderedAscending)
            }
        case .add: return try addition(leftValue, rightValue)
        case .subtract: return try subtraction(leftValue, rightValue)
        case .multiply, .divide, .remainder: return try multiplicative(binaryOperator, leftValue, rightValue)
        case .and, .or: return .boolean(false)
        }
    }

    /// Obsidian's syntax help describes `now() - file.ctime` as the difference in
    /// milliseconds, so filters such as `(now() - file.ctime) > 86400000` compare the
    /// duration's length in milliseconds. The difference stays a duration so `.days` works.
    private static func millisecondsIfComparedWithNumber(_ value: BaseValue, _ otherValue: BaseValue) -> BaseValue {
        guard case .duration(let duration) = value, case .number = otherValue else { return value }
        return .number(duration.totalMilliseconds)
    }

    private func duration(from value: BaseValue) -> BaseDuration? {
        switch value {
        case .duration(let duration): return duration
        case .string(let text): return BaseDurationParsing.duration(from: text)
        case .number(let milliseconds): return BaseDuration(milliseconds: milliseconds)
        default: return nil
        }
    }

    private func addition(_ leftValue: BaseValue, _ rightValue: BaseValue) throws -> BaseValue {
        switch (leftValue, rightValue) {
        case (.number(let leftNumber), .number(let rightNumber)): return .number(leftNumber + rightNumber)
        case (.date(let date), _):
            if let duration = duration(from: rightValue) { return .date(BaseDateArithmetic.adding(duration, to: date, calendar: environment.calendar)) }
        case (.duration(let duration), .date(let date)):
            return .date(BaseDateArithmetic.adding(duration, to: date, calendar: environment.calendar))
        case (.duration(let leftDuration), _):
            if let rightDuration = duration(from: rightValue) { return .duration(leftDuration.adding(rightDuration)) }
        case (.list(let leftElements), .list(let rightElements)):
            return .list(leftElements + rightElements)
        default: break
        }
        if case .string(let leftText) = leftValue { return .string(leftText + rightValue.displayText) }
        if case .string(let rightText) = rightValue { return .string(leftValue.displayText + rightText) }
        if leftValue.isNull || rightValue.isNull { return .null }
        // As in JavaScript, true and false add as 1 and 0; text concatenates instead (above).
        if let leftNumber = Self.arithmeticNumber(leftValue, acceptsText: false), let rightNumber = Self.arithmeticNumber(rightValue, acceptsText: false) {
            return .number(leftNumber + rightNumber)
        }
        throw BaseExpressionError.evaluation("Cannot add \(Self.describe(leftValue)) and \(Self.describe(rightValue)).")
    }

    private func subtraction(_ leftValue: BaseValue, _ rightValue: BaseValue) throws -> BaseValue {
        switch (leftValue, rightValue) {
        case (.number(let leftNumber), .number(let rightNumber)): return .number(leftNumber - rightNumber)
        case (.date(let leftDate), .date(let rightDate)):
            return .duration(BaseDuration(milliseconds: (leftDate.date.timeIntervalSince1970 - rightDate.date.timeIntervalSince1970) * 1_000))
        case (.date(let date), _):
            if let duration = duration(from: rightValue) { return .date(BaseDateArithmetic.adding(duration.negated(), to: date, calendar: environment.calendar)) }
            if case .string(let text) = rightValue, let otherDate = BaseDateParsing.date(from: text, calendar: environment.calendar) {
                return .duration(BaseDuration(milliseconds: (date.date.timeIntervalSince1970 - otherDate.date.timeIntervalSince1970) * 1_000))
            }
        case (.duration(let leftDuration), _):
            if let rightDuration = duration(from: rightValue) { return .duration(leftDuration.adding(rightDuration.negated())) }
        default: break
        }
        if leftValue.isNull || rightValue.isNull { return .null }
        // Subtraction coerces numeric text and true/false exactly as `*`, `/` and `%` do.
        if let leftNumber = Self.arithmeticNumber(leftValue, acceptsText: true), let rightNumber = Self.arithmeticNumber(rightValue, acceptsText: true) {
            return .number(leftNumber - rightNumber)
        }
        throw BaseExpressionError.evaluation("Cannot subtract \(Self.describe(rightValue)) from \(Self.describe(leftValue)).")
    }

    private func multiplicative(_ binaryOperator: BaseBinaryOperator, _ leftValue: BaseValue, _ rightValue: BaseValue) throws -> BaseValue {
        if leftValue.isNull || rightValue.isNull { return .null }
        switch (binaryOperator, leftValue, rightValue) {
        case (.multiply, .duration(let duration), .number(let factor)), (.multiply, .number(let factor), .duration(let duration)):
            return .duration(duration.scaled(by: factor))
        case (.divide, .duration(let duration), .number(let divisor)):
            guard divisor != 0 else { throw BaseExpressionError.evaluation("Division by zero.") }
            return .duration(duration.scaled(by: 1 / divisor))
        default: break
        }
        guard case .number(let leftNumber) = try numberValue(leftValue, context: binaryOperator.rawValue),
              case .number(let rightNumber) = try numberValue(rightValue, context: binaryOperator.rawValue) else { return .null }
        switch binaryOperator {
        case .multiply: return .number(leftNumber * rightNumber)
        case .divide:
            guard rightNumber != 0 else { throw BaseExpressionError.evaluation("Division by zero.") }
            return .number(leftNumber / rightNumber)
        default:
            guard rightNumber != 0 else { throw BaseExpressionError.evaluation("Division by zero.") }
            return .number(leftNumber.truncatingRemainder(dividingBy: rightNumber))
        }
    }

    /// Numbers, numeric text and booleans used arithmetically.
    private func numberValue(_ value: BaseValue, context: String) throws -> BaseValue {
        if value.isNull { return .null }
        guard let number = Self.arithmeticNumber(value, acceptsText: true) else {
            throw BaseExpressionError.evaluation("“\(context)” needs numbers, not \(Self.describe(value)).")
        }
        return .number(number)
    }

    /// The number a value stands for in arithmetic: itself, 1 or 0 for true or false,
    /// and, when `acceptsText` is set, the number that text spells.
    private static func arithmeticNumber(_ value: BaseValue, acceptsText: Bool) -> Double? {
        switch value {
        case .number(let number): return number
        case .boolean(let isTrue): return isTrue ? 1 : 0
        case .string(let text) where acceptsText: return Double(text.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    // MARK: Global functions

    private func callFunction(_ name: String, arguments: [BaseExpression], in scope: Scope) throws -> BaseValue {
        if name == "if" {
            guard (2...3).contains(arguments.count) else { throw BaseExpressionError.evaluation("if() takes a condition, a result, and an optional alternative.") }
            if try evaluate(arguments[0], in: scope).isTruthy { return try evaluate(arguments[1], in: scope) }
            return arguments.count == 3 ? try evaluate(arguments[2], in: scope) : .null
        }
        let values = try arguments.map { argument in try evaluate(argument, in: scope) }
        func requireCount(_ range: ClosedRange<Int>) throws {
            guard range.contains(values.count) else {
                throw BaseExpressionError.evaluation("\(name)() takes \(range.lowerBound == range.upperBound ? "\(range.lowerBound)" : "\(range.lowerBound) to \(range.upperBound)") argument\(range.upperBound == 1 ? "" : "s").")
            }
        }
        switch name {
        case "now":
            try requireCount(0...0)
            return .date(BaseDate(date: environment.now, hasTime: true))
        case "today":
            try requireCount(0...0)
            return .date(BaseDate(date: environment.calendar.startOfDay(for: environment.now), hasTime: false))
        case "date":
            try requireCount(1...1)
            switch values[0] {
            case .null: return .null
            case .date: return values[0]
            case .number(let milliseconds): return .date(BaseDate(date: Date(timeIntervalSince1970: milliseconds / 1_000), hasTime: true))
            case .string(let text):
                guard let date = BaseDateParsing.date(from: text, calendar: environment.calendar) else { throw BaseExpressionError.evaluation("“\(text)” is not a date. Use YYYY-MM-DD or YYYY-MM-DD HH:mm:ss.") }
                return .date(date)
            case .link(let link):
                // Daily-note links are often aliased, as in [[2024-01-05|Friday]], so the
                // linked note's name comes first and the alias is only a fallback.
                let noteName = BaseLink(target: (link.pathPart as NSString).lastPathComponent).displayText
                guard let date = BaseDateParsing.date(from: noteName, calendar: environment.calendar)
                        ?? BaseDateParsing.date(from: link.displayText, calendar: environment.calendar) else {
                    throw BaseExpressionError.evaluation("“\(link.displayText)” is not a date.")
                }
                return .date(date)
            default: throw BaseExpressionError.evaluation("date() needs text, not \(Self.describe(values[0])).")
            }
        case "duration":
            try requireCount(1...1)
            if values[0].isNull { return .null }
            guard let duration = duration(from: values[0]) else { throw BaseExpressionError.evaluation("“\(values[0].displayText)” is not a duration, for example \"1 day\" or \"2h\".") }
            return .duration(duration)
        case "number":
            try requireCount(1...1)
            switch values[0] {
            case .date(let date): return .number((date.date.timeIntervalSince1970 * 1_000).rounded())
            case .duration(let duration): return .number(duration.totalMilliseconds)
            default: return try numberValue(values[0], context: "number()")
            }
        case "list":
            try requireCount(1...1)
            switch values[0] {
            case .list: return values[0]
            case .null: return .list([])
            default: return .list([values[0]])
            }
        case "min", "max":
            let numbers = values.flatMap { value -> [BaseValue] in if case .list(let elements) = value { return elements } else { return [value] } }
                .compactMap { value -> Double? in if case .number(let number) = value { return number } else { return nil } }
            guard let extreme = name == "min" ? numbers.min() : numbers.max() else { return .null }
            return .number(extreme)
        case "link":
            try requireCount(1...2)
            let display = values.count == 2 && !values[1].isNull ? values[1].displayText : nil
            switch values[0] {
            case .null: return .null
            case .file(let path): return .link(BaseLink(target: path.rawValue, display: display))
            case .link(var link):
                if let display { link.display = display }
                return .link(link)
            default:
                var link = BaseLink.parse(values[0].displayText, source: scope.record?.path) ?? BaseLink(target: values[0].displayText, source: scope.record?.path)
                if let display { link.display = display }
                return .link(link)
            }
        case "file":
            try requireCount(1...1)
            guard let path = filePath(of: values[0], from: scope.record?.path) else { return .null }
            return .file(path)
        case "image":
            try requireCount(1...1)
            switch values[0] {
            case .null: return .null
            case .file(let path): return .image(path.rawValue)
            case .link(let link): return .image(link.isExternal ? link.target : "[[\(link.target)]]")
            default: return .image(values[0].displayText)
            }
        case "icon":
            try requireCount(1...1)
            return values[0].isNull ? .null : .icon(values[0].displayText)
        case "escapeHTML":
            try requireCount(1...1)
            return .string(values[0].displayText.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;"))
        case "html":
            throw BaseExpressionError.evaluation("html() is not supported in Graphite.")
        case "random":
            try requireCount(0...0)
            return .number(Double.random(in: 0..<1))
        default:
            throw BaseExpressionError.evaluation("There is no function named “\(name)”.")
        }
    }

    // MARK: Methods

    private func callMethod(_ name: String, on receiverExpression: BaseExpression, arguments: [BaseExpression], in scope: Scope) throws -> BaseValue {
        let receiver = try evaluate(receiverExpression, in: scope)
        // Callbacks see `value`, `index` and `acc`, so they are evaluated per element.
        if case .list(let elements) = receiver, ["filter", "map", "reduce"].contains(name) {
            return try listCallback(name, elements: elements, arguments: arguments, in: scope)
        }
        let values = try arguments.map { argument in try evaluate(argument, in: scope) }
        if let result = try typedMethod(name, receiver: receiver, arguments: values, in: scope) { return result }
        switch name {
        case "isTruthy": return .boolean(receiver.isTruthy)
        case "isEmpty": return .boolean(receiver.isEmptyValue)
        case "toString": return .string(receiver.displayText)
        case "isType":
            guard let typeName = values.first?.displayText.lowercased() else { throw BaseExpressionError.evaluation("isType() needs a type name.") }
            return .boolean(receiver.typeName == typeName || (typeName == "regex" && receiver.typeName == "regexp"))
        default: break
        }
        if receiver.isNull { return name == "contains" || name.hasPrefix("contains") || name.hasPrefix("has") ? .boolean(false) : .null }
        throw BaseExpressionError.evaluation("\(Self.describe(receiver).capitalizedFirstLetter) has no function “\(name)()”.")
    }

    private func typedMethod(_ name: String, receiver: BaseValue, arguments: [BaseValue], in scope: Scope) throws -> BaseValue? {
        switch receiver {
        case .string(let text): return try stringMethod(name, text: text, arguments: arguments)
        case .number(let number): return try numberMethod(name, number: number, arguments: arguments)
        case .list(let elements): return try listMethod(name, elements: elements, arguments: arguments)
        case .date(let date): return try dateMethod(name, date: date, arguments: arguments)
        case .file(let path): return try fileMethod(name, path: path, arguments: arguments)
        case .link(let link): return try linkMethod(name, link: link, arguments: arguments)
        case .object(let object):
            switch name {
            case "keys": return .list(object.entries.map { entry in .string(entry.key) })
            case "values": return .list(object.entries.map(\.value))
            default: return nil
            }
        case .regularExpression(let expression):
            guard name == "matches" else { return nil }
            let text = arguments.first?.displayText ?? ""
            let compiled = try compiledRegularExpression(expression)
            let firstMatches = try Self.matches(of: compiled, in: text, maximumMatchCount: 1)
            return .boolean(!firstMatches.isEmpty)
        default:
            return nil
        }
    }

    private func compiledRegularExpression(_ expression: BaseRegularExpression) throws -> NSRegularExpression {
        if let cachedResult = compiledRegularExpressions[expression] { return try cachedResult.get() }
        let result = Result { try expression.compiled() }.mapError { error in
            (error as? BaseExpressionError) ?? .evaluation(error.localizedDescription)
        }
        compiledRegularExpressions[expression] = result
        return try result.get()
    }

    private func stringMethod(_ name: String, text: String, arguments: [BaseValue]) throws -> BaseValue? {
        let texts = arguments.map(\.displayText)
        switch name {
        // Foundation's contains("") is false; JavaScript's includes("") is true, matching startsWith("").
        case "contains": return .boolean(texts.first.map { query in query.isEmpty || text.contains(query) } ?? false)
        case "containsAll": return .boolean(texts.allSatisfy { query in query.isEmpty || text.contains(query) })
        case "containsAny": return .boolean(texts.contains { query in query.isEmpty || text.contains(query) })
        case "startsWith": return .boolean(texts.first.map { query in text.hasPrefix(query) } ?? false)
        case "endsWith": return .boolean(texts.first.map { query in text.hasSuffix(query) } ?? false)
        case "isEmpty": return .boolean(text.isEmpty)
        case "lower": return .string(text.lowercased())
        case "upper": return .string(text.uppercased())
        case "title":
            return .string(text.split(separator: " ", omittingEmptySubsequences: false).map { word in word.prefix(1).uppercased() + word.dropFirst() }.joined(separator: " "))
        case "trim": return .string(text.trimmingCharacters(in: .whitespacesAndNewlines))
        case "reverse": return .string(String(text.reversed()))
        case "repeat":
            guard case .number(let count) = arguments.first ?? .null, count >= 0, let repetitions = Int(clampingWholePartOf: count),
                  text.isEmpty || count * Double(text.count) <= 1_000_000 else {
                throw BaseExpressionError.evaluation("repeat() needs a reasonable, non-negative count.")
            }
            // An empty text allows any count, and repeating it that many times would never end.
            return .string(text.isEmpty ? "" : String(repeating: text, count: repetitions))
        case "slice":
            let characters = Array(text)
            let range = try sliceRange(count: characters.count, arguments: arguments)
            return .string(String(characters[range]))
        case "replace":
            guard arguments.count == 2 else { throw BaseExpressionError.evaluation("replace() takes a pattern and a replacement.") }
            let foundationText = text as NSString
            let template = JavaScriptReplacementTemplate(arguments[1].displayText)
            if case .regularExpression(let expression) = arguments[0] {
                let compiled = try compiledRegularExpression(expression)
                let matches = try Self.matches(of: compiled, in: text, maximumMatchCount: expression.isGlobal ? .max : 1)
                let patternHasNamedGroups = JavaScriptReplacementTemplate.hasNamedGroups(expression.pattern)
                return .string(template.replacing(matches.map { match in JavaScriptReplacementTemplate.Match(match, patternHasNamedGroups: patternHasNamedGroups) }, in: foundationText))
            }
            // Like JavaScript, a text pattern replaces only its first occurrence, and an
            // empty pattern matches at the start.
            let pattern = arguments[0].displayText
            let patternRange = pattern.isEmpty ? NSRange(location: 0, length: 0) : foundationText.range(of: pattern)
            guard patternRange.location != NSNotFound else { return .string(text) }
            return .string(template.replacing([JavaScriptReplacementTemplate.Match(range: patternRange)], in: foundationText))
        case "split":
            guard let separator = arguments.first else { throw BaseExpressionError.evaluation("split() needs a separator.") }
            var parts: [BaseValue]
            if case .regularExpression(let expression) = separator {
                parts = try Self.regularExpressionSplit(text, separator: compiledRegularExpression(expression))
            } else if separator.displayText.isEmpty {
                parts = text.map { character in .string(String(character)) }
            } else {
                parts = text.components(separatedBy: separator.displayText).map(BaseValue.string)
            }
            if arguments.count > 1, case .number(let limit) = arguments[1], limit >= 0 { parts = Array(parts.prefix(Int(clampingWholePartOf: limit) ?? parts.count)) }
            return .list(parts)
        default:
            return nil
        }
    }

    /// JavaScript's `split` with a regular expression: captured groups join the pieces (an
    /// unmatched group as an empty value), an empty match splits between characters, and
    /// empty text gives no pieces when the pattern matches it.
    private static func regularExpressionSplit(_ text: String, separator: NSRegularExpression) throws -> [BaseValue] {
        let foundationText = text as NSString
        guard foundationText.length > 0 else { return try matches(of: separator, in: text, maximumMatchCount: 1).isEmpty ? [.string("")] : [] }
        var pieces: [BaseValue] = []
        var pieceStart = 0
        for match in try matches(of: separator, in: text) {
            // JavaScript never splits at the very end of the text, and skips an empty
            // match where the previous piece ended.
            guard match.range.location < foundationText.length, NSMaxRange(match.range) != pieceStart else { continue }
            pieces.append(.string(foundationText.substring(with: NSRange(location: pieceStart, length: match.range.location - pieceStart))))
            for groupIndex in 1..<match.numberOfRanges {
                let groupRange = match.range(at: groupIndex)
                pieces.append(groupRange.location == NSNotFound ? .null : .string(foundationText.substring(with: groupRange)))
            }
            pieceStart = NSMaxRange(match.range)
        }
        pieces.append(.string(foundationText.substring(from: pieceStart)))
        return pieces
    }

    /// Matches of a formula's `/pattern/`, given up after `TimeLimitedRegularExpression`'s
    /// limit: a pattern such as `/(a+)+$/` can backtrack for minutes on one value, and a
    /// base runs it on every row.
    private static func matches(of regularExpression: NSRegularExpression, in text: String, maximumMatchCount: Int = .max) throws -> [NSTextCheckingResult] {
        do {
            return try TimeLimitedRegularExpression.matches(of: regularExpression, in: text, maximumMatchCount: maximumMatchCount)
        } catch TimeLimitedRegularExpression.Interruption.timeLimitExceeded {
            throw BaseExpressionError.evaluation("The regular expression /\(regularExpression.pattern)/ took too long to match.")
        } catch {
            throw BaseExpressionError.evaluation("The regular expression /\(regularExpression.pattern)/ stopped before it finished.")
        }
    }

    /// JavaScript `slice(start, end)`: negative positions count from the end.
    private func sliceRange(count: Int, arguments: [BaseValue]) throws -> Range<Int> {
        func position(_ value: BaseValue?, defaultPosition: Int) throws -> Int {
            guard let value, !value.isNull else { return defaultPosition }
            guard case .number(let number) = value else { throw BaseExpressionError.evaluation("slice() needs numbers.") }
            // JavaScript treats NaN as 0 and clamps infinite positions to the ends.
            let whole = Int(clampingWholePartOf: number) ?? 0
            return whole < 0 ? max(0, count + whole) : min(whole, count)
        }
        let start = try position(arguments.first, defaultPosition: 0)
        let end = try position(arguments.count > 1 ? arguments[1] : nil, defaultPosition: count)
        return start < end ? start..<end : start..<start
    }

    private func numberMethod(_ name: String, number: Double, arguments: [BaseValue]) throws -> BaseValue? {
        switch name {
        case "abs": return .number(abs(number))
        case "ceil": return .number(number.rounded(.up))
        case "floor": return .number(number.rounded(.down))
        case "round":
            var digits = 0.0
            if case .number(let requestedDigits) = arguments.first ?? .null { digits = min(max(requestedDigits.rounded(), 0), 15) }
            let scale = pow(10, digits)
            let scaledNumber = number * scale
            // From 2^52 on every Double is a whole number, so there is nothing to round,
            // and adding 0.5 could round up to the next representable value; a scaled
            // number that overflows to infinity must not replace the finite original.
            guard abs(scaledNumber) < 0x1p52 else { return .number(number) }
            // JavaScript's Math.round rounds halves toward positive infinity.
            return .number((scaledNumber + 0.5).rounded(.down) / scale)
        case "toFixed":
            var precision = 0
            if case .number(let requestedPrecision) = arguments.first ?? .null { precision = min(max(Int(clampingWholePartOf: requestedPrecision) ?? 0, 0), 20) }
            return .string(String(format: "%.\(precision)f", locale: Locale(identifier: "en_US_POSIX"), number))
        case "isEmpty": return .boolean(false)
        default: return nil
        }
    }

    private func listMethod(_ name: String, elements: [BaseValue], arguments: [BaseValue]) throws -> BaseValue? {
        func containsElement(_ candidate: BaseValue) -> Bool { elements.contains { element in isEqual(element, candidate) } }
        let numbers = elements.compactMap { element -> Double? in if case .number(let number) = element { return number } else { return nil } }
        switch name {
        case "contains": return .boolean(arguments.first.map(containsElement) ?? false)
        case "containsAll": return .boolean(arguments.allSatisfy(containsElement))
        case "containsAny": return .boolean(arguments.contains(where: containsElement))
        case "isEmpty": return .boolean(elements.isEmpty)
        case "join":
            let separator = arguments.first?.displayText ?? ","
            return .string(elements.map(\.displayText).joined(separator: separator))
        case "reverse": return .list(elements.reversed())
        case "sort":
            let normalizedElements = elements.map { element in (element, element.normalizedForSorting) }
            return .list(normalizedElements.sorted { leftElement, rightElement in BaseValue.sortOrder(leftElement.1, rightElement.1) == .orderedAscending }.map(\.0))
        case "unique": return .list(try uniqueElements(elements))
        case "flat":
            return .list(elements.flatMap { element -> [BaseValue] in if case .list(let nested) = element { return nested } else { return [element] } })
        case "slice":
            return .list(Array(elements[try sliceRange(count: elements.count, arguments: arguments)]))
        case "sum": return .number(numbers.reduce(0, +))
        case "mean", "average": return numbers.isEmpty ? .null : .number(numbers.reduce(0, +) / Double(numbers.count))
        case "median": return BaseSummaryCalculator.median(numbers).map(BaseValue.number) ?? .null
        case "min": return numbers.min().map(BaseValue.number) ?? .null
        case "max": return numbers.max().map(BaseValue.number) ?? .null
        default: return nil
        }
    }

    /// `==` identity for values whose equality needs no link resolution, so `unique()`
    /// can use a set. Text is kept apart from numbers and dates, which `==` compares
    /// with numeric or date text.
    private enum UniqueKey: Hashable {
        case null
        case boolean(Bool)
        case number(Double)
        case text(String)
        case date(Date)

        init?(_ value: BaseValue) {
            switch value {
            case .null: self = .null
            case .boolean(let isTrue): self = .boolean(isTrue)
            case .number(let number): self = .number(number)
            case .string(let text): self = .text(text)
            case .date(let date): self = .date(date.date)
            default: return nil
            }
        }
    }

    /// The first of each group of `==` values, in order. Swift's hashing agrees with `==`
    /// here: text compares by canonical equivalence, 0 equals -0, and NaN equals nothing.
    private func uniqueElements(_ elements: [BaseValue]) throws -> [BaseValue] {
        let keys = elements.compactMap(UniqueKey.init)
        let hasText = keys.contains { key in if case .text = key { true } else { false } }
        let hasNumberOrDate = keys.contains { key in
            switch key {
            case .number, .date: true
            default: false
            }
        }
        if keys.count == elements.count, !(hasText && hasNumberOrDate) {
            var seenKeys = Set<UniqueKey>()
            return zip(elements, keys).compactMap { element, key in seenKeys.insert(key).inserted ? element : nil }
        }
        guard elements.count <= Self.maximumPairwiseUniqueLength else { throw BaseExpressionError.evaluation("The list is too long for unique().") }
        var uniqueElements: [BaseValue] = []
        for element in elements where !uniqueElements.contains(where: { existing in isEqual(existing, element) }) {
            uniqueElements.append(element)
        }
        return uniqueElements
    }

    private func listCallback(_ name: String, elements: [BaseValue], arguments: [BaseExpression], in scope: Scope) throws -> BaseValue {
        guard elements.count <= Self.maximumListOperationLength else { throw BaseExpressionError.evaluation("The list is too long for \(name)().") }
        switch name {
        case "filter", "map":
            guard arguments.count == 1 else { throw BaseExpressionError.evaluation("\(name)() takes one expression that uses value and index.") }
            var results: [BaseValue] = []
            for (position, element) in elements.enumerated() {
                var elementScope = scope
                elementScope.variables["value"] = element
                elementScope.variables["index"] = .number(Double(position))
                let result = try evaluate(arguments[0], in: elementScope)
                if name == "map" { results.append(result) } else if result.isTruthy { results.append(element) }
            }
            return .list(results)
        default:
            guard arguments.count == 2 else { throw BaseExpressionError.evaluation("reduce() takes an expression that uses acc and value, and a starting value.") }
            var accumulator = try evaluate(arguments[1], in: scope)
            for (position, element) in elements.enumerated() {
                var elementScope = scope
                elementScope.variables["value"] = element
                elementScope.variables["index"] = .number(Double(position))
                elementScope.variables["acc"] = accumulator
                accumulator = try evaluate(arguments[0], in: elementScope)
            }
            return accumulator
        }
    }

    private func dateMethod(_ name: String, date: BaseDate, arguments: [BaseValue]) throws -> BaseValue? {
        switch name {
        case "date": return .date(BaseDateArithmetic.startOfDay(date, calendar: environment.calendar))
        case "format":
            guard let pattern = arguments.first?.displayText else { throw BaseExpressionError.evaluation("format() needs a pattern such as \"YYYY-MM-DD\".") }
            return .string(BaseDateFormatting.format(date.date, pattern: pattern, calendar: environment.calendar))
        case "time": return .string(BaseDateFormatting.format(date.date, pattern: "HH:mm:ss", calendar: environment.calendar))
        case "relative": return .string(BaseDateFormatting.relativeText(from: date.date, to: environment.now))
        case "isEmpty": return .boolean(false)
        default: return nil
        }
    }

    private func fileMethod(_ name: String, path: VaultPath, arguments: [BaseValue]) throws -> BaseValue? {
        let record = record(at: path)
        switch name {
        case "asLink":
            let display = arguments.first.flatMap { argument in argument.isNull ? nil : argument.displayText }
            return .link(BaseLink(target: path.rawValue, display: display))
        case "hasTag":
            let tags = record?.tags ?? []
            return .boolean(arguments.contains { argument in
                let query = argument.displayText.hasPrefix("#") ? String(argument.displayText.dropFirst()) : argument.displayText
                return tags.contains { tag in
                    tag.caseInsensitiveCompare(query) == .orderedSame || tag.lowercased().hasPrefix(query.lowercased() + "/")
                }
            })
        case "hasProperty":
            guard let propertyName = arguments.first?.displayText else { return .boolean(false) }
            return .boolean(record?.propertyEntry(named: propertyName) != nil)
        case "inFolder":
            let folder = (arguments.first?.displayText ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if folder.isEmpty { return .boolean(true) }
            let parentPath = path.parent.rawValue.lowercased()
            return .boolean(parentPath == folder.lowercased() || parentPath.hasPrefix(folder.lowercased() + "/"))
        case "hasLink":
            guard let argument = arguments.first, !argument.isNull else { return .boolean(false) }
            let targets = linkTargets(of: record, includesEmbeds: true)
            if let destination = filePath(of: argument, from: path) {
                return .boolean(targets.contains { target in link(target, from: path, pointsTo: destination) })
            }
            let writtenTarget: String
            if case .link(let link) = argument { writtenTarget = link.pathPart } else { writtenTarget = BaseLink.parse(argument.displayText)?.pathPart ?? argument.displayText }
            let normalizedTarget = Self.normalizedLinkText(writtenTarget)
            return .boolean(targets.contains { target in Self.normalizedLinkText(WikiLinkResolver.pathPart(target)) == normalizedTarget })
        default:
            return nil
        }
    }

    private func linkMethod(_ name: String, link: BaseLink, arguments: [BaseValue]) throws -> BaseValue? {
        switch name {
        case "asFile":
            return resolveLink(link.target, from: link.source).map(BaseValue.file) ?? .null
        case "linksTo":
            guard let linkedPath = resolveLink(link.target, from: link.source), let argument = arguments.first,
                  let destination = filePath(of: argument, from: link.source) else { return .boolean(false) }
            return .boolean(linkTargets(of: record(at: linkedPath), includesEmbeds: true).contains { target in self.link(target, from: linkedPath, pointsTo: destination) })
        default:
            // A link otherwise behaves like its text, so `author.contains("Smith")` works.
            return try stringMethod(name, text: link.displayText, arguments: arguments)
        }
    }

    static func describe(_ value: BaseValue) -> String {
        switch value {
        case .null: "an empty value"
        case .boolean: "a true/false value"
        case .number: "a number"
        case .string: "text"
        case .date: "a date"
        case .duration: "a duration"
        case .list: "a list"
        case .link: "a link"
        case .file: "a file"
        case .object: "an object"
        case .regularExpression: "a regular expression"
        case .image: "an image"
        case .icon: "an icon"
        }
    }
}

private extension String {
    var capitalizedFirstLetter: String { prefix(1).uppercased() + dropFirst() }
}

/// A JavaScript `String.replace` replacement, which Bases follows: `$$`, `$&`, `` $` ``,
/// `$'`, `$1` to `$99` and `$<name>` expand, and everything else is literal. Foundation's
/// templates differ: there a backslash escapes and the whole match is `$0`.
private struct JavaScriptReplacementTemplate {
    struct Match {
        let range: NSRange
        let groupRanges: [NSRange]
        /// Nil when the pattern has no named groups, where JavaScript keeps `$<name>` as written.
        let checkingResult: NSTextCheckingResult?

        /// A match of a text pattern, which has no groups.
        init(range: NSRange) {
            self.range = range
            groupRanges = []
            checkingResult = nil
        }

        init(_ checkingResult: NSTextCheckingResult, patternHasNamedGroups: Bool) {
            range = checkingResult.range
            groupRanges = (1..<checkingResult.numberOfRanges).map { groupIndex in checkingResult.range(at: groupIndex) }
            self.checkingResult = patternHasNamedGroups ? checkingResult : nil
        }
    }

    /// Whether a pattern declares a group such as `(?<year>…)`, as opposed to a lookbehind.
    static func hasNamedGroups(_ pattern: String) -> Bool {
        pattern.range(of: "\\(\\?<[A-Za-z]", options: .regularExpression) != nil
    }

    private let characters: [Character]

    init(_ template: String) {
        characters = Array(template)
    }

    /// `text` with each match, in order and not overlapping, replaced by the expanded template.
    func replacing(_ matches: [Match], in text: NSString) -> String {
        var replacedText = ""
        var copiedLocation = 0
        for match in matches {
            replacedText += text.substring(with: NSRange(location: copiedLocation, length: match.range.location - copiedLocation))
            replacedText += expansion(for: match, in: text)
            copiedLocation = NSMaxRange(match.range)
        }
        return replacedText + text.substring(from: copiedLocation)
    }

    private func expansion(for match: Match, in text: NSString) -> String {
        func substring(_ range: NSRange) -> String { range.location == NSNotFound ? "" : text.substring(with: range) }
        func asciiDigit(at position: Int) -> Int? {
            guard position < characters.count, characters[position].isASCII else { return nil }
            return characters[position].wholeNumberValue
        }
        var expandedText = ""
        var position = 0
        while position < characters.count {
            guard characters[position] == "$", position + 1 < characters.count else {
                expandedText.append(characters[position])
                position += 1
                continue
            }
            switch characters[position + 1] {
            case "$":
                expandedText += "$"
                position += 2
                continue
            case "&":
                expandedText += substring(match.range)
                position += 2
                continue
            case "`":
                expandedText += text.substring(to: match.range.location)
                position += 2
                continue
            case "'":
                expandedText += text.substring(from: NSMaxRange(match.range))
                position += 2
                continue
            case "<":
                if let checkingResult = match.checkingResult, let closingPosition = characters[(position + 2)...].firstIndex(of: ">") {
                    expandedText += substring(checkingResult.range(withName: String(characters[(position + 2)..<closingPosition])))
                    position = closingPosition + 1
                    continue
                }
            default:
                // Two digits win when they name an existing group; `$0` and missing groups stay literal.
                if let firstDigit = asciiDigit(at: position + 1) {
                    let twoDigitGroupNumber = asciiDigit(at: position + 2).map { secondDigit in firstDigit * 10 + secondDigit }
                    if let twoDigitGroupNumber, twoDigitGroupNumber >= 1, twoDigitGroupNumber <= match.groupRanges.count {
                        expandedText += substring(match.groupRanges[twoDigitGroupNumber - 1])
                        position += 3
                        continue
                    }
                    if firstDigit >= 1, firstDigit <= match.groupRanges.count {
                        expandedText += substring(match.groupRanges[firstDigit - 1])
                        position += 2
                        continue
                    }
                }
            }
            expandedText += "$"
            position += 1
        }
        return expandedText
    }
}
