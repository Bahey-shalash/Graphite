import Foundation
import Observation
import GraphiteCore
import GraphiteApple

/// Moving around what is being read, and what is read next: jumping to a place, skipping a
/// section or a PDF page, "Read from Here" after scrolling away, a listening queue across
/// notes and PDFs, and resuming each one where it was left. The reading session itself stays
/// with `ReadAloudController`; this only steers it.
@MainActor @Observable
final class ReadAloudNavigator {
    struct QueueItem: Identifiable, Equatable {
        let id = UUID()
        let path: VaultPath
        var title: String { path.stem }
    }

    /// Notes and PDFs to read after the current one, in order.
    private(set) var queue: [QueueItem] = []
    /// The item being read from the queue, for "previous item".
    private(set) var history: [VaultPath] = []
    /// Plays the chosen range again when it ends.
    var repeatsPassage = false
    /// Waiting for the person to tap where a range starts, then where it ends.
    private(set) var rangeSelection: RangeSelection = .off

    enum RangeSelection: Equatable {
        case off, awaitingStart, awaitingEnd(start: Int)
    }

    @ObservationIgnored private let reader: ReadAloudController
    @ObservationIgnored private let preferences: UserDefaults
    /// Opens a note or PDF and starts reading it; set by the workspace.
    @ObservationIgnored var startReading: ((VaultPath, _ resumeLocation: Int?) -> Void)?
    /// Where the first visible line of the note being read starts, from the view showing it.
    @ObservationIgnored var visibleLocation: (() -> Int?)?
    /// The first page shown of the PDF being read.
    @ObservationIgnored var visiblePageIndex: (() -> Int?)?
    /// Where the highlighted word is on screen, and the window, so the floating player can
    /// keep out of its way. Nil when the view showing it does not report it.
    var highlightFrameInWindow: CGRect?
    var windowBounds: CGRect?
    /// Where the floating player is, for checking that it keeps clear of the highlight.
    @ObservationIgnored var playerFrameInWindow: CGRect?
    private static let positionsKey = "GraphiteReadAloudPositions"
    private static let maximumRememberedPositions = 300

    init(reader: ReadAloudController, preferences: UserDefaults = .standard) {
        self.reader = reader
        self.preferences = preferences
        observeReading()
        ReadAloudNowPlaying.queueCommands = (
            next: { [weak self] in self?.advance() ?? false },
            previous: { [weak self] in
                guard let self, self.canGoToPreviousItem else { return false }
                self.goToPreviousItem()
                return true
            })
    }

    // MARK: Moving within what is read

    /// Moves reading to the passage at or after a place in the note, and plays from there.
    func read(fromSourceLocation location: Int) {
        resumedFromRememberedPlace = false
        guard let document = reader.session.document else { return }
        let index = document.passages.firstIndex { passage in
            (passage.spans.map { span in NSMaxRange(span.sourceRange) }.max() ?? 0) > location
        } ?? max(0, document.passages.count - 1)
        reader.session.move(to: index)
        reader.session.play()
        reader.followsReading = true
    }

    /// After scrolling away: read from the first line on screen.
    func readFromVisiblePosition() {
        if let pdf = reader.readingPDF, let page = visiblePageIndex?() {
            reader.readPDF(pdf, firstPageIndex: page, lastPageIndex: max(page, reader.readingPDFLastPageIndex ?? page))
        } else if let location = visibleLocation?() {
            read(fromSourceLocation: location)
        }
    }

    func backToReading() { reader.followsReading = true }

