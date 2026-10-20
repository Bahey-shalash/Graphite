import Foundation

/// The recordings of `Recordings/library.plist`, an XML property list keyed by recording identifier.
enum NotabilityRecordingsLibrary {
    private static let recordingsFolder = "Recordings"

    /// The recordings, and the file paths the library names that are not safe paths inside the note (left unused).
    static func recordings(fromLibraryBytes libraryBytes: ArraySlice<UInt8>,
                           limits: NotebookImportLimits) throws(NotabilityReadingError) -> (recordings: [NotabilityRecording], invalidPaths: [String]) {
        let library: PropertyListValue
        do throws(PropertyListDocumentError) {
            library = try PropertyListDocument.plainValue(of: libraryBytes, maximumNestingDepth: limits.maximumPropertyListNestingDepth,
                                                                 maximumValueCount: limits.maximumPlainValueCount)
        } catch {
            throw .recordingsLibrary(error)
        }
        guard let libraryDictionary = library.dictionary else { throw .recordingsLibraryLayoutNotRecognised }
        let recordingsByKey: PropertyListDictionary
        switch libraryDictionary["recordings"] {
        case nil, .null?: recordingsByKey = PropertyListDictionary()
        case .dictionary(let dictionary)?: recordingsByKey = dictionary
        case .boolean?, .integer?, .real?, .date?, .data?, .string?, .uid?, .array?: throw .recordingsLibraryLayoutNotRecognised
        }
        // Sorted by key as text, code point by code point, as the reference reader sorts them.
        let sortedKeys = recordingsByKey.keys.sorted { leftKey, rightKey in
            leftKey.unicodeScalars.lexicographicallyPrecedes(rightKey.unicodeScalars) { leftScalar, rightScalar in
                leftScalar.value < rightScalar.value
            }
        }
        var recordings: [NotabilityRecording] = []
        var invalidPaths: [String] = []
        for key in sortedKeys {
            guard let recording = recordingsByKey[key]?.dictionary else { throw .recordingsLibraryLayoutNotRecognised }
            let identifier: Int? = if case .integer(let identifier)? = recording["identifier"] { Int(identifier) } else { nil }
            var file: NotebookArchivePath?
            if let filePath = recording["filepath"]?.string {
                file = NotebookArchivePath(validating: recordingsFolder + "/" + filePath)
                if file == nil { invalidPaths.append(recordingsFolder + "/" + filePath) }
            }
            recordings.append(NotabilityRecording(identifier: identifier, file: file, durationSeconds: recording["duration"]?.number,
                                                  name: recording["name"]?.string))
        }
        return (recordings, invalidPaths)
    }
}

/// The stroke timing of `contentPlaybackEventManager`: parallel packed arrays of one entry per timed curve.
extension NotabilitySessionReading {
    mutating func readPlaybackEvents(in eventManager: KeyedArchiveFields, ink: NotabilityInk) throws(NotabilityReadingError) -> [NotabilityPlaybackEvent] {
        let eventCount = try NotabilityReadingError.readingSession { () throws(KeyedArchiveError) -> Int64 in
            try archive.nonNullValue(named: "NBCPTimeManagerSOANumEventsKey", in: eventManager).map(archive.integer) ?? 0
        }
        guard eventCount >= 0 else { throw .countNegative(key: "NBCPTimeManagerSOANumEventsKey", count: eventCount) }
        let uuids = try eventValues(.eventCurveUUIDs, eventCount: eventCount, in: eventManager)
        let timestamps = try eventValues(.eventTimestamps, eventCount: eventCount, in: eventManager)
        let recordingIdentifiers = try eventValues(.eventRecordingIdentifiers, eventCount: eventCount, in: eventManager)
        let durations = try eventValues(.eventDurations, eventCount: eventCount, in: eventManager)
        guard eventCount > 0 else { return [] }
        let curveIndicesByUUID = ink.curveIndicesByUUID()
        return (0..<Int(eventCount)).map { eventIndex in
            let curveUUID = uuids.uuid(at: eventIndex)
            let curveIndex = curveIndicesByUUID[curveUUID]
            if curveIndex == nil { issues.report(.playbackEventWithoutCurve(curveUUID: curveUUID)) }
            return NotabilityPlaybackEvent(curveIndex: curveIndex, curveUUID: curveUUID,
                                           recordingIdentifier: Int(recordingIdentifiers.uint32(at: eventIndex)),
                                           secondsFromRecordingStart: timestamps.float(at: eventIndex), durationSeconds: durations.float(at: eventIndex))
        }
    }

    /// An event array, empty when absent, checked to hold one entry per event.
    private func eventValues(_ array: NotabilityPackedArray, eventCount: Int64,
                             in eventManager: KeyedArchiveFields) throws(NotabilityReadingError) -> PackedLittleEndianValues {
        guard try NotabilityReadingError.readingSession({ () throws(KeyedArchiveError) in
            try archive.nonNullValue(named: array.rawValue, in: eventManager)
        }) != nil else {
            guard eventCount == 0 else { throw .packedArrayLengthWrong(array, byteCount: 0, expectedValueCount: eventCount) }
            return .empty
        }
        return try NotabilityInk.packedValues(array, entryCount: eventCount, in: eventManager, archive: archive)
    }
}
