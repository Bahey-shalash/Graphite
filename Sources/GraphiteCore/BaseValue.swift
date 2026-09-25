import Foundation

/// A point in time used by Bases. Date-only values sit at midnight in the evaluation
/// time zone and remember that they carry no time, so they display and compare like
/// Obsidian's date properties.
public struct BaseDate: Hashable, Sendable {
    public var date: Date
    public var hasTime: Bool
    public init(date: Date, hasTime: Bool) {
        self.date = date
        self.hasTime = hasTime
    }
}

/// A Bases duration. Calendar months and calendar days stay separate from exact
/// milliseconds, so `date + "1M"` adds a calendar month the way moment.js does.
public struct BaseDuration: Sendable {
    /// Years are folded into months (12 per year).
    public var months: Int
    /// Weeks are folded into days (7 per week). Calendar days, so daylight-saving
    /// changes keep the wall-clock time.
    public var days: Int
    public var milliseconds: Double

    /// moment.js converts months to days with the 400-year Gregorian average.
    static let averageDaysPerMonth = 146_097.0 / 4_800.0
    static let millisecondsPerDay = 86_400_000.0

    public init(months: Int = 0, days: Int = 0, milliseconds: Double = 0) {
        self.months = months
        self.days = days
        self.milliseconds = milliseconds
    }

    /// Total length, approximating calendar months with the Gregorian average.
    public var totalMilliseconds: Double {
        (Double(months) * Self.averageDaysPerMonth + Double(days)) * Self.millisecondsPerDay + milliseconds
    }

    public var isZero: Bool { months == 0 && days == 0 && milliseconds == 0 }

    // Durations come from `.base` formulas and notes (`duration("999999999y") * 999999999`),
    // so calendar parts are combined with checked arithmetic. When a part would leave
    // ±Int.max, the result collapses to exact milliseconds, as a fractional factor does.
    // Int.min is excluded too, so negating a part or taking its `abs` never traps later.

    public func negated() -> BaseDuration {
        guard let parts = Self.checkedCalendarParts(months: 0.subtractingReportingOverflow(months), days: 0.subtractingReportingOverflow(days)) else {
            return BaseDuration(milliseconds: -totalMilliseconds)
        }
        return BaseDuration(months: parts.months, days: parts.days, milliseconds: -milliseconds)
    }

    public func adding(_ other: BaseDuration) -> BaseDuration {
        guard let parts = Self.checkedCalendarParts(months: months.addingReportingOverflow(other.months), days: days.addingReportingOverflow(other.days)) else {
            return BaseDuration(milliseconds: totalMilliseconds + other.totalMilliseconds)
        }
        return BaseDuration(months: parts.months, days: parts.days, milliseconds: milliseconds + other.milliseconds)
    }

    public func scaled(by factor: Double) -> BaseDuration {
        // Whole factors keep calendar parts; fractional ones collapse to exact time.
        if factor.rounded() == factor, abs(factor) < 1e9 {
            let wholeFactor = Int(factor)
            if let parts = Self.checkedCalendarParts(months: months.multipliedReportingOverflow(by: wholeFactor), days: days.multipliedReportingOverflow(by: wholeFactor)) {
                return BaseDuration(months: parts.months, days: parts.days, milliseconds: milliseconds * factor)
            }
        }
        return BaseDuration(milliseconds: totalMilliseconds * factor)
    }

    private static func checkedCalendarParts(months: (partialValue: Int, overflow: Bool), days: (partialValue: Int, overflow: Bool)) -> (months: Int, days: Int)? {
        guard !months.overflow, !days.overflow, months.partialValue != .min, days.partialValue != .min else { return nil }
        return (months.partialValue, days.partialValue)
    }
}

// Equality treats NaN milliseconds as equal to themselves, so a duration scaled by NaN
// stays reflexive in sets, dictionaries and SwiftUI diffing.
extension BaseDuration: Hashable {
    public static func == (leftDuration: BaseDuration, rightDuration: BaseDuration) -> Bool {
        leftDuration.months == rightDuration.months && leftDuration.days == rightDuration.days
            && leftDuration.milliseconds.isReflexivelyEqual(to: rightDuration.milliseconds)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(months)
        hasher.combine(days)
        hasher.combine(milliseconds.canonicalForHashing)
    }
}

