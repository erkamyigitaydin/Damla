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

if let index = CommandLine.arguments.firstIndex(of: "--agent-status") {
    // Claude Code's status line: records context and rate-limit use, then prints a short line. When the user
    // had a status line of their own, it runs after `--then` with the same input and its output is printed instead.
    var data = Data()
    while let chunk = try? FileHandle.standardInput.read(upToCount: 65_536), !chunk.isEmpty {
        data.append(chunk)
        if data.count > 2 * 1024 * 1024 { exit(0) }
    }
    let arguments = CommandLine.arguments
    let provider = arguments.indices.contains(index + 1) ? AgentProvider(rawValue: arguments[index + 1]) ?? .claude : .claude
    let line = AgentEventStore.receiveStatus(provider: provider, input: data)
    if let then = arguments.firstIndex(of: "--then"), arguments.indices.contains(then + 1) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", arguments[then + 1]]
        let input = Pipe()
        task.standardInput = input
        if (try? task.run()) != nil {
            input.fileHandleForWriting.write(data)
            try? input.fileHandleForWriting.close()
            task.waitUntilExit()
            exit(task.terminationStatus)
        }
    }
    print(line)
    exit(0)
}

if let index = CommandLine.arguments.firstIndex(where: { $0 == "--agent-approval" || $0 == "--agent-question" }) {
    // Installed only on request (the tour, Settings → Agents, or install-agent-hooks.py --approvals). Prints a
    // decision only when the user made one in Damla; otherwise nothing, and the agent shows its own prompt.
    // --agent-question is the PreToolUse hook for Claude Code's multiple-choice questions.
    if CommandLine.arguments.indices.contains(index + 1),
       let provider = AgentProvider(rawValue: CommandLine.arguments[index + 1]) {
        var data = Data()
        while let chunk = try? FileHandle.standardInput.read(upToCount: 65_536), !chunk.isEmpty {
            data.append(chunk)
            if data.count > 2 * 1024 * 1024 { exit(0) }
        }
        if let decision = AgentApprovals.handle(provider: provider, input: data, host: ProcessAncestry.hostBundleID()) {
            FileHandle.standardOutput.write(AgentApprovals.output(decision, input: data, provider: provider))
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
