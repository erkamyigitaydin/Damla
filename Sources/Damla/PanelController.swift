import AppKit
import SwiftUI
import Combine
import Carbon
import Quartz

final class NotchPanel: NSPanel {
    var quickLook: QuickLookController?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // AppKit pushes windows below the menu bar when their level drops (Quick Look, file dialog); the notch
    // must stay glued to the top edge regardless of level.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    // Quick Look asks the key window's responder chain who feeds the preview panel.
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { quickLook != nil }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = quickLook; panel.delegate = quickLook }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = nil; panel.delegate = nil }
}

/// Geometry of the screen a window sits on; one instance per window, observed by its views.
final class ScreenMetrics: ObservableObject {
    @Published var id: UInt32
    @Published var metrics: Layout.Metrics
    init(id: UInt32, metrics: Layout.Metrics) { self.id = id; self.metrics = metrics }
}

extension NSScreen {
    var displayID: UInt32 { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
}

/// One notch window on one screen. The window is a fixed-size transparent sheet pinned to the top of
/// its screen; it never animates its frame. Mouse passthrough is explicitly gated by the visible area;
/// transparent hosting/glass layers must not intercept other apps. With "all screens" every display gets its own
/// controller; the panel expands only on the screen that asked for it (`AppState.activeScreenID`).
final class PanelController {
    let model: AppState
    let panel: NotchPanel
    let host: NSHostingView<DamlaView>
    let screenInfo: ScreenMetrics
    let fixedScreen: NSScreen?
    private var cancellables = Set<AnyCancellable>()
    private var hoverTimer: Timer?
    private var mouseMonitors: [Any] = []
    private var scrollGesture = NotchScrollGesture()
    private var enteredAt: Date?
    private var exitedAt: Date?
    private var suppressHoverUntil = Date.distantPast
    private var lastExpandedHere = false
    private(set) var screen: NSScreen?
    var dialogShowing = false
    var pinnedBeforeQuickLook = false
    /// The menu bar on this screen is out of sight (a full-screen app, or "hide the menu bar automatically").
    /// The closed notch follows it away and comes back when the menu bar slides in.
    var menuBarHidden = false { didSet { if menuBarHidden != oldValue { updateVisibility() } } }
    private var concealed = false

