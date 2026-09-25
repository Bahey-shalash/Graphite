import SwiftUI
import GraphiteCore

/// A note's frontmatter shown as typed, editable properties, laid out like Obsidian's
/// Properties view. Edits are committed on submit or when a field loses focus, so the
/// note is rewritten once per change.
struct PropertiesPanel: View {
    let properties: [NoteProperty]
    /// Nil makes the panel read-only.
    let update: (([NoteProperty]) -> Void)?
    /// Follows a `[[link]]` written in a property value.
    var follow: ((String, Bool) -> Void)?
    /// Types from `.obsidian/types.json`. They decide which lists read as tags or aliases,
    /// as in Obsidian; without them, names such as `tags` keep their built-in types.
    var declaredTypes: [String: PropertyType] = [:]
    @State private var editing = PropertyListEditing()
    @State private var isExpanded = true
    @State private var newPropertyName = ""
    @State private var isAddingProperty = false
    @State private var panelWidth: CGFloat = 0
    @FocusState private var isNewPropertyNameFocused: Bool

    /// The names take up to 210 points, and less in a narrow pane (a split, or beside the
    /// right sidebar), so the values keep at least half the width.
    private var keyColumnWidth: CGFloat {
        guard panelWidth > 0 else { return PropertyRow.maximumKeyColumnWidth }
        return min(PropertyRow.maximumKeyColumnWidth, max(PropertyRow.iconWidth + 70, panelWidth * 0.38))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // As in Obsidian, the heading folds the properties.
            Button { withAnimation(.snappy) { isExpanded.toggle() } } label: {
                HStack(spacing: 8) {
                    Text("Properties").font(.title3.weight(.semibold)).foregroundStyle(.primary)
                    if !isExpanded {
                        Text("\(shownProperties.count)").font(.callout).foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Hides the properties" : "Shows the properties")
            .padding(.bottom, isExpanded ? 10 : 0)
            if isExpanded {
                ForEach(shownProperties) { property in
                    PropertyRow(property: property, declaredType: declaredType(forKey: property.key), isEditable: update != nil,
                                keyColumnWidth: keyColumnWidth, follow: follow) { newValue in
                        commit(editing.replacing(property.key, with: newValue, parsedProperties: properties))
                    } remove: {
                        commit(editing.removing(property.key, parsedProperties: properties))
                    }
                }
                if update != nil { addPropertyControl }
            }
        }
        .padding(.bottom, 18)
        .onGeometryChange(for: CGFloat.self) { geometry in geometry.size.width } action: { width in panelWidth = width }
        .onChange(of: properties) { editing.parsedPropertiesChanged() }
    }

    /// The note's properties, or the list this panel last committed while the note has not
    /// been parsed again yet.
    private var shownProperties: [NoteProperty] { editing.properties(parsedProperties: properties) }

    private func commit(_ updatedProperties: [NoteProperty]?) {
        guard let updatedProperties else { return }
        update?(updatedProperties)
    }

    /// Obsidian matches property names without regard to case.
    private func declaredType(forKey key: String) -> PropertyType? {
        declaredTypes[key]
            ?? declaredTypes.first { entry in entry.key.caseInsensitiveCompare(key) == .orderedSame }?.value
            ?? NoteProperties.defaultType(forKey: key)
    }

    @ViewBuilder private var addPropertyControl: some View {
        if isAddingProperty {
            HStack(spacing: 12) {
                Image(systemName: "plus").foregroundStyle(.secondary).frame(width: PropertyRow.iconWidth)
                TextField("Property name", text: $newPropertyName)
                    .focused($isNewPropertyNameFocused)
                    .autocorrectionDisabled()
                    #if canImport(UIKit)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit {
                        commit(editing.adding(newPropertyName, parsedProperties: properties))
                        newPropertyName = ""; isAddingProperty = false
                    }
                Button("Cancel") { newPropertyName = ""; isAddingProperty = false }.buttonStyle(.borderless)
            }
            .padding(.top, 8)
            .onAppear { isNewPropertyNameFocused = true }
        } else {
            Button { isAddingProperty = true } label: {
                Label("Add property", systemImage: "plus")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }
}

/// The property list the panel's edits build on. Each edit commits the whole list, and
/// the reading view parses the note again only after a short delay. Until the parsed list
/// arrives, the panel keeps the list it last committed, so a second quick edit builds on
/// the first instead of reverting it.
struct PropertyListEditing: Equatable {
    private(set) var committedProperties: [NoteProperty]?

    func properties(parsedProperties: [NoteProperty]) -> [NoteProperty] {
        committedProperties ?? parsedProperties
    }

    /// The note was parsed again, so its properties include every committed edit, or an
    /// edit made in another app that must not be overwritten with an older list.
    mutating func parsedPropertiesChanged() {
        committedProperties = nil
    }

    mutating func replacing(_ key: String, with value: PropertyValue, parsedProperties: [NoteProperty]) -> [NoteProperty] {
        record(properties(parsedProperties: parsedProperties).map { existing in existing.key == key ? NoteProperty(key: key, value: value) : existing })
    }

    mutating func removing(_ key: String, parsedProperties: [NoteProperty]) -> [NoteProperty] {
        record(properties(parsedProperties: parsedProperties).filter { existing in existing.key != key })
    }

    /// Nil when the name is empty or already used, which changes nothing.
    mutating func adding(_ name: String, parsedProperties: [NoteProperty]) -> [NoteProperty]? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentProperties = properties(parsedProperties: parsedProperties)
        guard !trimmedName.isEmpty, !currentProperties.contains(where: { existing in existing.key == trimmedName }) else { return nil }
        return record(currentProperties + [NoteProperty(key: trimmedName, value: .empty)])
    }

    private mutating func record(_ updatedProperties: [NoteProperty]) -> [NoteProperty] {
        committedProperties = updatedProperties
        return updatedProperties
    }
}

private struct PropertyRow: View {
    static let iconWidth: CGFloat = 24
    static let maximumKeyColumnWidth: CGFloat = 210

    let property: NoteProperty
    let declaredType: PropertyType?
    let isEditable: Bool
    let keyColumnWidth: CGFloat
    let follow: ((String, Bool) -> Void)?
    let commit: (PropertyValue) -> Void
    let remove: () -> Void
    @State private var draftText = ""
    @State private var draftListItem = ""
    @State private var isEditingLinkText = false
    @FocusState private var isTextFocused: Bool
    @FocusState private var isListItemFocused: Bool

    /// Controls without a text baseline (a date picker, a checkbox) are centered on the name.
    private var rowAlignment: VerticalAlignment {
        switch property.value {
        case .date, .dateTime, .checkbox: .center
        default: .firstTextBaseline
        }
    }

    var body: some View {
        HStack(alignment: rowAlignment, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: typeImage)
                    .foregroundStyle(.secondary)
                    .frame(width: Self.iconWidth)
                Text(property.key).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: keyColumnWidth, alignment: .leading)
            valueEditor.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .contextMenu {
            if isEditable {
                // Nested YAML has no type to change to without losing it.
                if let currentKind = PropertyValueKind(property.value) {
                    Menu("Change Type") {
                        ForEach(PropertyValueKind.allCases.filter { kind in kind != currentKind }, id: \.self) { kind in
                            let convertedValue = PropertyValueKind.converted(property.value, to: kind)
                            Button(kind.title) { if let convertedValue { commit(convertedValue) } }
                                .disabled(convertedValue == nil)
                        }
                    }
                }
                if case .text(let text) = property.value, PropertyItems.linkTarget(in: text) != nil {
                    Button("Edit Link", systemImage: "pencil") { isEditingLinkText = true; isTextFocused = true }
                }
                Button("Remove Property", systemImage: "trash", role: .destructive) { remove() }
            }
        }
        .onAppear { draftText = property.value.displayText }
        .onChange(of: property.value) { _, newValue in draftText = newValue.displayText }
        // Leaving a field keeps what was typed, as in Obsidian.
        .onChange(of: isTextFocused) { _, isFocused in
            if !isFocused { commitDraftText(); isEditingLinkText = false }
        }
        .onChange(of: isListItemFocused) { _, isFocused in
            if !isFocused { commitDraftListItem() }
        }
    }

    @ViewBuilder private var valueEditor: some View {
        switch property.value {
        case .checkbox(let isChecked):
            Button { commit(.checkbox(!isChecked)) } label: {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isChecked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .disabled(!isEditable)
            .accessibilityLabel(property.key)
            .accessibilityValue(isChecked ? "Checked" : "Unchecked")
        case .list(let items):
            // Items wrap like text, and the field for a new item follows the last one.
            WrappingRowLayout(horizontalSpacing: 10, verticalSpacing: 8) {
                PropertyItems(items: items, style: declaredType == .tags ? .tags : .plain, isEditable: isEditable, follow: follow) { remainingItems in
                    commit(.list(remainingItems))
                }
                if isEditable {
                    TextField(items.isEmpty ? "Empty" : "", text: $draftListItem)
                        .focused($isListItemFocused)
                        .frame(minWidth: 60, maxWidth: 160)
                        .autocorrectionDisabled()
                        #if canImport(UIKit)
                        .textInputAutocapitalization(.never)
                        #endif
                        .onSubmit(commitDraftListItem)
                }
            }
        case .date(let dateText):
            dateEditor(dateText, includesTime: false)
        case .dateTime(let dateText):
            dateEditor(dateText, includesTime: true)
        case .unsupported(let yaml):
            Text(yaml).font(.callout.monospaced()).foregroundStyle(.secondary)
        case .number:
            TextField("Empty", text: $draftText)
                .focused($isTextFocused)
                .disabled(!isEditable)
                #if canImport(UIKit)
                .keyboardType(.decimalPad)
                #endif
                .onSubmit(commitDraftText)
        case .text(let text) where !isEditingLinkText && PropertyItems.linkTarget(in: text) != nil:
            // A link reads as a link, as in Obsidian; its menu edits the text.
            PropertyLink(item: text, follow: follow)
        case .text, .empty:
            textField
        }
    }

    private var textField: some View {
        TextField("Empty", text: $draftText)
            .focused($isTextFocused)
            .disabled(!isEditable)
            .onSubmit(commitDraftText)
    }

    private func commitDraftText() {
        let trimmedText = draftText.trimmingCharacters(in: .whitespaces)
        switch property.value {
        case .number:
            // An empty field clears the value. Text that is not a finite number is not
            // saved, so the field shows the stored number again rather than unsaved text.
            if trimmedText.isEmpty { commit(.empty); return }
            guard let number = PropertyNumberText.number(from: trimmedText) else { draftText = property.value.displayText; return }
            if .number(number) != property.value { commit(.number(number)) } else { draftText = property.value.displayText }
        case .text, .empty:
            let newValue: PropertyValue = draftText.isEmpty ? .empty : .text(draftText)
            if newValue != property.value { commit(newValue) }
        case .date, .dateTime:
            // Only a date the picker cannot show, such as `2026-02-30`, is edited as text.
            guard trimmedText != property.value.displayText else { return }
            if trimmedText.isEmpty { commit(.empty) }
            else if let parsedDate = PropertyDateText.parse(trimmedText) { commit(parsedDate.hasTime ? .dateTime(trimmedText) : .date(trimmedText)) }
            else { commit(.text(trimmedText)) }
        default:
            break
        }
    }

    /// Leaving the field keeps a typed item, as leaving a text field does.
    private func commitDraftListItem() {
        guard case .list(let items) = property.value else { return }
        let item = draftListItem.trimmingCharacters(in: .whitespacesAndNewlines)
        draftListItem = ""
        if !item.isEmpty { commit(.list(items + [item])) }
    }

    @ViewBuilder private func dateEditor(_ dateText: String, includesTime: Bool) -> some View {
        if let parsedDate = PropertyDateText.parse(dateText) {
            DatePicker(property.key, selection: Binding(get: { parsedDate.date }, set: { pickedDate in
                // The value keeps its written form (a space or `T`, seconds) and the part
                // of the time the picker does not show.
                let committedDate = PropertyDateText.combining(pickedDate: pickedDate, original: parsedDate.date, pickerShowsTime: includesTime)
                let committedText = PropertyDateText.text(for: committedDate, pattern: parsedDate.pattern)
                commit(includesTime ? .dateTime(committedText) : .date(committedText))
            }), displayedComponents: includesTime ? [.date, .hourAndMinute] : [.date])
            .labelsHidden().disabled(!isEditable)
        } else {
            textField
        }
    }

    /// Obsidian's icons for each property type.
    private var typeImage: String {
        switch property.value {
        case .list where declaredType == .tags: "tag"
        case .list where declaredType == .aliases: "arrow.turn.up.right"
        case .text, .empty: "text.alignleft"
        case .list: "list.bullet"
        case .number: "number"
        case .checkbox: "checkmark.square"
        case .date: "calendar"
        case .dateTime: "clock"
        case .unsupported: "curlybraces"
        }
    }
}

/// The types the Properties view's "Change Type" menu converts between.
enum PropertyValueKind: CaseIterable, Hashable {
    case text, list, number, checkbox, date, dateTime

    /// Nil for nested YAML, which has no editable type.
    init?(_ value: PropertyValue) {
        switch value {
        case .empty, .text: self = .text
        case .list: self = .list
        case .number: self = .number
        case .checkbox: self = .checkbox
        case .date: self = .date
        case .dateTime: self = .dateTime
        case .unsupported: return nil
        }
    }

    var title: String {
        switch self {
        case .text: "Text"
        case .list: "List"
        case .number: "Number"
        case .checkbox: "Checkbox"
        case .date: "Date"
        case .dateTime: "Date & time"
        }
    }

    /// `value` as this type, or nil when converting would lose it (text that is not a
    /// number, a date or a checkbox state). Graphite does not write `types.json`, so the
    /// converted value is the change; it never replaces a value with a made-up one. An
    /// empty value takes a starting value (0, unchecked, today) for the user to change.
    @MainActor static func converted(_ value: PropertyValue, to kind: PropertyValueKind, now: Date = .now) -> PropertyValue? {
        if case .unsupported = value { return nil }
        let scalarText: String? = switch value {
        case .list(let items): items.count == 1 ? items[0] : (items.isEmpty ? "" : nil)
        default: value.displayText
        }
        let trimmedText = scalarText?.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .text:
            return value.displayText.isEmpty ? .empty : .text(value.displayText)
        case .list:
            if case .list = value { return value }
            return value.displayText.isEmpty ? .list([]) : .list([value.displayText])
        case .number:
            if case .number = value { return value }
            guard let trimmedText else { return nil }
            if trimmedText.isEmpty { return .number(0) }
            return PropertyNumberText.number(from: trimmedText).map(PropertyValue.number)
        case .checkbox:
            if case .checkbox = value { return value }
            switch trimmedText?.lowercased() {
            case "": return .checkbox(false)
            case "true": return .checkbox(true)
            case "false": return .checkbox(false)
            default: return nil
            }
        case .date, .dateTime:
            guard let trimmedText else { return nil }
            let includesTime = kind == .dateTime
            let date: Date
            if trimmedText.isEmpty { date = now }
            else if let parsedDate = PropertyDateText.parse(trimmedText) { date = parsedDate.date }
            else { return nil }
            let text = PropertyDateText.text(for: date, pattern: includesTime ? PropertyDateText.dateTimePattern : PropertyDateText.datePattern)
            return includesTime ? .dateTime(text) : .date(text)
        }
    }
}

/// Reads a typed number the way people write one: with a comma or a period as the
/// decimal separator, and with thousands separators. Anything else is refused rather
/// than guessed, including `nan`, `inf` and hexadecimal, which `Double(_:)` accepts but
/// YAML would read back as text.
enum PropertyNumberText {
    static func number(from text: String, locale: Locale = .current) -> Double? {
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        var body = Substring(trimmedText)
        var sign = ""
        if let first = body.first, first == "-" || first == "+" { sign = String(first); body = body.dropFirst() }
        guard let normalized = normalizedSeparators(in: String(body), commaIsDecimal: locale.decimalSeparator == ","),
              normalized.range(of: "^([0-9]+(\\.[0-9]*)?|\\.[0-9]+)([eE][-+]?[0-9]+)?$", options: .regularExpression) != nil,
              let number = Double(sign + normalized), number.isFinite else { return nil }
        return number
    }

