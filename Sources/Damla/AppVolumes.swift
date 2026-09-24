import AppKit
import Accelerate
import CoreAudio

/// An app that plays sound through its own processes (Chrome through its helpers, Safari through WebKit's).
struct AudioApp: Identifiable, Equatable {
    let id: String              // bundle id of the owning app
    let name: String
    var processes: [AudioObjectID]
    var playing: Bool           // some process is producing output right now
}

/// Per-app volume for apps without their own volume control. macOS has no per-app volume, so an app turned
/// below 100 % is captured with a Core Audio process tap (its own output muted while tapped) and played again,
/// scaled, through a private aggregate device on the current output. Apps at 100 % are never touched. Taps and
/// aggregates are private to Damla: if Damla quits or crashes, macOS removes them and the app sounds as before.
final class AppVolumeController: ObservableObject {
    @Published private(set) var apps: [AudioApp] = []
    @Published private(set) var levels: [String: Double]    // 0–100; a missing app is at 100
    /// macOS refused the "System Audio Recording" permission a tap needs.
    @Published private(set) var permissionDenied = false
    private var taps: [String: ProcessTap] = [:]
    private var processListener: AudioObjectPropertyListenerBlock?
    private var timer: Timer?
    private var traceTimer: Timer?
    private static let excluded: Set<String> = Set(MusicSource.allCases.map(\.bundleID))   // own volume, see MediaService

    init() {
        levels = (UserDefaults.standard.dictionary(forKey: "appVolumes") as? [String: Double]) ?? [:]
    }

    func start() {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.refresh() }
        processListener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        refresh()
    }

    /// While the mixer is open, apps starting and stopping sound show up within two seconds.
    func setWatching(_ watching: Bool) {
        timer?.invalidate(); timer = nil
        guard watching else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func level(_ id: String) -> Double { levels[id] ?? 100 }

    func setLevel(_ id: String, _ value: Double) {
        let level = min(100, max(0, value.rounded()))
        levels[id] = level >= 100 ? nil : level
        UserDefaults.standard.set(levels, forKey: "appVolumes")
        apply(id)
    }

    /// Rebuilds every tap on the new default output (AirPods connected, speakers picked…).
    func outputChanged() {
        for tap in taps.values { tap.invalidate() }
        taps.removeAll()
        for app in apps { apply(app.id) }
    }

    func stopAll() {
        for tap in taps.values { tap.invalidate() }
        taps.removeAll()
    }

    func refresh() {
        let found = Self.audioApps().filter { !Self.excluded.contains($0.id) && $0.id != Bundle.main.bundleIdentifier }
        if found != apps { apps = found }
        for app in found { apply(app.id) }
        // An app that quit takes its tap with it.
        for id in taps.keys where !found.contains(where: { $0.id == id }) { taps.removeValue(forKey: id)?.invalidate() }
    }

    /// Makes the tap for `id` match its level and current processes.
    private func apply(_ id: String) {
        let level = self.level(id)
        guard level < 100, let app = apps.first(where: { $0.id == id }), let output = AudioOutputs.defaultID(),
              let outputUID = AudioOutputs.list().first(where: { $0.id == output })?.uid else {
            taps.removeValue(forKey: id)?.invalidate()
            return
        }
        if let tap = taps[id], tap.processes == app.processes, tap.outputUID == outputUID {
            tap.gain = Float(level / 100)
            return
        }
        taps.removeValue(forKey: id)?.invalidate()
        do {
            taps[id] = try ProcessTap(processes: app.processes, outputUID: outputUID, gain: Float(level / 100))
            if permissionDenied { permissionDenied = false }
            MediaService.trace("tap \(id) started: \(app.processes.count) processes → \(outputUID) gain=\(level / 100)")
            startTracing()
        } catch {
            NSLog("Damla: tap for %@ failed: %@", id, String(describing: error))
            MediaService.trace("tap \(id) failed: \(error)")
            permissionDenied = true
        }
    }

    /// `--debug`: input/output loudness of each tap once a second, to prove audio flows (silence in = no permission).
    private func startTracing() {
        guard MediaService.tracing, traceTimer == nil else { return }
        traceTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.taps.isEmpty { self.traceTimer?.invalidate(); self.traceTimer = nil; return }
            for (id, tap) in self.taps {
                MediaService.trace(String(format: "tap %@ in=%.4f out=%.4f gain=%.2f", id, tap.levelsPointer[0], tap.levelsPointer[1], tap.gain))
            }
        }
    }

    static func openPermissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") { NSWorkspace.shared.open(url) }
    }

    // MARK: Finding who plays sound

    /// Core Audio's process objects, grouped by the app they work for.
    static func audioApps() -> [AudioApp] {
        var grouped: [String: AudioApp] = [:]
        for process in processObjects() {
            guard let pid = int32(process, kAudioProcessPropertyPID), pid > 0, let owner = owner(of: pid_t(pid)) else { continue }
            let playing = (uint32(process, kAudioProcessPropertyIsRunningOutput) ?? 0) != 0
            var app = grouped[owner.id] ?? AudioApp(id: owner.id, name: owner.name, processes: [], playing: false)
            app.processes.append(process)
            app.playing = app.playing || playing
            grouped[owner.id] = app
        }
        // Rows for apps that play now, or that the user turned down earlier and are running.
        let saved = (UserDefaults.standard.dictionary(forKey: "appVolumes") as? [String: Double]) ?? [:]
        return grouped.values.filter { $0.playing || saved[$0.id] != nil }
            .map { var app = $0; app.processes.sort(); return app }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func processObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    /// The Dock-visible app a process works for: itself, a parent (Chrome's helpers), or the process macOS
    /// holds responsible for it (WebKit's GPU process serving Safari).
    static func owner(of pid: pid_t) -> (id: String, name: String)? {
        func regular(_ pid: pid_t) -> (id: String, name: String)? {
            guard let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
                  let id = app.bundleIdentifier else { return nil }
            return (id, app.localizedName ?? id)
        }
        var current = pid
        for _ in 0..<12 {
            if let found = regular(current) { return found }
            guard let parent = ProcessAncestry.parent(of: current), parent > 1, parent != current else { break }
            current = parent
        }
        if let responsible = responsiblePID(pid), responsible != pid { return regular(responsible) }
        return nil
    }

    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    private static let responsibleFn: ResponsibleFn? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: ResponsibleFn.self)
    }()
    private static func responsiblePID(_ pid: pid_t) -> pid_t? {
        guard let fn = responsibleFn else { return nil }
        let value = fn(pid)
        return value > 0 ? value : nil
    }

    private static func uint32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func int32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Int32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Int32 = 0
        var size = UInt32(MemoryLayout<Int32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr ? value : nil
    }
}

