import SwiftUI

/// An alert for a message such as `WorkspaceModel.errorMessage`. Its first sentence is the
/// title, which says what happened, and the rest is the alert's text, rather than the app's
/// name over the whole message: Apple asks for a title that describes the situation.
struct MessageAlert: ViewModifier {
    @Binding var message: String?
    var dismiss: () -> Void = {}

    func body(content: Content) -> some View {
        let parts = Self.parts(of: message ?? "")
        content.alert(parts.title, isPresented: Binding(get: { message != nil }, set: { isPresented in
            guard !isPresented else { return }
            message = nil
            dismiss()
        })) {
            Button("OK", role: .cancel) {}
        } message: {
            if !parts.detail.isEmpty { Text(parts.detail) }
        }
    }

    /// The message's first sentence and the sentences after it. A sentence ends at a period,
    /// question mark or exclamation mark followed by a space, so a file name such as
    /// “Lecture.md” inside a sentence does not end it.
    static func parts(of message: String) -> (title: String, detail: String) {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sentenceEnd = trimmedMessage.range(of: #"[.?!](?=\s)"#, options: .regularExpression) else {
            return (trimmedMessage, "")
        }
        let title = String(trimmedMessage[..<sentenceEnd.upperBound])
        let detail = trimmedMessage[sentenceEnd.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, detail)
    }
}

extension View {
    func messageAlert(_ message: Binding<String?>, dismiss: @escaping () -> Void = {}) -> some View {
        modifier(MessageAlert(message: message, dismiss: dismiss))
    }
}

/// Something that happened as asked but not quite as expected, such as a file moved to the
/// vault's trash folder because the storage has no system trash: a banner over the top of
/// the document that stays until it is dismissed or another document is opened, rather than
/// an alert that stops the work.
struct NoticeBanner: View {
    @Binding var notice: String?

    var body: some View {
        if let notice {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text(notice).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                Button("Dismiss", systemImage: "xmark") { self.notice = nil }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .tint(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .padding(.leading, 14).padding(.trailing, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(maxWidth: 560)
            .padding(12)
            .accessibilityElement(children: .contain)
        }
    }
}
