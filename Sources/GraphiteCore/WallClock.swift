import Foundation

/// The one read of the wall clock for the name of a file made when something happens: a scan
/// that finished, a photo chosen or taken, a Gantt chart drawn with today's line. Logic that
/// decides anything takes `now` and the time zone as parameters (`FR-50`); only the moment an
/// event happens, and the device's time zone then, are read here, once, and handed on.
public enum WallClock {
    public static func currentDate() -> Date { Date.now }

    /// The device's time zone, following the person's setting.
    public static func currentTimeZone() -> TimeZone { .autoupdatingCurrent }
}
