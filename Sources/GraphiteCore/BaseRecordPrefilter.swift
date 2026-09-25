import Foundation

/// What a link requirement points at.
public enum BaseLinkDestination: Hashable, Sendable {
    case path(VaultPath)
    /// A written link target, resolved by the index.
    case target(String)
}

/// A condition every matching file must satisfy, cheap enough for the index to check
/// with its B-tree tables. Each case is satisfied when any of its options holds.
public enum BasePrefilterRequirement: Hashable, Sendable {
    case inAnyFolder([String])
    /// Tags without `#`; nested tags (`book/fiction` for `book`) also match.
    case hasAnyTag([String])
    case hasAnyExtension([String])
    case hasAnyProperty([String])
    case linksTo(BaseLinkDestination)
}

/// A note property that can equal a text only when its stored value contains that
/// text, from a filter such as `status == "reading"`. The text holds only ASCII
/// letters, digits and spaces, and does not read as a number.
///
/// A file satisfies it when it has a property named `key` (any capitalization) whose
/// indexed value contains `text` ignoring ASCII case, or contains `%` or any non-ASCII
/// character: the evaluator decodes percent-encoded link targets and compares text
/// with Unicode normalization, which can turn those into the text.
public struct BasePropertyTextRequirement: Hashable, Sendable {
    public let key: String
    public let text: String
    public init(key: String, text: String) {
        self.key = key
        self.text = text
    }
}

/// Conditions extracted from a base's filters so the index loads only files that can
/// possibly match. It is always a superset of the true result: anything the
/// extraction does not fully understand is left to the evaluator.
public struct BaseRecordPrefilter: Hashable, Sendable {
    public var requirements: [BasePrefilterRequirement]
    /// Every one must hold as well.
    public var propertyTextRequirements: [BasePropertyTextRequirement]

    public init(requirements: [BasePrefilterRequirement] = [], propertyTextRequirements: [BasePropertyTextRequirement] = []) {
        self.requirements = requirements
        self.propertyTextRequirements = propertyTextRequirements
    }

    /// Requirements implied by `filters` (all of which must hold). Only conjunctions are
    /// used: `and` groups, `&&`, and single expressions. `or` and `not` add nothing.
    public static func extract(from filters: [BaseFilter], definition: BaseDefinition, environment: BaseEvaluationEnvironment, thisRecord: BaseFileRecord?, provider: (any BaseRecordProvider)? = nil) -> BaseRecordPrefilter {
        let evaluator = BaseEvaluator(formulas: definition.formulas, environment: environment, thisRecord: thisRecord, provider: provider)
        var requirements: [BasePrefilterRequirement] = []
        var propertyTextRequirements: [BasePropertyTextRequirement] = []
        func visit(_ filter: BaseFilter) {
            switch filter {
            case .expression(let sourceText):
                guard case .success(let expression) = evaluator.parsed(sourceText) else { return }
                for conjunct in conjuncts(of: expression) {
                    if let requirement = requirement(for: conjunct, evaluator: evaluator) { requirements.append(requirement) }
                    if let requirement = propertyTextRequirement(for: conjunct, evaluator: evaluator), !propertyTextRequirements.contains(requirement) {
                        propertyTextRequirements.append(requirement)
                    }
                }
            case .and(let children):
                children.forEach(visit)
            case .or, .not:
                break
            }
        }
        filters.forEach(visit)
        var uniqueRequirements: [BasePrefilterRequirement] = []
        for requirement in requirements where !uniqueRequirements.contains(requirement) { uniqueRequirements.append(requirement) }
        return BaseRecordPrefilter(requirements: uniqueRequirements, propertyTextRequirements: propertyTextRequirements)
    }

    private static func conjuncts(of expression: BaseExpression) -> [BaseExpression] {
        if case .binary(.and, let leftExpression, let rightExpression) = expression {
            return conjuncts(of: leftExpression) + conjuncts(of: rightExpression)
        }
        return [expression]
    }

    private static let reservedNames: Set<String> = ["file", "note", "formula", "this"]

    /// The note property an expression reads directly, if any.
    private static func notePropertyName(_ expression: BaseExpression) -> String? {
        switch expression {
        case .identifier(let name) where !reservedNames.contains(name): return name
        case .member(.identifier("note"), let name): return name
        case .subscripted(.identifier("note"), .literal(.string(let name))): return name
        default: return nil
        }
    }