/// One app's audio, captured and played again at `gain` on `outputUID`.
final class ProcessTap {
    struct Failure: Error { let step: String; let status: OSStatus }

    let processes: [AudioObjectID]
    let outputUID: String
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    /// Read on the real-time audio thread; an aligned 32-bit store is atomic enough for a volume.
    private let gainPointer = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    /// Debug: last input and output RMS, to prove audio flows (read by `--debug` traces).
    let levelsPointer = UnsafeMutablePointer<Float>.allocate(capacity: 2)

    var gain: Float {
        get { gainPointer.pointee }
        set { gainPointer.pointee = min(1, max(0, newValue)) }
    }

    init(processes: [AudioObjectID], outputUID: String, gain: Float) throws {
        self.processes = processes
        self.outputUID = outputUID
        gainPointer.initialize(to: min(1, max(0, gain)))
        levelsPointer.initialize(repeating: 0, count: 2)
        do { try build() } catch { invalidate(); throw error }
    }

    private func build() throws {
        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.muteBehavior = .mutedWhenTapped   // the app's own output goes quiet; ours replaces it
        description.isPrivate = true
        description.name = "Damla"
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { throw Failure(step: "tap", status: status) }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Damla ses",
            kAudioAggregateDeviceUIDKey: "app.damla.volume." + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]]
        ]
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard status == noErr else { throw Failure(step: "aggregate", status: status) }

        let gain = gainPointer, levels = levelsPointer
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, input, _, output, _ in
            ProcessTap.render(input: input, output: output, gain: gain.pointee, levels: levels)
        }
        guard status == noErr, let procID else { throw Failure(step: "ioproc", status: status) }
        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else { throw Failure(step: "start", status: status) }
    }

    /// Real-time: copies the tap (the last input stream: taps follow the device's own streams) into every
    /// output stream, scaled by `gain`, mapping channels when the counts differ. No allocation, no locks.
    private static func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>,
                               gain: Float, levels: UnsafeMutablePointer<Float>) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        guard let source = inputs.last, let src = source.mData?.assumingMemoryBound(to: Float.self), source.mNumberChannels > 0 else {
            for buffer in outputs { if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) } }
            return
        }
        let srcChannels = Int(source.mNumberChannels)
        let srcFrames = Int(source.mDataByteSize) / (4 * srcChannels)
        var inputRMS: Float = 0
        vDSP_rmsqv(src, 1, &inputRMS, vDSP_Length(srcFrames * srcChannels))
        levels[0] = inputRMS
        var outputRMS: Float = 0
        for (index, buffer) in outputs.enumerated() {
            guard let dst = buffer.mData?.assumingMemoryBound(to: Float.self), buffer.mNumberChannels > 0 else { continue }
            let dstChannels = Int(buffer.mNumberChannels)
            let dstFrames = Int(buffer.mDataByteSize) / (4 * dstChannels)
            let frames = min(srcFrames, dstFrames)
            if dstChannels == srcChannels && outputs.count == 1 {
                var g = gain
                vDSP_vsmul(src, 1, &g, dst, 1, vDSP_Length(frames * dstChannels))
            } else {
                // Non-interleaved outputs take one source channel per buffer; interleaved ones map channel by channel.
                for frame in 0..<frames {
                    for channel in 0..<dstChannels {
                        let from = outputs.count == 1 ? min(channel, srcChannels - 1) : min(index, srcChannels - 1)
                        dst[frame * dstChannels + channel] = src[frame * srcChannels + from] * gain
                    }
                }
            }
            if dstFrames > frames { memset(dst + frames * dstChannels, 0, (dstFrames - frames) * dstChannels * 4) }
            if index == 0 { vDSP_rmsqv(dst, 1, &outputRMS, vDSP_Length(frames * dstChannels)) }
        }
        levels[1] = outputRMS
    }

    func invalidate() {
        if aggregateID != kAudioObjectUnknown {
            if let procID { AudioDeviceStop(aggregateID, procID); AudioDeviceDestroyIOProcID(aggregateID, procID) }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil; aggregateID = AudioObjectID(kAudioObjectUnknown); tapID = AudioObjectID(kAudioObjectUnknown)
    }

    deinit {
        invalidate()
        gainPointer.deallocate()
        levelsPointer.deallocate()
    }
}
