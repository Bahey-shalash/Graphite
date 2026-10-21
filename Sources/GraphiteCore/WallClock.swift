import Foundation

/// The one read of the wall clock for the name of a file made when something happens: a scan
/// that finished, a photo chosen or taken. Logic that decides anything takes `now` as a
/// parameter (`FR-50`); only the moment an event happens is read here, once, and handed on.
public enum WallClock {
    public static func currentDate() -> Date { Date.now }
}