    /// Evaluates an argument that does not depend on the row (literals, `this`, …).
    private static func constantValue(_ expression: BaseExpression, evaluator: BaseEvaluator) -> BaseValue? {
        guard !expression.dependsOnCurrentRow, let value = try? evaluator.evaluate(expression, for: nil), !value.isNull else { return nil }
        return value
    }

    private static func requirement(for expression: BaseExpression, evaluator: BaseEvaluator) -> BasePrefilterRequirement? {
        switch expression {
        case .methodCall(.identifier("file"), let name, let arguments):
            let constants = arguments.map { argument in constantValue(argument, evaluator: evaluator) }
            guard !constants.isEmpty, constants.allSatisfy({ constant in constant != nil }) else { return nil }
            let values = constants.compactMap { constant in constant }
            switch name {
            case "inFolder":
                let folder = values[0].displayText.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                return folder.isEmpty ? nil : .inAnyFolder([folder])
            case "hasTag":
                return .hasAnyTag(values.map { value in value.displayText.hasPrefix("#") ? String(value.displayText.dropFirst()) : value.displayText })
            case "hasProperty":
                return .hasAnyProperty([values[0].displayText])
            case "hasLink":
                switch values[0] {
                case .file(let path): return .linksTo(.path(path))
                case .link(let link) where !link.isExternal: return .linksTo(.target(link.pathPart))
                case .string(let text): return .linksTo(.target(BaseLink.parse(text)?.pathPart ?? text))
                default: return nil
                }
            default:
                return nil
            }
        case .binary(let binaryOperator, let leftExpression, let rightExpression):
            guard [.equal, .less, .lessOrEqual, .greater, .greaterOrEqual].contains(binaryOperator) else { return nil }
            for (propertyExpression, otherExpression) in [(leftExpression, rightExpression), (rightExpression, leftExpression)] {
                if binaryOperator == .equal, case .member(.identifier("file"), "ext") = propertyExpression,
                   let constant = constantValue(otherExpression, evaluator: evaluator), case .string(let fileExtension) = constant {
                    // Every file without an extension has the empty one, which no
                    // `*.extension` path pattern selects.
                    return fileExtension.isEmpty ? nil : .hasAnyExtension([fileExtension])
                }
                // A missing property is empty, and empty never equals or orders against a
                // non-empty constant, so the property must exist.
                if let propertyName = notePropertyName(propertyExpression), let constant = constantValue(otherExpression, evaluator: evaluator), !constant.isNull {
                    return .hasAnyProperty([propertyName])
                }
            }
            return nil
        case .methodCall(let receiver, let name, _):
            // These return false for an empty receiver, so the property must exist.
            guard ["contains", "containsAll", "containsAny", "startsWith", "endsWith"].contains(name), let propertyName = notePropertyName(receiver) else { return nil }
            return .hasAnyProperty([propertyName])
        default:
            return nil
        }
    }

    /// Letters, digits and spaces are stored unescaped in the index's JSON and compared
    /// by exact text or, against a link, by its lowercased target with surrounding
    /// spaces trimmed. Text that reads as a number is excluded, because `==` compares it
    /// with a number by value (`"1e1"` equals `10`).
    private static let propertyTextCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ")

    private static func propertyTextRequirement(for expression: BaseExpression, evaluator: BaseEvaluator) -> BasePropertyTextRequirement? {
        guard case .binary(.equal, let leftExpression, let rightExpression) = expression else { return nil }
        for (propertyExpression, otherExpression) in [(leftExpression, rightExpression), (rightExpression, leftExpression)] {
            guard let propertyName = notePropertyName(propertyExpression), case .string(let text)? = constantValue(otherExpression, evaluator: evaluator) else { continue }
            let trimmedText = text.trimmingCharacters(in: .whitespaces)
            guard !trimmedText.isEmpty, text.unicodeScalars.allSatisfy(propertyTextCharacters.contains), Double(trimmedText) == nil else { return nil }
            return BasePropertyTextRequirement(key: propertyName, text: trimmedText)
        }
        return nil
    }
}