extension Double {
    /// `==`, except that NaN equals NaN. Swift's `==` follows IEEE 754, where NaN is
    /// unequal to itself, which breaks Equatable's reflexivity for values that store one.
    fileprivate func isReflexivelyEqual(to other: Double) -> Bool {
        self == other || (isNaN && other.isNaN)
    }

    /// Every NaN payload hashes alike, matching `isReflexivelyEqual(to:)`. Double's own
    /// hash already treats -0 and +0 alike.
    fileprivate var canonicalForHashing: Double { isNaN ? .nan : self }

    /// Reads plain decimal text: an optional sign, digits with an optional fraction and
    /// an optional exponent (`-3.5`, `.5`, `1e3`). `Double(_:)` alone also accepts `nan`,
    /// `inf` and hexadecimal such as `0x1A`, which Bases comparisons and CSS colors do
    /// not treat as numbers.
    init?(decimalText text: some StringProtocol) {
        let codeUnits = Array(text.utf8)
        var position = 0
        func isAtSign() -> Bool {
            position < codeUnits.count && (codeUnits[position] == UInt8(ascii: "+") || codeUnits[position] == UInt8(ascii: "-"))
        }
        func skipDigits() -> Int {
            let startPosition = position
            while position < codeUnits.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(codeUnits[position]) { position += 1 }
            return position - startPosition
        }
        if isAtSign() { position += 1 }
        var mantissaDigitCount = skipDigits()
        if position < codeUnits.count, codeUnits[position] == UInt8(ascii: ".") {
            position += 1
            mantissaDigitCount += skipDigits()
        }
        guard mantissaDigitCount > 0 else { return nil }
        if position < codeUnits.count, codeUnits[position] == UInt8(ascii: "e") || codeUnits[position] == UInt8(ascii: "E") {
            position += 1
            if isAtSign() { position += 1 }
            guard skipDigits() > 0 else { return nil }
        }
        guard position == codeUnits.count, let number = Double(String(text)) else { return nil }
        self = number
    }
}

/// An internal link such as `[[Note|Label]]`, or an external URL.
public struct BaseLink: Hashable, Sendable {
    /// The target as written, possibly with a `#heading` part, or a URL.
    public var target: String
    public var display: String?
    /// The note that contains the link. Relative targets resolve from here.
    public var source: VaultPath?

    public init(target: String, display: String? = nil, source: VaultPath? = nil) {
        self.target = target
        self.display = display
        self.source = source
    }

    public var isExternal: Bool {
        target.contains("://") || target.lowercased().hasPrefix("mailto:")
    }

    /// The target without a heading or block part.
    public var pathPart: String { isExternal ? target : WikiLinkResolver.pathPart(target) }

    public var displayText: String {
        if let display, !display.isEmpty { return display }
        let pathText = pathPart
        return pathText.lowercased().hasSuffix(".md") ? String(pathText.dropLast(3)) : pathText
    }

    /// Parses `[[target|display]]`, `![[target]]` or `[display](target)` when the whole
    /// text is one link, as Obsidian does for property values.
    public static func parse(_ text: String, source: VaultPath? = nil) -> BaseLink? {
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        var body = Substring(trimmedText)
        if body.hasPrefix("!") { body = body.dropFirst() }
        if body.hasPrefix("[["), body.hasSuffix("]]"), body.count > 4 {
            let inner = body.dropFirst(2).dropLast(2)
            guard !inner.contains("[["), !inner.contains("]]") else { return nil }
            let parts = inner.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            let target = String(parts[0]).trimmingCharacters(in: .whitespaces)
            guard !target.isEmpty else { return nil }
            return BaseLink(target: target, display: parts.count > 1 ? String(parts[1]) : nil, source: source)
        }
        if body.hasPrefix("["), body.hasSuffix(")"), let separatorRange = body.range(of: "](") {
            let display = String(body[body.index(after: body.startIndex)..<separatorRange.lowerBound])
            var target = String(body[separatorRange.upperBound..<body.index(before: body.endIndex)])
            if target.hasPrefix("<"), target.hasSuffix(">") {
                target = String(target.dropFirst().dropLast())
                guard !target.contains("<"), !target.contains(">") else { return nil }
            } else {
                // `[a](b) and [c](d)` also starts with `[` and ends with `)`; its target
                // `b) and [c](d` has an unbalanced parenthesis, so it is not one link.
                guard hasBalancedParentheses(target) else { return nil }
            }
            guard !target.isEmpty else { return nil }
            var link = BaseLink(target: target, display: display.isEmpty ? nil : display, source: source)
            // A note path is written percent-encoded (`My%20Note.md`). A URL keeps its
            // escapes: decoding `%2F`, `%26` or `%23` would change the address it names.
            if !link.isExternal, let decodedTarget = target.removingPercentEncoding { link.target = decodedTarget }
            return link
        }
        return nil
    }

