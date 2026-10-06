import AppKit
import Carbon
import SwiftUI

/// A regular macOS settings window: toolbar tabs, grouped forms, system controls. It lives outside the
/// notch so the panel stays a glanceable surface and settings get room to explain themselves.
final class SettingsWindowController: NSWindowController {
    /// One size for every tab. Letting each tab report its own height made the window show the new page at the
    /// old size and snap ~0.6 s later; a fixed size never resizes, and a longer page scrolls inside itself.
    static let contentSize = NSSize(width: 500, height: 420)
    private let model: AppState
    private let tabs: NSTabViewController

    init(model: AppState) {
        self.model = model
        tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.allowUserInteraction, .crossfade]
        func tab<Content: View>(_ title: String.LocalizationValue, _ symbol: String, _ content: Content) -> NSTabViewItem {
            let title = String(localized: title)
            let size = SettingsWindowController.contentSize
            let host = NSHostingController(rootView: content.formStyle(.grouped).frame(width: size.width, height: size.height))
            host.sizingOptions = []
            host.preferredContentSize = size
            host.title = title   // the tab controller hands it to the window title
            let item = NSTabViewItem(viewController: host)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            return item
        }
        tabs.addTabViewItem(tab("Genel", "gearshape", GeneralSettings(model: model)))
        tabs.addTabViewItem(tab("Panel", "rectangle.topthird.inset.filled", PanelSettings(model: model)))
        tabs.addTabViewItem(tab("Ekran", "display", DisplaySettings(model: model, keys: model.keys)))
        tabs.addTabViewItem(tab("Medya", "music.note", MediaSettings(media: model.media, lyrics: model.lyrics)))
        tabs.addTabViewItem(tab("Ajanlar", "sparkles", AgentSettings(agents: model.agents)))
        tabs.addTabViewItem(tab("Hakkında", "info.circle", AboutSettings(updater: model.updater) { [weak model] in model?.presentOnboarding?() }))
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("DamlaSettings")
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Opens on Genel unless a tab is asked for; an already open window keeps the tab the user is on.
    func present(tab: Int? = nil) {
        if let tab { tabs.selectedTabViewItemIndex = min(max(0, tab), tabs.tabViewItems.count - 1) }
        else if window?.isVisible != true { tabs.selectedTabViewItemIndex = 0 }
        if window?.isVisible != true, UserDefaults.standard.string(forKey: "NSWindow Frame DamlaSettings") == nil { window?.center() }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()   // an accessory app's activation request can be declined; still show it
    }
}

// MARK: - Tabs
// Every row says what it does in its title; a subtitle is kept only where the user must know something the
// title cannot say (privacy, a permission, how to get out).

