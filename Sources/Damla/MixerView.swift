import SwiftUI
import AppKit
import CoreAudio

/// The Ses page: the system level, then one level per source Damla can reach: Music and Spotify over Apple
/// Events, any other app through a process tap, and under a browser each tab that plays, through the page's own
/// media elements. The output sits in the header; a tap on it lists the outputs in place. The same view is the
/// pane Özet's level capsule opens when the page is switched off.
struct SoundView: View {
    @ObservedObject var model: AppState
    @ObservedObject var media: MediaService
    @ObservedObject var apps: AppVolumeController
    @ObservedObject var tabs: BrowserTabVolumes
    /// Opened from Özet: a back arrow leads to the player.
    var asPane = false
    @State private var choosingOutput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PageHeader(title: Text(choosingOutput ? String(localized: "Ses çıkışı") : PanelTab.sound.title), back: back) {
                if !choosingOutput { outputChip }
            }
            if choosingOutput {
                OutputList(model: model) { withAnimation(Theme.quick) { choosingOutput = false } }
                    .transition(.opacity)
            } else {
                levels.transition(.opacity)
            }
        }
        .onAppear { media.refreshAppVolumes(); apps.setWatching(true); tabs.setWatching(true); tabs.watch(apps.apps.map(\.id)) }
        .onDisappear { apps.setWatching(false); tabs.setWatching(false) }
        .onChange(of: apps.apps) { _, found in tabs.watch(found.map(\.id)) }
    }

    private var back: (() -> Void)? {
        guard asPane || choosingOutput else { return nil }
        return { withAnimation(Theme.quick) { if choosingOutput { choosingOutput = false } else { model.homePane = .player } } }
    }

    /// The current output, short ("Hoparlör", "AirPods Pro"); a tap shows every output to pick from.
    private var outputChip: some View {
        let output = model.outputs.first { $0.id == model.currentOutput }
        return Button { withAnimation(Theme.quick) { choosingOutput = true } } label: {
            HStack(spacing: 5) {
                Image(systemName: output?.icon ?? "hifispeaker").font(.system(size: 10, weight: .semibold))
                Text(output.map { AudioOutput.shortName($0.name, transport: $0.transport) } ?? String(localized: "Ses çıkışı"))
                    .font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 7.5, weight: .bold)).foregroundStyle(Theme.dim)
            }
            .foregroundStyle(.white).padding(.leading, 9).padding(.trailing, 8).frame(height: 24).frame(maxWidth: 150)
            .glassLook(AnyShape(Capsule()))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(Text("Ses çıkışı: \(output?.name ?? "—") · değiştir"))
    }

    private var levels: some View {
        ScrollView {
            VStack(spacing: 7) {
                SoundRow(icon: .symbol(model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill"), name: String(localized: "Sistem"),
                         value: model.muted ? 0 : Double(model.volume ?? 0) * 100,
                         onChange: { level in
                             SystemMonitor.setVolume(Float(level / 100))
                             if model.muted && level > 0 { SystemMonitor.setMute(false) }
                         },
                         onMute: { SystemMonitor.setMute(!model.muted) })
                ForEach(media.scriptablePlayers, id: \.self) { id in
                    SoundRow(icon: .app(id), name: MediaService.appName(for: id), value: media.appVolumes[id] ?? 0,
                             onChange: { media.setAppVolume(id, $0) }, onMute: { media.toggleAppMute(id) })
                        .opacity(media.appVolumes[id] == nil ? 0.5 : 1)
                }
                ForEach(apps.apps) { app in
                    SoundRow(icon: .app(app.id), name: app.name, quiet: !app.playing, value: apps.level(app.id),
                             onChange: { apps.setLevel(app.id, $0) }, onMute: { apps.toggleMute(app.id) })
                    ForEach(tabs.tabs[app.id] ?? []) { tab in
                        SoundRow(icon: .symbol("globe"), name: tab.title.isEmpty ? tab.host : tab.title, indent: true, value: tab.volume,
                                 onChange: { tabs.setVolume(tab, $0) }, onMute: { tabs.toggleMute(tab) })
                            .help(Text(verbatim: tab.title.isEmpty ? tab.host : "\(tab.host) · \(tab.title)"))
                    }
                    if tabs.javaScriptOff.contains(app.id) && !tabs.dismissed.contains(app.id) {
                        // Optional, and said so: the browser's own switch comes with the browser's own warning.
                        hint(Text("Sekme sesleri isteğe bağlı: \(shortName(app.id)) bir kez izin ister ve bir onay kutusu gösterir."),
                             action: Text("Aç"), secondary: Text("Gerek yok"),
                             perform: { tabs.enableJavaScript(app.id) }, dismiss: { withAnimation(Theme.quick) { tabs.dismiss(app.id) } })
                            .help(Text("\(shortName(app.id)) → \(BrowserTabVolumes.menuPath(app.id))"))
                    }
                    if tabs.automationDenied.contains(app.id) {
                        hint(Text("\(shortName(app.id)) için otomasyon izni kapalı · Sistem Ayarları → Gizlilik → Otomasyon"), action: Text("Ayarlar")) {
                            BrowserTabVolumes.openAutomationSettings()
                        }
                    }
                }
                if apps.permissionDenied {
                    Button { AppVolumeController.openPermissionSettings() } label: {
                        Label("Uygulama sesleri için “Sistem sesi kaydı” izni gerekli · ayarları aç", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.amber).lineLimit(2)
                    }.buttonStyle(.plain)
                }
                if media.scriptablePlayers.isEmpty && apps.apps.isEmpty {
                    Text("Ses çalan uygulamalar ve tarayıcı sekmeleri burada görünür; her birinin sesini ayrı ayarlayabilirsin.")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.faint).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }
            }
            .animation(Theme.quick, value: apps.apps)
            .animation(Theme.quick, value: tabs.tabs)
        }
        .scrollIndicators(.hidden)
    }

    /// "Chrome" rather than "Google Chrome": it has to fit a line.
    private func shortName(_ bundleID: String) -> String {
        let name = MediaService.appName(for: bundleID)
        return name.hasPrefix("Google ") ? String(name.dropFirst(7)) : name.hasPrefix("Microsoft ") ? String(name.dropFirst(10)) : name
    }

    /// A one-time setup step under a browser's row, with the button that takes care of it and, for an optional
    /// step, a quiet way to wave it off.
    private func hint(_ text: Text, action: Text, secondary: Text? = nil, perform: @escaping () -> Void, dismiss: (() -> Void)? = nil) -> some View {
        HStack(spacing: 7) {
            Image(systemName: secondary == nil ? "exclamationmark.triangle.fill" : "info.circle.fill").font(.system(size: 9.5, weight: .semibold))
            text.font(.system(size: 10, weight: .medium)).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 3) {
                Button(action: perform) { action.font(.system(size: 10, weight: .semibold)) }.buttonStyle(PillStyle())
                if let secondary, let dismiss {
                    Button(action: dismiss) { secondary.font(.system(size: 9.5, weight: .medium)).foregroundStyle(Theme.dim) }.buttonStyle(.plain)
                }
            }
        }
        .foregroundStyle(secondary == nil ? Theme.amber : Theme.dim)
        .padding(.leading, 14)
    }
}

