import SwiftUI
import GraphiteCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The Emoji button of the folder popover: it shows the chosen emoji, or "Emoji", and opens the
/// system's own emoji picker. On iOS a touch brings up the emoji keyboard; on the Mac a click
/// opens the Character Viewer. The first emoji typed is the one chosen.
struct EmojiInputButton: View {
    let currentEmoji: String?
    let choose: (String) -> Void

    var body: some View {
        label
            .bottomButtonLabel()
            .overlay { EmojiInputField(choose: choose) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(currentEmoji.map { emoji in "Emoji, \(emoji)" } ?? "Emoji")
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var label: some View {
        // As Finder's: the chosen emoji takes the symbol's place beside the word.
        if let currentEmoji {
            Label { Text("Emoji") } icon: { Text(currentEmoji) }
        } else {
            Label("Emoji", systemImage: "face.smiling")
        }
    }
}

#if canImport(UIKit)
/// A text field the size of the button, drawn as nothing: touching it begins editing with
/// the emoji keyboard, and each emoji typed is handed over and cleared.
private struct EmojiInputField: UIViewRepresentable {
    let choose: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(choose: choose) }

    func makeUIView(context: Context) -> EmojiKeyboardTextField {
        let field = EmojiKeyboardTextField()
        field.textColor = .clear
        field.tintColor = .clear
        field.autocorrectionType = .no
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: EmojiKeyboardTextField, context: Context) {
        context.coordinator.choose = choose
    }

    @MainActor final class Coordinator: NSObject {
        var choose: (String) -> Void
        init(choose: @escaping (String) -> Void) { self.choose = choose }

        @objc func textChanged(_ field: UITextField) {
            let typedText = field.text ?? ""
            field.text = ""
            guard let emoji = FolderMark.firstEmoji(in: typedText) else { return }
            field.resignFirstResponder()
            choose(emoji)
        }
    }
}

/// Asks for the emoji keyboard, as the system offers no public switch to it: the input mode
/// whose language is "emoji" is the one Messages and Notes bring up.
private final class EmojiKeyboardTextField: UITextField {
    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { inputMode in inputMode.primaryLanguage == "emoji" } ?? super.textInputMode
    }

    override func caretRect(for position: UITextPosition) -> CGRect { .zero }
}
#else
/// A field the size of the button, drawn as nothing: a click makes it the place the
/// Character Viewer types into and opens the viewer; each emoji typed is handed over and cleared.
private struct EmojiInputField: NSViewRepresentable {
    let choose: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(choose: choose) }

    func makeNSView(context: Context) -> CharacterPaletteField {
        let field = CharacterPaletteField()
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: CharacterPaletteField, context: Context) {
        context.coordinator.choose = choose
    }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var choose: (String) -> Void
        init(choose: @escaping (String) -> Void) { self.choose = choose }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let typedText = field.stringValue
            field.stringValue = ""
            guard let emoji = FolderMark.firstEmoji(in: typedText) else { return }
            choose(emoji)
        }
    }
}

private final class CharacterPaletteField: NSTextField {
    init() {
        super.init(frame: .zero)
        isBordered = false
        drawsBackground = false
        textColor = .clear
        focusRingType = .none
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        (currentEditor() as? NSTextView)?.insertionPointColor = .clear
        NSApp.orderFrontCharacterPalette(self)
    }
}
#endif
