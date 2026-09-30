import AppKit
import Combine
import SwiftUI
import CoreAudio
import ServiceManagement
import UniformTypeIdentifiers

enum PanelTab: String, CaseIterable, Identifiable {
    case home = "Özet", files = "Dosyalar", clipboard = "Pano", focus = "Odak", mirror = "Ayna", shortcuts = "Kestirmeler", notifications = "Bildirimler", agents = "Agent’lar"   // raw values are stored settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return String(localized: "Özet"); case .files: return String(localized: "Dosyalar"); case .clipboard: return String(localized: "Pano")
        case .focus: return String(localized: "Odak"); case .mirror: return String(localized: "Ayna")
        case .shortcuts: return String(localized: "Kestirmeler"); case .notifications: return String(localized: "Bildirimler")
        case .agents: return String(localized: "Agent’lar")
        }
    }
    var icon: String {
        switch self {
        case .home: return "square.grid.2x2"; case .files: return "tray"; case .clipboard: return "doc.on.clipboard"; case .focus: return "timer"
        case .mirror: return "person.crop.square"; case .shortcuts: return "bolt"; case .notifications: return "bell"; case .agents: return "terminal"
        }
    }
    /// Pages the user keeps in the panel, in the fixed order; never empty. A page added in an update starts
    /// switched on: only pages the user has already seen in the settings can be off.
    static func loadEnabled(defaults: UserDefaults = .standard) -> Set<PanelTab> {
        guard let saved = defaults.array(forKey: "enabledTabs") as? [String] else { return Set(allCases) }
        // Settings saved before "knownTabs" existed knew every page except the ones added since.
        let known = (defaults.array(forKey: "knownTabs") as? [String]).map { Set($0.compactMap(PanelTab.init(rawValue:))) }
            ?? Set(allCases).subtracting([.mirror, .shortcuts])
        let tabs = Set(saved.compactMap(PanelTab.init(rawValue:))).union(Set(allCases).subtracting(known))
        return tabs.isEmpty ? Set(allCases) : tabs
    }
    /// The user's order of the pages. Pages added in an update take their place after the page they follow by
    /// default (or first), so a saved order never loses one.
    static func loadOrder(defaults: UserDefaults = .standard) -> [PanelTab] {
        var order: [PanelTab] = []
        for name in defaults.array(forKey: "tabOrder") as? [String] ?? [] {
            if let tab = PanelTab(rawValue: name), !order.contains(tab) { order.append(tab) }
        }
        for (index, tab) in allCases.enumerated() where !order.contains(tab) {
            let after = allCases[..<index].last(where: order.contains).flatMap { order.firstIndex(of: $0) }
            order.insert(tab, at: after.map { $0 + 1 } ?? 0)
        }
        return order
    }
}