    /// Whether every `)` closes an earlier `(`, as CommonMark requires of a link
    /// destination without angle brackets. A backslash escapes the next character.
    private static func hasBalancedParentheses(_ target: String) -> Bool {
        var openParenthesisCount = 0
        var isEscaped = false
        for character in target {
            if isEscaped { isEscaped = false; continue }
            switch character {
            case "\\": isEscaped = true
            case "(": openParenthesisCount += 1
            case ")":
                openParenthesisCount -= 1
                if openParenthesisCount < 0 { return false }
            default: break
            }
        }
        return openParenthesisCount == 0
    }
}

public struct BaseObjectEntry: Hashable, Sendable {
    public var key: String
    public var value: BaseValue
    public init(key: String, value: BaseValue) {
        self.key = key
        self.value = value
    }
}

/// An ordered key/value object, such as nested frontmatter or `file.properties`.
public struct BaseObject: Hashable, Sendable {
    public var entries: [BaseObjectEntry]
    public init(entries: [BaseObjectEntry]) { self.entries = entries }

    /// Exact key first, then a case-insensitive match (property names are
    /// case-insensitive in Obsidian).
    public subscript(key: String) -> BaseValue? {
        if let exactEntry = entries.first(where: { entry in entry.key == key }) { return exactEntry.value }
        return entries.first(where: { entry in entry.key.caseInsensitiveCompare(key) == .orderedSame })?.value
    }
}

/// A `/pattern/flags` literal.
public struct BaseRegularExpression: Hashable, Sendable {
    public var pattern: String
    public var flags: String
    public init(pattern: String, flags: String) {
        self.pattern = pattern
        self.flags = flags
    }
    public var isGlobal: Bool { flags.contains("g") }

    public func compiled() throws -> NSRegularExpression {
        var options: NSRegularExpression.Options = []
        if flags.contains("i") { options.insert(.caseInsensitive) }
        if flags.contains("m") { options.insert(.anchorsMatchLines) }
        if flags.contains("s") { options.insert(.dotMatchesLineSeparators) }
        do { return try NSRegularExpression(pattern: pattern, options: options) }
        catch { throw BaseExpressionError.evaluation("Invalid regular expression /\(pattern)/.") }
    }
}

/// Every value a Bases expression can produce.
public indirect enum BaseValue: Sendable {
    case null
    case boolean(Bool)
    case number(Double)
    case string(String)
    case date(BaseDate)
    case duration(BaseDuration)
    case list([BaseValue])
    case link(BaseLink)
    /// A vault file. Its metadata is looked up when a field is read.
    case file(VaultPath)
    case object(BaseObject)
    case regularExpression(BaseRegularExpression)
    /// An image to render: a vault link, a path, a URL, or a hex color.
    case image(String)
    /// A Lucide icon name, from `icon()` or a marker icon property.
    case icon(String)

    /// Obsidian's type names, as `isType()` accepts them.
    public var typeName: String {
        switch self {
        case .null: "null"
        case .boolean: "boolean"
        case .number: "number"
        case .string: "string"
        case .date: "date"
        case .duration: "duration"
        case .list: "list"
        case .link: "link"
        case .file: "file"
        case .object: "object"
        case .regularExpression: "regexp"
        case .image: "image"
        case .icon: "icon"
        }
    }

    public var isNull: Bool { if case .null = self { true } else { false } }

    /// JavaScript-like truthiness, except that empty lists and objects are false, as
    /// Obsidian's list and object values report.
    public var isTruthy: Bool {
        switch self {
        case .null: false
        case .boolean(let isTrue): isTrue
        case .number(let number): number != 0 && !number.isNaN
        case .string(let text): !text.isEmpty
        case .date: true
        case .duration(let duration): !duration.isZero
        case .list(let elements): !elements.isEmpty
        case .object(let object): !object.entries.isEmpty
        case .link, .file, .regularExpression: true
        case .image(let target), .icon(let target): !target.isEmpty
        }
    }

    /// Empty in the sense of the Empty/Filled summaries and `isEmpty()`.
    public var isEmptyValue: Bool {
        switch self {
        case .null: true
        case .string(let text): text.isEmpty
        case .list(let elements): elements.isEmpty
        case .object(let object): object.entries.isEmpty
        default: false
        }
    }
}

