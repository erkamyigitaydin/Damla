import SwiftUI

/// The user's Apple Shortcuts (read from the `shortcuts` command), run from the notch; pinned ones lead the grid.
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
                .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !Self.isAutomation($0) }
            DispatchQueue.main.async {
                self.all = names
                self.loaded = true
                // A pinned shortcut that was renamed or deleted has nothing left to run; nor has an automation.
                self.pinned.removeAll { Self.isAutomation($0) || (!names.isEmpty && !names.contains($0)) }
            }
        }
    }

    /// Personal automations are listed as "Automation <UUID>": they run on their own trigger and their names say
    /// nothing, so they stay out of the grid.
    static func isAutomation(_ name: String) -> Bool {
        let parts = name.split(separator: " ", maxSplits: 1)
        return parts.count == 2 && parts[0].caseInsensitiveCompare("Automation") == .orderedSame && UUID(uuidString: String(parts[1])) != nil
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

/// A search on top and the shortcuts as a three-column grid of one-tap buttons, pinned ones first: about ten fit
/// at once where the old list showed four.
struct ShortcutsView: View {
    @ObservedObject var shortcuts: ShortcutsService
    /// The notch panel takes the keyboard only when asked; a click in the search field asks.
    var requestKeyFocus: (() -> Void)?
    @State private var search = ""
    @FocusState private var searching: Bool

    /// Pinned ones lead even before the list has loaded (or if it failed), so they stay one tap away.
    private var ordered: [String] { shortcuts.pinned + shortcuts.all.filter { !shortcuts.pinned.contains($0) } }
    private var shown: [String] { search.isEmpty ? ordered : ordered.filter { $0.localizedCaseInsensitiveContains(search) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PageHeader(title: Text("Kestirmeler"), detail: shortcuts.loaded ? Text("\(ordered.count)") : nil) { searchField }
            if !shortcuts.loaded && ordered.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if ordered.isEmpty || shown.isEmpty {
                Text(ordered.isEmpty ? "Kestirme bulunamadı. Kestirmeler uygulamasında oluşturduklarının hepsi burada görünür." : "Eşleşen kestirme yok")
                    .font(.system(size: 11)).foregroundStyle(Theme.faint).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                        ForEach(shown, id: \.self) { name in ShortcutTile(name: name, shortcuts: shortcuts) }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { shortcuts.load() }
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.dim)
            TextField("Ara", text: $search).textFieldStyle(.plain).font(.system(size: 11.5))
                .focused($searching)
                .simultaneousGesture(TapGesture().onEnded { requestKeyFocus?(); searching = true })
            if !search.isEmpty { IconButton(icon: "xmark.circle.fill", label: "Temizle", size: 18) { search = "" } }
        }
        .padding(.leading, 9).padding(.trailing, 3).frame(width: 160, height: 24).background(Theme.fill, in: Capsule())
    }
}

/// One shortcut: a tap runs it. Pinned ones carry a filled accent bolt and an outline; the pin shows on hover
/// and in the context menu.
private struct ShortcutTile: View {
    let name: String
    @ObservedObject var shortcuts: ShortcutsService
    @State private var hovering = false
    var body: some View {
        let pinned = shortcuts.pinned.contains(name)
        HStack(spacing: 0) {
            Button { shortcuts.run(name) } label: {
                HStack(spacing: 5) {
                    if shortcuts.running.contains(name) { ProgressView().controlSize(.mini).frame(width: 12) }
                    else {
                        Image(systemName: pinned ? "bolt.fill" : "bolt").font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(pinned ? Theme.accent : Theme.dim).frame(width: 12)
                    }
                    Text(name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 8).padding(.trailing, hovering ? 2 : 8).frame(maxHeight: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "Çalıştır: \(name)"))
            if hovering {
                Button { shortcuts.togglePin(name) } label: {
                    Image(systemName: pinned ? "pin.fill" : "pin").font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(pinned ? Theme.accent : Theme.dim).frame(width: 22).frame(maxHeight: .infinity).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(pinned ? "Sabitlemeyi kaldır" : "Üste sabitle")
            }
        }
        .frame(height: 30)
        .background(hovering ? Theme.fillStrong : Theme.fill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            if pinned { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white.opacity(0.22), lineWidth: 0.5) }
        }
        .onHover { hovering = $0 }
        .contextMenu {
            Button(pinned ? "Sabitlemeyi kaldır" : "Üste sabitle") { shortcuts.togglePin(name) }
        }
    }
}
