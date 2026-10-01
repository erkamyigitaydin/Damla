import AppKit
import AVFoundation
import EventKit
import SwiftUI

/// The first-run tour, told inside the notch itself: each step opens the page it is about, draws that page as
/// a shimmering placeholder, says what it does in a line or two and, where a part needs one, asks for its
/// permission right there. It replaces a separate tour window.
enum TourStep: Int, CaseIterable {
    case welcome, permissions, media, sound, files, notifications, agents, mirror, pages, done

    static let doneKey = "onboardingDone"

    /// A fresh install: nothing of Damla's is stored yet (an upgrade from an older version skips the tour).
    static var shouldShowOnLaunch: Bool {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return false }
        let stored = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        return stored.keys.allSatisfy { $0.hasPrefix("NS") || $0.hasPrefix("SU") || $0 == doneKey }
    }

    /// The page the tab pill points at during this step.
    var tab: PanelTab {
        switch self {
        case .files: return .files
        case .notifications: return .notifications
        case .agents: return .agents
        case .mirror: return .mirror
        default: return .home
        }
    }
    var title: String {
        switch self {
        case .welcome: return String(localized: "Damla’ya hoş geldin")
        case .permissions: return String(localized: "İzinler")
        case .notifications: return String(localized: "Bildirimler")
        case .media: return String(localized: "Şimdi çalan")
        case .sound: return String(localized: "Ses")
        case .files: return String(localized: "Raf")
        case .agents: return String(localized: "Ajanlar")
        case .mirror: return String(localized: "Ayna")
        case .pages: return String(localized: "Sayfalar")
        case .done: return String(localized: "Hazırsın")
        }
    }
    var text: String {
        switch self {
        case .welcome: return String(localized: "Çentikte yaşar. İmleci çentiğe getir ya da ⌃⌥Space’e bas.")
        case .permissions: return String(localized: "Hepsi isteğe bağlı; vermediğin izin yalnızca o özelliği kapatır. Sonra Ayarlar’dan da verebilirsin.")
        case .notifications: return String(localized: "Gelen bildirim çentikte görünür. Tıkla: yanıtla ya da düğmesine bas. Kaçırdıkların Bildirimler sayfasında.")
        case .media: return String(localized: "Müzik, Spotify, tarayıcılar: çalan ne varsa burada. Video başlayınca müziği duraklatmak için izin ver.")
        case .sound: return String(localized: "Çıkışı değiştir, her uygulamanın sesini ayrı ayarla. Ses tuşlarının göstergesi de çentikte olabilir.")
        case .files: return String(localized: "Bir dosyayı sürüklemeye başla, çentik açılır. Bırak, sonra istediğin yere taşı.")
        case .agents: return String(localized: "Claude Code ve Codex ne yapıyor gör, izin sorularını buradan yanıtla.")
        case .mirror: return String(localized: "Görüşmeden önce kendine bak, anlık fotoğraf çek. Kamera yalnızca bu sayfada çalışır.")
        case .pages: return String(localized: "Alttaki kapsül sayfalar arasında geçer: pano, odak, kestirmeler. Ayarlar’dan açıp kapat.")
        case .done: return String(localized: "Her şeyi Ayarlar’dan değiştirebilirsin: dişli, menü çubuğundaki damla ya da ⌘,.")
        }
    }
}

struct TourView: View {
    let step: TourStep
    @ObservedObject var model: AppState
    @ObservedObject var keys: MediaKeyInterceptor
    @State private var music: AutomationPermission.State = .notAsked
    @State private var hooks: Set<HookInstaller.Provider> = []

