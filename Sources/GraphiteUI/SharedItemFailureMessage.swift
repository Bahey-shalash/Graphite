import Foundation
import ShareInbox
import GraphiteCore

/// What the person is told when something shared to Graphite cannot be added.
enum SharedItemFailureMessage {
    static func inboxUnreadable(_ error: any Error) -> String {
        "Graphite couldn't read what was shared to it. " + reason(for: error)
    }

    static func unreadable(_ error: any Error) -> String {
        "Something shared to Graphite can't be read, so it stays in the share inbox. " + reason(for: error)
    }

    static func notDelivered(title: String, vaultName: String, error: any Error) -> String {
        "“\(title)”, shared to Graphite, couldn't be added to “\(vaultName)”. " + reason(for: error)
            + " It stays in the share inbox and is tried again the next time Graphite opens."
    }

    private static func reason(for error: any Error) -> String {
        switch error {
        case SharedItemDeliveryFailure.unknownDestination, ShareInboxError.newerFormat:
            return "It was shared by a newer version of Graphite; update Graphite to add it."
        case ShareInboxError.attachmentMissing(let fileName):
            return "The shared file “\(fileName)” is missing."
        case ShareInboxError.fileTooLarge(let fileName, _):
            return "“\(fileName)” is larger than Graphite reads."
        case ShareInboxError.noteNotUTF8:
            return "Its text is not UTF-8."
        case GraphiteError.conflict:
            return "The note changed in another app; resolve its conflict first."
        case is DailyNoteCreation.Failure:
            return WorkspaceModel.templatesFailureMessage(error)
        default:
            return error.localizedDescription
        }
    }
}
