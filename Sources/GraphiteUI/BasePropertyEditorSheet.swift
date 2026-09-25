import SwiftUI
import GraphiteCore

/// Edits one note property from a base. Saving rewrites only that note's frontmatter.
struct BasePropertyEditorSheet: View {
    let request: BaseEditRequest
    /// Saves the value and returns nil, or returns why the note was not saved. The sheet
    /// stays open with the typed value until the save succeeds.
    let saveEdit: (PropertyValue?) async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var draft: BasePropertyDraft
    /// Kept in state: the view is created again whenever its parent updates, and a draft
    /// made again would carry a new "now" for an empty date and read as changed.
    @State private var loadedDraft: BasePropertyDraft
    @State private var numberIsInvalid = false
    @State private var isSaving = false
    @State private var failureMessage: String?

    /// - Parameter writtenNode: The property as written in the note's frontmatter. With
    ///   it, links, embeds and dates are shown and kept exactly as written.
    init(request: BaseEditRequest, writtenNode: BaseFrontmatterNode? = nil, saveEdit: @escaping (PropertyValue?) async -> String?) {
        self.request = request
        self.saveEdit = saveEdit
        let initialDraft = BasePropertyDraft(kind: request.kind, currentValue: request.currentValue, writtenNode: writtenNode)
        _loadedDraft = State(initialValue: initialDraft)
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    editor
                } header: {
                    Text(request.path.stem)
                } footer: {
                    Text(footerText)
                }
                if let failureMessage {
                    Section { Label(failureMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(request.displayName)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveDraft)
                        .disabled(isSaving || draft.readOnlyReason != nil)
                }
            }
        }
        // An iOS sheet takes the width it is given, which can be narrower than this in Slide
        // Over or a narrow split, so only the Mac, where a sheet fits its content, sets one.
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 300)
        #endif
        .interactiveDismissDisabled(isSaving)
    }

    @ViewBuilder private var editor: some View {
        if let readOnlyReason = draft.readOnlyReason {
            Text(draft.text).font(.callout.monospaced()).foregroundStyle(.secondary)
            Text(readOnlyReason).font(.caption).foregroundStyle(.secondary)
        } else {
            switch request.kind {
            case .text:
                TextField("Value", text: $draft.text, axis: .vertical)
            case .number:
                TextField("Number", text: $draft.text)
                #if canImport(UIKit)
                    .keyboardType(.decimalPad)
                #endif
                if numberIsInvalid { Text("Enter a number, or leave it empty.").font(.caption).foregroundStyle(.red) }
            case .checkbox:
                Toggle(request.displayName, isOn: $draft.isChecked)
            case .date, .dateTime:
                Toggle("Has a date", isOn: $draft.hasDate)
                if draft.hasDate {
                    DatePicker(request.displayName, selection: $draft.date, displayedComponents: request.kind == .date ? [.date] : [.date, .hourAndMinute])
                }
                if let unreadableDateText = draft.unreadableDateText {
                    Text("The note has “\(unreadableDateText)”, which is not a date. It is kept unless you set a date.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .list:
                TextField("One value per line", text: $draft.text, axis: .vertical)
                    .lineLimit(4...12)
            }
        }
    }

    private var footerText: String {
        if draft.readOnlyReason != nil { return "Edit this property in the note." }
        switch request.kind {
        case .list: return "Write one value per line. Links keep their [[brackets]]."
        case .text: return "Links keep their [[brackets]]. Leave empty to clear the value."
        default: return "Only this property of the note changes."
        }
    }

    private func saveDraft() {
        guard draft.needsSaving(comparedTo: loadedDraft) else { dismiss(); return }
        guard let value = draft.editedValue(kind: request.kind) else { numberIsInvalid = true; return }
        numberIsInvalid = false
        failureMessage = nil
        isSaving = true
        Task {
            if let message = await saveEdit(value) {
                failureMessage = message
                isSaving = false
            } else {
                dismiss()
            }
        }
    }
}

/// What the property sheet edits, filled from the note's value.
struct BasePropertyDraft: Equatable {
    var text = ""
    var isChecked = false
    var date = Date()
    var hasDate = true
    /// Why the value cannot be edited here without losing part of it, such as a nested
    /// mapping. The sheet then shows the value and does not save.
    private(set) var readOnlyReason: String?
    /// A value that is not a date the picker can show, such as `next week`.
    private(set) var unreadableDateText: String?
    /// The value's date when it has one, whose seconds the picker does not show.
    private(set) var originalDate: Date?
    /// The date's form as written (`T` or a space, seconds), when it is known.
    private(set) var originalDatePattern: String?

    @MainActor init(kind: BasePropertyEditorKind, currentValue: BaseValue?, writtenNode: BaseFrontmatterNode? = nil, now: Date = .now) {
        let value = currentValue ?? .null
        switch kind {
        case .checkbox:
            if case .boolean(let isOn) = value { isChecked = isOn }
        case .date, .dateTime:
            date = now
            switch value {
            case .date(let baseDate):
                date = baseDate.date
                originalDate = baseDate.date
                if case .scalar(let writtenText, _) = writtenNode {
                    originalDatePattern = PropertyDateText.parse(writtenText.trimmingCharacters(in: .whitespaces))?.pattern
                }
            case .null:
                hasDate = false
            default:
                hasDate = false
                unreadableDateText = Self.writtenScalarText(writtenNode) ?? Self.sourceText(value)
            }
        case .text, .number:
            switch value {
            case .list, .object:
                text = value.displayText
                readOnlyReason = "This value holds several values, so it cannot be edited as one."
            default:
                text = Self.writtenScalarText(writtenNode) ?? Self.sourceText(value)
            }
        case .list:
            switch value {
            case .object:
                text = value.displayText
                readOnlyReason = "This value is a group of named values, which a list cannot hold."
            case .list(let elements):
                if elements.contains(where: { element in
                    switch element { case .list, .object: true; default: false }
                }) {
                    text = value.displayText
                    readOnlyReason = "This list holds nested lists or groups, which would be lost."
                } else {
                    text = (Self.writtenItemTexts(writtenNode, count: elements.count) ?? elements.map(Self.sourceText)).joined(separator: "\n")
                }
            case .null:
                text = ""
            default:
                text = Self.writtenScalarText(writtenNode) ?? Self.sourceText(value)
            }
        }
    }

    /// Whether Save writes anything. The text shown for a value cannot always reproduce it
    /// as written, so a draft the user did not change is never written. Neither is a date
    /// left off when the value had no date the picker could show, such as `next week`,
    /// which is kept rather than cleared.
    func needsSaving(comparedTo loadedDraft: BasePropertyDraft) -> Bool {
        if !hasDate && !loadedDraft.hasDate { return false }
        return self != loadedDraft
    }

    /// Nil when the input cannot be saved (an invalid number); `.some(.empty)` clears.
    @MainActor func editedValue(kind: BasePropertyEditorKind) -> PropertyValue?? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .text:
            return .some(trimmedText.isEmpty ? .empty : .text(trimmedText))
        case .number:
            if trimmedText.isEmpty { return .some(.empty) }
            guard let number = PropertyNumberText.number(from: trimmedText) else { return nil }
            return .some(.number(number))
        case .checkbox:
            return .some(.checkbox(isChecked))
        case .date:
            return .some(hasDate ? .date(dateText(includesTime: false)) : .empty)
        case .dateTime:
            return .some(hasDate ? .dateTime(dateText(includesTime: true)) : .empty)
        case .list:
            let items = text.split(whereSeparator: \.isNewline).map { line in line.trimmingCharacters(in: .whitespaces) }.filter { item in !item.isEmpty }
            return .some(.list(items))
        }
    }

    /// The picked date in the value's written form. Seconds the picker does not show,
    /// and a time a date-only picker does not show, are kept from the original value.
    @MainActor private func dateText(includesTime: Bool) -> String {
        let committedDate = originalDate.map { original in
            PropertyDateText.combining(pickedDate: date, original: original, pickerShowsTime: includesTime)
        } ?? date
        if let originalDatePattern, (originalDatePattern != PropertyDateText.datePattern) == includesTime {
            return PropertyDateText.text(for: committedDate, pattern: originalDatePattern)
        }
        guard includesTime else { return PropertyDateText.text(for: committedDate, pattern: PropertyDateText.datePattern) }
        let hasSeconds = Calendar.current.component(.second, from: committedDate) != 0
        return PropertyDateText.text(for: committedDate, pattern: PropertyDateText.dateTimePattern + (hasSeconds ? ":ss" : ""))
    }

    private static func writtenScalarText(_ writtenNode: BaseFrontmatterNode?) -> String? {
        guard case .scalar(let writtenText, _) = writtenNode else { return nil }
        return writtenText
    }

    /// The list's items as written, when they match the evaluated items one for one.
    private static func writtenItemTexts(_ writtenNode: BaseFrontmatterNode?, count: Int) -> [String]? {
        guard case .sequence(let itemNodes) = writtenNode, itemNodes.count == count else { return nil }
        let itemTexts = itemNodes.compactMap { itemNode -> String? in
            if case .scalar(let itemText, _) = itemNode { return itemText }
            return nil
        }
        return itemTexts.count == count ? itemTexts : nil
    }

    /// The text to write back for a value when the written text is not known, keeping
    /// links in a form that reads back as the same link.
    static func sourceText(_ value: BaseValue) -> String {
        switch value {
        case .link(let link) where link.isExternal:
            guard let display = link.display, !display.isEmpty else { return link.target }
            return "[" + display + "](" + link.target + ")"
        case .link(let link):
            return "[[" + link.target + (link.display.map { display in "|" + display } ?? "") + "]]"
        case .number(let number):
            return BaseValue.formatted(number)
        default:
            return value.displayText
        }
    }
}