    init(model: AppState, fixedScreen: NSScreen?) {
        self.model = model
        self.fixedScreen = fixedScreen
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Damla"
        panel.isFloatingPanel = true
        // On notched displays the compositor draws the menu bar material over every window below
        // the screen-saver level (measured on macOS 27: 999 is tinted, 1000 is not). Sit at that level
        // so the closed notch stays pure black; drop below the drag layer while a file is dragged.
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        let initial = fixedScreen ?? NSScreen.main ?? NSScreen.screens[0]
        screenInfo = ScreenMetrics(id: initial.displayID, metrics: Layout.Metrics(notchWidth: 185, notchHeight: 32, hasNotch: true))
        host = NSHostingView(rootView: DamlaView(model: model, screen: screenInfo))
        host.sizingOptions = []
        panel.contentView = host
        panel.quickLook = QuickLookController(model: model)
        chooseScreen()
        Publishers.CombineLatest(model.$expanded, model.$activeScreenID).receive(on: RunLoop.main).sink { [weak self] expanded, active in
            guard let self else { return }
            let here = expanded && active == self.id
            if self.lastExpandedHere && !here {
                self.suppressHoverUntil = Date().addingTimeInterval(0.8)
                self.panel.resignKey()
            }
            self.lastExpandedHere = here
        }.store(in: &cancellables)
        // Read after @Published has committed, including screen ownership, compact activity and cleaning changes.
        Publishers.Merge3(model.objectWillChange, model.media.objectWillChange, model.cleaning.objectWillChange)
            .receive(on: RunLoop.main).sink { [weak self] in self?.updateVisibility() }.store(in: &cancellables)
        if fixedScreen == nil {
            model.$displayMode.dropFirst().receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.chooseScreen(); self?.layout() }.store(in: &cancellables)
        }
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.chooseScreen(); self?.layout() }.store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in self?.chooseScreen(); self?.layout() }.store(in: &cancellables)
        model.$dragActive.removeDuplicates().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateLevel() }.store(in: &cancellables)
        let mouseEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                                                  .leftMouseUp, .rightMouseUp, .otherMouseUp]
        // Global events cover other apps; local events cover the pointer leaving our own surface.
        // Keep this event-driven so a quick move followed by a click does not wait for the hover timer.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents, handler: { [weak self] _ in
            self?.updateMousePassthrough()
        }) { mouseMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents, handler: { [weak self] event in
            self?.updateMousePassthrough()
            return event
        }) { mouseMonitors.append(monitor) }
        // Scrolling on the notch strip itself (not the panel content below it) changes volume or skips a track.
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            guard let self, event.window === self.panel, self.model.notchGestures, self.inNotchStrip(NSEvent.mouseLocation) else { return event }
            self.handleScroll(event)
            return nil
        }) { mouseMonitors.append(monitor) }
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.trackHover() }
        if let hoverTimer { RunLoop.main.add(hoverTimer, forMode: .common) }
        layout()
        panel.orderFrontRegardless()
    }

    var id: UInt32 { screenInfo.id }
    var isActive: Bool { model.activeScreenID == id }
    var state: NotchState { model.state(for: id) }

    func close() {
        hoverTimer?.invalidate(); hoverTimer = nil
        mouseMonitors.forEach { NSEvent.removeMonitor($0) }; mouseMonitors.removeAll()
        cancellables.removeAll()
        panel.orderOut(nil)
    }

    /// Normally at the screen-saver level. That is above the drag layer (kCGDraggingWindowLevel = 500),
    /// where AppKit never looks for drop targets, so during a file drag the panel steps just below it;
    /// system dialogs (file picker, Quick Look) need it lower still.
    func updateLevel() {
        let target: NSWindow.Level
        if dialogShowing { target = .floating }
        else if model.dragActive { target = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.draggingWindow)) - 1) }
        else { target = .screenSaver }
        guard panel.level != target else { return }
        panel.level = target
        panel.orderFrontRegardless()
        layout()
    }

    /// Hidden only while closed: a HUD, the drop basket or an open panel still shows over a full-screen app.
    func updateVisibility() {
        let conceal = menuBarHidden && state == .closed && !model.pinnedOpen
        let changed = conceal != concealed
        concealed = conceal
        updateMousePassthrough()
        guard changed else { return }
        if conceal { enteredAt = nil }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = conceal ? 0.18 : 0.12
            panel.animator().alphaValue = conceal ? 0 : 1
        }
    }

    private func updateMousePassthrough() {
        // No hover tolerance here: even the transparent strip below a closed notch belongs to the app behind it.
        let ignores = concealed || !visibleRect().contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents != ignores { panel.ignoresMouseEvents = ignores }
    }

    static func screenUnderMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
    }

    func chooseScreen() {
        let screens = NSScreen.screens
        let notched = screens.first { $0.safeAreaInsets.top > 0 }
        if let fixedScreen {
            // NSScreen objects are replaced after a display reconfigure; follow the display id.
            screen = screens.first { $0.displayID == fixedScreen.displayID } ?? fixedScreen
        } else {
            switch model.displayMode {
            case .notch, .all: screen = notched ?? NSScreen.main ?? screens.first
            case .followMouse: screen = Self.screenUnderMouse() ?? notched ?? NSScreen.main ?? screens.first
            }
        }
        guard let screen else { return }
        let physicalNotch = screen.safeAreaInsets.top > 0
        let metrics: Layout.Metrics
        if physicalNotch {
            var width: CGFloat = 185
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea { width = max(130, right.minX - left.maxX) }
            metrics = Layout.Metrics(notchWidth: width, notchHeight: screen.safeAreaInsets.top, hasNotch: true)
        } else if model.externalStyle == .menuBar {
            let bar = screen.frame.maxY - screen.visibleFrame.maxY
            metrics = Layout.Metrics(notchWidth: Layout.fakeNotchWidth, notchHeight: bar > 0 ? bar : Layout.fakeNotchHeight, hasNotch: true)
        } else {
            metrics = Layout.Metrics(notchWidth: 0, notchHeight: Layout.fakeNotchHeight, hasNotch: false)
        }
        if screenInfo.id != screen.displayID { screenInfo.id = screen.displayID }
        if screenInfo.metrics != metrics { screenInfo.metrics = metrics }
    }

    private var topY: CGFloat {
        guard let screen else { return 0 }
        return screenInfo.metrics.hasNotch ? screen.frame.maxY : screen.visibleFrame.maxY - Layout.notchlessTopInset
    }

    func layout() {
        guard let screen else { return }
        let size = Layout.windowSize(screenInfo.metrics)
        let frame = NSRect(x: (screen.frame.midX - size.width / 2).rounded(), y: topY - size.height, width: size.width, height: size.height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        updateMousePassthrough()
    }

    /// The top band of the visible shape, as tall as the menu bar / physical notch.
    private func inNotchStrip(_ point: NSPoint) -> Bool {
        let visible = visibleRect()
        let height = Layout.closedHeight(screenInfo.metrics)
        return NSRect(x: visible.minX, y: visible.maxY - height, width: visible.width, height: height).contains(point)
    }

    private func handleScroll(_ event: NSEvent) {
        let finger = NotchScrollGesture.finger(event)
        let actions = scrollGesture.feed(up: finger.up, right: finger.right, precise: event.hasPreciseScrollingDeltas,
                                         began: event.phase.contains(.began) || event.phase.contains(.mayBegin),
                                         ended: event.phase.contains(.ended) || event.phase.contains(.cancelled),
                                         momentum: !event.momentumPhase.isEmpty)
        for action in actions {
            switch action {
            case .volume(let steps): model.monitor.adjustVolume(by: Float(steps) / 16, feedback: false)
            case .next: model.media.command("next track"); model.showHUD("forward.fill", String(localized: "Sonraki parça"), 1)
            case .previous: model.media.command("previous track"); model.showHUD("backward.fill", String(localized: "Önceki parça"), 1)
            }
        }
    }

    func visibleRect() -> NSRect {
        guard let screen else { return .zero }
        return Layout.visibleRect(state, screenInfo.metrics, compactSlots: model.compactSlots, midX: screen.frame.midX, top: topY, tall: model.tallPanel)
    }

    private func trackHover() {
        // Also refresh with a stationary pointer when the HUD, activity width or panel state changes.
        defer { updateMousePassthrough() }
        guard !model.cleaning.active, !concealed else { return }
        let now = Date()
        let location = NSEvent.mouseLocation
        if fixedScreen == nil, model.displayMode == .followMouse, state == .closed, !model.pinnedOpen,
           let under = Self.screenUnderMouse(), under != screen {
            chooseScreen(); layout()
        }
        let inside = visibleRect().insetBy(dx: -4, dy: -4).contains(location)
        if inside {
            exitedAt = nil
            if enteredAt == nil { enteredAt = now }
            if state != .expanded && !model.dragActive && model.automaticOpen && now >= suppressHoverUntil
                && now.timeIntervalSince(enteredAt!) > 0.12 {
                model.activeScreenID = id
                model.expanded = true
            }
        } else {
            enteredAt = nil
            if exitedAt == nil { exitedAt = now }
            let editing = panel.isKeyWindow && model.selectedTab == .clipboard
            // Lyrics are read from a distance while the song plays: they stay open until closed by hand
            // (the X, a click on the notch, ⌃⌥Space).
            if model.expanded && isActive && !model.pinnedOpen && !editing && !model.tallPanel && NSEvent.pressedMouseButtons == 0
                && now.timeIntervalSince(exitedAt!) > 0.28 {
                model.expanded = false
            }
        }
    }

    func show() {
        if fixedScreen == nil && model.displayMode == .followMouse { chooseScreen(); layout() }
        model.activeScreenID = id
        model.expanded = true; model.pinnedOpen = true
        updateVisibility()
        panel.orderFrontRegardless()
    }

    func toggleQuickLook(index: Int?) {
        guard let preview = QLPreviewPanel.shared() else { return }
        if preview.isVisible { preview.orderOut(nil); return }
        pinnedBeforeQuickLook = model.pinnedOpen
        model.pinnedOpen = true
        dialogShowing = true; updateLevel()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        preview.makeKeyAndOrderFront(nil)
        if preview.dataSource == nil { preview.dataSource = panel.quickLook; preview.delegate = panel.quickLook }
        preview.reloadData()
        if let index { preview.currentPreviewItemIndex = index }
    }
    func quickLookDidClose() {
        dialogShowing = false; updateLevel()
        model.pinnedOpen = pinnedBeforeQuickLook
        panel.makeKeyAndOrderFront(nil)
    }

    deinit {
        hoverTimer?.invalidate()
        mouseMonitors.forEach { NSEvent.removeMonitor($0) }
    }
}