    /// The text with the decimal separator as a period and no thousands separators, or
    /// nil when the separators are not in positions a number allows.
    private static func normalizedSeparators(in text: String, commaIsDecimal: Bool) -> String? {
        let commaCount = text.filter { character in character == "," }.count
        let periodCount = text.filter { character in character == "." }.count
        let decimalSeparator: Character?
        let groupingSeparator: Character?
        if commaCount > 0 && periodCount > 0 {
            // Both appear, as in `1.234,5` or `1,234.5`: the last one is the decimal separator.
            guard let lastSeparator = text.last(where: { character in character == "," || character == "." }) else { return nil }
            decimalSeparator = lastSeparator
            groupingSeparator = lastSeparator == "," ? "." : ","
        } else if commaCount + periodCount == 0 {
            return text
        } else {
            let separator: Character = commaCount > 0 ? "," : "."
            let digitsAfterSeparator = text.split(separator: separator, omittingEmptySubsequences: false).last?.count ?? 0
            // `1,000` is a thousand where the comma groups digits, and one where it is the
            // decimal separator; the device's language decides, as the keyboard does. A
            // single period is always a decimal point: numbers are shown and stored that
            // way, so editing a shown `2.125` must not read it as 2125.
            let commaGroupsDigits = separator == "," && !commaIsDecimal
            if commaCount + periodCount > 1 || (digitsAfterSeparator == 3 && commaGroupsDigits) {
                decimalSeparator = nil
                groupingSeparator = separator
            } else {
                decimalSeparator = separator
                groupingSeparator = nil
            }
        }
        var integerPart = Substring(text)
        var fractionPart: Substring?
        if let decimalSeparator {
            let parts = text.split(separator: decimalSeparator, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            integerPart = parts[0]
            fractionPart = parts[1]
            if let groupingSeparator, fractionPart?.contains(groupingSeparator) == true { return nil }
        }
        if let groupingSeparator, integerPart.contains(groupingSeparator) {
            let groups = integerPart.split(separator: groupingSeparator, omittingEmptySubsequences: false)
            guard let firstGroup = groups.first, (1...3).contains(firstGroup.count),
                  groups.dropFirst().allSatisfy({ group in group.count == 3 }) else { return nil }
            integerPart = Substring(groups.joined())
        }
        return fractionPart.map { fraction in integerPart + "." + fraction } ?? String(integerPart)
    }
}

/// Property dates in the forms Obsidian and `NoteProperties` recognize: `2026-09-23`,
/// then a `T` or a space, `14:30`, optional seconds and an optional fraction.
enum PropertyDateText {
    struct ParsedDate {
        let date: Date
        /// The `DateFormatter` pattern that writes the date back in the same form.
        let pattern: String
        var hasTime: Bool { pattern != PropertyDateText.datePattern }
    }

