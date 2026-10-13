import GraphiteApple

/// Starts keeping evidence of freezes for the developer: the system's hang and crash reports
/// and Graphite's own main-thread watchdog (`DiagnosticRecords`). Called once as the app starts.
public enum GraphiteDiagnostics {
    @MainActor public static func start() {
        MetricKitDiagnostics.shared.start()
        MainThreadWatchdog.shared.start()
        DiagnosticContext.note("Graphite started")
    }
}