    var body: some View {
        HStack(spacing: 18) {
            if step != .permissions {
                TourPlaceholder(step: step)
                    .frame(width: 132, height: 132)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(step.title).font(.system(size: 15, weight: .semibold))
                if step == .permissions {
                    PermissionList(model: model, keys: keys)
                } else {
                    Text(step.text).font(.system(size: 11)).foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true).lineLimit(3)
                    action.padding(.top, 2)
                }
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    ForEach(TourStep.allCases, id: \.rawValue) { item in
                        Capsule().fill(item == step ? Theme.accent : Theme.fillStrong)
                            .frame(width: item == step ? 14 : 5, height: 5)
                    }
                    Spacer()
                    if step != .done {
                        Button("Geç") { model.endTour() }.buttonStyle(.plain)
                            .font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.faint)
                    }
                    Button(step == .done ? "Başla" : "İleri") { model.advanceTour() }
                        .font(.system(size: 11, weight: .semibold)).buttonStyle(PillStyle(accent: true))
                }
                .animation(.snappy, value: step)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onAppear(perform: refresh)
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in refresh() }
    }

    /// The one thing this step may need from the user, with its state.
    @ViewBuilder private var action: some View {
        switch step {
        case .media:
            if model.media.bridgeActive || music != .notRunning {
                permission(music == .granted, done: "Müzik’i kontrol edebilir", ask: music == .denied ? "Ayarları aç" : "İzin ver") {
                    if music == .denied { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!) }
                    else { AutomationPermission.askMusic { music = $0 } }
                }
            }
        case .sound:
            if model.hideSystemHUD {
                permission(keys.active, done: "Gösterge çentikte", ask: "Erişilebilirlik izni") { Permissions.askAccessibility() }
            } else {
                Button("Göstergeyi çentiğe al") { model.setHideSystemHUD(true) }
                    .font(.system(size: 10.5, weight: .medium)).buttonStyle(PillStyle())
            }
        case .agents:
            let available = HookInstaller.Provider.allCases.filter { HookInstaller.isAvailable($0) }
            if available.isEmpty {
                Text("Claude Code ya da Codex kurulunca Ayarlar → Ajanlar’dan bağlanır.").font(.system(size: 10)).foregroundStyle(Theme.faint)
            } else {
                HStack(spacing: 6) {
                    ForEach(available, id: \.self) { provider in
                        let name = provider == .claude ? "Claude Code" : "Codex"
                        if hooks.contains(provider) {
                            Label(name, systemImage: "checkmark.circle.fill").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.green)
                        } else {
                            Button(provider == .claude ? String(localized: "Claude Code’u bağla") : String(localized: "Codex’i bağla")) {
                                try? HookInstaller.install(provider, approvals: true)
                                refresh()
                            }
                            .font(.system(size: 10.5, weight: .medium)).buttonStyle(PillStyle())
                        }
                    }
                }
            }
        case .notifications:
            if model.notifications.trusted {
                switchRow("Bildirimler çentikte", isOn: Binding(get: { model.notifications.enabled }, set: { model.notifications.enabled = $0 }))
            } else {
                permission(false, done: "", ask: "Erişilebilirlik izni") { Permissions.askAccessibility() }
            }
        case .mirror:
            Button("Dene") { model.endTour(); model.select(.mirror) }
                .font(.system(size: 10.5, weight: .medium)).buttonStyle(PillStyle())
        case .done:
            switchRow("Girişte başlat", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
        default:
            EmptyView()
        }
    }

    /// The panel's own switch (the system one turns grey inside the notch) with its label beside it.
    private func switchRow(_ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Toggle(title, isOn: isOn).toggleStyle(GlassSwitchStyle()).labelsHidden()
            Text(title).font(.system(size: 10.5, weight: .medium))
                .onTapGesture { isOn.wrappedValue.toggle() }
        }
    }

    private func permission(_ granted: Bool, done: LocalizedStringKey, ask: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Group {
            if granted {
                Label(done, systemImage: "checkmark.circle.fill").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.green)
            } else {
                Button(ask, action: action).font(.system(size: 10.5, weight: .medium)).buttonStyle(PillStyle())
            }
        }
    }

    private func refresh() {
        hooks = Set(HookInstaller.Provider.allCases.filter { HookInstaller.isInstalled($0, approvals: true) })
        guard step == .media else { return }
        DispatchQueue.global().async {
            let result = AutomationPermission.state(MusicSource.music.bundleID, ask: false)
            DispatchQueue.main.async { if result != .notRunning || music == .notAsked { music = result } }
        }
    }
}

