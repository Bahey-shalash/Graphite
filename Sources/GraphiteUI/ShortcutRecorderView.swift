import SwiftUI
import GraphiteCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// What a recording ended with.
enum ShortcutRecording {
    case recorded(KeyCombination)
    /// Escape was pressed alone.
    case cancelled
}

/// Takes the keyboard while a shortcut is recorded: the next key pressed with its modifiers is
/// the shortcut, and Escape alone cancels. A modifier key pressed alone is waited past.
struct ShortcutRecorderView: View {
    let finish: (ShortcutRecording) -> Void

    var body: some View {
        KeyPressCatcher(finish: finish)
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
    }

    static func recording(of combination: KeyCombination) -> ShortcutRecording {
        combination == KeyCombination([], .named(.escape)) ? .cancelled : .recorded(combination)
    }
}

#if canImport(UIKit)
private struct KeyPressCatcher: UIViewRepresentable {
    let finish: (ShortcutRecording) -> Void

    func makeUIView(context: Context) -> KeyPressCatcherView {
        KeyPressCatcherView(finish: finish)
    }

    func updateUIView(_ view: KeyPressCatcherView, context: Context) {}
}

/// A view that becomes first responder and reports the first key press. The menu bar gives up
/// its shortcuts while it records (`VaultKeyboardShortcuts.recordingCommandIdentifier`), so ⌘
/// shortcuts reach it too.
final class KeyPressCatcherView: UIView {
    private let finish: (ShortcutRecording) -> Void
    private var hasFinished = false

    init(finish: @escaping (ShortcutRecording) -> Void) {
        self.finish = finish
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { becomeFirstResponder() }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard !hasFinished, let combination = presses.lazy.compactMap({ press in press.key.flatMap(KeyCombination.init(key:)) }).first else {
            super.pressesBegan(presses, with: event)
            return
        }
        hasFinished = true
        finish(ShortcutRecorderView.recording(of: combination))
    }
}
#else
private struct KeyPressCatcher: NSViewRepresentable {
    let finish: (ShortcutRecording) -> Void

    func makeNSView(context: Context) -> KeyPressCatcherView {
        KeyPressCatcherView(finish: finish)
    }

    func updateNSView(_ view: KeyPressCatcherView, context: Context) {}
}

/// A view that becomes first responder and reports the first key press, ⌘ shortcuts included:
/// a window asks its views for key equivalents before the menu bar.
final class KeyPressCatcherView: NSView {
    private let finish: (ShortcutRecording) -> Void
    private var hasFinished = false

    init(finish: @escaping (ShortcutRecording) -> Void) {
        self.finish = finish
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        return record(event)
    }

    override func keyDown(with event: NSEvent) {
        if !record(event) { super.keyDown(with: event) }
    }

    private func record(_ event: NSEvent) -> Bool {
        guard !hasFinished, let combination = KeyCombination(event: event) else { return false }
        hasFinished = true
        finish(ShortcutRecorderView.recording(of: combination))
        return true
    }
}
#endif
