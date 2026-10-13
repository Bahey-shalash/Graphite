import Foundation
import os
#if canImport(MetricKit)
import MetricKit
#endif
#if canImport(Darwin)
import Darwin
import MachO
#endif

/// Saves the system's hang and crash diagnostics in `DiagnosticRecords.folder`. iOS delivers
/// them on a later launch, at most once a day, each as one payload; every payload becomes
/// one JSON file, named after the period it covers, so a payload delivered again is kept once.
public final class MetricKitDiagnostics: NSObject, @unchecked Sendable {
    // Unchecked: no stored state; MetricKit calls in on a queue of its own.
    public static let shared = MetricKitDiagnostics()

    /// Subscribes, and keeps the payloads iOS delivered before Graphite subscribed.
    public func start() {
        #if canImport(MetricKit) && !os(macOS)
        let manager = MXMetricManager.shared
        manager.add(self)
        save(manager.pastDiagnosticPayloads)
        #endif
    }

    #if canImport(MetricKit) && !os(macOS)
    private func save(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let period = DiagnosticRecords.fileTimestamp(payload.timeStampBegin) + "_" + DiagnosticRecords.fileTimestamp(payload.timeStampEnd)
            DiagnosticRecords.write(payload.jsonRepresentation(), named: "MetricKit-\(period).json")
        }
    }
    #endif
}

#if canImport(MetricKit) && !os(macOS)
extension MetricKitDiagnostics: MXMetricManagerSubscriber {
    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        save(payloads)
    }
}
#endif

/// Notices, from a thread of its own, when the main thread has not answered for more than
/// `stallThresholdSeconds`, and writes a record: when it began, what Graphite was showing and
/// doing (`DiagnosticContext`), and where the main thread was, as return addresses and the
/// images they are in, which `atos` turns into names with the build's dSYM. A second record
/// says how long it lasted once the main thread answers again. A process killed while
/// frozen keeps the first.
///
/// Its cost is one block on the main queue every `pingIntervalSeconds`. It does not run under
/// a debugger, where a breakpoint stops the main thread on purpose.
public final class MainThreadWatchdog: @unchecked Sendable {
    // Unchecked: every mutable value is in `state`, behind its lock; the main thread's port
    // and stack bounds are set once in `start` before the timer that reads them exists.
    public static let shared = MainThreadWatchdog()

    public static let stallThresholdSeconds: Double = 2
    public static let pingIntervalSeconds: Double = 0.5
    /// Return addresses kept from the main thread's stack.
    static let maximumFrameCount = 96

    private struct State {
        var isRunning = false
        /// When the ping waiting for the main thread was sent, on the uptime clock.
        var pingSentAt: Double?
        /// When the stall being reported began; nil while the main thread answers.
        var reportedStallSentAt: Double?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let queue = DispatchQueue(label: "com.graphite.study.main-thread-watchdog", qos: .utility)
    private var timer: DispatchSourceTimer?
    #if canImport(Darwin)
    private var mainThreadPort: thread_act_t = 0
    private var mainStackLowestAddress: UInt = 0
    private var mainStackHighestAddress: UInt = 0
    /// Filled while the main thread is suspended, when nothing may be allocated.
    private let frameBuffer = UnsafeMutablePointer<UInt>.allocate(capacity: MainThreadWatchdog.maximumFrameCount)
    #endif