struct HUDItem: Identifiable {
    enum Kind { case volume, mute, brightness, battery, done, agent, device }
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
    @Published var selectedTab: PanelTab = PanelTab.loadOrder().first(where: PanelTab.loadEnabled().contains) ?? .home {
        willSet {
            // Which way the next page comes in: from the right when it sits to the right in the pill.
            let from = tabOrder.firstIndex(of: selectedTab) ?? 0, to = tabOrder.firstIndex(of: newValue) ?? 0
            if from != to { pageDirection = to > from ? 1 : -1 }
        }
    }
    /// +1 when the page just shown lies to the right of the previous one (or the tour moved on), -1 to the left.
    private(set) var pageDirection = 1
    /// Pages shown in the tab pill. Turning off the page on screen moves to the first one still on.
    @Published private(set) var enabledTabs = PanelTab.loadEnabled() {
        didSet {
            UserDefaults.standard.set(PanelTab.allCases.filter(enabledTabs.contains).map(\.rawValue), forKey: "enabledTabs")
            UserDefaults.standard.set(PanelTab.allCases.map(\.rawValue), forKey: "knownTabs")
            if !enabledTabs.contains(selectedTab), let first = visibleTabs.first { selectedTab = first }
        }
    }
    /// The pages in the user's order (Settings → Sayfalar, drag to rearrange); the pill follows it.
    @Published private(set) var tabOrder = PanelTab.loadOrder() {
        didSet { UserDefaults.standard.set(tabOrder.map(\.rawValue), forKey: "tabOrder") }
    }
    var visibleTabs: [PanelTab] { tabOrder.filter(enabledTabs.contains) }
    /// Puts a dragged page where another one is: before it when moving up, after it when moving down.
    func moveTab(_ tab: PanelTab, to target: PanelTab) {
        guard tab != target, let from = tabOrder.firstIndex(of: tab), let to = tabOrder.firstIndex(of: target) else { return }
        var order = tabOrder
        order.remove(at: from)
        order.insert(tab, at: to)
        tabOrder = order
    }
    func resetTabOrder() { tabOrder = PanelTab.allCases }
    /// Screen whose window currently shows the expanded panel (HUD and basket show on every screen).
    @Published var activeScreenID: UInt32?
    @Published var dragActive = false   // a file drag is in progress somewhere on the system
    @Published var dragURLs: [URL] = []  // what is being dragged, for the tray preview
    @Published var selectedFile: UUID?
    @Published var displayMode = DisplayMode(rawValue: UserDefaults.standard.string(forKey: "displayMode") ?? "") ?? .all
    @Published var externalStyle = ExternalStyle(rawValue: UserDefaults.standard.string(forKey: "externalStyle") ?? "") ?? .menuBar
    @Published var hideSystemHUD = UserDefaults.standard.bool(forKey: "hideSystemHUD")
    /// With nothing playing, no agent at work and no timer, the fake notch on a notchless screen is not drawn.
    /// Off by default: the user wants the fake notch in place on the external display.
    @Published var hideIdleNotch = UserDefaults.standard.bool(forKey: "hideIdleFakeNotch") {
        didSet { UserDefaults.standard.set(hideIdleNotch, forKey: "hideIdleFakeNotch") }
    }
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var noticeAction: (() -> Void)?
    @Published var battery = BatterySnapshot()
    @Published var volume: Float?
    @Published var brightness: Float?
    @Published var muted = false
    @Published var outputs: [AudioOutput] = []
    /// What Özet shows: the player, the output list, or the volume levels.
    enum HomePane { case player, outputs, levels, sources, videoSetup }
    @Published var homePane: HomePane = .player {
        willSet { if newValue != homePane { pageDirection = newValue == .player ? -1 : 1 } }   // a pane opens forward, closes back
    }
    /// Lyrics mode: the panel grows down with the lyrics flowing under the player, and stays open when the pointer
    /// leaves. Left by the lyrics button or by closing the panel by hand; never restored on the next open.
    @Published var lyricsExpanded = false
    /// The lyrics stretch the panel down; it also stays open when the pointer leaves.
    var tallPanel: Bool { selectedTab == .home && homePane == .player && lyricsExpanded && media.hasTrack }
    /// Every page shares one height, so switching pages never pulls the panel out from under the pointer;
    /// only the lyrics, opened within the page, stretch it.
    var contentHeight: CGFloat { Layout.contentHeight(tall: tallPanel) }
    /// Scroll on the notch strip: vertical for volume, a horizontal swipe to skip tracks.
    @Published var notchGestures = UserDefaults.standard.object(forKey: "notchGestures") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notchGestures, forKey: "notchGestures") }
    }
    @Published var currentOutput: AudioDeviceID?
    /// Battery of the connected Bluetooth outputs (AirPods: each bud and the case), keyed by device name.
    @Published private(set) var outputBatteries: [String: BluetoothBattery.Levels] = [:]
    private var readingBatteries = false
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
    let appVolumes = AppVolumeController()
    let lyrics = LyricsService()
    let monitor = SystemMonitor()
    let deviceBatteries = DeviceBatteryWatcher()
    let devServers = DevServerMonitor()
    let calendar = CalendarService()
    let video = VideoNotch()
    let videoSetup = VideoSetup()
    let screenshots = ScreenshotWatcher()
    let shortcuts = ShortcutsService()
    @Published var screenshotsToShelf = UserDefaults.standard.object(forKey: "screenshotsToShelf") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(screenshotsToShelf, forKey: "screenshotsToShelf")
            if screenshotsToShelf && enabledTabs.contains(.files) { screenshots.start() } else { screenshots.stop() }
        }
    }
    let microphone = MicrophoneMonitor()
    @Published var micInNotch = UserDefaults.standard.object(forKey: "micInNotch") as? Bool ?? true {
        didSet { UserDefaults.standard.set(micInNotch, forKey: "micInNotch") }
    }
    /// The microphone slot: an app is using the mic and the user wants to see it.
    var micActive: Bool { micInNotch && microphone.inUse }
    let cleaning = KeyboardCleaning()
    let agents = AgentStatusService()
    let notifications = NotificationMirror()
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
    var presentOnboarding: (() -> Void)?
    private var openedForApproval = false   // the panel opened itself for a permission prompt
    private var pinnedBeforeApproval = false
    private var pinnedBeforeCleaning = false

    func state(for screenID: UInt32) -> NotchState {
        if cleaning.active || (expanded && activeScreenID == screenID) { return .expanded }
        if dragActive { return .drop }
        // A reply being written keeps its card over a volume or agent HUD.
        // The video under the notch keeps its place; the other screens show the card.
        if notifications.current != nil && (notifications.replying || hud == nil) && !videoShown(on: screenID) { return .notification }
        return hud != nil ? .hud : .closed
    }
    /// Height under the notch for a state: the page for the open panel, the card for a notification.
    func shapeContent(_ state: NotchState) -> CGFloat { state == .notification ? notifications.cardHeight : contentHeight }
    /// Live activities the closed notch can show (focus timer, agent, media), at most two at once.
    var compactSlots: Int { compactSlots(on: nil) }
    /// On the screen showing the video, the video stands for the media and the agents stay out of its way.
    func compactSlots(on screenID: UInt32?) -> Int {
        let video = screenID.map(videoShown(on:)) ?? false
        return min(2, [micActive, session.hasStarted, calendar.soon != nil, agentBadge != nil && !video, mediaInNotch && !video, unreadInNotch].filter { $0 }.count)
    }
    /// Notifications that came while the Bildirimler page was not looked at: a bell with the count on the closed notch.
    var unreadInNotch: Bool { notifications.unread > 0 && enabledTabs.contains(.notifications) }
    /// The track earns a place on the closed notch only while it plays (or paused a moment ago).
    var mediaInNotch: Bool { media.hasTrack && media.recentlyPlaying }
    /// Nothing to show on a screen without a physical notch: the closed notch steps out of sight (hovering the
    /// spot still opens the panel). A physical notch is there anyway, so it keeps its usual shape.
    func idleHidden(on screenID: UInt32, physicalNotch: Bool) -> Bool {
        hideIdleNotch && !physicalNotch && state(for: screenID) == .closed && compactSlots(on: screenID) == 0 && !videoShown(on: screenID)
    }
    /// The video under the closed notch, when one is showing.
    /// Only on the screen it was started from; the other screens keep their usual notch.
    private(set) var videoScreenID: UInt32?
    func videoShown(on screenID: UInt32) -> Bool { video.active && (videoScreenID == nil || videoScreenID == screenID) }
    func videoSpec(on screenID: UInt32) -> Layout.VideoSpec? {
        videoShown(on: screenID) ? Layout.VideoSpec(base: video.pipSize, large: video.large) : nil
    }
    /// The browser to take the video from: the one playing, else the first supported one that is running.
    var videoBrowser: String? {
        if VideoNotch.canShow(media.sourceBundleID) { return media.sourceBundleID }
        return NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier).first(where: VideoNotch.canShow)
    }
    /// Puts the browser's video under the notch of the screen it was asked from. The panel stays open while it
    /// starts (a problem shows there as a notice) and folds away once the video is in place.
    func startVideo() {
        guard let id = videoBrowser else { return }
        startVideo(bundleID: id)
    }
    /// The ⧉ button: straight in when everything is set up, the setup card otherwise.
    func requestVideo() {
        guard let id = videoBrowser else { return }
        videoSetup.use(id)
        if videoSetup.quickReady { startVideo(bundleID: id) } else { showVideoSetup() }
    }
    func showVideoSetup() {
        selectedTab = .home
        withAnimation(Theme.quick) { homePane = .videoSetup }
        activeScreenID = activeScreenID ?? videoScreenID
        expanded = true
    }
    func startVideo(bundleID: String) {
        videoScreenID = activeScreenID
        video.start(bundleID: bundleID)
    }
    func stopVideo() { video.stop() }
    /// True when the closed notch has something to show beside the physical notch.
    var compactContent: Bool { compactSlots > 0 }

    func start() {
        // Published only on change: every assignment redraws both notch windows, even with the same value.
        monitor.onBattery = { [weak self] value in if self?.battery != value { self?.battery = value } }
        monitor.onLevels = { [weak self] volume, brightness, muted in
            guard let self else { return }
            if self.volume != volume { self.volume = volume }
            if self.brightness != brightness { self.brightness = brightness }
            if self.muted != muted { self.muted = muted }
        }
        monitor.onHUD = { [weak self] icon, title, level in self?.showHUD(icon, title, level) }
        notifications.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        notifications.isViewing = { [weak self] in self.map { $0.expanded && $0.selectedTab == .notifications } ?? false }
        // Looking at the page reads everything on it; leaving it (another page, or the panel closing) clears
        // what was read.
        Publishers.CombineLatest($expanded, $selectedTab).removeDuplicates { $0 == $1 }.receive(on: RunLoop.main)
            .sink { [weak self] expanded, tab in
                if expanded && tab == .notifications { self?.notifications.markRead() } else { self?.notifications.dropRead() }
            }
            .store(in: &cancellables)
        notifications.start()
        monitor.onOutputs = { [weak self] outputs, current in
            guard let self else { return }
            if self.outputs != outputs {
                let connected = outputs.contains { $0.isBluetooth && !self.outputs.contains($0) }
                self.outputs = outputs
                if connected { self.refreshOutputBatteries() }
            }
            if self.currentOutput != current {
                let switched = self.currentOutput != nil
                self.currentOutput = current
                if switched { self.appVolumes.outputChanged() }   // turned-down apps follow the new output
            }
        }
        monitor.onDeviceBattery = { [weak self] icon, title, detail in self?.showDeviceHUD(icon, title, detail: detail) }
        deviceBatteries.onLow = { [weak self] name, icon, level in
            self?.showDeviceHUD(icon, AudioOutput.shortName(name, transport: kAudioDeviceTransportTypeBluetooth),
                                detail: String(localized: "Pil azaldı · %\(level)"))
        }
        deviceBatteries.start()
        // The notch's size depends on the meeting countdown and the mic slot: redraw with them.
        calendar.objectWillChange.merge(with: microphone.objectWillChange, video.objectWillChange).receive(on: RunLoop.main)
            .sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        video.onProblem = { [weak self] text in self?.showNotice(text, duration: 6) }
        video.onSetupNeeded = { [weak self] javaScript in
            if javaScript { self?.videoSetup.javaScriptTurnedOff() }
            self?.showVideoSetup()
        }
        video.$active.removeDuplicates().filter { $0 }.sink { [weak self] _ in
            self?.pinnedOpen = false; self?.expanded = false
        }.store(in: &cancellables)
        calendar.onStarting = { [weak self] meeting in
            self?.showDeviceHUD("calendar", meeting.title, detail: meeting.joinURL == nil ? String(localized: "1 dk sonra başlıyor")
                                                                                       : String(localized: "1 dk sonra · çentikten katıl"))
        }
        calendar.start()
        microphone.start()
        screenshots.onNew = { [weak self] urls in
            guard let self, self.screenshotsToShelf, self.enabledTabs.contains(.files) else { return }
            self.addFiles(urls, open: false)
            self.showDeviceHUD("camera.viewfinder", String(localized: "Ekran görüntüsü rafta"), detail: urls.count > 1 ? "\(urls.count)" : "")
        }
        if screenshotsToShelf && enabledTabs.contains(.files) { screenshots.start() }
        shortcuts.onFinish = { [weak self] name, ok in
            self?.showDeviceHUD(ok ? "bolt.fill" : "exclamationmark.triangle.fill", name, detail: ok ? String(localized: "Bitti") : String(localized: "Çalışmadı"))
        }
        agents.onUsageWarning = { [weak self] percent, resets in
            self?.showDeviceHUD("gauge.with.dots.needle.67percent", String(localized: "Claude kullanımı %\(percent)"),
                                detail: String(localized: "\(resets.formatted(date: .omitted, time: .shortened)) sıfırlanır"))
        }
        appVolumes.start()
        // The accent follows the cover; every view reads it, so a new colour redraws the panel.
        media.$accent.removeDuplicates().sink { [weak self] cover in
            Accent.update(from: cover)
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        // A song without lyrics folds the lyrics view away: its button is hidden, so nothing else could close it.
        lyrics.$state.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] state in
            guard let self, state == .missing, self.lyricsExpanded else { return }
            self.lyricsExpanded = false   // the panel animates its own height change
        }.store(in: &cancellables)
        // Lyrics follow the shown track; only songs a player named an artist for, 30 s – 20 min long.
        Publishers.CombineLatest4(media.$title, media.$artist, media.$duration, media.$artistKnown)
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] title, artist, duration, known in
                guard let self else { return }
                // A new track often reports its length a moment after its title: wait for it instead of
                // briefly declaring "no lyrics".
                if self.media.hasTrack && known && duration <= 0 { self.lyrics.expecting(title: title, artist: artist); return }
                let song = self.media.hasTrack && known && duration >= 30 && duration <= 20 * 60
                self.lyrics.show(title: song ? title : "", artist: song ? artist : "", album: self.media.album, duration: song ? duration : 0)
            }.store(in: &cancellables)
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
                // The approval card lives on the agents page even when that page is off; leave it again.
                if !self.enabledTabs.contains(self.selectedTab), let first = self.visibleTabs.first { self.selectedTab = first }
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
            self.showNotice(String(localized: "Damla \(version) hazır · yüklemek için dokun"), duration: 12) { [weak self] in self?.updater.checkForUpdates() }
            self.showHUD("arrow.down.circle.fill", String(localized: "Damla \(version) hazır"), 1)
        }
        updater.start()
        keys.onDenied = { [weak self] in
            self?.showNotice(String(localized: "Erişilebilirlik izni gerekli · ayarları açmak için dokun"), duration: 8) { MediaKeyInterceptor.openAccessibilitySettings() }
        }
        if hideSystemHUD { keys.start(prompt: false) }
        $expanded.removeDuplicates().sink { [weak self] expanded in
            guard let self else { return }
            self.media.wantsFrequentUpdates = expanded
            if !expanded {
                self.homePane = .player; self.lyricsExpanded = false
                // Never reopen on the mirror: hovering the notch must not switch the camera on.
                if self.selectedTab == .mirror { self.selectedTab = self.visibleTabs.first ?? .home }
            }
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
                self.showHUD("checkmark.circle.fill", self.session.phase == .focus ? String(localized: "Odak tamamlandı") : String(localized: "Mola tamamlandı"), 1)
                self.showNotice(self.session.phase == .focus ? String(localized: "Güzel iş. Kısa bir mola ver.") : String(localized: "Yeni bir odak turuna hazırsın."))
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
    /// A device's name on the left, a line of text (AirPods battery) on the right.
    func showDeviceHUD(_ icon: String, _ title: String, detail: String) {
        hudClear?.cancel()
        hud = HUDItem(kind: .device, icon: icon, title: title, level: 1, detail: detail)
        let work = DispatchWorkItem { [weak self] in self?.hud = nil }
        hudClear = work; DispatchQueue.main.asyncAfter(deadline: .now() + 3.2, execute: work)
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
                showNotice(String(localized: "Giriş öğesi onay bekliyor · Sistem Ayarları'nı aç"), duration: 8) { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            showNotice(String(localized: "Girişte başlatma ayarlanamadı: \(error.localizedDescription)"), duration: 6)
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
            showNotice(String(localized: "Temizlik modu için Erişilebilirlik izni gerekli · ayarları aç"), duration: 8) { MediaKeyInterceptor.openAccessibilitySettings() }
            return
        }
        pinnedBeforeCleaning = pinnedOpen
        guard cleaning.start() else { showNotice(String(localized: "Klavye kilitlenemedi. Erişilebilirlik iznini kontrol et."), duration: 6); return }
        keys.stop()
        pinnedOpen = true; expanded = true
    }
    /// Opens the settings window; the panel folds away so it does not sit over it.
    func openSettings() {
        pinnedOpen = false; expanded = false
        presentSettings?()
    }
    /// The last page cannot be turned off: the panel always has something to open to.
    func setTab(_ tab: PanelTab, enabled: Bool) {
        if enabled { enabledTabs.insert(tab) } else if enabledTabs.count > 1 { enabledTabs.remove(tab) }
    }
    /// The tour told inside the notch; nil when it is not running.
    @Published private(set) var tour: TourStep?
    private var pinnedBeforeTour = false

    func startTour(at step: TourStep = .welcome) {
        if tour == nil { pinnedBeforeTour = pinnedOpen }
        homePane = .player; lyricsExpanded = false
        showTourStep(step)
        pinnedOpen = true; expanded = true
        presentPanel?()
    }
    func advanceTour() {
        guard let tour else { return }
        if let next = TourStep(rawValue: tour.rawValue + 1) { showTourStep(next) } else { endTour() }
    }
    /// Finished or skipped: it will not open by itself again (the menu and Ayarlar → Hakkında still offer it).
    func endTour() {
        guard tour != nil else { return }
        tour = nil
        UserDefaults.standard.set(true, forKey: TourStep.doneKey)
        pinnedOpen = pinnedBeforeTour
    }
    private func showTourStep(_ step: TourStep) {
        pageDirection = (tour?.rawValue ?? -1) < step.rawValue ? 1 : -1
        tour = step
        // The pill points at the page the step is about, when that page is switched on.
        if enabledTabs.contains(step.tab) { selectedTab = step.tab } else if let first = visibleTabs.first { selectedTab = first }
    }

    func select(_ tab: PanelTab) {
        endTour()   // picking a page from the pill means the user has taken over
        selectedTab = tab
        if tab == .clipboard { requestKeyFocus?() }
    }
    /// Reads the Bluetooth outputs' batteries again; one system_profiler run covers every device.
    func refreshOutputBatteries() {
        guard !readingBatteries, outputs.contains(where: \.isBluetooth) else { return }
        readingBatteries = true
        BluetoothBattery.read { [weak self] levels in
            guard let self else { return }
            self.readingBatteries = false
            if self.outputBatteries != levels { self.outputBatteries = levels }
        }
    }
    /// The current output's battery, when it is a Bluetooth device that reports one.
    var currentOutputBattery: BluetoothBattery.Levels? {
        outputs.first { $0.id == currentOutput && $0.isBluetooth }.flatMap { outputBatteries[$0.name] }
    }
    func toggleMicrophone() {
        if microphone.toggleMute() {
            showHUD(microphone.muted ? "mic.slash.fill" : "mic.fill", microphone.muted ? String(localized: "Mikrofon kapalı") : String(localized: "Mikrofon açık"), 1)
        } else {
            showNotice(String(localized: "Bu mikrofonun sessize alma anahtarı yok."))
        }
    }
    /// How far the page follows a swipe right now (0 at rest).
    @Published private(set) var swipeOffset: CGFloat = 0

    /// Whether a swipe that way has a page to go to (in the tour: a step).
    func canTurnPage(forward: Bool) -> Bool {
        if let tour { return forward || tour.rawValue > 0 }
        guard let index = visibleTabs.firstIndex(of: selectedTab) else { return false }
        return visibleTabs.indices.contains(index + (forward ? 1 : -1))
    }
    /// The page moves with the fingers; with nothing on that side it only gives a little.
    func dragPage(_ travel: CGFloat) {
        swipeOffset = canTurnPage(forward: travel < 0) ? travel : PanelSwipeGesture.rubberBand(travel)
    }
    /// Fingers lifted: turn the page, or spring back into place.
    func releasePage(_ action: PanelSwipeGesture.Action?) {
        if let action, canTurnPage(forward: action == .next) {
            // The page that leaves keeps where it was dragged to; the new one starts centred.
            var instant = Transaction(); instant.disablesAnimations = true
            withTransaction(instant) { swipeOffset = 0 }
            turnPage(forward: action == .next)
        } else {
            withAnimation(.spring(duration: 0.42, bounce: 0.28)) { swipeOffset = 0 }
        }
    }
    /// The neighbouring page for a swipe; the first and last pages do not wrap around. In the tour it moves
    /// between steps instead.
    func turnPage(forward: Bool) {
        if let tour {
            if forward { advanceTour() } else if let previous = TourStep(rawValue: tour.rawValue - 1) { showTourStep(previous) }
            return
        }
        let tabs = visibleTabs
        guard let index = tabs.firstIndex(of: selectedTab) else { return }
        let target = index + (forward ? 1 : -1)
        guard tabs.indices.contains(target) else { return }
        select(tabs[target])
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
        showNotice(String(localized: "Kopyalandı · ⌘V ile yapıştır"))
    }
    func pinClip(_ entry: ClipEntry) {
        guard let index = clips.firstIndex(where: { $0.id == entry.id }) else { return }
        clips[index].pinned.toggle(); clips = ClipRules.trimmed(clips); saveClips()
    }
    func removeClip(_ entry: ClipEntry) { clips.removeAll { $0.id == entry.id }; saveClips() }
    private func saveClips() { DiskStore.save(clips, name: "clipboard.json") }
    /// Puts files on the shelf. `open` shows the shelf; screenshots and conversions arrive quietly instead.
    func addFiles(_ urls: [URL], open: Bool = true) {
        var added = 0
        for url in urls where url.isFileURL {
            let url = url.standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path),
                  !files.contains(where: { $0.url.standardizedFileURL.path == url.path }) else { continue }
            files.insert(ShelfItem(url: url), at: 0); added += 1
        }
        DiskStore.save(files, name: "shelf.json")
        guard open else { return }
        selectedTab = .files; expanded = true
        if added > 0 { showNotice(String(localized: "\(added) öğe rafa eklendi")) }
    }

    func runShelfAction(_ action: ShelfAction, on item: ShelfItem) {
        action.run(on: item.url, shelf: files.map(\.url)) { [weak self] result in
            guard let self else { return }
            if let result {
                self.addFiles([result], open: false)
                self.selectedFile = self.files.first?.id
                self.showNotice(String(localized: "Hazır: \(result.lastPathComponent)"))
            } else {
                self.showNotice(String(localized: "Bu dosyayla yapılamadı."))
            }
        }
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
        if !NSWorkspace.shared.open(item.url) { showNotice(String(localized: "Dosya bulunamadı. Rafa yeniden ekleyebilirsin.")) }
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
    static let focusMinutes = 1...240
    func setFocus(minutes: Int, phase: FocusSession.Phase = .focus) {
        session.reset(minutes: min(max(minutes, Self.focusMinutes.lowerBound), Self.focusMinutes.upperBound), phase: phase); saveSession()
    }
    /// Scrolling on the ring: a minute at a time, only while the timer is stopped.
    func adjustFocus(by minutes: Int) {
        guard !session.running, minutes != 0 else { return }
        setFocus(minutes: Int(session.duration / 60) + minutes, phase: session.phase)
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
