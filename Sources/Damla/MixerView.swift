import SwiftUI
import CoreAudio

/// Where sound goes and how loud each source is: the output device, the system volume, and one level per
/// player Damla can reach. Opened from the volume reading on Özet; lives inside the panel (no popover over
/// a screen-saver-level window).
struct MixerView: View {
    @ObservedObject var model: AppState
    @ObservedObject var media: MediaService
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Ses").font(.system(size: 15, weight: .semibold))
                Spacer()
                Menu {
                    ForEach(model.outputs) { output in
                        Button { AudioOutputs.setDefault(output.id) } label: {
                            Label(output.name, systemImage: output.id == model.currentOutput ? "checkmark" : output.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: current?.icon ?? "speaker.wave.2").font(.system(size: 10, weight: .semibold))
                        Text(current?.name ?? "Çıkış").font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 7.5, weight: .bold)).foregroundStyle(Theme.faint)
                    }
                    .foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 5)
                    .glassLook(AnyShape(Capsule()))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Ses çıkışı")
                IconButton(icon: "xmark", label: "Kapat", size: 24) { withAnimation(Theme.quick) { model.mixerVisible = false } }
            }
            ScrollView {
                VStack(spacing: 7) {
                    MixerRow(icon: Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill"), name: "Sistem",
                             value: Double(model.volume ?? 0) * 100) { SystemMonitor.setVolume(Float($0 / 100)) }
                    ForEach(media.scriptablePlayers, id: \.self) { id in
                        MixerRow(icon: MediaService.icon(for: id).map { Image(nsImage: $0) } ?? Image(systemName: "music.note"),
                                 name: MediaService.appName(for: id), value: media.appVolumes[id] ?? 0) { media.setAppVolume(id, $0) }
                            .opacity(media.appVolumes[id] == nil ? 0.5 : 1)
                    }
                    if media.scriptablePlayers.isEmpty {
                        Text("Apple Music veya Spotify açıkken burada kendi ses ayarları görünür.")
                            .font(.system(size: 10.5)).foregroundStyle(Theme.faint).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .onAppear { media.refreshAppVolumes() }
    }
    private var current: AudioOutput? { model.outputs.first { $0.id == model.currentOutput } }
}

struct MixerRow: View {
    let icon: Image
    let name: String
    let value: Double          // 0–100
    let onChange: (Double) -> Void
    var body: some View {
        HStack(spacing: 9) {
            icon.resizable().scaledToFit().frame(width: 16, height: 16).foregroundStyle(Theme.dim)
            Text(name).font(.system(size: 11, weight: .medium)).lineLimit(1).frame(width: 78, alignment: .leading)
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
