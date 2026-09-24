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
        try? AgentEventStore.receive(provider: provider, input: data, host: ProcessAncestry.hostBundleID())
    }
    exit(0)
}

if let index = CommandLine.arguments.firstIndex(of: "--agent-approval") {
    // Installed only on request (install-agent-hooks.py --approvals). Prints a decision only when the user
    // made one in Damla; otherwise nothing, and Claude Code shows its own prompt.
    if CommandLine.arguments.indices.contains(index + 1),
       let provider = AgentProvider(rawValue: CommandLine.arguments[index + 1]) {
        var data = Data()
        while let chunk = try? FileHandle.standardInput.read(upToCount: 65_536), !chunk.isEmpty {
            data.append(chunk)
            if data.count > 2 * 1024 * 1024 { exit(0) }
        }
        if let decision = AgentApprovals.handle(provider: provider, input: data, host: ProcessAncestry.hostBundleID()) {
            FileHandle.standardOutput.write(AgentApprovals.output(decision))
        }
    }
    exit(0)
}

if CommandLine.arguments.contains("--self-test") {
    // The checks compare Turkish texts; run them in Turkish whatever the Mac's language is.
    UserDefaults.standard.setVolatileDomain(["AppleLanguages": ["tr"]], forName: UserDefaults.argumentDomain)
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
    let current = AudioOutputs.defaultID()
    for output in AudioOutputs.list() {
        print("Output: \(output.id == current ? "*" : " ") \(output.name) [\(output.icon)] transport=\(String(format: "%08x", output.transport))")
    }
    exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
