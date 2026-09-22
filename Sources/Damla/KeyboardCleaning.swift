import AppKit
import ApplicationServices
import Combine

/// Uses monotonic time, so clock changes cannot extend a cleaning session.
struct CleaningSession {
    private(set) var deadline: TimeInterval?
    private(set) var escapeSince: TimeInterval?
    mutating func start(at time: TimeInterval, duration: TimeInterval = 60) {
        deadline = time + min(60, max(1, duration)); escapeSince = nil
    }
    mutating func stop() { deadline = nil; escapeSince = nil }
    mutating func escape(down: Bool, at time: TimeInterval) {
        if down { if escapeSince == nil { escapeSince = time } }
        else { escapeSince = nil }
    }
    func remaining(at time: TimeInterval) -> Int { Int(ceil(max(0, (deadline ?? time) - time))) }
    func shouldUnlock(at time: TimeInterval) -> Bool {
        guard let deadline else { return true }
        return time >= deadline || escapeSince.map { time - $0 >= 2 } == true
    }
}

/// A short, explicitly activated keyboard lock. Mouse events are never intercepted.
/// The tap fails open on timeout, sleep, session lock, permission loss or process exit.
final class KeyboardCleaning: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var remaining = 0
    var onEnd: (() -> Void)?
    private var session = CleaningSession()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private let clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    init() {
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.stop() })
        }
    }

    func start() -> Bool {
        guard !active else { return true }
        guard AXIsProcessTrusted() else { return false }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, CGEventType(rawValue: 14)!]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            return Unmanaged<KeyboardCleaning>.fromOpaque(info).takeUnretainedValue().handle(type, event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else { return false }
        self.tap = tap; self.source = source
        session.start(at: clock()); remaining = 60
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        active = true
        CGEvent.tapEnable(tap: tap, enable: true)
        timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.session.shouldUnlock(at: self.clock()) || !AXIsProcessTrusted() { self.stop(); return }
            let seconds = self.session.remaining(at: self.clock())
            if self.remaining != seconds { self.remaining = seconds }
        }
        RunLoop.main.add(timer!, forMode: .common)
        return true
    }

    func stop() {
        let wasActive = active
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
        timer?.invalidate(); timer = nil
        session.stop(); active = false; remaining = 0
        if wasActive { onEnd?() }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            stop(); return Unmanaged.passUnretained(event)
        }
        guard active else { return Unmanaged.passUnretained(event) }
        if session.shouldUnlock(at: clock()) { stop(); return Unmanaged.passUnretained(event) }
        if type.rawValue == 14 {
            // System-defined: hold back media keys (subtype 8) only; extra mouse buttons (subtype 7) pass through.
            guard let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else { return Unmanaged.passUnretained(event) }
            return nil
        }
        if (type == .keyDown || type == .keyUp), event.getIntegerValueField(.keyboardEventKeycode) == 53 {
            session.escape(down: type == .keyDown, at: clock())
        }
        // Never persist, forward or inspect the typed characters.
        return nil
    }

    deinit {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        timer?.invalidate()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}
