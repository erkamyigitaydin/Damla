import AppKit

if CommandLine.arguments.contains("--self-test") {
    exit(runSelfTests())
}

let app = NSApplication.shared
if CommandLine.arguments.contains("--diagnose") {
    let monitor = SystemMonitor()
    let battery = SystemMonitor.battery()
    let (volume, muted) = SystemMonitor.audio()
    print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
    print("Screens: \(NSScreen.screens.count); notch inset: \(NSScreen.screens.map { $0.safeAreaInsets.top })")
    print("Battery: \(battery.available ? String(battery.percentage) : "unavailable"); plugged: \(battery.plugged)")
    print("Volume: \(volume.map(String.init(describing:)) ?? "unavailable"); muted: \(muted)")
    print("Brightness: \(monitor.brightnessValue().map(String.init(describing:)) ?? "unavailable")")
    exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
