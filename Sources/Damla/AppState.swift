import AppKit
import Combine
import ServiceManagement
import UniformTypeIdentifiers

enum PanelTab: String, CaseIterable, Identifiable {
    case home = "Özet", files = "Dosyalar", clipboard = "Pano", focus = "Odak"
    var id: String { rawValue }
    var icon: String {
        switch self { case .home: return "square.grid.2x2"; case .files: return "tray"; case .clipboard: return "doc.on.clipboard"; case .focus: return "timer" }
    }
}

struct HUDItem: Identifiable {
    enum Kind { case volume, mute, brightness, battery, done }
    var id = UUID()
    var kind: Kind
    var icon: String
    var title: String
    var level: Double
}

final class AppState: ObservableObject {
    @Published var expanded = false
    @Published var pinnedOpen = false
    @Published var selectedTab: PanelTab = .home
    @Published var notchHeight: CGFloat = 32
    @Published var notchWidth: CGFloat = 185
    @Published var hasNotch = true
    @Published var displayMode = DisplayMode(rawValue: UserDefaults.standard.string(forKey: "displayMode") ?? "") ?? .followMouse
    @Published var externalStyle = ExternalStyle(rawValue: UserDefaults.standard.string(forKey: "externalStyle") ?? "") ?? .menuBar
    @Published var hideSystemHUD = UserDefaults.standard.bool(forKey: "hideSystemHUD")
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var noticeAction: (() -> Void)?
    @Published var battery = BatterySnapshot()
    @Published var volume: Float?
    @Published var brightness: Float?
    @Published var muted = false
    @Published var hud: HUDItem?
    @Published var notice: String?
    @Published var files: [ShelfItem] = DiskStore.load([ShelfItem].self, name: "shelf.json") ?? []
    @Published var clips: [ClipEntry] = DiskStore.load([ClipEntry].self, name: "clipboard.json") ?? []
    @Published var clipboardEnabled = UserDefaults.standard.bool(forKey: "clipboardEnabled")
    @Published var session = DiskStore.load(FocusSession.self, name: "focus.json") ?? FocusSession()
    @Published var now = Date()
    @Published var completedSessions = UserDefaults.standard.integer(forKey: "completedSessions")
    @Published var settingsVisible = false
    @Published var automaticOpen = UserDefaults.standard.object(forKey: "automaticOpen") as? Bool ?? true
    let media = MediaService()
    let monitor = SystemMonitor()
    lazy var keys = MediaKeyInterceptor(monitor: monitor)
    private var timer: Timer?
    private var clipboardTimer: Timer?
    private var pasteboardCount = NSPasteboard.general.changeCount
    private var hudClear: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private var noticeClear: DispatchWorkItem?
    var requestKeyFocus: (() -> Void)?
    var setDialogMode: ((Bool) -> Void)?

    var state: NotchState { expanded ? .expanded : hud != nil ? .hud : .closed }
    var metrics: Layout.Metrics { Layout.Metrics(notchWidth: notchWidth, notchHeight: notchHeight, hasNotch: hasNotch) }
    /// True when the closed notch has something to show beside the physical notch.
    var compactContent: Bool { session.hasStarted || media.hasTrack }

