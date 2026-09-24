import AppKit
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
        func tab<Content: View>(_ title: String, _ symbol: String, _ content: Content) -> NSTabViewItem {
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

private struct GeneralSettings: View {
    @ObservedObject var model: AppState
    var body: some View {
        Form {
            Section {
                Toggle("İmleç çentiğe gelince aç", isOn: $model.automaticOpen)
                    .onChange(of: model.automaticOpen) { _, _ in model.savePreferences() }
                Toggle("Girişte başlat", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                Toggle(isOn: Binding(get: { model.clipboardEnabled }, set: { model.toggleClipboard($0) })) {
                    Text("Pano geçmişini tut")
                    Text("Kopyaladığın metin ve görseller Pano sekmesinde listelenir. Parola yöneticilerinden gelenler atlanır.")
                }
            }
            Section("Kısayol") {
                LabeledContent("Paneli aç veya kapat") {
                    Text("⌃ ⌥ Space").font(.system(.body, design: .rounded)).foregroundStyle(.secondary)
                }
            }
            Section {
                LabeledContent {
                    Button("Klavyeyi kilitle") { model.startCleaning() }
                } label: {
                    Text("Temizlik modu")
                    Text("Tüm klavyeler 60 saniye kilitlenir, fare çalışır. Çıkmak için Esc’yi 2 saniye basılı tut.")
                }
            }
        }
    }
}

private struct PanelSettings: View {
    @ObservedObject var model: AppState
    var body: some View {
        Form {
            Section {
                ForEach(PanelTab.allCases) { tab in
                    let on = model.enabledTabs.contains(tab)
                    Toggle(isOn: Binding(get: { on }, set: { model.setTab(tab, enabled: $0) })) {
                        Label {
                            Text(tab.rawValue)
                            Text(tab.summary)
                        } icon: {
                            Image(systemName: tab.icon)
                        }
                    }
                    .disabled(on && model.enabledTabs.count == 1)
                }
            } header: {
                Text("Sayfalar")
            } footer: {
                Text("Kapattığın sayfa panelin alt kapsülünden kalkar. En az bir sayfa açık kalır.")
            }
            Section {
                Toggle(isOn: $model.notchGestures) {
                    Text("Çentikte kaydırma")
                    Text("Çentiğin üzerinde yukarı/aşağı kaydırınca ses değişir; trackpad’de sola kaydırmak sonraki, sağa kaydırmak önceki parçaya geçer.")
                }
            } header: {
                Text("Hareketler")
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
                    ForEach(DisplayMode.allCases) { Text($0.rawValue).tag($0) }
                } label: {
                    Text("Gösterilen ekranlar")
                    Text(displayHint)
                }
                Picker(selection: $model.externalStyle) {
                    ForEach(ExternalStyle.allCases) { Text($0.rawValue).tag($0) }
                } label: {
                    Text("Çentiksiz ekranda")
                    Text(model.externalStyle == .menuBar ? "Menü çubuğuna çentik biçiminde oturur." : "Menü çubuğunun hemen altında yüzen bir hap.")
                }
            }
            .onChange(of: model.displayMode) { _, _ in model.savePreferences() }
            .onChange(of: model.externalStyle) { _, _ in model.savePreferences() }
            Section {
                Toggle(isOn: Binding(get: { model.hideSystemHUD }, set: { model.setHideSystemHUD($0) })) {
                    Text("Ses ve parlaklık göstergesini Damla çizsin")
                    Text("macOS’un ekran ortasındaki göstergesi yerine çentikte küçük bir gösterge çıkar. Erişilebilirlik izni ister.")
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
        case .all: return "Her ekranın üstünde ayrı bir çentik."
        case .followMouse: return "Yalnızca imlecin bulunduğu ekranda."
        case .notch: return "Yalnızca çentikli yerleşik ekranda."
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
                    Text(media.bridgeActive ? "Sistem · tüm oynatıcılar" : "Apple Music veya Spotify").foregroundStyle(.secondary)
                }
                if !media.bridgeActive {
                    Picker("Oynatıcı", selection: Binding(get: { media.source }, set: { media.connect($0) })) {
                        ForEach(MusicSource.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if media.connected { Button("Bağlantıyı kes") { media.disconnect() } }
                }
            } footer: {
                if media.bridgeActive {
                    Text("Müzik, Spotify, Safari, Chrome ve Şimdi Çalıyor’a bilgi veren her uygulama görünür. Birden fazlası çalıyorsa panelde ikonlarına dokunarak geçiş yapabilirsin.")
                }
            }
            if media.bridgeActive {
                Section {
                    Picker(selection: $media.handoffMode) {
                        ForEach(HandoffMode.allCases) { Text($0.title).tag($0) }
                    } label: {
                        Text("Video başlayınca müzik")
                        Text(media.handoffMode == .duck
                             ? "Apple Music ve Spotify’ın sesi %20’ye iner; video durunca yavaşça eski seviyesine döner."
                             : media.handoffMode == .pause
                             ? "Apple Music ve Spotify duraklar; video durunca kaldığı yerden devam eder."
                             : "Müziğe dokunulmaz.")
                    }
                } footer: {
                    Text("İlk seferde macOS, Damla’nın Müzik veya Spotify’ı kontrol etmesi için izin ister.")
                }
                Section {
                    Toggle(isOn: $lyrics.enabled) {
                        Text("Şarkı sözleri")
                        Text("Özet’te o an söylenen satır görünür; dokununca sözlerin tamamı akar.")
                    }
                } footer: {
                    Text("Sözler lrclib.net’ten gelir: çalan şarkının adı, sanatçısı, albümü ve süresi gönderilir, başka hiçbir şey gitmez. Bulunan sözler bu Mac’te saklanır. Tarayıcı videoları ve canlı yayınlar için sorgu yapılmaz.")
                }
            }
        }
    }
}

private struct AgentSettings: View {
    @ObservedObject var agents: AgentStatusService
    @State private var approvalHookInstalled = AgentSettings.checkApprovalHook()
    var body: some View {
        Form {
            Section {
                Toggle(isOn: $agents.approvalsEnabled) {
                    Text("İzinleri çentikten onayla")
                    Text("Claude Code bir komut veya dosya için izin isteyince çentik açılır; tam komutu görüp İzin ver ya da Reddet diyebilirsin.")
                }
                Picker("Bekleme süresi", selection: $agents.approvalWait) {
                    ForEach(AgentApprovals.waitChoices, id: \.self) { Text("\(Int($0)) sn").tag($0) }
                }
                .disabled(!agents.approvalsEnabled)
                LabeledContent("Onay hook’u") {
                    Text(approvalHookInstalled ? "Kurulu" : "Kurulu değil").foregroundStyle(approvalHookInstalled ? Color.secondary : Color.orange)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sorunun sahibi uygulama (Terminal, Claude…) öndeyse çentik sormaz; süre dolarsa veya terminalde yanıtlarsan soru orada kalır.")
                    if !approvalHookInstalled {
                        Text("Kurmak için: python3 scripts/install-agent-hooks.py --binary <Damla.app/Contents/MacOS/Damla> --approvals --apply")
                            .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }
            .onAppear { approvalHookInstalled = AgentSettings.checkApprovalHook() }
            Section {
                Toggle(isOn: $agents.soundEnabled) {
                    Text("Onay beklerken ses çal")
                    Text("Claude Code veya Codex senden izin beklediğinde kısa bir ses çıkar.")
                }
            } footer: {
                Text("Durumlar Claude Code ve Codex hook’larıyla gelir. Codex ilk bağlantıda /hooks üzerinden güven onayı ister.")
            }
        }
    }

    /// True when ~/.claude/settings.json runs Damla's approval hook.
    static func checkApprovalHook() -> Bool {
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: file), data.count < 4_000_000 else { return false }
        return String(decoding: data, as: UTF8.self).contains("--agent-approval")
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
                    Toggle(isOn: $updater.automaticChecks) {
                        Text("Güncellemeleri otomatik denetle")
                        Text("Günde bir kez GitHub’daki sürüm listesine bakar; sunucu yok, veri gönderilmez.")
                    }
                    LabeledContent {
                        Button(updater.availableVersion.map { "\($0) sürümünü yükle" } ?? "Şimdi denetle") { updater.checkForUpdates() }
                    } label: {
                        Text(updater.availableVersion == nil ? "Güncel" : "Yeni sürüm hazır")
                    }
                }
            }
            Section {
                LabeledContent {
                    Button("Tanıtımı göster", action: showTour)
                } label: {
                    Text("İlk açılış rehberi")
                    Text("İzinleri ve ajan bağlantısını adım adım yeniden kur.")
                }
            }
            Section {
                LabeledContent {
                    Button("Çık") { NSApp.terminate(nil) }
                } label: {
                    Text("Damla’dan çık")
                }
            }
        }
    }
}
