import SwiftUI

/// The user's Apple Shortcuts, run from the notch. Pinned ones sit on top as buttons; the full list (read from the
/// `shortcuts` command) lets you pin more.
final class ShortcutsService: ObservableObject {
    static let pinnedKey = "pinnedShortcuts"
    @Published private(set) var all: [String] = []
    @Published private(set) var loaded = false
    @Published private(set) var running: Set<String> = []
    @Published var pinned: [String] = UserDefaults.standard.stringArray(forKey: ShortcutsService.pinnedKey) ?? [] {
        didSet { UserDefaults.standard.set(pinned, forKey: Self.pinnedKey) }
    }
    /// A shortcut finished: name, succeeded.
    var onFinish: ((String, Bool) -> Void)?

    func load() {
        DispatchQueue.global(qos: .userInitiated).async {
            let names = Self.execute(["list"]).output
                .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            DispatchQueue.main.async {
                self.all = names
                self.loaded = true
                // A pinned shortcut that was renamed or deleted has nothing left to run.
                if !names.isEmpty { self.pinned.removeAll { !names.contains($0) } }
            }
        }
    }

    func togglePin(_ name: String) {
        if let index = pinned.firstIndex(of: name) { pinned.remove(at: index) } else { pinned.append(name) }
    }

    func run(_ name: String) {
        guard !running.contains(name) else { return }
        running.insert(name)
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = Self.execute(["run", name]).status == 0
            DispatchQueue.main.async {
                self.running.remove(name)
                self.onFinish?(name, ok)
            }
        }
    }

    private static func execute(_ arguments: [String]) -> (status: Int32, output: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

struct ShortcutsView: View {
    @ObservedObject var shortcuts: ShortcutsService
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !shortcuts.pinned.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(shortcuts.pinned, id: \.self) { name in
                            Button { shortcuts.run(name) } label: {
                                HStack(spacing: 5) {
                                    if shortcuts.running.contains(name) { ProgressView().controlSize(.mini) }
                                    else { Image(systemName: "bolt.fill").font(.system(size: 9.5, weight: .bold)) }
                                    Text(name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                                }
                            }
                            .buttonStyle(PillStyle(accent: true))
                            .help(String(localized: "Çalıştır: \(name)"))
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            Text(shortcuts.pinned.isEmpty ? "Sık kullandıklarını sabitle; burada tek dokunuşluk düğme olurlar." : "Tüm kestirmeler")
                .font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.dim)
            if !shortcuts.loaded {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shortcuts.all.isEmpty {
                Text("Kestirme bulunamadı. Kestirmeler uygulamasında oluşturduklarının hepsi burada görünür.")
                    .font(.system(size: 11)).foregroundStyle(Theme.faint).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(shortcuts.all, id: \.self) { name in ShortcutRow(name: name, shortcuts: shortcuts) }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { shortcuts.load() }
    }
}

private struct ShortcutRow: View {
    let name: String
    @ObservedObject var shortcuts: ShortcutsService
    @State private var hovering = false
    var body: some View {
        let pinned = shortcuts.pinned.contains(name)
        HStack(spacing: 8) {
            Button { shortcuts.run(name) } label: {
                HStack(spacing: 8) {
                    if shortcuts.running.contains(name) { ProgressView().controlSize(.mini).frame(width: 14) }
                    else { Image(systemName: "bolt").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.dim).frame(width: 14) }
                    Text(name).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "Çalıştır: \(name)"))
            Button { shortcuts.togglePin(name) } label: {
                Image(systemName: pinned ? "pin.fill" : "pin").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(pinned ? Theme.accent : Theme.dim).frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(pinned || hovering ? 1 : 0.35)
            .help(pinned ? "Sabitlemeyi kaldır" : "Üste sabitle")
        }
        .padding(.horizontal, 8).frame(height: 30)
        .background(hovering ? Theme.fillStrong : Theme.fill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onHover { hovering = $0 }
    }
}