    /// Obsidian's stored formats: `YYYY-MM-DD` and `YYYY-MM-DDTHH:mm`.
    static let datePattern = "yyyy-MM-dd"
    static let dateTimePattern = "yyyy-MM-dd'T'HH:mm"
    /// Fractions longer than nanoseconds are not dates any app writes.
    private static let maximumFractionDigits = 9
    private static let shapeExpression = try? NSRegularExpression(pattern: "^\\d{4}-\\d{2}-\\d{2}(?:([T ])\\d{2}:\\d{2}(?::\\d{2}(?:\\.(\\d{1,\(maximumFractionDigits)}))?)?)?$")

    /// Nil for text that is not a real date in one of those forms, such as `2026-02-30`.
    @MainActor static func parse(_ text: String) -> ParsedDate? {
        guard let pattern = pattern(for: text) else { return nil }
        let dateFormatter = formatter(pattern: pattern)
        // A formatter rolls `2026-02-30` over to March; only text it writes back the same
        // way is a real date.
        guard let date = dateFormatter.date(from: text), dateFormatter.string(from: date) == text else { return nil }
        return ParsedDate(date: date, pattern: pattern)
    }

    @MainActor static func text(for date: Date, pattern: String) -> String {
        formatter(pattern: pattern).string(from: date)
    }

