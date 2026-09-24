import SwiftUI
import AppKit
import CoreAudio

/// How loud each source is: the system volume and one level per player Damla can reach. Opened from the level
/// on Özet; lives inside the panel (no popover over a screen-saver-level window).
struct MixerView: View {
    @ObservedObject var model: AppState
    @ObservedObject var media: MediaService
    @ObservedObject var apps: AppVolumeController
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaneHeader(title: Text("Ses seviyesi")) { withAnimation(Theme.quick) { model.homePane = .player } }
            ScrollView {
                VStack(spacing: 7) {
                    MixerRow(icon: Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill"), name: String(localized: "Sistem"),
                             value: Double(model.volume ?? 0) * 100) { SystemMonitor.setVolume(Float($0 / 100)) }
                    ForEach(media.scriptablePlayers, id: \.self) { id in
                        MixerRow(icon: MediaService.icon(for: id).map { Image(nsImage: $0) } ?? Image(systemName: "music.note"),
                                 name: MediaService.appName(for: id), value: media.appVolumes[id] ?? 0) { media.setAppVolume(id, $0) }
                            .opacity(media.appVolumes[id] == nil ? 0.5 : 1)
                    }
                    ForEach(apps.apps) { app in
                        MixerRow(icon: MediaService.icon(for: app.id).map { Image(nsImage: $0) } ?? Image(systemName: "app"),
                                 name: app.name, value: apps.level(app.id)) { apps.setLevel(app.id, $0) }
                            .opacity(app.playing ? 1 : 0.6)
                    }
                    if apps.permissionDenied {
                        Button { AppVolumeController.openPermissionSettings() } label: {
                            Label("Uygulama sesleri için “Sistem sesi kaydı” izni gerekli · ayarları aç", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.amber).lineLimit(2)
                        }.buttonStyle(.plain)
                    }
                    if media.scriptablePlayers.isEmpty && apps.apps.isEmpty {
                        Text("Ses çalan uygulamalar burada görünür; her birinin sesini ayrı ayarlayabilirsin.")
                            .font(.system(size: 10.5)).foregroundStyle(Theme.faint).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .onAppear { media.refreshAppVolumes(); apps.setWatching(true) }
        .onDisappear { apps.setWatching(false) }
    }
}

struct MixerRow: View {
    let icon: Image
    let name: String
    let value: Double          // 0–100
    let onChange: (Double) -> Void
    var body: some View {
        HStack(spacing: 9) {
            icon.resizable().scaledToFit().frame(width: 16, height: 16).foregroundStyle(Theme.dim)
            Text(name).font(.system(size: 11, weight: .medium)).lineLimit(1).frame(width: 100, alignment: .leading)
            LevelSlider(value: value, onChange: onChange)
            Text("\(Int(value.rounded()))").font(.system(size: 10, weight: .medium, design: .rounded)).monospacedDigit()
                .foregroundStyle(Theme.faint).frame(width: 24, alignment: .trailing)
        }
        .frame(height: 22)
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

/// Where sound goes: every output device, the current one marked; a tap switches and returns to the player.
struct OutputsView: View {
    @ObservedObject var model: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaneHeader(title: Text("Ses çıkışı")) { withAnimation(Theme.quick) { model.homePane = .player } }
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(model.outputs) { output in
                        let chosen = output.id == model.currentOutput
                        Button {
                            AudioOutputs.setDefault(output.id)
                            withAnimation(Theme.quick) { model.homePane = .player }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: output.icon).font(.system(size: 13, weight: .medium)).frame(width: 20)
                                    .foregroundStyle(chosen ? Theme.accent : Theme.dim)
                                Text(output.name).font(.system(size: 11.5, weight: chosen ? .semibold : .medium)).lineLimit(1)
                                Spacer(minLength: 6)
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
        }
    }
}

/// Title and close button shared by the panes that replace the player on Özet.
struct PaneHeader: View {
    let title: Text
    let close: () -> Void
    var body: some View {
        HStack {
            title.font(.system(size: 15, weight: .semibold)).lineLimit(1)
            Spacer()
            IconButton(icon: "xmark", label: "Kapat", size: 24, action: close)
        }
    }
}

/// Lyrics the way Apple Music shows them: big bold lines, the sung one bright and held a third of the way down,
/// the rest dimmed and softly blurred the further they are. Scrolling by hand pauses the follow for a few
/// seconds; tapping a line jumps the song there. The panel grows down for it (see AppState.tallPanel).
struct LyricsView: View {
    @ObservedObject var model: AppState
    @ObservedObject var media: MediaService
    @ObservedObject var lyrics: LyricsService
    @State private var followPausedUntil = Date.distantPast
    private var tint: Color { media.accent.map { Color(nsColor: $0) } ?? .white }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Artwork(image: media.artwork, placeholder: "music.note", size: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: media.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(verbatim: media.artist).font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(1)
                }
                Spacer(minLength: 6)
                IconButton(icon: "xmark", label: "Kapat", size: 24) { withAnimation(Theme.quick) { model.homePane = .player } }
            }
            Group {
                if !lyrics.lyrics.lines.isEmpty { synced }
                else if !lyrics.lyrics.plain.isEmpty || lyrics.lyrics.instrumental { plain }
                else {
                    // Still looking, or nothing to show: say so instead of an empty panel.
                    VStack(spacing: 8) {
                        Image(systemName: lyrics.state == .loading ? "text.magnifyingglass" : "text.quote").font(.system(size: 24, weight: .light))
                        Text(lyrics.state == .loading ? "Sözler aranıyor…" : "Bu şarkının sözü bulunamadı").font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Theme.faint)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 10) {
                small("backward.fill", "Önceki") { media.command("previous track") }
                Button { media.command("playpause") } label: {
                    Image(systemName: media.playing ? "pause.fill" : "play.fill").font(.system(size: 12.5, weight: .bold))
                        .frame(width: 30, height: 30).contentShape(Circle()).contentTransition(.symbolEffect(.replace))
                }.buttonStyle(GlassCircleStyle()).help(media.playing ? "Duraklat" : "Oynat")
                small("forward.fill", "Sonraki") { media.command("next track") }
                ScrubBar(position: media.livePosition(at: model.now), duration: media.duration, tint: tint) { media.seek($0) }
                    .padding(.leading, 4)
            }
            .frame(height: 32)
        }
    }

    private var synced: some View {
        let lines = lyrics.lyrics.lines
        let current = lyrics.lyrics.index(at: media.livePosition(at: model.now))
        let following = model.now >= followPausedUntil
        return ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 13) {
                    Color.clear.frame(height: 24)
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
                guard let line, Date() >= followPausedUntil else { return }
                withAnimation(.spring(duration: 0.65, bounce: 0.12)) { reader.scrollTo(line, anchor: UnitPoint(x: 0, y: 0.3)) }
            }
            .onChange(of: following) { _, resumed in
                if resumed, let current { withAnimation(.spring(duration: 0.65, bounce: 0.12)) { reader.scrollTo(current, anchor: UnitPoint(x: 0, y: 0.3)) } }
            }
            .onAppear {
                MediaService.trace("lyrics view: \(lines.count) lines, current=\(current.map(String.init) ?? "nil"), state=\(lyrics.state)")
                if let current { reader.scrollTo(current, anchor: UnitPoint(x: 0, y: 0.3)) }
            }
        }
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

    private func small(_ icon: String, _ label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 26, height: 26).contentShape(Circle())
        }.buttonStyle(GlassCircleStyle()).help(label)
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
