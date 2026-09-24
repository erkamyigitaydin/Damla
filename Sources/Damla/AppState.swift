import AppKit
import Combine
import ServiceManagement
import UniformTypeIdentifiers

enum PanelTab: String, CaseIterable, Identifiable {
    case home = "Özet", files = "Dosyalar", clipboard = "Pano", focus = "Odak", agents = "Agent’lar"
    var id: String { rawValue }
    var icon: String {
        switch self { case .home: return "square.grid.2x2"; case .files: return "tray"; case .clipboard: return "doc.on.clipboard"; case .focus: return "timer"; case .agents: return "terminal" }
    }
}

struct HUDItem: Identifiable {
    enum Kind { case volume, mute, brightness, battery, done, agent }
    var id = UUID()
    var kind: Kind
    var icon: String
    var title: String
    var level: Double
    var image: NSImage? = nil      // app icon instead of the symbol (agent HUDs)
    var detail: String = ""        // right-hand text instead of the level bar (agent HUDs)
    var phase: AgentPhase? = nil
}

final class AppState: ObservableObject {
    @Published var expanded = false
    @Published var pinnedOpen = false
    @Published var selectedTab: PanelTab = .home
    /// Screen whose window currently shows the expanded panel (HUD and basket show on every screen).
    @Published var activeScreenID: UInt32?
    @Published var dragActive = false   // a file drag is in progress somewhere on the system
    @Published var dragURLs: [URL] = []  // what is being dragged, for the tray preview
    @Published var selectedFile: UUID?
    @Published var displayMode = DisplayMode(rawValue: UserDefaults.standard.string(forKey: "displayMode") ?? "") ?? .all
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
    @Published var automaticOpen = UserDefaults.standard.object(forKey: "automaticOpen") as? Bool ?? true
    let media = MediaService()
    let monitor = SystemMonitor()
    let cleaning = KeyboardCleaning()
    let agents = AgentStatusService()
    let updater = UpdateService()
    @Published private(set) var agentBadge: AgentSession?
    @Published var agentAttention = false   // brief pulse of the mascot when an agent starts waiting
    lazy var keys = MediaKeyInterceptor(monitor: monitor)
    private var timer: Timer?
    private var clipboardTimer: Timer?
    private var pasteboardCount = NSPasteboard.general.changeCount
    private var hudClear: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private var noticeClear: DispatchWorkItem?
    var requestKeyFocus: (() -> Void)?
    var setDialogMode: ((Bool) -> Void)?
    var requestQuickLook: ((Int?) -> Void)?
    var requestShare: ((URL) -> Void)?
    var presentSettings: (() -> Void)?
    var presentPanel: (() -> Void)?
    private var openedForApproval = false   // the panel opened itself for a permission prompt
    private var pinnedBeforeApproval = false
    private var pinnedBeforeCleaning = false

    func state(for screenID: UInt32) -> NotchState {
        cleaning.active || (expanded && activeScreenID == screenID) ? .expanded : dragActive ? .drop : hud != nil ? .hud : .closed
    }
    /// Live activities the closed notch can show (focus timer, agent, media), at most two at once.
    var compactSlots: Int { min(2, [session.hasStarted, agentBadge != nil, media.hasTrack].filter { $0 }.count) }
    /// True when the closed notch has something to show beside the physical notch.
    var compactContent: Bool { compactSlots > 0 }

