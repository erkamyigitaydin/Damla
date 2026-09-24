import AppKit
import SwiftUI

/// The tour's current page, owned by the window so it can be opened on a given step.
final class OnboardingState: ObservableObject { @Published var page = 0 }

/// First-run tour: what Damla does and, one step at a time, the permissions each part needs, each with its
/// current state and a button that asks for it. Opens by itself only on a fresh install; the menu bar item and
/// Ayarlar → Hakkında open it again.
final class OnboardingWindowController: NSWindowController {
    static let doneKey = "onboardingDone"
    private let state = OnboardingState()

    /// A fresh install: nothing of Damla's is stored yet (an upgrade from an older version skips the tour).
    static var shouldShowOnLaunch: Bool {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return false }
        let stored = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        return stored.keys.allSatisfy { $0.hasPrefix("NS") || $0.hasPrefix("SU") || $0 == doneKey }
    }

    init(model: AppState) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 470), styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: OnboardingView(model: model, keys: model.keys, state: state) { [weak self] in
            UserDefaults.standard.set(true, forKey: Self.doneKey)
            self?.close()
        }.frame(width: 540, height: 470))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func present(page: Int? = nil) {
        if let page { state.page = min(max(0, page), 4) } else if window?.isVisible != true { state.page = 0 }
        if window?.isVisible != true { window?.center() }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

/// Whether Damla may send Apple Events to an app (Music, Spotify), without asking unless `ask` is set.
enum AutomationPermission {
    enum State { case granted, denied, notAsked, notRunning }

    static func state(_ bundleID: String, ask: Bool) -> State {
        var target = AEAddressDesc()
        let bytes = Array(bundleID.utf8)
        AECreateDesc(DescType(typeApplicationBundleID), bytes, bytes.count, &target)
        defer { AEDisposeDesc(&target) }
        switch AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask) {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(procNotFound): return .notRunning
        default: return .notAsked
        }
    }
}