/// One level: the source's icon (a tap mutes it and brings it back), its name, the slider and the number. A tab
/// row sits indented under its browser; the name column shrinks by the indent so the sliders stay in one column.
struct SoundRow: View {
    enum Icon { case symbol(String), app(String) }
    let icon: Icon
    let name: String
    var indent = false
    /// The app is open but silent right now.
    var quiet = false
    let value: Double          // 0–100
    let onChange: (Double) -> Void
    let onMute: () -> Void
    @State private var hoveringIcon = false

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onMute) {
                iconView
                    .frame(width: 16, height: 16)
                    .opacity(value <= 0 ? 0.35 : 1)
                    .padding(3)
                    .background(Circle().fill(Theme.fillStrong).opacity(hoveringIcon ? 1 : 0))
                    .padding(-3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoveringIcon = $0 }
            .animation(.easeOut(duration: 0.12), value: hoveringIcon)
            .help(value <= 0 ? "Sesi aç" : "Sessize al")
            .accessibilityLabel(Text(value <= 0 ? "Sesi aç" : "Sessize al"))
            .padding(.leading, indent ? 14 : 0)
            Text(name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                .foregroundStyle(quiet ? Theme.dim : .white)
                .frame(width: indent ? 86 : 100, alignment: .leading)
            LevelSlider(value: value, onChange: onChange)
            Text("\(Int(value.rounded()))").font(.system(size: 10, weight: .medium, design: .rounded)).monospacedDigit()
                .foregroundStyle(Theme.faint).frame(width: 24, alignment: .trailing)
        }
        .frame(height: 22)
    }

    @ViewBuilder private var iconView: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name).font(.system(size: indent ? 11 : 13, weight: .medium)).foregroundStyle(Theme.dim)
        case .app(let bundleID):
            if let image = MediaService.icon(for: bundleID) { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "app").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.dim) }
        }
    }
}