/// Owns one controller per screen (or a single roaming one), plus everything that must exist once:
/// keyboard shortcuts, system-wide drag detection, Quick Look ownership.
final class PanelManager {
    private let sharing = ShelfSharing()
    let model: AppState
    private(set) var controllers: [PanelController] = []
    private var cancellables = Set<AnyCancellable>()
    private var localMonitor: Any?
    private var dragMonitors: [Any] = []
    private var dragTimer: Timer?
    private var menuBarTimer: Timer?
    private var menuBarFastUntil: CFAbsoluteTime = 0
    private var lastMenuBarCheck: CFAbsoluteTime = 0
    private var lastMenuBarScreens: [UInt32] = []
    private var revealedNotchBars = Set<UInt32>()
    private var lastDragCount = NSPasteboard(name: .drag).changeCount
    private weak var quickLookOwner: PanelController?
    var holdBasket = false // debug: keep the basket open without a real drag

    init(model: AppState) {
        self.model = model
        model.requestKeyFocus = { [weak self] in self?.focusController?.panel.makeKeyAndOrderFront(nil) }
        model.setDialogMode = { [weak self] showing in
            self?.controllers.forEach { $0.dialogShowing = showing; $0.updateLevel() }
        }
        model.requestQuickLook = { [weak self] index in
            guard let self, let owner = self.focusController else { return }
            self.quickLookOwner = owner
            owner.toggleQuickLook(index: index)
        }
        model.requestShare = { [weak self] url in
            guard let self, let owner = self.focusController else { return }
            self.sharing.show(url, from: owner.host, model: model)
        }
        rebuild()
        model.$displayMode.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.rebuild() }.store(in: &cancellables)
        model.$externalStyle.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.controllers.forEach { $0.chooseScreen(); $0.layout() } }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.rebuild() }.store(in: &cancellables)
        // Something opened the panel without naming a screen (drop, shortcut, file picker): use the mouse's.
        model.$expanded.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] expanded in
            guard let self, expanded, self.model.activeScreenID == nil else { return }
            self.model.activeScreenID = self.controllerForMouse()?.id
        }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)
            .filter { QLPreviewPanel.sharedPreviewPanelExists() && ($0.object as? NSWindow) === QLPreviewPanel.shared() }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.quickLookOwner?.quickLookDidClose() }.store(in: &cancellables)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.model.cleaning.active { return nil }
            if event.keyCode == 53 { // Esc: Quick Look first, then the notch
                if QuickLookController.isShowing { QLPreviewPanel.shared().orderOut(nil); return nil }
                self.model.pinnedOpen = false; self.model.expanded = false
                return nil
            }
            if event.keyCode == 49, self.model.expanded, self.model.selectedTab == .files,
               event.modifierFlags.intersection([.command, .option, .control]).isEmpty { // Space
                self.model.quickLook()
                return nil
            }
            return event
        }
        // Basket: watch for file drags anywhere. Mouse monitors need no permission; the drag pasteboard's
        // change count ticks once per drag session, so the check is cheap.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] _ in self?.checkDrag() }) { dragMonitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in self?.endDrag() }) { dragMonitors.append(monitor) }
        dragTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if NSEvent.pressedMouseButtons != 0 { self.checkDrag() }
            else if self.model.dragActive && !self.holdBasket { self.endDrag() }
        }
        if let dragTimer { RunLoop.main.add(dragTimer, forMode: .common) }
        menuBarTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in self?.menuBarTick() }
        menuBarTimer?.tolerance = 0.03
        if let menuBarTimer { RunLoop.main.add(menuBarTimer, forMode: .common) }
        // Entering or leaving full screen switches Space; keep checking while the Space animation settles.
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .merge(with: workspace.publisher(for: NSWorkspace.didActivateApplicationNotification))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.menuBarsMayChange(for: 1.5) }.store(in: &cancellables)
    }

    /// The window-list query behind `updateMenuBars` was the largest idle cost at 0.15 s. The tick itself only
    /// reads the pointer: the full check runs every tick after a Space or app switch and while the pointer is
    /// near a menu bar (it can reveal one, and a revealed bar hides a moment after the pointer leaves),
    /// otherwise once a second as a fallback.
    private func menuBarsMayChange(for seconds: CFAbsoluteTime) {
        menuBarFastUntil = max(menuBarFastUntil, CFAbsoluteTimeGetCurrent() + seconds)
        updateMenuBars()
    }

    private func menuBarTick() {
        let now = CFAbsoluteTimeGetCurrent()
        let mouse = NSEvent.mouseLocation
        let nearBar = controllers.contains { controller in
            guard let frame = controller.screen?.frame else { return false }
            let band = max(40, (controller.screen?.safeAreaInsets.top ?? 0) + 8)
            return NSMouseInRect(mouse, frame, false) && mouse.y >= frame.maxY - band
        }
        if nearBar { menuBarFastUntil = max(menuBarFastUntil, now + 2) }
        // A roaming controller that just moved to another screen needs that screen's state right away.
        let screens = controllers.map { $0.screen?.displayID ?? 0 }
        guard now < menuBarFastUntil || now - lastMenuBarCheck >= 1 || screens != lastMenuBarScreens else { return }
        lastMenuBarScreens = screens
        updateMenuBars()
    }

    /// The menu bar is one Window Server window per display at the main-menu level. It leaves the on-screen
    /// window list while a full-screen app (or the auto-hide setting) keeps it away, and returns when the
    /// pointer reveals it (measured on macOS 27). Owner name and layer need no screen-recording permission.
    private func updateMenuBars() {
        lastMenuBarCheck = CFAbsoluteTimeGetCurrent()
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }
        let menuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        let bars: [CGRect] = list.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == menuLevel, info[kCGWindowOwnerName as String] as? String == "Window Server",
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: bounds)
        }
        let fullScreen = controllers.contains { ($0.screen?.safeAreaInsets.top ?? 0) > 0 } ? FullScreenSpaces.current() : nil
        let mouse = NSEvent.mouseLocation
        for controller in controllers {
            guard let screen = controller.screen else { continue }
            if screen.safeAreaInsets.top > 0 {
                // A notched display keeps its menu bar window in full screen (it paints the black band around
                // the notch), so ask the Space instead. The menu bar drops in when the pointer touches the top
                // edge and stays while the pointer is on it.
                guard fullScreen?.contains(controller.id) == true else {
                    revealedNotchBars.remove(controller.id); controller.menuBarHidden = false; continue
                }
                let onScreen = NSMouseInRect(mouse, screen.frame, false)
                if onScreen && mouse.y >= screen.frame.maxY - 2 { revealedNotchBars.insert(controller.id) }
                else if !onScreen || mouse.y < screen.frame.maxY - screen.safeAreaInsets.top - 6 { revealedNotchBars.remove(controller.id) }
                controller.menuBarHidden = !revealedNotchBars.contains(controller.id)
                continue
            }
            // With one Space across all displays only the main display has a menu bar; the rest follow it.
            let visible = NSScreen.screensHaveSeparateSpaces
                ? bars.contains { $0.intersects(CGDisplayBounds(controller.id)) }
                : !bars.isEmpty
            controller.menuBarHidden = !visible
        }
    }

    /// The controller showing the panel, else the one under the mouse.
    var focusController: PanelController? { active ?? controllerForMouse() }
    var active: PanelController? { controllers.first { $0.id == model.activeScreenID } }

    func controllerForMouse() -> PanelController? {
        if let under = PanelController.screenUnderMouse(), let match = controllers.first(where: { $0.id == under.displayID }) { return match }
        return controllers.first { ($0.screen?.safeAreaInsets.top ?? 0) > 0 } ?? controllers.first
    }

    func rebuild() {
        switch model.displayMode {
        case .all:
            let screens = NSScreen.screens
            let stale = controllers.filter { c in c.fixedScreen == nil || !screens.contains { $0.displayID == c.id } }
            stale.forEach { $0.close() }
            controllers.removeAll { c in stale.contains { $0 === c } }
            for screen in screens where !controllers.contains(where: { $0.id == screen.displayID }) {
                controllers.append(PanelController(model: model, fixedScreen: screen))
            }
        case .followMouse, .notch:
            if controllers.count == 1, controllers[0].fixedScreen == nil {
                controllers[0].chooseScreen(); controllers[0].layout()
            } else {
                controllers.forEach { $0.close() }
                controllers = [PanelController(model: model, fixedScreen: nil)]
            }
        }
        if let activeID = model.activeScreenID, !controllers.contains(where: { $0.id == activeID }) {
            model.expanded = false; model.activeScreenID = nil
        }
    }

    func toggle() {
        if model.expanded { model.pinnedOpen = false; model.expanded = false } else { show() }
    }
    func show() { controllerForMouse()?.show() }

    private func checkDrag() {
        guard !model.expanded, model.enabledTabs.contains(.files) else { return }
        let board = NSPasteboard(name: .drag)
        guard board.changeCount != lastDragCount else { return }
        lastDragCount = board.changeCount
        if board.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            model.dragURLs = (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
            model.dragActive = true
        }
    }
    private func endDrag() {
        // Give the drop a moment to land on our target before the basket folds away.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, !self.holdBasket, NSEvent.pressedMouseButtons == 0 else { return }
            self.model.dragActive = false
            self.model.dragURLs = []
        }
    }

    deinit {
        dragTimer?.invalidate()
        menuBarTimer?.invalidate()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        for monitor in dragMonitors { NSEvent.removeMonitor(monitor) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppState!
    var manager: PanelManager!
    private var statusItem: NSStatusItem!
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private lazy var settings = SettingsWindowController(model: model)
    private lazy var onboarding = OnboardingWindowController(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model = AppState()
        manager = PanelManager(model: model)
        model.presentSettings = { [weak self] in self?.settings.present() }
        model.presentPanel = { [weak self] in self?.manager.show() }
        model.presentOnboarding = { [weak self] in self?.onboarding.present() }
        if OnboardingWindowController.shouldShowOnLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.onboarding.present() }
        }
        model.start()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "drop", accessibilityDescription: "Damla")
        let menu = NSMenu()
        menu.addItem(withTitle: String(localized: "Damla’yı aç"), action: #selector(showPanel), keyEquivalent: "")
        menu.addItem(withTitle: String(localized: "Ayarlar"), action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: String(localized: "Tanıtım…"), action: #selector(showOnboarding), keyEquivalent: "")
        menu.addItem(withTitle: String(localized: "Temizlik modu · 60 sn"), action: #selector(startCleaning), keyEquivalent: "")
        menu.addItem(withTitle: String(localized: "Güncellemeleri denetle…"), action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Damla’dan çık"), action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        registerShortcut()
        if UserDefaults.standard.integer(forKey: "lastSeenBuild") < 3 {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            UserDefaults.standard.set(3, forKey: "lastSeenBuild")
            manager.show()
        }
        if ProcessInfo.processInfo.arguments.contains("--show") { manager.show() }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(debugCommand(_:)), name: Notification.Name("app.local.damla.debug"), object: nil)
    }
    /// Local-only automation hook for screenshots: `--debug` builds respond to these commands.
    @objc private func debugCommand(_ note: Notification) {
        guard ProcessInfo.processInfo.arguments.contains("--debug"), let command = note.object as? String else { return }
        switch command {
        case "open": manager.show()
        case "close": model.pinnedOpen = false; model.expanded = false
        case "hud-volume": model.showHUD("speaker.wave.2.fill", "Ses", 0.62)
        case "hud-brightness": model.showHUD("sun.max.fill", "Parlaklık", 0.8)
        case "hud-airpods": model.showDeviceHUD("airpods.pro", "AirPods Pro", detail: "S %80 · Sa %75 · K %60")
        case "hud-battery": model.showHUD("battery.100percent.bolt", "Şarja bağlandı", 0.8)
        case "tab-home": model.select(.home)
        case "mixer": model.select(.home); model.homePane = .levels
        case "outputs": model.select(.home); model.homePane = .outputs
        case "lyrics": model.select(.home); model.homePane = .player; model.lyricsExpanded = true
        case "sources": model.select(.home); model.homePane = .sources
        case "lyrics-on": model.lyrics.enabled = true
        case "lyrics-off": model.lyrics.enabled = false
        case "lyrics-probe":   // fetch a known song through the real service, report what came back
            model.lyrics.show(title: "The Black Dog", artist: "Taylor Swift", album: "THE TORTURED POETS DEPARTMENT", duration: 238)
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let lyrics = self?.model.lyrics else { return }
                MediaService.trace("lyrics-probe state=\(lyrics.state) lines=\(lyrics.lyrics.lines.count) first=\(lyrics.lyrics.lines.first?.text ?? "-") at60=\(lyrics.lyrics.index(at: 60).map { lyrics.lyrics.lines[$0].text } ?? "-")")
            }
        case "tab-files": model.select(.files)
        case "tab-clipboard": model.select(.clipboard)
        case "tab-focus": model.select(.focus)
        case "tab-agents": model.select(.agents)
        case "share": model.select(.files); model.shareFile()
        case "settings": model.openSettings()
        case "onboarding": onboarding.present()
        case let step where step.hasPrefix("onboarding-"): onboarding.present(page: Int(step.dropFirst(11)))
        case let tab where tab.hasPrefix("settings-"): model.pinnedOpen = false; model.expanded = false; settings.present(tab: Int(tab.dropFirst(9)))
        case "media-demo": model.media.injectDemoSessions()
        case let id where id.hasPrefix("select:"): model.media.select(String(id.dropFirst(7)))
        case let list where list.hasPrefix("tabs:"):   // e.g. tabs:home,focus,agents
            let wanted = Set(list.dropFirst(5).split(separator: ",").compactMap { name in PanelTab.allCases.first { "\($0)" == name } })
            for tab in PanelTab.allCases { model.setTab(tab, enabled: true) }
            for tab in PanelTab.allCases where !wanted.contains(tab) { model.setTab(tab, enabled: false) }
        case let body where body.hasPrefix("music:"): model.media.debugMusic(String(body.dropFirst(6)))
        case "render-media": MainActor.assumeIsolated { renderMedia() }
        case "approval-allow", "approval-deny":
            if let request = model.agents.approvals.first { model.agents.decide(request, command == "approval-allow" ? .allow : .deny) }
        case "media-sessions": NSLog("Damla media: %@", model.media.sessions.map { "\($0.bundleID) playing=\($0.playing) \($0.title)" }.joined(separator: " | "))
        case "display-notch": model.displayMode = .notch
        case "display-mouse": model.displayMode = .followMouse
        case "display-all": model.displayMode = .all
        case "external-menubar": model.externalStyle = .menuBar
        case "external-island": model.externalStyle = .island
        case "vol-up": model.monitor.adjustVolume(by: 1 / 16, feedback: false)
        case "vol-down": model.monitor.adjustVolume(by: -1 / 16, feedback: false)
        case "bright-up": model.monitor.adjustBrightness(by: 1 / 16)
        case "bright-down": model.monitor.adjustBrightness(by: -1 / 16)
        case "keys-on": model.setHideSystemHUD(true)
        case "keys-off": model.setHideSystemHUD(false)
        case "drag-on":
            manager.holdBasket = true
            model.dragURLs = [URL(fileURLWithPath: "/Users/erkamyigitaydin/Desktop/Projects/Damla/docs/damla-0.3-overview.png")]
            model.dragActive = true
        case "drag-off": manager.holdBasket = false; model.dragActive = false; model.dragURLs = []
        case "quicklook": model.quickLook()
        case "check-updates": model.updater.checkForUpdates()
        case "quit": NSApp.terminate(nil)
        case "focus-start": model.setFocus(minutes: 25); model.toggleFocus()
        case "focus-stop": model.setFocus(minutes: 25)
        case "files-demo":
            let base = URL(fileURLWithPath: "/Users/erkamyigitaydin/Desktop/Projects/Damla")
            model.addFiles(["README.md", "Package.swift", "build.sh", "Resources/AppIcon.icns", "Sources/Damla/Views.swift"].map { base.appendingPathComponent($0) })
        case "clip-demo":
            model.clips = [ClipEntry(kind: .text, text: "https://getdroppy.app/changelog"),
                           ClipEntry(kind: .text, text: "Invoice #2041 gönderildi. Cuma ödenmezse hatırlat."),
                           ClipEntry(kind: .text, text: "#153AA4"),
                           ClipEntry(kind: .text, text: "Bu metni daha samimi bir tonda, 40 kelimeyi geçmeden yeniden yaz.")]
        default: break
        }
    }
    /// Draws the media views off screen into /tmp (for checks while the real screen is busy or protected).
    @MainActor private func renderMedia() {
        let m = Layout.Metrics(notchWidth: 180, notchHeight: 32, hasNotch: true)
        let pairs: [(String, AnyView)] = [
            ("home", AnyView(HomeView(model: model, media: model.media, lyrics: model.lyrics).padding(.horizontal, 24).padding(.vertical, 12)
                .frame(width: Layout.panelWidth, height: Layout.contentHeight))),
            ("compact", AnyView(CompactRow(model: model, media: model.media, metrics: m).padding(8))),
            ("mascots", AnyView(HStack(spacing: 18) {
                ForEach([AgentPhase.working, .waiting, .done, .failed, .idle, .stale], id: \.self) { phase in
                    VStack(spacing: 6) { DropletMascot(phase: phase, size: 64); Text(phase.shortTitle).font(.caption).foregroundStyle(.white) }
                }
            }.padding(20))),
            ("agents", AnyView(AgentPanelView(service: model.agents).padding(.horizontal, 24).padding(.vertical, 12)
                .frame(width: Layout.panelWidth, height: Layout.contentHeight)))
        ]
        for (name, view) in pairs {
            let renderer = ImageRenderer(content: view.background(Color.black).environment(\.colorScheme, .dark))
            renderer.scale = 2
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "/tmp/damla-render-\(name).png"))
            }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        manager.show(); return true
    }
    @objc func showPanel() { manager.show() }
    @objc func showSettings() { model.openSettings() }
    @objc func showOnboarding() { onboarding.present() }
    @objc func startCleaning() { manager.show(); model.startCleaning() }
    @objc func checkForUpdates() { model.updater.checkForUpdates() }
    @objc func quit() { NSApp.terminate(nil) }
    private func registerShortcut() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { delegate.manager.toggle() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        let identifier = EventHotKeyID(signature: 0x444D4C41, id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), identifier, GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { model.showNotice(String(localized: "Kısayol kullanılıyor. Menüdeki damladan açabilirsin.")) }
    }
    func applicationWillTerminate(_ notification: Notification) {
        model.media.restoreDucked()   // never leave the music quiet after a ducked handoff
        model.appVolumes.stopAll()
        model.cleaning.onEnd = nil
        model.cleaning.stop()
        model.keys.stop()
        model.agents.stop()
        model.saveSession()
        model.media.bridge.stop()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}


