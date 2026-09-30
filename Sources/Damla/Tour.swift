import AppKit
import SwiftUI

/// The first-run tour, told inside the notch itself: each step opens the page it is about, draws that page as
/// a shimmering placeholder, says what it does in a line or two and, where a part needs one, asks for its
/// permission right there. It replaces a separate tour window.
enum TourStep: Int, CaseIterable {
    case welcome, media, sound, files, agents, mirror, pages, done

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
        case .agents: return .agents
        case .mirror: return .mirror
        default: return .home
        }
    }
    var title: String {
        switch self {
        case .welcome: return String(localized: "Damla’ya hoş geldin")
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
            TourPlaceholder(step: step)
                .frame(width: 132, height: 132)
            VStack(alignment: .leading, spacing: 6) {
                Text(step.title).font(.system(size: 15, weight: .semibold))
                Text(step.text).font(.system(size: 11)).foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true).lineLimit(3)
                action.padding(.top, 2)
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
                permission(keys.active, done: "Gösterge çentikte", ask: "Erişilebilirlik izni") { MediaKeyInterceptor.openAccessibilitySettings() }
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
        case .mirror:
            Button("Dene") { model.endTour(); model.select(.mirror) }
                .font(.system(size: 10.5, weight: .medium)).buttonStyle(PillStyle())
        case .done:
            Toggle("Girişte başlat", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                .toggleStyle(.switch).controlSize(.mini).font(.system(size: 10.5, weight: .medium))
        default:
            EmptyView()
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
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color(red: 0.86, green: 0.84, blue: 0.8))
                        .frame(width: 16, height: 16)
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.white.opacity(0.8), lineWidth: 1))
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
