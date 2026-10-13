#if os(iOS)
import UIKit
import Darwin

/// Finger touches delivered through UIKit's own event path, as the screen delivers them, for
/// hosted tests of scrolling and zooming: a drag or a pinch reaches every gesture recognizer
/// of the views under it, PDFKit's scroll view's included. PencilKit draws nothing from
/// them: it reads a touch's coalesced samples, which UIKit gives only to touches from the
/// screen.
///
/// UIKit has no public way to make a touch. This uses the private calls the open-source
/// KIF testing framework uses (a `UITouch` positioned in a window, carrying an IOHIDEvent
/// for its fingers, sent in UIKit's touches event); they are used only by the test bundle,
/// never by the app. When IOKit's event functions cannot be found, `unavailableReason` says
/// so and the tests that need touches are skipped with it rather than failing.
@MainActor
final class SynthesizedTouches {
    /// Why touches cannot be made, or nil when they can.
    static let unavailableReason: String? = HIDEvents.shared == nil ? "IOKit's digitizer event functions were not found" : nil

    private let window: UIWindow
    private var touches: [UITouch] = []

    init(window: UIWindow) {
        self.window = window
    }

    // MARK: Gestures

    /// One finger from `start` to `end` in the window's points, in `steps` moves `stepSeconds`
    /// apart, held still at the end for `holdSeconds` before lifting, so the drag does not
    /// fling the page on.
    func drag(from start: CGPoint, to end: CGPoint, steps: Int = 20, stepSeconds: Double = 0.016, holdSeconds: Double = 0.3) async {
        await move(paths: [(start, end)], steps: steps, stepSeconds: stepSeconds, holdSeconds: holdSeconds)
    }

    /// Two fingers moving from their start points to their end points together: apart for a
    /// pinch out, together for a pinch in.
    func pinch(firstFinger: (start: CGPoint, end: CGPoint), secondFinger: (start: CGPoint, end: CGPoint),
               steps: Int = 24, stepSeconds: Double = 0.016, holdSeconds: Double = 0.3) async {
        await move(paths: [firstFinger, secondFinger], steps: steps, stepSeconds: stepSeconds, holdSeconds: holdSeconds)
    }

    /// Fingers along straight paths, all lifting at the end.
    func move(paths: [(start: CGPoint, end: CGPoint)], steps: Int, stepSeconds: Double, holdSeconds: Double) async {
        begin(at: paths.map(\.start))
        await pause(stepSeconds)
        let stepCount = max(steps, 1)
        for step in 1...stepCount {
            let fraction = CGFloat(step) / CGFloat(stepCount)
            moveTo(paths.map { path in
                CGPoint(x: path.start.x + (path.end.x - path.start.x) * fraction, y: path.start.y + (path.end.y - path.start.y) * fraction)
            })
            await pause(stepSeconds)
        }
        // Still fingers, as when a person stops before lifting.
        let holdSteps = Int((holdSeconds / 0.05).rounded(.up))
        for _ in 0..<holdSteps {
            stay()
            await pause(0.05)
        }
        end()
        await pause(0.05)
    }

    // MARK: Phases

    func begin(at points: [CGPoint]) {
        touches = points.map { point in makeTouch(at: point) }
        send(touches)
    }

    func moveTo(_ points: [CGPoint]) {
        for (touch, point) in zip(touches, points) {
            Private.setLocation(of: touch, to: point, resetPrevious: false)
            Private.setPhase(of: touch, to: .moved)
            Private.setTimestamp(of: touch)
        }
        send(touches)
    }

    /// The fingers held still. Each is reported as moving to where it is, as the screen
    /// reports a finger at rest, so the scroll view's estimate of the finger's speed falls
    /// to nothing and the page does not fling on after the lift.
    func stay() {
        for touch in touches {
            Private.setLocation(of: touch, to: touch.location(in: window), resetPrevious: false)
            Private.setPhase(of: touch, to: .moved)
            Private.setTimestamp(of: touch)
        }
        send(touches)
    }