    /// The picked day and, when the picker shows the time, its hour and minute. The rest
    /// of the time comes from `original`: a date picker never shows seconds, and a
    /// date-only picker does not show the time of a value that has one.
    static func combining(pickedDate: Date, original: Date, pickerShowsTime: Bool, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: pickedDate)
        let originalTime = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: original)
        if pickerShowsTime {
            let pickedTime = calendar.dateComponents([.hour, .minute], from: pickedDate)
            let keepsOriginalSeconds = pickedTime.hour == originalTime.hour && pickedTime.minute == originalTime.minute
            components.hour = pickedTime.hour
            components.minute = pickedTime.minute
            components.second = keepsOriginalSeconds ? originalTime.second : 0
            components.nanosecond = keepsOriginalSeconds ? originalTime.nanosecond : 0
        } else {
            components.hour = originalTime.hour
            components.minute = originalTime.minute
            components.second = originalTime.second
            components.nanosecond = originalTime.nanosecond
        }
        return calendar.date(from: components) ?? pickedDate
    }

    private static func pattern(for text: String) -> String? {
        let textRange = NSRange(text.startIndex..., in: text)
        guard let match = shapeExpression?.firstMatch(in: text, range: textRange) else { return nil }
        let separatorRange = match.range(at: 1)
        guard separatorRange.location != NSNotFound else { return datePattern }
        let separator = (text as NSString).substring(with: separatorRange) == "T" ? "'T'" : " "
        var pattern = "yyyy-MM-dd" + separator + "HH:mm"
        // `yyyy-MM-ddTHH:mm` is 16 characters; anything longer has seconds.
        if text.count > 16 { pattern += ":ss" }
        let fractionRange = match.range(at: 2)
        if fractionRange.location != NSNotFound { pattern += "." + String(repeating: "S", count: fractionRange.length) }
        return pattern
    }

