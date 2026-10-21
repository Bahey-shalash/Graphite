import GraphiteCore

extension DeletionMethod {
    /// What the deletion question says happens to the items, by the vault's "Deleted files" setting.
    func confirmationExplanation(itemCount: Int) -> String {
        let pronoun = itemCount == 1 ? "It" : "They"
        switch self {
        case .systemTrash: return "\(pronoun) \(itemCount == 1 ? "goes" : "go") to the trash, where \(itemCount == 1 ? "it" : "they") can be recovered."
        case .vaultTrash: return "\(pronoun) \(itemCount == 1 ? "goes" : "go") to the vault's .trash folder."
        case .permanent: return "\(pronoun) \(itemCount == 1 ? "is" : "are") deleted for good. This cannot be undone."
        }
    }
}