/// A sketch of the page a step is about, in grey placeholder shapes with a light sweeping across them.
private struct TourPlaceholder: View {
    let step: TourStep
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.fill)
            content.padding(14)
        }
        .shimmering()
        .id(step)
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            DropletMascot(phase: .done, size: 70)
        case .permissions:
            Image(systemName: "lock.shield").font(.system(size: 44, weight: .light)).foregroundStyle(Theme.dim)
        case .notifications:
            // A notification card under the notch, with a reply field.
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top, spacing: 7) {
                    bone(22, 22, radius: 6)
                    VStack(alignment: .leading, spacing: 4) { bone(30, 5); bone(52, 7); bone(70, 5) }
                }
                capsule(96, 16)
            }
        case .media:
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    bone(44, 44, radius: 10)
                    VStack(alignment: .leading, spacing: 5) { bone(48, 7); bone(32, 6) }
                }
                bone(104, 3)
                HStack(spacing: 8) { circle(16); circle(22); circle(16) }.frame(maxWidth: .infinity)
            }
        case .sound:
            VStack(spacing: 10) {
                HStack(spacing: 5) { capsule(46, 18); capsule(30, 18) }
                HStack(alignment: .bottom, spacing: 7) {
                    ForEach([0.5, 0.8, 0.35, 0.65], id: \.self) { level in
                        VStack(spacing: 4) { Capsule().fill(Self.boneColor).frame(width: 8, height: 48 * level); circle(10) }
                    }
                }
            }
        case .files:
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])).foregroundStyle(Theme.faint)
                HStack(spacing: 6) { tile(); tile(); tile() }
                Image(systemName: "arrow.down").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.dim).offset(y: -44)
            }
        case .agents:
            HStack(spacing: 8) {
                DropletMascot(phase: .working, size: 40)
                VStack(alignment: .leading, spacing: 5) { bone(44, 7); bone(56, 6); HStack(spacing: 4) { circle(9); circle(9); circle(9) } }
            }
        case .mirror:
            // A wide viewfinder with the date stamp, the shutter and the last photo in its corner.
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.1))
                .frame(width: 150, height: 66)
                .overlay(alignment: .bottomLeading) {
                    // The last print, a small wide instant-film card.
                    RoundedRectangle(cornerRadius: 1).fill(Color(red: 0.6, green: 0.58, blue: 0.55))
                        .frame(width: 22, height: 9)
                        .padding([.horizontal, .top], 1.5).padding(.bottom, 4.5)
                        .background(Color(red: 0.97, green: 0.95, blue: 0.9), in: RoundedRectangle(cornerRadius: 1))
                        .rotationEffect(.degrees(-4))
                        .padding(6)
                }
                .overlay(alignment: .bottom) { Circle().fill(.white.opacity(0.85)).frame(width: 14, height: 14).padding(.bottom, 6) }
                .overlay(alignment: .bottomTrailing) {
                    Text(verbatim: "’26 10 1").font(.system(size: 6.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(red: 1, green: 0.56, blue: 0.16)).padding(6)
                }
        case .pages:
            VStack(spacing: 10) {
                HStack(spacing: 7) {
                    ForEach([PanelTab.clipboard, .focus, .shortcuts], id: \.self) { tab in
                        Image(systemName: tab.icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.dim)
                    }
                }
                .padding(.horizontal, 10).frame(height: 26).background(Theme.fillStrong, in: Capsule())
                bone(70, 6)
            }
        case .done:
            Image(systemName: "checkmark").font(.system(size: 34, weight: .semibold)).foregroundStyle(Theme.accent)
        }
    }

    private static let boneColor = Color.white.opacity(0.24)
    private func bone(_ width: CGFloat, _ height: CGFloat, radius: CGFloat = 3) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Self.boneColor).frame(width: width, height: height)
    }
    private func circle(_ size: CGFloat) -> some View { Circle().fill(Self.boneColor).frame(width: size, height: size) }
    private func capsule(_ width: CGFloat, _ height: CGFloat) -> some View { Capsule().fill(Self.boneColor).frame(width: width, height: height) }
    private func tile() -> some View {
        VStack(spacing: 4) { bone(26, 22, radius: 5); bone(22, 4) }.padding(5).background(Theme.fill, in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(colors: [.clear, .white.opacity(0.10), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: proxy.size.width * 0.6)
                        .offset(x: phase * proxy.size.width * 1.3)
                        .blendMode(.plusLighter)
                }
                .mask(content)
                .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.8).delay(0.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}
private extension View { func shimmering() -> some View { modifier(Shimmer()) } }

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

    /// macOS only asks about a running app: start Music in the background first when it is closed.
    static func askMusic(_ completion: @escaping (State) -> Void) {
        let id = MusicSource.music.bundleID
        func ask() {
            DispatchQueue.global().async {
                let result = state(id, ask: true)
                DispatchQueue.main.async { completion(result) }
            }
        }
        guard !MediaService.isRunning(id), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { ask(); return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { ask() }
        }
    }
}