    /// Formatters are costly to create and rows ask for them on every render. The shape
    /// expression bounds the patterns (two separators, seconds or not, nine fraction
    /// lengths), so the cache stays small.
    @MainActor private static var cachedFormatters: [String: DateFormatter] = [:]

    @MainActor private static func formatter(pattern: String) -> DateFormatter {
        if let cachedFormatter = cachedFormatters[pattern] { return cachedFormatter }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = pattern
        cachedFormatters[pattern] = formatter
        return formatter
    }
}

/// The items of a list property: tags as accent chips, links as underlined links, and
/// other text as neutral chips, each followed by a remove button.
private struct PropertyItems: View {
    enum Style { case tags, plain }

    let items: [String]
    let style: Style
    let isEditable: Bool
    let follow: ((String, Bool) -> Void)?
    let commit: ([String]) -> Void

    var body: some View {
        ForEach(Array(items.enumerated()), id: \.offset) { itemIndex, item in
            if style == .plain, Self.linkTarget(in: item) != nil {
                HStack(spacing: 6) {
                    PropertyLink(item: item, follow: follow)
                    removeButton(for: itemIndex, item: item).foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    Text(style == .tags && item.hasPrefix("#") ? String(item.dropFirst()) : item).lineLimit(1)
                    removeButton(for: itemIndex, item: item)
                }
                .foregroundStyle(style == .tags ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(style == .tags ? AnyShapeStyle(.tint.opacity(0.16)) : AnyShapeStyle(Color.secondary.opacity(0.16)), in: Capsule())
            }
        }
    }

    @ViewBuilder private func removeButton(for itemIndex: Int, item: String) -> some View {
        if isEditable {
            Button {
                var remainingItems = items
                remainingItems.remove(at: itemIndex)
                commit(remainingItems)
            } label: {
                Image(systemName: "xmark").font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(item)")
        }
    }

    /// Obsidian stores links in properties as quoted `[[Note]]` or `[[Note|alias]]`.
    static func linkTarget(in item: String) -> String? {
        guard item.hasPrefix("[["), item.hasSuffix("]]"), item.count > 4 else { return nil }
        return String(item.dropFirst(2).dropLast(2).split(separator: "|", maxSplits: 1).first ?? "")
    }

    static func linkLabel(in item: String) -> String {
        let content = item.dropFirst(2).dropLast(2).split(separator: "|", maxSplits: 1).map(String.init)
        return content.count == 2 ? content[1] : content.first ?? item
    }
}

/// A `[[link]]` in a property, underlined in the accent color like links in the note.
private struct PropertyLink: View {
    let item: String
    let follow: ((String, Bool) -> Void)?

    var body: some View {
        let label = PropertyItems.linkLabel(in: item)
        if let follow, let target = PropertyItems.linkTarget(in: item) {
            Button { follow(target, true) } label: {
                Text(label).underline().foregroundStyle(.tint).multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
        } else {
            Text(label).underline().foregroundStyle(.tint)
        }
    }
}

/// Places its views left to right like words, starting a new row when the next one does
/// not fit. Rows are as tall as their tallest view, which is centered in them.
struct WrappingRowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maximumWidth = proposal.width ?? .infinity
        let rows = arrangedRows(of: subviews, maximumWidth: maximumWidth)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + verticalSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: min(width, maximumWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var rowTop = bounds.minY
        for row in arrangedRows(of: subviews, maximumWidth: bounds.width) {
            var itemLeft = bounds.minX
            for index in row.indices {
                let size = fittedSize(of: subviews[index], maximumWidth: bounds.width)
                subviews[index].place(at: CGPoint(x: itemLeft, y: rowTop + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                itemLeft += size.width + horizontalSpacing
            }
            rowTop += row.height + verticalSpacing
        }
    }

    /// A view's natural size, narrowed to the available width when it is wider.
    private func fittedSize(of subview: LayoutSubview, maximumWidth: CGFloat) -> CGSize {
        let naturalSize = subview.sizeThatFits(.unspecified)
        guard naturalSize.width > maximumWidth else { return naturalSize }
        return subview.sizeThatFits(ProposedViewSize(width: maximumWidth, height: nil))
    }

    private func arrangedRows(of subviews: Subviews, maximumWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var currentRow = Row()
        for index in subviews.indices {
            let size = fittedSize(of: subviews[index], maximumWidth: maximumWidth)
            let widthWithItem = currentRow.indices.isEmpty ? size.width : currentRow.width + horizontalSpacing + size.width
            if !currentRow.indices.isEmpty && widthWithItem > maximumWidth {
                rows.append(currentRow)
                currentRow = Row(indices: [index], width: size.width, height: size.height)
            } else {
                currentRow.indices.append(index)
                currentRow.width = widthWithItem
                currentRow.height = max(currentRow.height, size.height)
            }
        }
        if !currentRow.indices.isEmpty { rows.append(currentRow) }
        return rows
    }
}