    func start() {
        monitor.onBattery = { [weak self] value in self?.battery = value }
        monitor.onLevels = { [weak self] volume, brightness, muted in
            self?.volume = volume; self?.brightness = brightness; self?.muted = muted
        }
        monitor.onHUD = { [weak self] icon, title, level in self?.showHUD(icon, title, level) }
        media.onNotice = { [weak self] text in
            self?.showNotice(text, duration: 8) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") { NSWorkspace.shared.open(url) }
            }
        }
        monitor.start(); media.start()
        cleaning.$active.dropFirst().sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        cleaning.onEnd = { [weak self] in
            guard let self else { return }
            self.pinnedOpen = self.pinnedBeforeCleaning
            if self.hideSystemHUD { self.keys.start(prompt: false) }
        }
        agents.onApproval = { [weak self] _ in
            // A permission prompt needs an answer: open on the agents tab, where the approval card waits.
            guard let self, !self.cleaning.active else { return }
            if !self.expanded { self.openedForApproval = true; self.pinnedBeforeApproval = self.pinnedOpen }
            self.select(.agents)
            self.presentPanel?()
        }
        agents.onRefresh = { [weak self] in
            guard let self else { return }
            if self.openedForApproval && self.agents.approvals.isEmpty {
                // Answered (here or in the terminal) or timed out: give the notch back.
                self.openedForApproval = false
                self.pinnedOpen = self.pinnedBeforeApproval
                if !self.pinnedOpen { self.expanded = false }
            }
            let badge = self.agents.sessions.first { $0.visibleInNotch(at: Date()) }
            if self.agentBadge != badge { self.agentBadge = badge }
        }
        agents.onChange = { [weak self] record in
            guard let self, !self.cleaning.active else { return }
            self.showAgentHUD(record)
            if record.phase == .waiting {
                // The HUD owns the notch for 3 s; the mascot pulses right after it hands the island back.
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.05) { [weak self] in self?.agentAttention = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.6) { [weak self] in self?.agentAttention = false }
                if self.agents.soundEnabled { NSSound(named: "Tink")?.play() }
            }
        }
        agents.start()
        updater.onUpdateFound = { [weak self] version in
            guard let self else { return }
            self.showNotice("Damla \(version) hazır · yüklemek için dokun", duration: 12) { [weak self] in self?.updater.checkForUpdates() }
            self.showHUD("arrow.down.circle.fill", "Damla \(version) hazır", 1)
        }
        updater.start()
        keys.onDenied = { [weak self] in
            self?.showNotice("Erişilebilirlik izni gerekli · ayarları açmak için dokun", duration: 8) { MediaKeyInterceptor.openAccessibilitySettings() }
        }
        if hideSystemHUD { keys.start(prompt: false) }
        $expanded.removeDuplicates().sink { [weak self] expanded in
            guard let self else { return }
            self.media.wantsFrequentUpdates = expanded
            if expanded { self.now = Date(); if !self.media.bridgeActive { self.media.refresh() } }
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
    func showAgentHUD(_ record: AgentSession) {
        hudClear?.cancel()
        hud = HUDItem(kind: .agent, icon: record.phase.icon, title: record.provider.title, level: 1,
                      image: record.provider.icon, detail: record.phase == .waiting && !record.detail.isEmpty ? record.detail : record.phase.shortTitle,
                      phase: record.phase)
        let work = DispatchWorkItem { [weak self] in self?.hud = nil }
        hudClear = work; DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
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
        if enabled && !cleaning.active { keys.start(prompt: true) } else { keys.stop() }
    }
    func startCleaning() {
        guard !cleaning.active else { return }
        guard MediaKeyInterceptor.trusted else {
            showNotice("Temizlik modu için Erişilebilirlik izni gerekli · ayarları aç", duration: 8) { MediaKeyInterceptor.openAccessibilitySettings() }
            return
        }
        pinnedBeforeCleaning = pinnedOpen
        guard cleaning.start() else { showNotice("Klavye kilitlenemedi. Erişilebilirlik iznini kontrol et.", duration: 6); return }
        keys.stop()
        pinnedOpen = true; expanded = true
    }
    /// Opens the settings window; the panel folds away so it does not sit over it.
    func openSettings() {
        pinnedOpen = false; expanded = false
        presentSettings?()
    }
    func select(_ tab: PanelTab) {
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
        if selectedFile == item.id { selectedFile = nil }
    }
    /// Opens (or closes) the system Quick Look panel on the given shelf item, else the selection, else the first item.
    func quickLook(_ item: ShelfItem? = nil) {
        guard !files.isEmpty else { return }
        if let item { selectedFile = item.id }
        let index = files.firstIndex { $0.id == selectedFile } ?? 0
        selectedFile = files[index].id
        requestQuickLook?(index)
    }
    func openFile(_ item: ShelfItem) {
        if !NSWorkspace.shared.open(item.url) { showNotice("Dosya bulunamadı. Rafa yeniden ekleyebilirsin.") }
    }
    func shareFile(_ item: ShelfItem? = nil) {
        guard let item = item ?? files.first(where: { $0.id == selectedFile }) ?? files.first else { return }
        selectedFile = item.id
        requestShare?(item.url)
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