/// A 0–100 level in the panel's own style (NSSlider ignores the tint in this non-key panel).
struct LevelSlider: View {
    let value: Double
    let onChange: (Double) -> Void
    @State private var dragging: Double?
    @State private var hovering = false
    var body: some View {
        GeometryReader { g in
            let shown = dragging ?? value
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16))
                Capsule().fill(Theme.accent).frame(width: max(0, g.size.width * min(1, max(0, shown / 100))))
            }
            .frame(height: hovering || dragging != nil ? 6 : 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let level = Double(min(max(0, drag.location.x / g.size.width), 1)) * 100
                    dragging = level; onChange(level)
                }
                .onEnded { _ in dragging = nil })
        }
        .frame(height: 16)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Where sound goes, as a pane on Özet: every output device, the current one marked; a tap switches and
/// returns to the player.
struct OutputsView: View {
    @ObservedObject var model: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaneHeader(title: Text("Ses çıkışı")) { withAnimation(Theme.quick) { model.homePane = .player } }
            OutputList(model: model) { withAnimation(Theme.quick) { model.homePane = .player } }
        }
    }
}

/// The output devices, the current one marked (with its battery when it is Bluetooth); a tap switches and
/// calls `picked`.
struct OutputList: View {
    @ObservedObject var model: AppState
    let picked: () -> Void
    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(model.outputs) { output in
                    let chosen = output.id == model.currentOutput
                    Button {
                        AudioOutputs.setDefault(output.id)
                        picked()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: output.icon).font(.system(size: 13, weight: .medium)).frame(width: 20)
                                .foregroundStyle(chosen ? Theme.accent : Theme.dim)
                            Text(output.name).font(.system(size: 11.5, weight: chosen ? .semibold : .medium)).lineLimit(1)
                            Spacer(minLength: 6)
                            if output.isBluetooth, let battery = model.outputBatteries[output.name] {
                                BatteryLabel(levels: battery)
                            }
                            if chosen { Image(systemName: "checkmark").font(.system(size: 10.5, weight: .bold)).foregroundStyle(Theme.accent) }
                        }
                        .padding(.horizontal, 10).frame(height: 32)
                        .background(chosen ? Theme.fillStrong : Theme.fill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
        .onAppear { model.refreshOutputBatteries() }
    }
}