    /// The headings of what is read, in reading order, with the passage each starts.
    var sections: [(title: String, passageIndex: Int)] {
        let source = reader.readingSourceText.map { $0 as NSString }
        return (reader.session.document?.passages ?? []).filter { passage in passage.kind == .heading }.map { passage in
            // The heading as written ("The CMOS Inverter"), not as it is said ("see moss").
            let range = passage.spans.map(\.sourceRange).reduce(nil as NSRange?) { union, range in union.map { NSUnionRange($0, range) } ?? range }
            if let source, let range, NSMaxRange(range) <= source.length {
                return (source.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines), passage.id)
            }
            return (passage.text, passage.id)
        }
    }

    /// The heading the current passage belongs to.
    var currentSectionIndex: Int? {
        sections.last { section in section.passageIndex <= reader.session.passageIndex }?.passageIndex
    }

    var canSkipSection: (backward: Bool, forward: Bool) {
        if let pdf = reader.readingPDF, let page = reader.sourcePageIndex {
            return (page > 0, page + 1 < pdf.pageCount)
        }
        let current = reader.session.passageIndex
        return (sections.contains { $0.passageIndex < current } || current > 0, sections.contains { $0.passageIndex > current })
    }

    /// The next section's heading, or the next PDF page.
    func skipSection(forward: Bool) {
        if let pdf = reader.readingPDF, let page = reader.sourcePageIndex {
            let target = forward ? page + 1 : page - 1
            guard target >= 0, target < pdf.pageCount else { return }
            reader.readPDF(pdf, firstPageIndex: target, lastPageIndex: max(target, reader.readingPDFLastPageIndex ?? target))
            return
        }
        let current = reader.session.passageIndex
        let target: Int?
        if forward {
            target = sections.first { $0.passageIndex > current }?.passageIndex
        } else {
            // Back goes to the start of this section, or to the previous one when already there.
            let starts = sections.map(\.passageIndex)
            target = starts.last { $0 < current } ?? (current > 0 ? 0 : nil)
        }
        guard let target else { return }
        let wasSpeaking = reader.session.state == .speaking
        reader.session.move(to: target)
        if wasSpeaking || reader.session.state != .speaking { reader.session.play() }
        reader.followsReading = true
    }

    func jump(toSection passageIndex: Int) {
        reader.session.move(to: passageIndex)
        reader.session.play()
        reader.followsReading = true
    }

    /// Once the passage just chosen is prepared, moves reading to where it was left.
    func resumeWhenPrepared(at location: Int?) {
        guard let location, location > 0 else { return }
        Task { [weak self] in
            for _ in 0..<200 {
                guard let self else { return }
                if !self.reader.isPreparing { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard let self, self.reader.session.document != nil else { return }
            let wasSpeaking = self.reader.session.state == .speaking
            self.read(fromSourceLocation: location)
            if !wasSpeaking { self.reader.session.pause() }
            self.resumedFromRememberedPlace = true
        }
    }

    /// Shown in the player after resuming, with a way to start over.
    var resumedFromRememberedPlace = false

    func startOver() {
        resumedFromRememberedPlace = false
        reader.session.move(to: 0)
        reader.session.play()
        reader.followsReading = true
    }

    // MARK: Reading a range by tapping its ends

    func beginRangeSelection() { rangeSelection = .awaitingStart }
    func cancelRangeSelection() { rangeSelection = .off }

    /// A tap in the note being read: a range end while choosing one, otherwise a jump there.
    /// Returns the range chosen once both ends are tapped.
    func tapped(atSourceLocation location: Int) -> NSRange? {
        switch rangeSelection {
        case .awaitingStart:
            rangeSelection = .awaitingEnd(start: location)
            return nil
        case .awaitingEnd(let start):
            rangeSelection = .off
            let range = NSRange(location: min(start, location), length: abs(location - start))
            return range.length > 0 ? range : nil
        case .off:
            read(fromSourceLocation: location)
            return nil
        }
    }

    // MARK: Queue

    func playNext(_ path: VaultPath) {
        queue.removeAll { item in item.path == path }
        queue.insert(QueueItem(path: path), at: 0)
        if !reader.isActive { advance() }
    }

    func addToQueue(_ path: VaultPath) {
        guard !queue.contains(where: { item in item.path == path }) else { return }
        queue.append(QueueItem(path: path))
        if !reader.isActive { advance() }
    }

    func removeFromQueue(_ item: QueueItem) { queue.removeAll { $0.id == item.id } }

    var canGoToPreviousItem: Bool { !history.isEmpty }

    /// Reads the next queued note or PDF, from where it was left.
    @discardableResult
    func advance() -> Bool {
        guard !queue.isEmpty else { return false }
        let next = queue.removeFirst()
        if let current = reader.sourceIdentifier.map({ identifier in identifier }), let path = try? VaultPath(current) { history.append(path) }
        startReading?(next.path, rememberedLocation(for: next.path.rawValue))
        return true
    }

    /// Back to the note or PDF read before this one; the current one goes back to the queue.
    func goToPreviousItem() {
        guard let previous = history.popLast() else { return }
        if let current = reader.sourceIdentifier, let path = try? VaultPath(current) { queue.insert(QueueItem(path: path), at: 0) }
        startReading?(previous, rememberedLocation(for: previous.rawValue))
    }

    // MARK: Remembered positions

    /// Where reading stopped in a note (a source location) or a PDF (a page index).
    func rememberedLocation(for identifier: String) -> Int? {
        Self.rememberedLocation(for: identifier, preferences: preferences)
    }

    static func rememberedLocation(for identifier: String, preferences: UserDefaults = .standard) -> Int? {
        (preferences.dictionary(forKey: positionsKey) as? [String: Int])?[identifier]
    }

    func forgetLocation(for identifier: String) {
        var positions = preferences.dictionary(forKey: Self.positionsKey) as? [String: Int] ?? [:]
        positions[identifier] = nil
        preferences.set(positions, forKey: Self.positionsKey)
    }

    private func remember(_ location: Int, for identifier: String) {
        var positions = preferences.dictionary(forKey: Self.positionsKey) as? [String: Int] ?? [:]
        positions[identifier] = location
        if positions.count > Self.maximumRememberedPositions, let oldest = positions.keys.sorted().first { positions[oldest] = nil }
        preferences.set(positions, forKey: Self.positionsKey)
    }

    /// Keeps each note's place as passages go by, and moves on to the queue (or repeats the
    /// chosen range) when one finishes.
    private func observeReading() {
        withObservationTracking {
            _ = reader.session.passageIndex
            _ = reader.session.state
            _ = reader.sourcePageIndex
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.readingChanged()
                self?.observeReading()
            }
        }
    }

    private func readingChanged() {
        guard let identifier = reader.sourceIdentifier else { return }
        let session = reader.session
        if reader.readingPDF != nil, let page = reader.sourcePageIndex {
            remember(page, for: identifier)
        } else if session.state == .speaking || session.state == .paused,
                  let location = session.currentPassage?.spans.map(\.sourceRange.location).min() {
            remember(location, for: identifier)
        }
        guard session.state == .finished, !reader.isPreparing else { return }
        if repeatsPassage, session.document != nil {
            session.move(to: 0)
            session.play()
        } else if reader.readingPDF == nil || reader.sourcePageIndex == reader.readingPDFLastPageIndex {
            // Finished: start over next time, and go on with the queue.
            forgetLocation(for: identifier)
            advance()
        }
    }
}

import SwiftUI

/// "Play Next" and "Add to Queue" for a note or PDF, in the file list's and a tab's menus.
struct ReadAloudQueueMenuItems: View {
    let navigator: ReadAloudNavigator
    let path: VaultPath

    var body: some View {
        if ["md", "pdf"].contains((path.name as NSString).pathExtension.lowercased()) {
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { navigator.playNext(path) }
            Button("Add to Listening Queue", systemImage: "text.badge.plus") { navigator.addToQueue(path) }
        }
    }
}
