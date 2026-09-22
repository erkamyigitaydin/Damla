import AppKit
import ApplicationServices
import Combine

/// Intercepts the volume, mute and brightness keys before macOS handles them. The system never
/// sees the key, so it never shows its own bezel; Damla applies the change and shows the notch HUD.
/// Needs the Accessibility permission (an event tap that can swallow key events).
final class MediaKeyInterceptor: ObservableObject {
    enum Key: Int { case volumeUp = 0, volumeDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7 }
    private static let systemDefined = CGEventType(rawValue: 14)! // NX_SYSDEFINED
    private static let auxControlSubtype = 8                        // NX_SUBTYPE_AUX_CONTROL_BUTTONS

    @Published private(set) var active = false
    let monitor: SystemMonitor
    var onDenied: (() -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retry: Timer?
    private var deniedShown = false

    init(monitor: SystemMonitor) { self.monitor = monitor }

    static var trusted: Bool { AXIsProcessTrusted() }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// `prompt` shows the system's "allow accessibility access" dialog when the permission is missing.
    func start(prompt: Bool) {
        guard tap == nil else { return }
        if !AXIsProcessTrusted() {
            if prompt {
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
                if !deniedShown { deniedShown = true; onDenied?() }
            }
            scheduleRetry()
            return
        }
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            return Unmanaged<MediaKeyInterceptor>.fromOpaque(info).takeUnretainedValue().handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(1 << Self.systemDefined.rawValue),
                                          callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            if !deniedShown { deniedShown = true; onDenied?() }
            scheduleRetry()
            return
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        retry?.invalidate(); retry = nil
        active = true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
        retry?.invalidate(); retry = nil
        deniedShown = false
        active = false
    }

    /// The permission can be granted in System Settings while the app is running; pick it up when it lands.
    private func scheduleRetry() {
        retry?.invalidate()
        retry = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, self.tap == nil else { return }
            if AXIsProcessTrusted() { self.start(prompt: false) }
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == Self.systemDefined, let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == Self.auxControlSubtype else { return Unmanaged.passUnretained(event) }
        let data = nsEvent.data1
        let keyCode = (data & 0xFFFF_0000) >> 16
        let keyFlags = data & 0xFFFF
        let isDown = ((keyFlags & 0xFF00) >> 8) == 0x0A
        guard let key = Key(rawValue: keyCode) else { return Unmanaged.passUnretained(event) }
        if (key == .brightnessUp || key == .brightnessDown) && !monitor.canSetBrightness {
            return Unmanaged.passUnretained(event) // let macOS handle displays we cannot drive
        }
        if isDown {
            let flags = nsEvent.modifierFlags
            let fine = flags.contains(.shift) && flags.contains(.option)
            let step: Float = fine ? 1 / 64 : 1 / 16
            let feedback = flags.contains(.shift) || Self.volumeFeedbackEnabled
            switch key {
            case .volumeUp: monitor.adjustVolume(by: step, feedback: feedback)
            case .volumeDown: monitor.adjustVolume(by: -step, feedback: feedback)
            case .mute: monitor.toggleMute()
            case .brightnessUp: monitor.adjustBrightness(by: step)
            case .brightnessDown: monitor.adjustBrightness(by: -step)
            }
        }
        return nil // swallow key-down and key-up alike so the system bezel never appears
    }

    /// Mirrors System Settings → Sound → "Play feedback when volume is changed".
    private static var volumeFeedbackEnabled: Bool {
        (CFPreferencesCopyAppValue("com.apple.sound.beep.feedback" as CFString, kCFPreferencesAnyApplication) as? Int) == 1
    }
}