private struct GeneralSettings: View {
    @ObservedObject var model: AppState
    @State private var language = AppLanguage.current
    @State private var restartNeeded = AppLanguage.pendingRestart
    var body: some View {
        Form {
            Section {
                Picker("Çentiği aç", selection: $model.automaticOpen) {
                    Text("Üzerine gelince").tag(true)
                    Text("Tıklayınca").tag(false)
                }
                .onChange(of: model.automaticOpen) { _, _ in model.savePreferences() }
                if model.automaticOpen {
                    Picker("Bekleme", selection: $model.hoverDelay) {
                        ForEach(HoverDelay.allCases) { Text($0.title).tag($0) }
                    }
                }
                Toggle("Girişte başlat", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                Picker("Dil", selection: $language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: language) { _, picked in AppLanguage.set(picked); restartNeeded = AppLanguage.pendingRestart }
                if restartNeeded {
                    LabeledContent("Yeni dil yeniden açılınca gelir") { Button("Yeniden başlat") { AppLanguage.relaunch() } }
                }
            }
            MeetingSettings(model: model, calendar: model.calendar)
            NotificationSettings(mirror: model.notifications)
            Section("Kısayollar") {
                PanelShortcutRow(model: model)
                shortcut("Onayda izin ver · reddet", "⌃ ⌥ ↩ · ⌃ ⌥ ⌫")
            }
            Section {
                LabeledContent {
                    Button("Klavyeyi kilitle") { model.startCleaning() }
                } label: {
                    Text("Temizlik modu")
                    Text("60 saniye; çıkmak için Esc’yi 2 saniye basılı tut.")
                }
            }
        }
    }
    private func shortcut(_ title: LocalizedStringKey, _ keys: String) -> some View {
        LabeledContent(title) { Text(verbatim: keys).font(.system(.body, design: .rounded)).foregroundStyle(.secondary) }
    }
}

private struct PanelSettings: View {
    @ObservedObject var model: AppState
    @AppStorage(PolaroidCard.datedKey) private var polaroidDate = true
    var body: some View {
        Form {
            // The pill's pages in its order, then the ones switched off (Bildirimler too while notifications are off).
            let shown = model.visibleTabs
            Section {
                ForEach(shown) { tab in TabOrderRow(tab: tab, model: model) }
            } header: {
                HStack {
                    Text("Çentikte")
                    Spacer()
                    if shown != PanelTab.allCases.filter(shown.contains) {
                        Button("Varsayılan sıra") { withAnimation { model.resetTabOrder() } }
                            .buttonStyle(.link).font(.caption)
                    }
                }
            } footer: {
                Text("Sıralamak için sürükle.").font(.caption).foregroundStyle(.secondary)
            }
            let off = model.tabOrder.filter { !shown.contains($0) }
            if !off.isEmpty {
                // "Kapalı" alone is the muted microphone's label, "Muted" in English.
                Section(String(localized: "Kapalı sayfalar", defaultValue: "Kapalı")) {
                    ForEach(off) { tab in TabOrderRow(tab: tab, model: model) }
                }
            }
            Section("Dosyalar ve Pano") {
                Toggle("Ekran görüntüleri rafa düşsün", isOn: $model.screenshotsToShelf)
                Toggle(isOn: Binding(get: { model.clipboardEnabled }, set: { model.toggleClipboard($0) })) {
                    Text("Pano geçmişini tut")
                    Text("Parola yöneticilerinden gelenler kaydedilmez.")
                }
            }
            Section("Ayna") {
                Toggle("Polaroide tarih yaz", isOn: $polaroidDate)
            }
            Section("Hareketler") {
                Toggle("Trackpad’de iki parmakla sayfa değiştir", isOn: $model.notchGestures)
            }
        }
    }
}

private struct DisplaySettings: View {
    @ObservedObject var model: AppState
    @ObservedObject var keys: MediaKeyInterceptor
    var body: some View {
        Form {
            Section {
                Picker(selection: $model.displayMode) {
                    ForEach(DisplayMode.allCases) { Text($0.title).tag($0) }
                } label: {
                    Text("Gösterilen ekranlar")
                    Text(displayHint)
                }
                Picker(selection: $model.externalStyle) {
                    ForEach(ExternalStyle.allCases) { Text($0.title).tag($0) }
                } label: {
                    Text("Çentiksiz ekranda")
                    Text(model.externalStyle == .menuBar ? "Menü çubuğuna oturur." as LocalizedStringKey : "Menü çubuğunun altında yüzer.")
                }
                Toggle(isOn: $model.hideIdleNotch) {
                    Text("Boştayken çakma çentiği gizle")
                    Text("Bir şey çalmıyor, ajan çalışmıyorsa çentiksiz ekranda görünmez. İmleci götürünce açılır.")
                }
            }
            .onChange(of: model.displayMode) { _, _ in model.savePreferences() }
            .onChange(of: model.externalStyle) { _, _ in model.savePreferences() }
            Section {
                Toggle(isOn: Binding(get: { model.hideSystemHUD }, set: { model.setHideSystemHUD($0) })) {
                    Text("Ses ve parlaklık göstergesi çentikte")
                    Text("Erişilebilirlik izni ister.")
                }
                if model.hideSystemHUD && !keys.active {
                    LabeledContent {
                        Button("Ayarları aç") { MediaKeyInterceptor.openAccessibilitySettings() }
                    } label: {
                        Label("Erişilebilirlik izni bekleniyor", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
            }
        }
    }
    private var displayHint: String {
        switch model.displayMode {
        case .all: return String(localized: "Her ekranın üstünde ayrı bir çentik.")
        case .followMouse: return String(localized: "Yalnızca imlecin bulunduğu ekranda.")
        case .notch: return String(localized: "Yalnızca çentikli yerleşik ekranda.")
        }
    }
}

private struct MediaSettings: View {
    @ObservedObject var media: MediaService
    @ObservedObject var lyrics: LyricsService
    var body: some View {
        Form {
            Section {
                LabeledContent("Kaynak") {
                    Text(media.bridgeActive ? "Tüm oynatıcılar" : "Apple Music veya Spotify").foregroundStyle(.secondary)
                }
                if !media.bridgeActive {
                    Picker("Oynatıcı", selection: Binding(get: { media.source }, set: { media.connect($0) })) {
                        ForEach(MusicSource.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if media.connected { Button("Bağlantıyı kes") { media.disconnect() } }
                }
            }
            if media.bridgeActive {
                Section {
                    Picker(selection: $media.handoffMode) {
                        ForEach(HandoffMode.allCases) { Text($0.title).tag($0) }
                    } label: {
                        Text("Video başlayınca müzik")
                        Text(media.handoffMode == .duck ? "Ses kısılır, video bitince geri gelir."
                             : media.handoffMode == .pause ? "Duraklar, video bitince kaldığı yerden devam eder." : "Müziğe dokunulmaz.")
                    }
                    Toggle(isOn: $lyrics.enabled) {
                        Text("Şarkı sözleri")
                        Text("lrclib.net’e yalnızca şarkı adı, sanatçı, albüm ve süre gider.")
                    }
                }
            }
        }
    }
}

/// Calendar countdown and the microphone slot, in General.
private struct MeetingSettings: View {
    @ObservedObject var model: AppState
    @ObservedObject var calendar: CalendarService
    var body: some View {
        Section("Takvim ve görüşmeler") {
            Toggle(isOn: $calendar.enabled) {
                Text("Sıradaki toplantı")
                Text("10 dakika kala geri sayım, bağlantısı varsa tek tıkla katıl. Takvim bu Mac’te kalır.")
            }
            if calendar.enabled && (calendar.access == .denied || calendar.access == .restricted) {
                LabeledContent {
                    Button("Ayarları aç") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") { NSWorkspace.shared.open(url) }
                    }
                } label: {
                    Label("Takvim izni kapalı", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            Toggle("Kullanımdaki mikrofonu göster", isOn: $model.micInNotch)
        }
    }
}

private struct AgentSettings: View {
    @ObservedObject var agents: AgentStatusService
    @State private var approvalHooks = AgentSettings.checkApprovalHooks()
    @State private var codexTrusted = HookInstaller.codexApprovalTrusted()
    @State private var installError: String?
    var body: some View {
        Form {
            Section {
                Toggle(isOn: $agents.approvalsEnabled) {
                    Text("İzinleri çentikten yanıtla")
                    Text("Sorunun sahibi uygulama öndeyse çentik sormaz.")
                }
                Picker("Bekleme süresi", selection: $agents.approvalWait) {
                    ForEach(AgentApprovals.waitChoices, id: \.self) { Text("\(Int($0)) sn").tag($0) }
                }
                .disabled(!agents.approvalsEnabled)
                Toggle("Onay beklerken ses çal", isOn: $agents.soundEnabled)
            } header: {
                Text("Onaylar")
            }
            Section {
                ForEach(HookInstaller.Provider.allCases.filter { HookInstaller.isAvailable($0) }, id: \.self) { provider in
                    let installed = approvalHooks.contains(provider)
                    let untrusted = installed && provider == .codex && codexTrusted == false
                    LabeledContent(provider == .claude ? "Claude Code" : "Codex") {
                        HStack {
                            Text(untrusted ? "Codex’te /hooks ile güven ver" : installed ? "Bağlı" : "Bağlı değil")
                                .foregroundStyle(installed && !untrusted ? Color.secondary : Color.orange)
                            if !installed { Button("Bağla") { installApprovalHook(provider) } }
                        }
                    }
                }
                if let installError { Text(installError).foregroundStyle(.orange) }
            } header: {
                Text("Bağlantı")
            } footer: {
                Text("Codex’te onaylar terminaldeki Codex CLI’de çalışır; ChatGPT uygulamasının soruları kendi penceresinde yanıtlanır.")
            }
            .onAppear { approvalHooks = AgentSettings.checkApprovalHooks(); codexTrusted = HookInstaller.codexApprovalTrusted() }
        }
    }

    /// Adds the status and approval hooks to the agent's settings; the installer keeps a backup.
    private func installApprovalHook(_ provider: HookInstaller.Provider) {
        do {
            try HookInstaller.install(provider, approvals: true)
            installError = nil
        } catch {
            installError = String(localized: "Kurulamadı: \(String(describing: error))")
        }
        approvalHooks = AgentSettings.checkApprovalHooks(); codexTrusted = HookInstaller.codexApprovalTrusted()
    }

    /// The agents whose settings run Damla's approval hook.
    static func checkApprovalHooks() -> Set<HookInstaller.Provider> {
        Set(HookInstaller.Provider.allCases.filter { HookInstaller.isInstalled($0, approvals: true) })
    }
}

private struct AboutSettings: View {
    @ObservedObject var updater: UpdateService
    let showTour: () -> Void
    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Damla").font(.title3.weight(.semibold))
                        Text("Sürüm \(updater.currentVersion)").foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            if updater.isConfigured {
                Section {
                    Toggle("Güncellemeleri otomatik denetle", isOn: $updater.automaticChecks)
                    LabeledContent {
                        Button(updater.availableVersion.map { "\($0) sürümünü yükle" } ?? "Şimdi denetle") { updater.checkForUpdates() }
                    } label: {
                        Text(updater.availableVersion == nil ? "Güncel" : "Yeni sürüm hazır")
                    }
                }
            }
            Section {
                LabeledContent("İlk açılış rehberi") { Button("Tanıtımı göster", action: showTour) }
                LabeledContent("Damla’dan çık") { Button("Çık") { NSApp.terminate(nil) } }
            }
        }
    }
}

/// The language Damla shows: the Mac's own, or one picked here (stored as the app's AppleLanguages).
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, tr, en
    var id: String { rawValue }
    var title: String {
        switch self { case .system: return String(localized: "Sistem"); case .tr: return "Türkçe"; case .en: return "English" }
    }
    static var current: AppLanguage {
        guard let saved = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String],
              let first = saved.first else { return .system }
        return first.hasPrefix("tr") ? .tr : .en
    }
    /// Set once a different language is picked, until Damla restarts.
    nonisolated(unsafe) static var pendingRestart = false
    static func set(_ language: AppLanguage) {
        guard language != current else { return }
        if language == .system { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
        else { UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages") }
        pendingRestart = true
    }
    /// Opens a fresh copy of Damla and quits this one.
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

/// Other apps' notifications in the notch; read from Notification Center with the Accessibility permission.
/// Off, nothing is read and the Bildirimler page leaves the pill (the page itself is switched in Panel → Sayfalar).
private struct NotificationSettings: View {
    @ObservedObject var mirror: NotificationMirror
    var body: some View {
        Section("Bildirimler") {
            Toggle(isOn: $mirror.enabled) {
                Text("Bildirimler çentikte")
                Text("Kart olarak çentikten iner; tıkla: ilgili yerde açılır, düğmeleri ve yanıt çentikte. Kapalıyken Damla bildirimlere hiç dokunmaz.")
            }
            if mirror.enabled {
                Toggle("Sistem balonunu gizle", isOn: $mirror.hideBanners)
                if !mirror.trusted {
                    LabeledContent {
                        Button("Ayarları aç") { MediaKeyInterceptor.openAccessibilitySettings() }
                    } label: {
                        Label("Erişilebilirlik izni bekleniyor", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
            }
        }
    }
}

/// One page in Settings → Panel. Under Çentikte it is dragged by its row to a new place in the pill and switched
/// off into Kapalı; switched on from Kapalı, it joins the end of the pill.
private struct TabOrderRow: View {
    let tab: PanelTab
    @ObservedObject var model: AppState
    @State private var targeted = false
    var body: some View {
        if model.visibleTabs.contains(tab) {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                    .help("Sıralamak için sürükle")
                toggle(shown: true)
            }
            .contentShape(Rectangle())
            .draggable(tab.rawValue) {
                Label(tab.title, systemImage: tab.icon).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
            }
            .dropDestination(for: String.self) { items, _ in
                guard let dragged = items.first.flatMap(PanelTab.init(rawValue:)), model.visibleTabs.contains(dragged) else { return false }
                withAnimation(.snappy(duration: 0.25)) { model.moveTab(dragged, to: tab) }
                return true
            } isTargeted: { targeted = $0 }
            .overlay {
                // The page it takes the place of (it lands before it moving up, after it moving down).
                if targeted {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 1.5).padding(-4).allowsHitTesting(false)
                }
            }
        } else {
            toggle(shown: false)
        }
    }
    private func toggle(shown: Bool) -> some View {
        let unavailable = tab == .notifications && !model.notifications.enabled   // its own switch is in Genel
        return Toggle(isOn: Binding(get: { shown }, set: { on in withAnimation(.snappy(duration: 0.25)) { model.setTab(tab, enabled: on) } })) {
            Label(tab.title, systemImage: tab.icon)
            if unavailable { Text("Bildirimler kapalı; Genel’den aç.") }
        }
        .disabled(unavailable || (shown && model.visibleTabs.count == 1))   // one page always stays
    }
}

/// Settings → Kısayollar: the panel's shortcut on a key cap. Clicking it listens for the next combination with
/// ⌘, ⌃ or ⌥; Esc, a second click or leaving the window gives up and keeps the old one.
private struct PanelShortcutRow: View {
    @ObservedObject var model: AppState
    @State private var monitor: Any?
    @State private var held = ""                  // modifiers down while listening, shown on the cap
    @State private var refused: HotKey.Problem?
    var body: some View {
        let recording = model.recordingHotKey
        LabeledContent {
            HStack(spacing: 10) {
                if model.panelHotKey != .panelDefault && !recording {
                    Button("Varsayılana dön") { model.panelHotKey = .panelDefault }.buttonStyle(.link)
                }
                Button { recording ? stop() : start() } label: {
                    Text(verbatim: recording ? (held.isEmpty ? "…" : held) : model.panelHotKey.display)
                        .font(.system(.body, design: .rounded)).frame(minWidth: 84)
                }
                .overlay {
                    if recording { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 2).allowsHitTesting(false) }
                }
                .help("Yeni kısayol için tıkla")
            }
        } label: {
            Text("Paneli aç veya kapat")
            if recording {
                Text(refused == .reserved ? "⌃ ⌥ ↩ ve ⌃ ⌥ ⌫ onaylar için ayrılmış." as LocalizedStringKey
                     : refused == .needsModifier ? "⌘, ⌃ ya da ⌥ ile birlikte bas." : "Yeni kısayola bas; Esc vazgeçer.")
            } else if model.hotKeyTaken {
                Text("Başka bir uygulama bu kısayolu kullanıyor; başka birini seç.").foregroundStyle(.orange)
            }
        }
        .onDisappear { stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in stop() }
    }

    private func start() {
        refused = nil; held = ""
        model.recordingHotKey = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                held = HotKey.symbols(HotKey.carbonModifiers(event.modifierFlags)).joined(separator: " ")
                return event
            }
            if event.keyCode == UInt16(kVK_Escape) { stop(); return nil }
            let key = HotKey(keyCode: UInt32(event.keyCode), modifiers: HotKey.carbonModifiers(event.modifierFlags))
            if let problem = key.problem { refused = problem } else { model.panelHotKey = key; stop() }
            return nil   // nothing typed while listening reaches the window (⌘W must not close it)
        }
    }
    /// Also clears a flag left on without its monitor, so the panel key and the notch's Esc always come back.
    private func stop() {
        guard monitor != nil || model.recordingHotKey else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil; held = ""
        model.recordingHotKey = false
    }
}
