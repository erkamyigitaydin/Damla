import AppKit
import CoreAudio
import IOKit.ps
import Darwin

struct BatterySnapshot {
    var percentage = 0
    var charging = false
    var plugged = false
    var available = false
    var symbol: String { plugged ? "battery.100percent.bolt" : (percentage < 20 ? "battery.25percent" : "battery.75percent") }
}

final class SystemMonitor {
    private var timer: Timer?
    private var oldVolume: Float?
    private var oldBrightness: Float?
    private var oldMuted: Bool?
    private var oldPlugged: Bool?
    private var tickCount = 0
    private var listenerDevice: AudioDeviceID?
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var deviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var brightnessHandle: UnsafeMutableRawPointer?
    private var brightnessGetter: (@convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32)?
    private var brightnessSetter: (@convention(c) (UInt32, Float) -> Int32)?
    private static let feedbackSound = NSSound(contentsOfFile: "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff", byReference: true)
    var onBattery: ((BatterySnapshot) -> Void)?
    var onLevels: ((Float?, Float?, Bool) -> Void)?
    var onHUD: ((String, String, Double) -> Void)?
    /// Output devices and the default one; called at start and whenever either changes.
    var onOutputs: (([AudioOutput], AudioDeviceID?) -> Void)?
    var onDeviceBattery: ((String, String, String) -> Void)?   // icon, name, "S %80 · Sa %75 · K %60"
    private var devicesListenerBlock: AudioObjectPropertyListenerBlock?
    private var lastOutput: AudioDeviceID?