    func start() {
        monitor.onBattery = { [weak self] value in self?.battery = value }
        monitor.onLevels = { [weak self] volume, brightness, muted in
            self?.volume = volume; self?.brightness = brightness; self?.muted = muted
        }
        monitor.onHUD = { [weak self] icon, title, level in self?.showHUD(icon, title, level) }
        monitor.start(); media.start()
        keys.onDenied = { [weak self] in
            self?.showNotice("Erişilebilirlik izni gerekli · ayarları açmak için dokun", duration: 8) { MediaKeyInterceptor.openAccessibilitySettings() }
        }
        if hideSystemHUD { keys.start(prompt: false) }
        $expanded.removeDuplicates().sink { [weak self] expanded in
            guard let self else { return }
            self.media.wantsFrequentUpdates = expanded
            if expanded { self.now = Date(); self.media.refresh() }
        }.store(in: &cancellables)
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let date = Date()
            // Only republish the clock when something on screen depends on it; keeps the closed notch idle.
            if self.expanded || self.session.running { self.now = date }
            if self.session.finishIfNeeded(at: date) {
                if self.session.phase == .focus {
                    self.completedSessions += 1
                    UserDefaults.standard.set(self.completedSessions, forKey: "completedSessions")
                }
                self.saveSession()
                NSSound(named: "Glass")?.play()
                self.showHUD("checkmark.circle.fill", self.session.phase == .focus ? "Odak tamamlandı" : "Mola tamamlandı", 1)
                self.showNotice(self.session.phase == .focus ? "Güzel iş. Kısa bir mola ver." : "Yeni bir odak turuna hazırsın.")
            }
        }
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in self?.captureClipboard() }
    }
    func showHUD(_ icon: String, _ title: String, _ level: Double) {
        hudClear?.cancel()
        let kind: HUDItem.Kind = icon.hasPrefix("speaker.slash") ? .mute : icon.hasPrefix("speaker") ? .volume
            : icon.hasPrefix("sun") ? .brightness : icon.hasPrefix("battery") ? .battery : .done
        hud = HUDItem(kind: kind, icon: icon, title: title, level: min(1, max(0, level)))
        let work = DispatchWorkItem { [weak self] in self?.hud = nil }
        hudClear = work; DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: work)
    }
    func showNotice(_ message: String, duration: TimeInterval = 3, action: (() -> Void)? = nil) {
        noticeClear?.cancel(); notice = message; noticeAction = action
        let work = DispatchWorkItem { [weak self] in self?.notice = nil; self?.noticeAction = nil }
        noticeClear = work; DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && SMAppService.mainApp.status == .requiresApproval {
                showNotice("Giriş öğesi onay bekliyor · Sistem Ayarları'nı aç", duration: 8) { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            showNotice("Girişte başlatma ayarlanamadı: \(error.localizedDescription)", duration: 6)
        }
    }
    func setHideSystemHUD(_ enabled: Bool) {
        hideSystemHUD = enabled
        UserDefaults.standard.set(enabled, forKey: "hideSystemHUD")
        if enabled { keys.start(prompt: true) } else { keys.stop() }
    }
    func select(_ tab: PanelTab) {
        settingsVisible = false
        selectedTab = tab
        if tab == .clipboard { requestKeyFocus?() }
    }
    func toggleClipboard(_ enabled: Bool) {
        clipboardEnabled = enabled; pasteboardCount = NSPasteboard.general.changeCount
        UserDefaults.standard.set(enabled, forKey: "clipboardEnabled")
    }
    private func captureClipboard() {
        guard clipboardEnabled else { return }
        let board = NSPasteboard.general
        guard board.changeCount != pasteboardCount else { return }
        pasteboardCount = board.changeCount
        let types = Set((board.types ?? []).map(\.rawValue))
        guard ClipRules.shouldCapture(types: types) else { return }
        var entry: ClipEntry?
        if let data = board.data(forType: .png), data.count <= 4 * 1024 * 1024 {
            entry = ClipEntry(kind: .image, imageData: data)
        } else if let tiff = board.data(forType: .tiff), tiff.count < 20 * 1024 * 1024,
                  let rep = NSBitmapImageRep(data: tiff), let data = rep.representation(using: .png, properties: [:]), data.count <= 4 * 1024 * 1024 {
            entry = ClipEntry(kind: .image, imageData: data)
        } else if let text = board.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  text.utf8.count <= 200_000 {
            entry = ClipEntry(kind: .text, text: text)
        }
        guard var entry else { return }
        if let old = clips.first(where: { $0.kind == entry.kind && $0.text == entry.text && $0.imageData == entry.imageData }) {
            entry.pinned = old.pinned
            clips.removeAll { $0.id == old.id }
        }
        clips = ClipRules.trimmed([entry] + clips)
        saveClips()
    }
    func copy(_ entry: ClipEntry) {
        let item = NSPasteboardItem()
        if let text = entry.text { item.setString(text, forType: .string) }
        if let data = entry.imageData { item.setData(data, forType: .png) }
        item.setString("Damla", forType: NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
        pasteboardCount = NSPasteboard.general.changeCount
        showNotice("Kopyalandı · ⌘V ile yapıştır")
    }
    func pinClip(_ entry: ClipEntry) {
        guard let index = clips.firstIndex(where: { $0.id == entry.id }) else { return }
        clips[index].pinned.toggle(); clips = ClipRules.trimmed(clips); saveClips()
    }
    func removeClip(_ entry: ClipEntry) { clips.removeAll { $0.id == entry.id }; saveClips() }
    private func saveClips() { DiskStore.save(clips, name: "clipboard.json") }
    func addFiles(_ urls: [URL]) {
        var added = 0
        for url in urls where url.isFileURL {
            let url = url.standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path),
                  !files.contains(where: { $0.url.standardizedFileURL.path == url.path }) else { continue }
            files.insert(ShelfItem(url: url), at: 0); added += 1
        }
        DiskStore.save(files, name: "shelf.json")
        selectedTab = .files; expanded = true
        if added > 0 { showNotice("\(added) öğe rafa eklendi") }
    }
    func removeFile(_ item: ShelfItem) {
        files.removeAll { $0.id == item.id }; DiskStore.save(files, name: "shelf.json")
    }
    func openFile(_ item: ShelfItem) {
        if !NSWorkspace.shared.open(item.url) { showNotice("Dosya bulunamadı. Rafa yeniden ekleyebilirsin.") }
    }
    func chooseFiles() {
        pinnedOpen = true; requestKeyFocus?()
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        panel.prompt = "Ekle"
        setDialogMode?(true)
        panel.begin { [weak self] result in
            guard let self else { return }
            self.setDialogMode?(false)
            if result == .OK { self.addFiles(panel.urls) }
            self.pinnedOpen = false
        }
    }
    func setFocus(minutes: Int, phase: FocusSession.Phase = .focus) {
        session.reset(minutes: minutes, phase: phase); saveSession()
    }
    func toggleFocus() {
        if session.running { session.pause() } else { session.start() }
        saveSession()
    }
    func resetFocus() { session.reset(minutes: Int(session.duration / 60), phase: session.phase); saveSession() }
    func saveSession() { DiskStore.save(session, name: "focus.json") }
    var timeLabel: String {
        let seconds = Int(ceil(session.remaining(at: now)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    func savePreferences() {
        UserDefaults.standard.set(automaticOpen, forKey: "automaticOpen")
        UserDefaults.standard.set(displayMode.rawValue, forKey: "displayMode")
        UserDefaults.standard.set(externalStyle.rawValue, forKey: "externalStyle")
    }
    func clearFiles() { files.removeAll(); DiskStore.save(files, name: "shelf.json") }
}