    func end() {
        for touch in touches {
            Private.setPhase(of: touch, to: .ended)
            Private.setTimestamp(of: touch)
        }
        send(touches)
        touches = []
    }

    // MARK: UIKit

    private func makeTouch(at point: CGPoint) -> UITouch {
        let touch = UITouch()
        let touchedView = window.hitTest(point, with: nil)
        Private.call(touch, "setWindow:", object: window)
        Private.callInteger(touch, "setTapCount:", 1)
        Private.setLocation(of: touch, to: point, resetPrevious: true)
        Private.call(touch, "setView:", object: touchedView)
        Private.setPhase(of: touch, to: .began)
        Private.callBool(touch, "_setIsFirstTouchForView:", true)
        Private.callBool(touch, "setIsTap:", false)
        Private.setTimestamp(of: touch)
        if touch.responds(to: NSSelectorFromString("setGestureView:")) { Private.call(touch, "setGestureView:", object: touchedView) }
        return touch
    }

    private func send(_ touches: [UITouch]) {
        guard let hidEvents = HIDEvents.shared,
              let event = UIApplication.shared.perform(NSSelectorFromString("_touchesEvent"))?.takeUnretainedValue() as? UIEvent else { return }
        let handEvent = hidEvents.handEvent(for: touches, in: window)
        for touch in touches { Private.call(touch, "_setHidEvent:", object: handEvent) }
        _ = event.perform(NSSelectorFromString("_clearTouches"))
        Private.call(event, "_setHIDEvent:", object: handEvent)
        for touch in touches { Private.callObjectBool(event, "_addTouch:forDelayedDelivery:", object: touch, false) }
        UIApplication.shared.sendEvent(event)
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}

/// Calls of private UIKit methods that take plain values, by their Objective-C names.
@MainActor
private enum Private {
    static func call(_ target: NSObject, _ selectorName: String, object: AnyObject?) {
        let selector = NSSelectorFromString(selectorName)
        guard target.responds(to: selector) else { return }
        typealias Function = @convention(c) (NSObject, Selector, AnyObject?) -> Void
        unsafeBitCast(target.method(for: selector), to: Function.self)(target, selector, object)
    }

    static func callBool(_ target: NSObject, _ selectorName: String, _ flag: Bool) {
        let selector = NSSelectorFromString(selectorName)
        guard target.responds(to: selector) else { return }
        typealias Function = @convention(c) (NSObject, Selector, Bool) -> Void
        unsafeBitCast(target.method(for: selector), to: Function.self)(target, selector, flag)
    }

    static func callInteger(_ target: NSObject, _ selectorName: String, _ number: Int) {
        let selector = NSSelectorFromString(selectorName)
        guard target.responds(to: selector) else { return }
        typealias Function = @convention(c) (NSObject, Selector, Int) -> Void
        unsafeBitCast(target.method(for: selector), to: Function.self)(target, selector, number)
    }

    static func callObjectBool(_ target: NSObject, _ selectorName: String, object: AnyObject, _ flag: Bool) {
        let selector = NSSelectorFromString(selectorName)
        guard target.responds(to: selector) else { return }
        typealias Function = @convention(c) (NSObject, Selector, AnyObject, Bool) -> Void
        unsafeBitCast(target.method(for: selector), to: Function.self)(target, selector, object, flag)
    }

    static func setLocation(of touch: UITouch, to point: CGPoint, resetPrevious: Bool) {
        let selector = NSSelectorFromString("_setLocationInWindow:resetPrevious:")
        typealias Function = @convention(c) (NSObject, Selector, CGPoint, Bool) -> Void
        unsafeBitCast(touch.method(for: selector), to: Function.self)(touch, selector, point, resetPrevious)
    }

    static func setPhase(of touch: UITouch, to phase: UITouch.Phase) {
        callInteger(touch, "setPhase:", phase.rawValue)
    }

