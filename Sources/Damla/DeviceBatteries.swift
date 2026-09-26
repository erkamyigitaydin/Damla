import CoreAudio
import Foundation

/// Warns in the notch when a Bluetooth device (mouse, keyboard, trackpad, AirPods…) runs low: once at 10 %,
/// once more at 5 %, and again only after it was charged above 20 %. system_profiler takes about a second, so
/// it runs every ten minutes at utility priority.
final class DeviceBatteryWatcher {
    static let interval: TimeInterval = 600
    static let thresholds = [10, 5]
    static let rearmAbove = 20

    /// Device name, SF Symbol, the lowest level.
    var onLow: ((String, String, Int) -> Void)?
    private var timer: Timer?
    private var warned: [String: Int] = [:]   // device name → lowest threshold already announced

    func start() {
        timer?.invalidate()
        check()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in self?.check() }
        timer?.tolerance = 60
    }
    func stop() { timer?.invalidate(); timer = nil }

    private func check() {
        BluetoothBattery.read { [weak self] devices in self?.evaluate(devices) }
    }

    /// Separate from reading so the self-test can drive it.
    func evaluate(_ devices: [String: BluetoothBattery.Levels]) {
        for (name, levels) in devices {
            guard let lowest = levels.lowest else { continue }
            if lowest > Self.rearmAbove { warned[name] = nil; continue }
            guard let threshold = Self.thresholds.last(where: { lowest <= $0 }),
                  threshold < (warned[name] ?? Int.max) else { continue }
            warned[name] = threshold
            onLow?(name, Self.icon(for: levels, name: name), lowest)
        }
    }

    static func icon(for levels: BluetoothBattery.Levels, name: String) -> String {
        switch levels.kind?.lowercased() ?? "" {
        case let kind where kind.contains("mouse"): return "magicmouse"
        case let kind where kind.contains("trackpad"): return "rectangle.and.hand.point.up.left"
        case let kind where kind.contains("keyboard"): return "keyboard"
        case let kind where kind.contains("gamepad") || kind.contains("game"): return "gamecontroller"
        default: return AudioOutput.icon(name: name, transport: kAudioDeviceTransportTypeBluetooth)
        }
    }
}