/// Which displays currently show a full-screen Space. Private SkyLight call (loaded lazily, so a missing
/// symbol only disables the check): `CGSCopyManagedDisplaySpaces` lists every display's current Space,
/// and type 4 is a full-screen one (measured on macOS 27).
enum FullScreenSpaces {
    private typealias ConnectionFn = @convention(c) () -> Int32
    private typealias SpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private static let functions: (ConnectionFn, SpacesFn)? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
              let connection = dlsym(handle, "CGSMainConnectionID"), let spaces = dlsym(handle, "CGSCopyManagedDisplaySpaces")
        else { return nil }
        return (unsafeBitCast(connection, to: ConnectionFn.self), unsafeBitCast(spaces, to: SpacesFn.self))
    }()

    static func current() -> Set<UInt32> {
        guard let (connection, copySpaces) = functions,
              let displays = copySpaces(connection())?.takeRetainedValue() as? [[String: Any]] else { return [] }
        var result = Set<UInt32>()
        for display in displays {
            guard (display["Current Space"] as? [String: Any])?["type"] as? Int == 4 else { continue }
            let identifier = display["Display Identifier"] as? String
            for screen in NSScreen.screens {
                // "Main" when all displays share one Space.
                let uuid = CGDisplayCreateUUIDFromDisplayID(screen.displayID).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
                if identifier == "Main" || identifier == uuid { result.insert(screen.displayID) }
            }
        }
        return result
    }
}
