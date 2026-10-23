import Foundation

/// The Git graph inputs of the benchmark: Mermaid's 35 documentation examples, as Pele collects them, and generated
/// histories of feature branches merged back into `main`.
enum GitGraphCorpus {
    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "git-docs", withExtension: "json", subdirectory: "Resources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// `branchCount` feature branches, each of `commitsPerBranch` commits with ids, made from `main` after a commit of
    /// its own and merged back with a tag.
    static func generated(branchCount: Int, commitsPerBranch: Int = 3) -> String {
        var source = "gitGraph\n  commit id:\"start\"\n"
        for branch in 0..<branchCount {
            source += "  branch feature-\(branch)\n"
            for commit in 0..<commitsPerBranch { source += "  commit id:\"f\(branch)-\(commit)\"\n" }
            source += "  checkout main\n  commit\n  merge feature-\(branch) tag:\"v\(branch)\"\n"
        }
        return source
    }
}