/// The permissions Damla can use, asked for in one place on the first run. Each is optional and turns on only
/// its own features; the list shows what is already granted.
enum Permissions {
    /// One permission behind three features: the volume and brightness indicator, video in the notch, notifications.
    static func askAccessibility() {
        if AXIsProcessTrusted() { return }
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
    static func openSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") { NSWorkspace.shared.open(url) }
    }
}

/// The İzinler step: one row per permission, with why it is needed and its state, granted ones ticked.
private struct PermissionList: View {
    @ObservedObject var model: AppState
    @ObservedObject var keys: MediaKeyInterceptor
    @ObservedObject private var calendar: CalendarService
    @State private var accessibility = AXIsProcessTrusted()
    @State private var camera = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var music: AutomationPermission.State = .notAsked

    init(model: AppState, keys: MediaKeyInterceptor) {
        self.model = model; self.keys = keys; calendar = model.calendar
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            row("accessibility", "Erişilebilirlik", "Ses göstergesi, video, bildirimler", granted: accessibility, denied: false) {
                Permissions.askAccessibility()
            }
            row("music.note", "Müzik", "Parçayı göster, oynatmayı yönet", granted: music == .granted, denied: music == .denied) {
                if music == .denied { Permissions.openSettings("Privacy_Automation") } else { AutomationPermission.askMusic { music = $0 } }
            }
            row("camera", "Kamera", "Ayna", granted: camera == .authorized, denied: camera == .denied || camera == .restricted) {
                if camera == .notDetermined {
                    AVCaptureDevice.requestAccess(for: .video) { _ in DispatchQueue.main.async { camera = AVCaptureDevice.authorizationStatus(for: .video) } }
                } else { Permissions.openSettings("Privacy_Camera") }
            }
            row("calendar", "Takvim", "Sıradaki toplantı ve katılma bağlantısı",
                granted: calendar.enabled && calendar.access == .fullAccess, denied: calendar.access == .denied || calendar.access == .restricted) {
                if calendar.access == .denied || calendar.access == .restricted { Permissions.openSettings("Privacy_Calendars") }
                else { calendar.enabled = true }   // turns the meetings on and asks
            }
        }
        .onAppear(perform: refresh)
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in refresh() }
    }

    private func row(_ icon: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey, granted: Bool, denied: Bool,
                     action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.dim).frame(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 11, weight: .semibold))
                Text(detail).font(.system(size: 9.5)).foregroundStyle(Theme.faint).lineLimit(1)
            }
            Spacer(minLength: 6)
            if granted {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(.green)
                    .help("İzin verildi")
            } else {
                Button(denied ? "Ayarları aç" : "İzin ver", action: action)
                    .font(.system(size: 10, weight: .medium)).buttonStyle(PillStyle())
            }
        }
        .frame(height: 24)
    }

    private func refresh() {
        accessibility = AXIsProcessTrusted()
        camera = AVCaptureDevice.authorizationStatus(for: .video)
        calendar.refresh()
        DispatchQueue.global().async {
            let result = AutomationPermission.state(MusicSource.music.bundleID, ask: false)
            DispatchQueue.main.async { if result != .notRunning || music == .notAsked { music = result } }
        }
    }
}