// MARK: Equality

// Written out rather than synthesized so that `.number(.nan)` equals itself. Synthesized
// equality compares the Double with IEEE `==`, and a NaN from `number("nan")` or
// `0 * Infinity` then made a value unequal to itself: a Set kept duplicates and a row
// holding it never compared equal to its previous state. Formula `==` does not use this;
// `BaseEvaluator.isEqual` keeps JavaScript's NaN != NaN.
extension BaseValue: Hashable {
    public static func == (leftValue: BaseValue, rightValue: BaseValue) -> Bool {
        // Switching over the left value alone keeps the switch exhaustive, so a new case
        // cannot silently fall into a default and compare unequal to itself.
        switch leftValue {
        case .null:
            if case .null = rightValue { return true }
        case .boolean(let leftFlag):
            if case .boolean(let rightFlag) = rightValue { return leftFlag == rightFlag }
        case .number(let leftNumber):
            if case .number(let rightNumber) = rightValue { return leftNumber.isReflexivelyEqual(to: rightNumber) }
        case .string(let leftText):
            if case .string(let rightText) = rightValue { return leftText == rightText }
        case .date(let leftDate):
            if case .date(let rightDate) = rightValue { return leftDate == rightDate }
        case .duration(let leftDuration):
            if case .duration(let rightDuration) = rightValue { return leftDuration == rightDuration }
        case .list(let leftElements):
            if case .list(let rightElements) = rightValue { return leftElements == rightElements }
        case .link(let leftLink):
            if case .link(let rightLink) = rightValue { return leftLink == rightLink }
        case .file(let leftPath):
            if case .file(let rightPath) = rightValue { return leftPath == rightPath }
        case .object(let leftObject):
            if case .object(let rightObject) = rightValue { return leftObject == rightObject }
        case .regularExpression(let leftExpression):
            if case .regularExpression(let rightExpression) = rightValue { return leftExpression == rightExpression }
        case .image(let leftTarget):
            if case .image(let rightTarget) = rightValue { return leftTarget == rightTarget }
        case .icon(let leftName):
            if case .icon(let rightName) = rightValue { return leftName == rightName }
        }
        return false
    }

    public func hash(into hasher: inout Hasher) {
        // The type name tells the cases apart, so `.string("x")` and `.image("x")` differ.
        hasher.combine(typeName)
        switch self {
        case .null: break
        case .boolean(let isTrue): hasher.combine(isTrue)
        case .number(let number): hasher.combine(number.canonicalForHashing)
        case .string(let text): hasher.combine(text)
        case .date(let date): hasher.combine(date)
        case .duration(let duration): hasher.combine(duration)
        case .list(let elements): hasher.combine(elements)
        case .link(let link): hasher.combine(link)
        case .file(let path): hasher.combine(path)
        case .object(let object): hasher.combine(object)
        case .regularExpression(let expression): hasher.combine(expression)
        case .image(let target): hasher.combine(target)
        case .icon(let name): hasher.combine(name)
        }
    }
}

// MARK: Text

extension BaseValue {
    /// Plain-text rendering used by `toString()`, string concatenation and cells.
    public var displayText: String {
        switch self {
        case .null: ""
        case .boolean(let isTrue): isTrue ? "true" : "false"
        case .number(let number): Self.formatted(number)
        case .string(let text): text
        case .date(let date): BaseDateFormatting.defaultText(for: date, calendar: BaseDateFormatting.displayCalendar)
        case .duration(let duration): BaseDateFormatting.text(for: duration)
        case .list(let elements): elements.map(\.displayText).joined(separator: ", ")
        case .link(let link): link.displayText
        case .file(let path): DocumentKind(path: path) == .markdown ? path.stem : path.name
        case .object(let object):
            "{" + object.entries.map { entry in "\(entry.key): \(entry.value.displayText)" }.joined(separator: ", ") + "}"
        case .regularExpression(let expression): "/\(expression.pattern)/\(expression.flags)"
        case .image(let target): target
        case .icon(let name): name
        }
    }

