import Foundation
import XCTest

/// The owner's real Goodnotes and Notability samples, which are personal notebooks and are never in the repository.
/// They live only in the owner's local `samples/import-formats` branch, under `ImportSamples/`. To run the sample tests,
/// copy that folder out (`git archive samples/import-formats ImportSamples | tar -x -C <folder>`), write the reference
/// readers' counts with `python3 scripts/import-reference-counts.py <folder>/ImportSamples > <counts>.json`, and set
/// `GRAPHITE_IMPORT_SAMPLES=<folder>/ImportSamples` and `GRAPHITE_IMPORT_REFERENCE_COUNTS=<counts>.json`. Without them
/// the sample tests are skipped: no other machine has the samples.
enum NotebookImportSamples {
    static let samplesFolderVariable = "GRAPHITE_IMPORT_SAMPLES"
    static let referenceCountsVariable = "GRAPHITE_IMPORT_REFERENCE_COUNTS"
    static let skipReason = "Set GRAPHITE_IMPORT_SAMPLES and GRAPHITE_IMPORT_REFERENCE_COUNTS to compare with the owner's samples."

    struct Configuration {
        let samplesFolder: URL
        /// Each sample's counts from the reference reader, keyed by its path relative to the samples folder.
        let referenceCounts: [String: [String: JSONValue]]
    }

    /// The configured samples and the reference readers' counts, or a skip when they are not configured.
    static func configuration() throws -> Configuration {
        let environment = ProcessInfo.processInfo.environment
        guard let samplesPath = environment[samplesFolderVariable], let countsPath = environment[referenceCountsVariable] else {
            throw XCTSkip(skipReason)
        }
        let countsData = try Data(contentsOf: URL(fileURLWithPath: countsPath))
        let referenceCounts = try JSONDecoder().decode([String: [String: JSONValue]].self, from: countsData)
        return Configuration(samplesFolder: URL(fileURLWithPath: samplesPath, isDirectory: true), referenceCounts: referenceCounts)
    }

    /// The relative paths of the samples with this extension, sorted.
    static func samplePaths(withExtension fileExtension: String, in configuration: Configuration) -> [String] {
        configuration.referenceCounts.keys.filter { path in path.hasSuffix(".\(fileExtension)") }.sorted()
    }

    /// One value of the reference counts file: a number, a string, a list or null.
    enum JSONValue: Decodable, Equatable {
        case number(Double)
        case text(String)
        case list([JSONValue])
        case null

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let number = try? container.decode(Double.self) { // not a number: one of the other shapes
                self = .number(number)
            } else if let text = try? container.decode(String.self) { // not a string: a list
                self = .text(text)
            } else {
                self = .list(try container.decode([JSONValue].self))
            }
        }
    }
}
