import AppKit

if let index = CommandLine.arguments.firstIndex(of: "--agent-event") {
    // No AppKit session is started by hooks, and stdout never alters an agent's decisions.
    if CommandLine.arguments.indices.contains(index + 1),
       let provider = AgentProvider(rawValue: CommandLine.arguments[index + 1]) {
        var data = Data()
        while let chunk = try? FileHandle.standardInput.read(upToCount: 65_536), !chunk.isEmpty {
            data.append(chunk)
            if data.count > 2 * 1024 * 1024 { exit(0) }
        }
        try? AgentEventStore.receive(provider: provider, input: data)
    }
    exit(0)
}

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