    /// Numbers print like JavaScript's `String(number)`: whole numbers without a decimal
    /// point, plain digits from 1e-6 up to 1e21, and exponent form (`1e-7`, `1e+21`) outside.
    public static func formatted(_ number: Double) -> String {
        if number.isNaN { return "NaN" }
        if number.isInfinite { return number > 0 ? "Infinity" : "-Infinity" }
        // The common case, and exact: every whole Double below 1e15 fits in Int64.
        if number.rounded() == number, abs(number) < 1e15 { return String(Int64(number)) }
        return javaScriptText(forFinite: number)
    }

    /// ECMAScript's Number::toString layout (ECMA-262, section 6.1.6.1.20). Swift's
    /// `description` already gives the shortest digits that read back as the same Double,
    /// the digits JavaScript prints, but lays them out differently (`1e-05`, `1.5e+16`).
    private static func javaScriptText(forFinite number: Double) -> String {
        let swiftText = abs(number).description
        let textParts = swiftText.split(separator: "e", maxSplits: 1)
        let mantissa = textParts[0]
        let swiftExponent = textParts.count > 1 ? Int(textParts[1]) ?? 0 : 0
        let integerDigits = mantissa.prefix { character in character != "." }
        let fractionDigits = mantissa.drop { character in character != "." }.dropFirst()
        var digits = String(integerDigits + fractionDigits)
        // The number equals 0.<digits> × 10^pointPosition.
        var pointPosition = integerDigits.count + swiftExponent
        while digits.count > 1, digits.first == "0" {
            digits.removeFirst()
            pointPosition -= 1
        }
        while digits.count > 1, digits.last == "0" { digits.removeLast() }

        let digitCount = digits.count
        let signText = number < 0 ? "-" : ""
        if digitCount <= pointPosition, pointPosition <= 21 {
            return signText + digits + String(repeating: "0", count: pointPosition - digitCount)
        }
        if 0 < pointPosition, pointPosition <= 21 {
            let splitIndex = digits.index(digits.startIndex, offsetBy: pointPosition)
            return signText + digits[..<splitIndex] + "." + digits[splitIndex...]
        }
        if -6 < pointPosition, pointPosition <= 0 {
            return signText + "0." + String(repeating: "0", count: -pointPosition) + digits
        }
        let exponent = pointPosition - 1
        let exponentText = (exponent < 0 ? "e-" : "e+") + String(abs(exponent))
        let leadingDigit = digits.prefix(1)
        let remainingDigits = digits.dropFirst()
        return signText + leadingDigit + (remainingDigits.isEmpty ? "" : "." + remainingDigits) + exponentText
    }
}

// MARK: Comparison

extension BaseValue {
    /// Rank used to order values of different types deterministically.
    private var sortRank: Int {
        switch self {
        case .boolean: 0
        case .number: 1
        case .date: 2
        case .duration: 3
        case .string, .link, .file, .image, .icon: 4
        case .list: 5
        case .object: 6
        case .regularExpression: 7
        case .null: 8
        }
    }

    /// Text that reads as a number or a date becomes that value, so sorting compares it
    /// the same way whatever it is next to. Without this, "2027-03-15" sorted as text
    /// against other text but as a date against a date, which is not a consistent order.
    public var normalizedForSorting: BaseValue {
        guard case .string(let text) = self else { return self }
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        if let number = Self.numericValue(ofText: trimmedText) { return .number(number) }
        if let date = BaseDateParsing.date(from: trimmedText, calendar: BaseDateFormatting.displayCalendar) { return .date(date) }
        return self
    }

    /// Text read as a number when it is compared with one: plain decimal text only. Swift's
    /// `Double(_:)` also reads "NaN", which made every number equal to that text, and
    /// hexadecimal such as "0x1A". Sorting and comparison share this so they agree.
    static func numericValue(ofText text: String) -> Double? {
        Double(decimalText: text.trimmingCharacters(in: .whitespaces))
    }

