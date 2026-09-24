import SwiftUI
import CoreAudio

/// How loud each source is: the system volume and one level per player Damla can reach. Opened from the level
/// on Özet; lives inside the panel (no popover over a screen-saver-level window).
struct MixerView: View {
    @ObservedObject var model: AppState
    @ObservedObject var media: MediaService
    @ObservedObject var apps: AppVolumeController
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaneHeader(title: "Ses seviyesi") { withAnimation(Theme.quick) { model.homePane = .player } }
            ScrollView {
                VStack(spacing: 7) {
                    MixerRow(icon: Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill"), name: "Sistem",
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
            PaneHeader(title: "Ses çıkışı") { withAnimation(Theme.quick) { model.homePane = .player } }
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
    let title: String
    let close: () -> Void
    var body: some View {
        HStack {
            Text(title).font(.system(size: 15, weight: .semibold))
            Spacer()
            IconButton(icon: "xmark", label: "Kapat", size: 24, action: close)
        }
    }
}