    init() {
        // Read-only fallback: Apple has no public brightness getter for all modern built-in displays.
        // It is optional; audio/battery keep working when this symbol is unavailable.
        brightnessHandle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        if let brightnessHandle, let symbol = dlsym(brightnessHandle, "DisplayServicesGetBrightness") {
            brightnessGetter = unsafeBitCast(symbol, to: (@convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32).self)
        }
        if let brightnessHandle, let symbol = dlsym(brightnessHandle, "DisplayServicesSetBrightness") {
            brightnessSetter = unsafeBitCast(symbol, to: (@convention(c) (UInt32, Float) -> Int32).self)
        }
    }
    func start() {
        poll()
        installAudioListeners()
        // Volume and mute arrive through CoreAudio listeners; the timer only covers brightness and battery.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.poll() }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    private static let volumeAddresses: [AudioObjectPropertyAddress] = [
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain),
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: 1),
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    ]
    private func installAudioListeners() {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.attachVolumeListener(); self?.poll(); self?.publishOutputs() }
        deviceListenerBlock = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        attachVolumeListener()
        // Devices coming and going (AirPods connecting, a display plugged in) change the output list.
        var devices = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let devicesBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.publishOutputs() }
        devicesListenerBlock = devicesBlock
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devices, DispatchQueue.main, devicesBlock)
        publishOutputs()
    }
    private func attachVolumeListener() {
        if let old = listenerDevice, let block = listenerBlock {
            for address in Self.volumeAddresses { var a = address; AudioObjectRemovePropertyListenerBlock(old, &a, DispatchQueue.main, block) }
        }
        listenerDevice = nil
        guard let device = Self.defaultOutputDevice() else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.poll() }
        listenerBlock = block; listenerDevice = device
        for address in Self.volumeAddresses {
            var a = address
            if AudioObjectHasProperty(device, &a) { AudioObjectAddPropertyListenerBlock(device, &a, DispatchQueue.main, block) }
        }
    }
    /// Publishes the output list; a new default device (picked here, in Control Center, or AirPods connecting)
    /// shows its name in the HUD with the volume it plays at.
    private func publishOutputs() {
        let outputs = AudioOutputs.list(), current = AudioOutputs.defaultID()
        onOutputs?(outputs, current)
        defer { lastOutput = current }
        guard let lastOutput, let current, current != lastOutput, let device = outputs.first(where: { $0.id == current }) else { return }
        let (volume, muted) = Self.audio()
        let title = AudioOutput.shortName(device.name, transport: device.transport)
        onHUD?(device.icon, title, muted ? 0 : Double(volume ?? 1))
        // AirPods and other Bluetooth headphones: follow up with their battery once it can be read.
        guard device.isBluetooth else { return }
        BluetoothBattery.levels(for: device.name) { [weak self] levels in
            guard let self, let levels, AudioOutputs.defaultID() == current else { return }
            self.onDeviceBattery?(device.icon, title, levels.summary)
        }
    }
    func poll() {
        let (volume, muted) = Self.audio()
        let brightness = brightnessValue()
        onLevels?(volume, brightness, muted)
        if let volume, let oldVolume, abs(volume - oldVolume) > 0.005 || muted != oldMuted {
            onHUD?(muted ? "speaker.slash.fill" : "speaker.wave.2.fill", muted ? String(localized: "Ses kapalı") : String(localized: "Ses"), muted ? 0 : Double(volume))
        }
        if let brightness, let oldBrightness, abs(brightness - oldBrightness) > 0.009 {
            onHUD?("sun.max.fill", String(localized: "Parlaklık"), Double(brightness))
        }
        oldVolume = volume; oldBrightness = brightness; oldMuted = muted
        if tickCount % 5 == 0 {
            let battery = Self.battery()
            onBattery?(battery)
            if let oldPlugged, oldPlugged != battery.plugged {
                onHUD?(battery.symbol, battery.plugged ? String(localized: "Şarja bağlandı") : String(localized: "Pil kullanılıyor"), Double(battery.percentage) / 100)
            }
            oldPlugged = battery.plugged
        }
        tickCount += 1
    }
    private var builtInDisplayID: UInt32? {
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
        return (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
    func brightnessValue() -> Float? {
        guard let getter = brightnessGetter, let id = builtInDisplayID else { return nil }
        var value: Float = 0
        return getter(id, &value) == 0 ? min(1, max(0, value)) : nil
    }
    var canSetBrightness: Bool { brightnessSetter != nil && brightnessValue() != nil }

    // MARK: Applying changes ourselves (used when the system bezel is suppressed)

    func adjustVolume(by delta: Float, feedback: Bool) {
        let (current, muted) = Self.audio()
        guard let current else { return }
        let value = min(1, max(0, (current + delta * 1.0001).rounded(toStep: abs(delta))))
        if muted && delta > 0 { Self.setMute(false) }
        Self.setVolume(value)
        let (applied, nowMuted) = Self.audio()
        oldVolume = applied ?? value; oldMuted = nowMuted
        onLevels?(applied ?? value, brightnessValue(), nowMuted)
        onHUD?(nowMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", nowMuted ? String(localized: "Ses kapalı") : String(localized: "Ses"), nowMuted ? 0 : Double(applied ?? value))
        if feedback { Self.feedbackSound?.stop(); Self.feedbackSound?.play() }
    }
    func toggleMute() {
        let (volume, muted) = Self.audio()
        Self.setMute(!muted)
        let (applied, nowMuted) = Self.audio()
        oldVolume = applied ?? volume; oldMuted = nowMuted
        onLevels?(applied ?? volume, brightnessValue(), nowMuted)
        onHUD?(nowMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", nowMuted ? String(localized: "Ses kapalı") : String(localized: "Ses"), nowMuted ? 0 : Double(applied ?? volume ?? 0))
    }
    func adjustBrightness(by delta: Float) {
        guard let setter = brightnessSetter, let id = builtInDisplayID, let current = brightnessValue() else { return }
        let value = min(1, max(0, (current + delta * 1.0001).rounded(toStep: abs(delta))))
        _ = setter(id, value)
        let applied = brightnessValue() ?? value
        oldBrightness = applied
        onLevels?(oldVolume, applied, oldMuted ?? false)
        onHUD?("sun.max.fill", String(localized: "Parlaklık"), Double(applied))
    }
    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return nil }
        return device
    }
    static func setVolume(_ value: Float) {
        guard let device = defaultOutputDevice() else { return }
        var value = value
        let size = UInt32(MemoryLayout<Float>.size)
        var applied = false
        for element in [UInt32(0), 1, 2] {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                     mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            var settable: DarwinBoolean = false
            guard AudioObjectHasProperty(device, &address),
                  AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { continue }
            if AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr {
                applied = true
                if element == 0 { break }
            }
        }
        if !applied {
            // Devices without a direct scalar volume still expose the system-level "virtual main volume" ('vmvc').
            var address = AudioObjectPropertyAddress(mSelector: AudioObjectPropertySelector(0x766D_7663),
                                                     mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            if AudioObjectHasProperty(device, &address) { AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) }
        }
    }
    static func setMute(_ muted: Bool) {
        guard let device = defaultOutputDevice() else { return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                 mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(device, &address, 0, nil, 4, &value)
    }
    static func audio() -> (Float?, Bool) {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return (nil, false) }
        address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                             mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var mute: UInt32 = 0; size = 4
        _ = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &mute)
        var levels: [Float] = []
        for element in [UInt32(0), 1, 2] {
            address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                 mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            var value: Float = 0; size = 4
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr {
                levels.append(value)
                if element == 0 { break }
            }
        }
        return (levels.isEmpty ? nil : levels.reduce(0, +) / Float(levels.count), mute != 0)
    }
    static func battery() -> BatterySnapshot {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return BatterySnapshot() }
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = d[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            return BatterySnapshot(percentage: min(100, max(0, current * 100 / maximum)),
                                   charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                                   plugged: (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue, available: true)
        }
        return BatterySnapshot()
    }
    deinit { timer?.invalidate(); if let brightnessHandle { dlclose(brightnessHandle) } }
}

private extension Float {
    /// Snaps to macOS's 16 (or 64) volume/brightness steps so repeated presses land on the same grid.
    func rounded(toStep step: Float) -> Float { step > 0 ? (self / step).rounded() * step : self }
}