private struct OnboardingView: View {
    @ObservedObject var model: AppState
    @ObservedObject var keys: MediaKeyInterceptor
    @ObservedObject var state: OnboardingState
    let finish: () -> Void
    private var page: Int {
        get { state.page }
        nonmutating set { state.page = newValue }
    }
    @State private var music: AutomationPermission.State = .notAsked
    @State private var hookState: [HookInstaller.Provider: Bool] = [:]
    @State private var approvals = true
    @State private var hookError: String?
    private let pages = 5

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0: welcome
                case 1: media
                case 2: keysPage
                case 3: agents
                default: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 36).padding(.top, 44)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            .id(page)
            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<pages, id: \.self) { index in
                        Circle().fill(index == page ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 6, height: 6)
                    }
                }
                Spacer()
                if page > 0 { Button("Geri") { withAnimation(.snappy) { page -= 1 } }.keyboardShortcut(.cancelAction) }
                Button(page == pages - 1 ? "Başla" : "İleri") {
                    if page == pages - 1 { finish() } else { withAnimation(.snappy) { page += 1 } }
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24).padding(.vertical, 18)
        }
        .onAppear(perform: refresh)
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in refresh() }
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
            Text("Damla’ya hoş geldin").font(.largeTitle.weight(.semibold))
            Text("Damla çentikte yaşar. İmleci çentiğe getir ya da ⌃⌥Space’e bas.").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                feature("music.note", "Şimdi çalan her şey", "Müzik, Spotify, tarayıcılar; birden fazla kaynak arasında geçiş")
                feature("slider.horizontal.3", "Ses", "Çıkış seçimi ve her uygulama için ayrı ses seviyesi")
                feature("tray", "Raf ve pano", "Dosyaları çentiğe bırak, kopyaladıklarına geri dön")
                feature("terminal", "Ajanlar", "Claude Code ve Codex ne yapıyor, izinleri çentikten onayla")
            }.padding(.top, 6)
        }
    }

    private var media: some View {
        page(icon: "music.note", title: "Müzik", text: "Şimdi çalan bilgisi izin istemez. Video başlayınca müziği duraklatmak ve Apple Music’in sesini ayarlamak için Damla’nın Müzik’i kontrol etmesine izin vermen gerekir.") {
            status(model.media.bridgeActive, "Şimdi Çalıyor köprüsü çalışıyor", "Şimdi Çalıyor köprüsü kullanılamıyor; Apple Events yedeği devrede")
            HStack {
                status(music == .granted, "Müzik’i kontrol izni verildi", music == .denied ? "İzin reddedildi · Sistem Ayarları → Gizlilik → Otomasyon" : "Müzik’i kontrol izni henüz verilmedi")
                Spacer()
                if music != .granted {
                    Button(music == .denied ? "Ayarları aç" : "İzin ver") {
                        if music == .denied {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                        } else {
                            askMusic()
                        }
                    }
                    .help("Müzik açık değilse önce açılır")
                }
            }
        }
    }

    private var keysPage: some View {
        page(icon: "speaker.wave.2", title: "Ses ve parlaklık", text: "İstersen ses ve parlaklık tuşlarına basınca macOS’un ekran ortasındaki göstergesi yerine çentikte küçük bir gösterge çıkar. Bunun için Erişilebilirlik izni gerekir; istemezsen bu adımı geçebilirsin.") {
            Toggle("Göstergeyi Damla çizsin", isOn: Binding(get: { model.hideSystemHUD }, set: { model.setHideSystemHUD($0) }))
            if model.hideSystemHUD {
                HStack {
                    status(keys.active, "Erişilebilirlik izni verildi", "Erişilebilirlik izni bekleniyor")
                    Spacer()
                    if !keys.active { Button("Ayarları aç") { MediaKeyInterceptor.openAccessibilitySettings() } }
                }
            }
        }
    }

    private var agents: some View {
        page(icon: "terminal", title: "Ajanlar", text: "Claude Code ve Codex’in ne yaptığını çentikte görmek için Damla onların ayar dosyasına küçük bir durum bildirimi ekler. Yalnızca Damla’nın kayıtlarına dokunulur, önce yedek alınır.") {
            ForEach(HookInstaller.Provider.allCases, id: \.self) { provider in
                let name = provider == .claude ? "Claude Code" : "Codex"
                HStack {
                    if HookInstaller.isAvailable(provider) {
                        status(hookState[provider] == true, "\(name) bağlı", "\(name) bağlı değil")
                        Spacer()
                        Button(hookState[provider] == true ? "Güncelle" : "Bağla") { install(provider) }
                    } else {
                        Label("\(name) bu Mac’te kurulu görünmüyor", systemImage: "minus.circle").foregroundStyle(.secondary)
                    }
                }
            }
            Toggle("Claude Code’un izin sorularını çentikten yanıtla", isOn: $approvals)
                .help("Terminal öndeyken çentik sormaz; süre dolarsa soru terminalde kalır.")
            if let hookError { Label(hookError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout) }
            Text("Codex, yeni hook’lara /hooks içinde güven onayı verilene kadar çalıştırmaz.").font(.callout).foregroundStyle(.secondary)
        }
    }

    private var done: some View {
        page(icon: "checkmark.circle", title: "Hazır", text: "Her şeyi Ayarlar’dan değiştirebilirsin: çentikteki dişli, menü çubuğundaki damla ya da ⌘,.") {
            Toggle("Girişte başlat", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            Toggle("İmleç çentiğe gelince aç", isOn: $model.automaticOpen).onChange(of: model.automaticOpen) { _, _ in model.savePreferences() }
        }
    }

    // MARK: Pieces

    private func page<Content: View>(icon: String, title: String, text: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon).font(.system(size: 34, weight: .light)).foregroundStyle(Color.accentColor).frame(height: 44)
            Text(title).font(.title.weight(.semibold))
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10, content: content).padding(.top, 6)
        }
    }

    private func feature(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Color.accentColor).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func status(_ ok: Bool, _ yes: String, _ no: String) -> some View {
        Label(ok ? yes : no, systemImage: ok ? "checkmark.circle.fill" : "circle.dashed")
            .foregroundStyle(ok ? Color.green : Color.secondary)
    }

    private func refresh() {
        for provider in HookInstaller.Provider.allCases { hookState[provider] = HookInstaller.isInstalled(provider) }
        DispatchQueue.global().async {
            let result = AutomationPermission.state(MusicSource.music.bundleID, ask: false)
            DispatchQueue.main.async { if result != .notRunning || music == .notAsked { music = result == .notRunning ? music : result } }
        }
    }

    /// macOS only asks about a running app: start Music in the background first when it is closed.
    private func askMusic() {
        let id = MusicSource.music.bundleID
        func ask() {
            DispatchQueue.global().async {
                let result = AutomationPermission.state(id, ask: true)
                DispatchQueue.main.async { music = result }
            }
        }
        guard !MediaService.isRunning(id), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { ask(); return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { ask() }
        }
    }

    private func install(_ provider: HookInstaller.Provider) {
        do {
            try HookInstaller.install(provider, approvals: approvals && provider == .claude)
            hookError = nil
        } catch {
            hookError = "Kurulamadı: \(error)"
        }
        refresh()
    }
}