/// "S %80 · Sa %75 · K %60" beside a Bluetooth output; turns orange when a bud or the case is nearly empty.
struct BatteryLabel: View {
    let levels: BluetoothBattery.Levels
    var body: some View {
        let low = (levels.lowest ?? 100) <= 20
        HStack(spacing: 4) {
            Image(systemName: low ? "battery.25percent" : "battery.75percent").font(.system(size: 10, weight: .medium))
            Text(levels.summary).font(.system(size: 10.5, weight: .medium, design: .rounded)).monospacedDigit()
        }
        .foregroundStyle(low ? Color.orange : Theme.dim)
        .lineLimit(1).fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// Title and close button shared by the panes that replace the player on Özet.
/// The player's sub-views (levels, outputs, sources) lead back to it from the same corner as every other page.
struct PaneHeader: View {
    let title: Text
    let close: () -> Void
    var body: some View { PageHeader(title: title, back: close) }
}

/// Lyrics the way Apple Music shows them, flowing under the player in lyrics mode: big bold lines, the sung one
/// bright and held a third of the way down, the rest dimmed and softly blurred the further they are. Scrolling by
/// hand pauses the follow for a few seconds; tapping a line jumps the song there.
struct LyricsFlow: View {
    @ObservedObject var model: AppState
    @ObservedObject var media: MediaService
    @ObservedObject var lyrics: LyricsService
    @State private var followPausedUntil = Date.distantPast

    var body: some View {
        Group {
            if !lyrics.lyrics.lines.isEmpty { synced }
            else if !lyrics.lyrics.plain.isEmpty || lyrics.lyrics.instrumental { plain }
            else if lyrics.state == .failed {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.bubble").font(.system(size: 22, weight: .light))
                    Text("Sözler yüklenemedi").font(.system(size: 13, weight: .medium))
                    Button { lyrics.retry() } label: {
                        Label("Tekrar dene", systemImage: "arrow.clockwise").font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(PillStyle())
                }
                .foregroundStyle(Theme.dim)
            }
            else {
                // Still looking, or nothing to show: say so instead of an empty panel.
                VStack(spacing: 8) {
                    let searching = lyrics.state == .loading || lyrics.state == .idle
                    Image(systemName: searching ? "text.magnifyingglass" : "text.quote").font(.system(size: 22, weight: .light))
                    Text(searching ? "Sözler aranıyor…" : "Bu şarkının sözü bulunamadı").font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Theme.faint)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var synced: some View {
        let lines = lyrics.lyrics.lines
        let current = lyrics.lyrics.index(at: media.livePosition(at: model.now))
        let following = model.now >= followPausedUntil
        return ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 13) {
                    Color.clear.frame(height: 24).id(-1)   // the top, for the moments before the first line
                    ForEach(lines.indices, id: \.self) { index in
                        LyricLineView(text: lines[index].text,
                                      role: index == current ? .current : (current.map { index < $0 } ?? false) ? .past : .upcoming,
                                      distance: abs(index - (current ?? 0)), blurred: following)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture { media.seek(lines[index].time + 0.05); followPausedUntil = .distantPast }
                    }
                    Color.clear.frame(height: 150)
                }
            }
            .scrollIndicators(.hidden)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.1),
                                         .init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .onScrollPhaseChange { _, phase in
                // Only the user's own scrolling pauses the follow, not our animated scrollTo.
                if phase == .interacting || phase == .decelerating { followPausedUntil = Date().addingTimeInterval(3) }
            }
            .onChange(of: current) { _, line in
                guard Date() >= followPausedUntil else { return }
                // Before the first line (a new song, a seek back to the start): back to the top.
                withAnimation(.spring(duration: 0.65, bounce: 0.12)) {
                    if let line { reader.scrollTo(line, anchor: UnitPoint(x: 0, y: 0.3)) } else { reader.scrollTo(-1, anchor: .top) }
                }
            }
            .onChange(of: following) { _, resumed in
                if resumed, let current { withAnimation(.spring(duration: 0.65, bounce: 0.12)) { reader.scrollTo(current, anchor: UnitPoint(x: 0, y: 0.3)) } }
            }
            .onAppear {
                if let current { reader.scrollTo(current, anchor: UnitPoint(x: 0, y: 0.3)) }
            }
        }
        // Rows are keyed by index, so without this a new song would inherit the old one's scroll position.
        .id("\(media.title)|\(media.artist)|\(lines.count)")
    }

    private var plain: some View {
        ScrollView {
            Group {
                if lyrics.lyrics.instrumental {
                    Label("Enstrümantal", systemImage: "music.note").font(.system(size: 20, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                } else {
                    Text(verbatim: lyrics.lyrics.plain).font(.system(size: 16, weight: .semibold)).lineSpacing(5)
                        .foregroundStyle(.white.opacity(0.85)).textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
        }.scrollIndicators(.hidden)
    }
}

/// One lyric line: bright and full size while sung, dim before and after, blurred a little more with distance.
/// An empty line is an instrumental gap and shows three breathing dots.
struct LyricLineView: View {
    enum Role { case past, current, upcoming }
    let text: String
    let role: Role
    let distance: Int
    let blurred: Bool
    var body: some View {
        Group {
            if text.isEmpty {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { dot in
                        Circle().frame(width: 7, height: 7)
                            .phaseAnimator(role == .current ? [0.35, 1] : [0.35]) { view, phase in view.opacity(phase) } animation: { _ in
                                .easeInOut(duration: 0.6).delay(Double(dot) * 0.2)
                            }
                    }
                }
                .frame(height: 24)
            } else {
                Text(verbatim: text).font(.system(size: 21, weight: .bold)).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white.opacity(role == .current ? 1 : role == .past ? 0.3 : 0.45))
        .scaleEffect(role == .current ? 1 : 0.965, anchor: .leading)
        .blur(radius: blurred && role != .current ? min(Double(distance) * 0.55, 2.4) : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.35), value: role)
        .animation(.easeOut(duration: 0.35), value: blurred)
    }
}

/// Every player Damla knows, to switch between: the shown one marked, playing ones with a moving equalizer.
struct SourcesView: View {
    @ObservedObject var model: AppState
    @ObservedObject var media: MediaService
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaneHeader(title: Text("Kaynaklar")) { withAnimation(Theme.quick) { model.homePane = .player } }
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(media.sessions) { session in
                        let shown = session.bundleID == media.sourceBundleID
                        let live = media.isLive(session)
                        HStack(spacing: 10) {
                            Button {
                                media.select(session.bundleID)
                                withAnimation(Theme.quick) { model.homePane = .player }
                            } label: {
                                HStack(spacing: 10) {
                                    ZStack {
                                        if let art = session.artwork {
                                            Image(nsImage: art).resizable().scaledToFill().frame(width: 30, height: 30)
                                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                        } else {
                                            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.fill).frame(width: 30, height: 30)
                                        }
                                        if let icon = MediaService.icon(for: session.bundleID) {
                                            Image(nsImage: icon).resizable().frame(width: 14, height: 14).offset(x: 12, y: 12)
                                        }
                                    }
                                    .frame(width: 34, height: 34)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(session.title.isEmpty ? MediaService.appName(for: session.bundleID) : session.title)
                                            .font(.system(size: 11.5, weight: shown ? .semibold : .medium)).lineLimit(1)
                                        Text(live ? session.artist : String(localized: "\(MediaService.appName(for: session.bundleID)) · arka planda"))
                                            .font(.system(size: 10)).foregroundStyle(Theme.dim).lineLimit(1)
                                    }
                                    Spacer(minLength: 6)
                                    if session.playing && live {
                                        Equalizer(playing: true, color: Theme.accent)
                                    } else if shown {
                                        Image(systemName: "checkmark").font(.system(size: 10.5, weight: .bold)).foregroundStyle(Theme.accent)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            IconButton(icon: "arrow.up.forward.app", label: "\(MediaService.appName(for: session.bundleID)) uygulamasını aç", size: 24) {
                                NSWorkspace.shared.urlForApplication(withBundleIdentifier: session.bundleID).map {
                                    NSWorkspace.shared.openApplication(at: $0, configuration: NSWorkspace.OpenConfiguration())
                                }
                            }
                        }
                        .padding(.horizontal, 8).frame(height: 44)
                        .background(shown ? Theme.fillStrong : Theme.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}