    /// Order for sorting: values of different types by a fixed type rank, numbers
    /// numerically (NaN last), dates chronologically, false before true, and text, links
    /// and files with natural (Finder-like) ordering. Because the type rank decides first,
    /// this is a strict weak ordering for any values; `normalizedForSorting` beforehand
    /// decides which text counts as a number or date. Callers put empty values last.
    public static func sortOrder(_ leftValue: BaseValue, _ rightValue: BaseValue) -> ComparisonResult {
        if leftValue.sortRank != rightValue.sortRank { return leftValue.sortRank < rightValue.sortRank ? .orderedAscending : .orderedDescending }
        switch (leftValue, rightValue) {
        case (.number(let leftNumber), .number(let rightNumber)):
            return sortOrder(leftNumber, rightNumber)
        case (.date(let leftDate), .date(let rightDate)):
            return sortOrder(leftDate.date.timeIntervalSince1970, rightDate.date.timeIntervalSince1970)
        case (.duration(let leftDuration), .duration(let rightDuration)):
            return sortOrder(leftDuration.totalMilliseconds, rightDuration.totalMilliseconds)
        case (.boolean(let leftFlag), .boolean(let rightFlag)):
            return sortOrder(leftFlag ? 1 : 0, rightFlag ? 1 : 0)
        default:
            return leftValue.displayText.localizedStandardCompare(rightValue.displayText)
        }
    }

    /// NaN has no numeric order, so it sorts after every number and ties with NaN.
    private static func sortOrder(_ leftNumber: Double, _ rightNumber: Double) -> ComparisonResult {
        switch (leftNumber.isNaN, rightNumber.isNaN) {
        case (true, true): .orderedSame
        case (true, false): .orderedDescending
        case (false, true): .orderedAscending
        case (false, false): leftNumber < rightNumber ? .orderedAscending : (leftNumber > rightNumber ? .orderedDescending : .orderedSame)
        }
    }

    /// The comparison `<`, `>`, `<=` and `>=` use, or nil when the values cannot be
    /// ordered (for example a number and a list, or NaN and anything).
    public static func orderedComparison(_ leftValue: BaseValue, _ rightValue: BaseValue) -> ComparisonResult? {
        switch (leftValue, rightValue) {
        case (.number(let leftNumber), .number(let rightNumber)):
            return compare(leftNumber, rightNumber)
        case (.date(let leftDate), .date(let rightDate)):
            return compare(leftDate.date.timeIntervalSince1970, rightDate.date.timeIntervalSince1970)
        case (.duration(let leftDuration), .duration(let rightDuration)):
            return compare(leftDuration.totalMilliseconds, rightDuration.totalMilliseconds)
        case (.boolean(let leftFlag), .boolean(let rightFlag)):
            return compare(leftFlag ? 1 : 0, rightFlag ? 1 : 0)
        case (.date(let leftDate), .string(let text)):
            guard let rightDate = BaseDateParsing.date(from: text, calendar: BaseDateFormatting.displayCalendar) else { return nil }
            return compare(leftDate.date.timeIntervalSince1970, rightDate.date.timeIntervalSince1970)
        case (.string(let text), .date(let rightDate)):
            guard let leftDate = BaseDateParsing.date(from: text, calendar: BaseDateFormatting.displayCalendar) else { return nil }
            return compare(leftDate.date.timeIntervalSince1970, rightDate.date.timeIntervalSince1970)
        case (.number(let number), .string(let text)):
            guard let parsedNumber = numericValue(ofText: text) else { return nil }
            return compare(number, parsedNumber)
        case (.string(let text), .number(let number)):
            guard let parsedNumber = numericValue(ofText: text) else { return nil }
            return compare(parsedNumber, number)
        case (.string(let leftText), .string(let rightText)):
            // Binary order, as JavaScript's `<` compares strings; sorting uses natural order.
            return leftText < rightText ? .orderedAscending : (leftText > rightText ? .orderedDescending : .orderedSame)
        case (.link, _), (_, .link), (.file, _), (_, .file):
            // Links and files compare as their text, by exactly the rules text follows, so
            // a link is never ordered against a number or list that the same text is not.
            return orderedComparison(leftValue.textForComparison, rightValue.textForComparison)
        default:
            return nil
        }
    }

    /// A link or file as the text it shows; any other value unchanged.
    private var textForComparison: BaseValue {
        switch self {
        case .link, .file: .string(displayText)
        default: self
        }
    }

    /// Nil when either number is NaN: in JavaScript every comparison with NaN is false.
    private static func compare(_ leftNumber: Double, _ rightNumber: Double) -> ComparisonResult? {
        if leftNumber < rightNumber { return .orderedAscending }
        if leftNumber > rightNumber { return .orderedDescending }
        return leftNumber == rightNumber ? .orderedSame : nil
    }
}
