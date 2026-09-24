import AppKit
import SwiftUI

/// A regular macOS settings window: toolbar tabs, grouped forms, system controls. It lives outside the
/// notch so the panel stays a glanceable surface and settings get room to explain themselves.
final class SettingsWindowController: NSWindowController {
    private let model: AppState
    private let tabs: NSTabViewController

    init(model: AppState) {
        self.model = model
        tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.allowUserInteraction, .crossfade]
        func tab<Content: View>(_ title: String, _ symbol: String, _ content: Content) -> NSTabViewItem {
            let host = NSHostingController(rootView: content.formStyle(.grouped).frame(width: 500).fixedSize(horizontal: false, vertical: true))
            host.sizingOptions = .preferredContentSize
            host.title = title   // the tab controller hands it to the window title
            let item = NSTabViewItem(viewController: host)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            return item
        }
        tabs.addTabViewItem(tab("Genel", "gearshape", GeneralSettings(model: model)))
        tabs.addTabViewItem(tab("Ekran", "display", DisplaySettings(model: model, keys: model.keys)))
        tabs.addTabViewItem(tab("Medya", "music.note", MediaSettings(media: model.media)))
        tabs.addTabViewItem(tab("Ajanlar", "sparkles", AgentSettings(agents: model.agents)))
        tabs.addTabViewItem(tab("Hakkında", "info.circle", AboutSettings(updater: model.updater)))
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
                    Toggle(isOn: $media.handoffEnabled) {
                        Text("Video başlayınca müziği duraklat")
                        Text("Tarayıcıda ya da başka bir oynatıcıda bir şey çalmaya başlayınca Apple Music ve Spotify duraklar; o durunca müzik kaldığı yerden devam eder.")
                    }
                } footer: {
                    Text("İlk seferde macOS, Damla’nın Müzik veya Spotify’ı kontrol etmesi için izin ister.")
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
                    Button("Çık") { NSApp.terminate(nil) }
                } label: {
                    Text("Damla’dan çık")
                }
            }
        }
    }
}