    static func setTimestamp(of touch: UITouch) {
        let selector = NSSelectorFromString("setTimestamp:")
        typealias Function = @convention(c) (NSObject, Selector, TimeInterval) -> Void
        unsafeBitCast(touch.method(for: selector), to: Function.self)(touch, selector, ProcessInfo.processInfo.systemUptime)
    }
}

/// IOKit's digitizer events, which UIKit reads a touch's fingers from.
private final class HIDEvents: @unchecked Sendable {
    // The functions are looked up once and only read afterwards.
    static let shared = HIDEvents()

    private typealias CreateDigitizerEvent = @convention(c) (CFAllocator?, UInt64, UInt32, UInt32, UInt32, UInt32, UInt32,
                                                             Double, Double, Double, Double, Double, Bool, Bool, UInt32) -> Unmanaged<CFTypeRef>?
    private typealias CreateFingerEvent = @convention(c) (CFAllocator?, UInt64, UInt32, UInt32, UInt32, Double, Double, Double, Double, Double,
                                                          Double, Double, Double, Double, Double, Bool, Bool, UInt32) -> Unmanaged<CFTypeRef>?
    private typealias AppendEvent = @convention(c) (CFTypeRef, CFTypeRef, UInt32) -> Void
    private typealias SetIntegerValue = @convention(c) (CFTypeRef, UInt32, Int, UInt32) -> Void

    private let createDigitizerEvent: CreateDigitizerEvent
    private let createFingerEvent: CreateFingerEvent
    private let appendEvent: AppendEvent
    private let setIntegerValue: SetIntegerValue

    private static let handTransducer: UInt32 = 3
    private static let rangeAndTouchMask: UInt32 = 0b011
    private static let positionMask: UInt32 = 0b100
    /// The digitizer's "is display integrated" field: event type 11, field 25.
    private static let displayIntegratedField: UInt32 = (11 << 16) | 25
    private static let displayIntegratedOptions: UInt32 = 0xF000_0000

    private init?() {
        _ = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
        let handle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let createDigitizer = dlsym(handle, "IOHIDEventCreateDigitizerEvent"),
              let createFinger = dlsym(handle, "IOHIDEventCreateDigitizerFingerEventWithQuality"),
              let append = dlsym(handle, "IOHIDEventAppendEvent"),
              let setInteger = dlsym(handle, "IOHIDEventSetIntegerValueWithOptions") else { return nil }
        createDigitizerEvent = unsafeBitCast(createDigitizer, to: CreateDigitizerEvent.self)
        createFingerEvent = unsafeBitCast(createFinger, to: CreateFingerEvent.self)
        appendEvent = unsafeBitCast(append, to: AppendEvent.self)
        setIntegerValue = unsafeBitCast(setInteger, to: SetIntegerValue.self)
    }

    /// A hand event with one finger for each touch, at its place in the window.
    @MainActor
    func handEvent(for touches: [UITouch], in window: UIWindow) -> AnyObject {
        let time = mach_absolute_time()
        let hand = createDigitizerEvent(kCFAllocatorDefault, time, Self.handTransducer, 0, 0, Self.rangeAndTouchMask, 0,
                                        0, 0, 0, 0, 0, true, true, 0)!.takeRetainedValue()
        setIntegerValue(hand, Self.displayIntegratedField, 1, Self.displayIntegratedOptions)
        for (index, touch) in touches.enumerated() {
            let location = touch.location(in: window)
            let isTouching = touch.phase != .ended && touch.phase != .cancelled
            let mask = touch.phase == .moved ? Self.positionMask : Self.rangeAndTouchMask
            let finger = createFingerEvent(kCFAllocatorDefault, time, UInt32(index + 1), 2, mask, Double(location.x), Double(location.y), 0,
                                           0, 0, 5, 5, 1, 1, 1, isTouching, isTouching, 0)!.takeRetainedValue()
            setIntegerValue(finger, Self.displayIntegratedField, 1, Self.displayIntegratedOptions)
            appendEvent(hand, finger, 0)
        }
        return hand as AnyObject
    }
}
#endif
