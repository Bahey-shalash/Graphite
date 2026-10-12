import Foundation
import Darwin

/// The app's memory as the system counts it for termination, and how much more it may use.
public enum ProcessResources {
    /// The physical footprint the system compares with the app's memory limit.
    public static func footprintBytes() -> UInt64 {
        var information = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &information) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), reboundPointer, &count)
            }
        }
        return status == KERN_SUCCESS ? information.phys_footprint : 0
    }

    /// Bytes the app can still allocate before iOS ends it; nil on the Mac, which has no such limit.
    public static func availableBytesBeforeTermination() -> UInt64? {
        #if os(iOS)
        return UInt64(os_proc_available_memory())
        #else
        return nil
        #endif
    }

    public static var physicalMemoryBytes: UInt64 { ProcessInfo.processInfo.physicalMemory }

    public static var thermalStateName: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}

/// Samples the footprint on a timer and keeps the highest value, because a model's peak lasts
/// only milliseconds inside a render and a single reading afterwards misses it.
public final class PeakFootprintSampler: @unchecked Sendable {
    // `@unchecked Sendable`: `peakBytes` is read and written only while holding `lock`, and the
    // timer source is created and cancelled once.
    private let lock = NSLock()
    private var peakBytes: UInt64 = 0
    private let timer: DispatchSourceTimer

    public init(intervalMilliseconds: Int = 25) {
        timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "graphite.footprint-sampler", qos: .utility))
        timer.schedule(deadline: .now(), repeating: .milliseconds(intervalMilliseconds))
        timer.setEventHandler { [weak self] in self?.record(ProcessResources.footprintBytes()) }
        timer.resume()
    }

    deinit { timer.cancel() }

    private func record(_ bytes: UInt64) {
        lock.lock(); defer { lock.unlock() }
        peakBytes = max(peakBytes, bytes)
    }

    /// The highest footprint since the last reset, then starts a new measurement.
    public func takePeakBytes() -> UInt64 {
        record(ProcessResources.footprintBytes())
        lock.lock(); defer { lock.unlock() }
        let peak = peakBytes
        peakBytes = 0
        return peak
    }
}
