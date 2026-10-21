/**
 * File: NotePDFExportDefaults.swift
 * ---------------------------------
 * Layer: UI
 * Description: The Export to PDF options last used on this device, which the next export starts from.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/10/2026
 */

import Foundation
import GraphiteCore

/// The options of the last note exported to PDF on this device, kept as JSON.
struct NotePDFExportDefaults {
    static let optionsKey = "GraphiteNotePDFOptions"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The last options, or Obsidian's defaults when none were kept or what was kept cannot
    /// be read; unreadable data is left as it is.
    var options: NotePDFOptions {
        guard let data = defaults.data(forKey: Self.optionsKey) else { return NotePDFOptions() }
        return (try? JSONDecoder().decode(NotePDFOptions.self, from: data)) ?? NotePDFOptions() // Damaged: the defaults, data kept.
    }

    func remember(_ options: NotePDFOptions) {
        guard let data = try? JSONEncoder().encode(options) else { return } // Options always encode; else nothing is kept.
        defaults.set(data, forKey: Self.optionsKey)
    }
}
