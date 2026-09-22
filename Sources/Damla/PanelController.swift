import AppKit
import SwiftUI
import Combine
import Carbon

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The window is a fixed-size transparent sheet pinned to the top of the chosen screen.
/// It never animates its frame; the SwiftUI notch shape inside grows and shrinks with springs.
/// Fully transparent pixels pass clicks through to whatever is underneath, so the big window
/// costs nothing in interaction terms. Hover tracking uses the shape rect, not the window.
final class PanelController {
    let model: AppState
    let panel: NotchPanel
    let host: NSHostingView<DamlaView>
    private var cancellables = Set<AnyCancellable>()
    private var hoverTimer: Timer?
    private var enteredAt: Date?
    private var exitedAt: Date?
    private var suppressHoverUntil = Date.distantPast
    private var lastExpanded = false
    private(set) var screen: NSScreen?
    private var localMonitor: Any?
    private var dragMonitors: [Any] = []
    var holdBasket = false // debug: keep the basket open without a real drag
    private var lastDragCount = NSPasteboard(name: .drag).changeCount

    init(model: AppState) {
        self.model = model
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Damla"
        panel.isFloatingPanel = true
        // On notched displays the compositor draws the menu bar material over every window below
        // the screen-saver level (measured on macOS 27: 999 is tinted, 1000 is not). Sit at that level
        // so the closed notch stays pure black; drop back down while a system dialog is showing.
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // the SwiftUI shape draws its own shadow
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        // The surface is black glass fading downwards; text is always white, so the panel is always dark.
        panel.appearance = NSAppearance(named: .darkAqua)
        host = NSHostingView(rootView: DamlaView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        model.requestKeyFocus = { [weak self] in self?.panel.makeKeyAndOrderFront(nil) }
        model.setDialogMode = { [weak self] showingDialog in
            guard let self else { return }
            self.panel.level = showingDialog ? .floating : .screenSaver
            if !showingDialog { self.panel.orderFrontRegardless() }
        }
        chooseScreen()
        model.$expanded.receive(on: RunLoop.main).sink { [weak self] expanded in
            guard let self else { return }
            if self.lastExpanded && !expanded {
                self.suppressHoverUntil = Date().addingTimeInterval(0.8)
                self.panel.resignKey()
            }
            self.lastExpanded = expanded
        }.store(in: &cancellables)
        model.$displayMode.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.chooseScreen(); self?.layout() }.store(in: &cancellables)
        model.$externalStyle.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.chooseScreen(); self?.layout() }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.chooseScreen(); self?.layout() }.store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in self?.chooseScreen(); self?.layout() }.store(in: &cancellables)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.model.pinnedOpen = false; self?.model.expanded = false
                return nil
            }
            return event
        }
        // Basket: watch for file drags anywhere. Mouse monitors need no permission; the drag pasteboard's
        // change count ticks once per drag session, so the check is cheap.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] _ in self?.checkDrag() }) { dragMonitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in self?.endDrag() }) { dragMonitors.append(monitor) }
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.trackHover() }
        if let hoverTimer { RunLoop.main.add(hoverTimer, forMode: .common) }
        layout()
        panel.orderFrontRegardless()
    }

    private static func screenUnderMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
    }

    func chooseScreen() {
        let screens = NSScreen.screens
        let notched = screens.first { $0.safeAreaInsets.top > 0 }
        switch model.displayMode {
        case .notch: screen = notched ?? NSScreen.main ?? screens.first
        case .followMouse: screen = Self.screenUnderMouse() ?? notched ?? NSScreen.main ?? screens.first
        }
        guard let screen else { return }
        let physicalNotch = screen.safeAreaInsets.top > 0
        if physicalNotch {
            model.hasNotch = true
            model.notchHeight = screen.safeAreaInsets.top
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                model.notchWidth = max(130, right.minX - left.maxX)
            } else { model.notchWidth = 185 }
        } else if model.externalStyle == .menuBar {
            // Fake notch: same outline as the real one, sized to this screen's menu bar.
            let bar = screen.frame.maxY - screen.visibleFrame.maxY
            model.hasNotch = true
            model.notchHeight = bar > 0 ? bar : Layout.fakeNotchHeight
            model.notchWidth = Layout.fakeNotchWidth
        } else {
            model.hasNotch = false
            model.notchHeight = Layout.fakeNotchHeight
            model.notchWidth = 0
        }
    }

    /// Top edge of the drawn shape in screen coordinates.
    private var topY: CGFloat {
        guard let screen else { return 0 }
        return model.hasNotch ? screen.frame.maxY : screen.visibleFrame.maxY - Layout.notchlessTopInset
    }

    func layout() {
        guard let screen else { return }
        let size = Layout.windowSize(model.metrics)
        let frame = NSRect(x: (screen.frame.midX - size.width / 2).rounded(), y: topY - size.height, width: size.width, height: size.height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    func visibleRect() -> NSRect {
        guard let screen else { return .zero }
        return Layout.visibleRect(model.state, model.metrics, compactContent: model.compactContent, midX: screen.frame.midX, top: topY)
    }

    private func checkDrag() {
        guard !model.expanded else { return }
        let board = NSPasteboard(name: .drag)
        guard board.changeCount != lastDragCount else { return }
        lastDragCount = board.changeCount
        if board.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            model.dragActive = true
        }
    }
    private func endDrag() {
        // Give the drop a moment to land on our target before the basket folds away.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, NSEvent.pressedMouseButtons == 0 else { return }
            self.model.dragActive = false
        }
    }
    private func trackHover() {
        let now = Date()
        let location = NSEvent.mouseLocation
        if NSEvent.pressedMouseButtons != 0 { checkDrag() }
        else if model.dragActive && !holdBasket { endDrag() }
        if model.displayMode == .followMouse, model.state == .closed, !model.pinnedOpen,
           let under = Self.screenUnderMouse(), under != screen {
            chooseScreen(); layout()
        }
        let inside = visibleRect().insetBy(dx: -4, dy: -4).contains(location)
        if inside {
            exitedAt = nil
            if enteredAt == nil { enteredAt = now }
            if !model.expanded && !model.dragActive && model.automaticOpen && now >= suppressHoverUntil && now.timeIntervalSince(enteredAt!) > 0.12 {
                model.expanded = true
            }
        } else {
            enteredAt = nil
            if exitedAt == nil { exitedAt = now }
            let editing = panel.isKeyWindow && (model.selectedTab == .clipboard || model.settingsVisible)
            if model.expanded && !model.pinnedOpen && !editing && NSEvent.pressedMouseButtons == 0 && now.timeIntervalSince(exitedAt!) > 0.28 {
                model.expanded = false
            }
        }
    }
    func toggle() {
        if model.expanded {
            model.pinnedOpen = false; model.expanded = false
        } else {
            if model.displayMode == .followMouse { chooseScreen(); layout() }
            model.expanded = true; model.pinnedOpen = true; panel.orderFrontRegardless()
        }
    }
    func show() {
        if model.displayMode == .followMouse { chooseScreen(); layout() }
        model.expanded = true; model.pinnedOpen = true; panel.orderFrontRegardless()
    }
    deinit {
        hoverTimer?.invalidate()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        for monitor in dragMonitors { NSEvent.removeMonitor(monitor) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppState!
    var controller: PanelController!
    private var statusItem: NSStatusItem!
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model = AppState()
        controller = PanelController(model: model)
        model.start()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "drop", accessibilityDescription: "Damla")
        let menu = NSMenu()
        menu.addItem(withTitle: "Damla’yı aç", action: #selector(showPanel), keyEquivalent: "")
        menu.addItem(withTitle: "Ayarlar", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Damla’dan çık", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        registerShortcut()
        if UserDefaults.standard.integer(forKey: "lastSeenBuild") < 3 {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            UserDefaults.standard.set(3, forKey: "lastSeenBuild")
            controller.show()
        }
        if ProcessInfo.processInfo.arguments.contains("--show") { controller.show() }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(debugCommand(_:)), name: Notification.Name("app.local.damla.debug"), object: nil)
    }
    /// Local-only automation hook for screenshots: `--debug` builds respond to open/close/hud/tab commands.
    @objc private func debugCommand(_ note: Notification) {
        guard ProcessInfo.processInfo.arguments.contains("--debug"), let command = note.object as? String else { return }
        switch command {
        case "open": controller.show()
        case "close": model.pinnedOpen = false; model.expanded = false
        case "hud-volume": model.showHUD("speaker.wave.2.fill", "Ses", 0.62)
        case "hud-brightness": model.showHUD("sun.max.fill", "Parlaklık", 0.8)
        case "hud-battery": model.showHUD("battery.100percent.bolt", "Şarja bağlandı", 0.8)
        case "tab-home": model.select(.home)
        case "tab-files": model.select(.files)
        case "tab-clipboard": model.select(.clipboard)
        case "tab-focus": model.select(.focus)
        case "settings": model.settingsVisible = true
        case "display-notch": model.displayMode = .notch
        case "files-demo":
            let base = URL(fileURLWithPath: "/Users/erkamyigitaydin/Desktop/Projects/Damla")
            model.addFiles(["README.md", "Package.swift", "build.sh", "Resources/AppIcon.icns", "Sources/Damla/Views.swift"].map { base.appendingPathComponent($0) })
        case "display-mouse": model.displayMode = .followMouse
        case "external-menubar": model.externalStyle = .menuBar
        case "external-island": model.externalStyle = .island
        case "vol-up": model.monitor.adjustVolume(by: 1 / 16, feedback: false)
        case "vol-down": model.monitor.adjustVolume(by: -1 / 16, feedback: false)
        case "bright-up": model.monitor.adjustBrightness(by: 1 / 16)
        case "bright-down": model.monitor.adjustBrightness(by: -1 / 16)
        case "keys-on": model.setHideSystemHUD(true)
        case "drag-on": controller.holdBasket = true; model.dragActive = true
        case "drag-off": controller.holdBasket = false; model.dragActive = false
        case "keys-off": model.setHideSystemHUD(false)
        case "focus-start": model.setFocus(minutes: 25); model.toggleFocus()
        case "focus-stop": model.setFocus(minutes: 25)
        case "clip-demo":
            model.clips = [ClipEntry(kind: .text, text: "https://getdroppy.app/changelog"),
                           ClipEntry(kind: .text, text: "Invoice #2041 gönderildi. Cuma ödenmezse hatırlat."),
                           ClipEntry(kind: .text, text: "#153AA4"),
                           ClipEntry(kind: .text, text: "Bu metni daha samimi bir tonda, 40 kelimeyi geçmeden yeniden yaz.")]
        default: break
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.show(); return true
    }
    @objc func showPanel() { controller.show() }
    @objc func showSettings() { model.settingsVisible = true; controller.show() }
    @objc func quit() { NSApp.terminate(nil) }
    private func registerShortcut() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { delegate.controller.toggle() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        let identifier = EventHotKeyID(signature: 0x444D4C41, id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), identifier, GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { model.showNotice("Kısayol kullanılıyor. Menüdeki damladan açabilirsin.") }
    }
    func applicationWillTerminate(_ notification: Notification) {
        model.saveSession()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