    /// Starts watching. Call on the main thread.
    public func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !Self.isDebuggerAttached else { return }
        let shouldStart = state.withLock { state in
            guard !state.isRunning else { return false }
            state.isRunning = true
            return true
        }
        guard shouldStart else { return }
        #if canImport(Darwin)
        mainThreadPort = mach_thread_self()
        let mainThread = pthread_self()
        mainStackHighestAddress = UInt(bitPattern: pthread_get_stackaddr_np(mainThread))
        mainStackLowestAddress = mainStackHighestAddress - UInt(pthread_get_stacksize_np(mainThread))
        #endif
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.pingIntervalSeconds, repeating: Self.pingIntervalSeconds, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.check() }
        self.timer = timer
        timer.resume()
    }

    private func check() {
        let now = ProcessInfo.processInfo.systemUptime
        enum Action { case ping, reportStall(sentAt: Double), none }
        let action: Action = state.withLock { state in
            guard let sentAt = state.pingSentAt else {
                state.pingSentAt = now
                return .ping
            }
            guard now - sentAt > Self.stallThresholdSeconds, state.reportedStallSentAt == nil else { return .none }
            state.reportedStallSentAt = sentAt
            return .reportStall(sentAt: sentAt)
        }
        switch action {
        case .ping:
            DispatchQueue.main.async { [weak self] in self?.mainThreadAnswered() }
        case .reportStall(let sentAt):
            reportStall(sentAt: sentAt, now: now)
        case .none:
            break
        }
    }

    private func mainThreadAnswered() {
        let now = ProcessInfo.processInfo.systemUptime
        let endedStallSentAt: Double? = state.withLock { state in
            let reported = state.reportedStallSentAt
            state.pingSentAt = nil
            state.reportedStallSentAt = nil
            return reported
        }
        guard let endedStallSentAt else { return }
        let seconds = now - endedStallSentAt
        DiagnosticContext.note(String(format: "The main thread answered again after %.1f s", seconds))
        DiagnosticRecords.write(kind: "MainThreadStallEnded", fields: ["stallSeconds": seconds])
    }

    private func reportStall(sentAt: Double, now: Double) {
        var fields: [String: Any] = [
            "unansweredSeconds": now - sentAt,
            "note": "The main thread had not answered for this long; MainThreadStallEnded follows if it answered again."
        ]
        let frames = mainThreadReturnAddresses()
        if !frames.isEmpty {
            fields["mainThreadFrames"] = frames.map(Self.describe)
            fields["images"] = Self.imagesDescription(of: frames)
        }
        DiagnosticRecords.write(kind: "MainThreadStall", fields: fields)
    }

    // MARK: The main thread's stack

    /// The main thread's program counter, link register and the return addresses of its
    /// frame records, read while it is suspended. Empty where this cannot be done.
    private func mainThreadReturnAddresses() -> [UInt] {
        #if canImport(Darwin) && arch(arm64)
        guard mainThreadPort != 0, thread_suspend(mainThreadPort) == KERN_SUCCESS else { return [] }
        // Nothing between suspending and resuming may allocate or take a lock the main
        // thread could hold: the frames go into a buffer allocated beforehand.
        var count = 0
        var threadState = arm_thread_state64_t()
        var stateCount = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &threadState) { statePointer in
            statePointer.withMemoryRebound(to: natural_t.self, capacity: Int(stateCount)) { rawState in
                thread_get_state(mainThreadPort, ARM_THREAD_STATE64, rawState, &stateCount)
            }
        }
        if result == KERN_SUCCESS {
            frameBuffer[count] = Self.strippedCodeAddress(UInt(threadState.__pc)); count += 1
            frameBuffer[count] = Self.strippedCodeAddress(UInt(threadState.__lr)); count += 1
            var framePointer = UInt(threadState.__fp)
            while count < Self.maximumFrameCount, framePointer % 8 == 0,
                  framePointer >= mainStackLowestAddress, framePointer + 16 <= mainStackHighestAddress,
                  let record = UnsafePointer<UInt>(bitPattern: framePointer) {
                let returnAddress = Self.strippedCodeAddress(record[1])
                guard returnAddress != 0 else { break }
                frameBuffer[count] = returnAddress; count += 1
                let callerFramePointer = record[0]
                // Frames go up the stack: a caller's record is above its callee's.
                guard callerFramePointer > framePointer else { break }
                framePointer = callerFramePointer
            }
        }
        thread_resume(mainThreadPort)
        return Array(UnsafeBufferPointer(start: frameBuffer, count: count))
        #else
        return []
        #endif
    }

    /// Return addresses saved by system code can carry a pointer authentication code above
    /// the address bits; code in this process sits well below 2^39.
    private static func strippedCodeAddress(_ address: UInt) -> UInt {
        address & 0x0000_007F_FFFF_FFFF
    }

    /// `image + offset (symbol)` for an address, with the nearest exported symbol, which for
    /// Graphite's own code is often far off: symbolicate with `atos` and the `images` list.
    private static func describe(_ address: UInt) -> String {
        var information = Dl_info()
        guard dladdr(UnsafeRawPointer(bitPattern: address), &information) != 0, let imagePath = information.dli_fname else {
            return String(format: "0x%lx", address)
        }
        let imageName = (String(cString: imagePath) as NSString).lastPathComponent
        let offset = address - UInt(bitPattern: information.dli_fbase)
        let symbol = information.dli_sname.map { String(cString: $0) } ?? "?"
        return String(format: "0x%lx %@ + 0x%lx (%@)", address, imageName, offset, symbol)
    }

    /// The images the addresses are in: their load address and UUID, for `atos -l`.
    private static func imagesDescription(of addresses: [UInt]) -> [[String: String]] {
        var seenBases = Set<UInt>()
        var images: [[String: String]] = []
        for address in addresses {
            var information = Dl_info()
            guard dladdr(UnsafeRawPointer(bitPattern: address), &information) != 0, let base = information.dli_fbase,
                  let imagePath = information.dli_fname, seenBases.insert(UInt(bitPattern: base)).inserted else { continue }
            images.append(["name": (String(cString: imagePath) as NSString).lastPathComponent,
                           "loadAddress": String(format: "0x%lx", UInt(bitPattern: base)),
                           "uuid": imageUUID(at: base) ?? "?"])
        }
        return images
    }

    private static func imageUUID(at base: UnsafeMutableRawPointer) -> String? {
        let header = base.assumingMemoryBound(to: mach_header_64.self)
        guard header.pointee.magic == MH_MAGIC_64 else { return nil }
        var command = UnsafeRawPointer(base).advanced(by: MemoryLayout<mach_header_64>.size)
        for _ in 0..<header.pointee.ncmds {
            let loadCommand = command.assumingMemoryBound(to: load_command.self).pointee
            if loadCommand.cmd == LC_UUID {
                let uuid = command.assumingMemoryBound(to: uuid_command.self).pointee.uuid
                return UUID(uuid: uuid).uuidString
            }
            command = command.advanced(by: Int(loadCommand.cmdsize))
        }
        return nil
    }

    /// Whether a debugger is attached, which stops the main thread at breakpoints.
    public static var isDebuggerAttached: Bool {
        var information = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, u_int(name.count), &information, &size, nil, 0) == 0 else { return false }
        return (information.kp_proc.p_flag & P_TRACED) != 0
    }
}
