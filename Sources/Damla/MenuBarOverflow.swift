import AppKit
import ApplicationServices

/// Reads menu bar items through Accessibility: the frontmost app's menus and every app's status items, with
/// where they sit on screen (Accessibility coordinates: origin at the top left of the main display).
enum MenuBarItems {
    struct Item {
        let title: String
        let frame: CGRect
        let element: AXUIElement
        let app: NSRunningApplication
    }

    static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
    static func frame(_ element: AXUIElement) -> CGRect {
        var point = CGPoint.zero, size = CGSize.zero
        if let value: AXValue = attribute(element, kAXPositionAttribute) { AXValueGetValue(value, .cgPoint, &point) }
        if let value: AXValue = attribute(element, kAXSizeAttribute) { AXValueGetValue(value, .cgSize, &size) }
        return CGRect(origin: point, size: size)
    }
    static func children(_ element: AXUIElement) -> [AXUIElement] { attribute(element, kAXChildrenAttribute) ?? [] }

    /// The app's menus in the menu bar, Apple menu excluded.
    static func appMenus(_ app: NSRunningApplication) -> [Item] {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.3)
        guard let bar: AXUIElement = attribute(ax, kAXMenuBarAttribute) else { return [] }
        return children(bar).dropFirst().map { Item(title: attribute($0, kAXTitleAttribute) ?? "", frame: frame($0), element: $0, app: app) }
    }

    /// Status items of every app that can have one. Background-only processes cannot, so they are not asked;
    /// the rest answer quickly, and a stuck one gives up after 0.15 s.
    static func statusItems() -> [Item] {
        let me = getpid()
        return NSWorkspace.shared.runningApplications.filter { $0.activationPolicy != .prohibited && $0.processIdentifier != me }.flatMap { app -> [Item] in
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(ax, 0.15)
            guard let extras: AXUIElement = attribute(ax, "AXExtrasMenuBar") else { return [] }
            return children(extras).map { element in
                let title: String = attribute(element, kAXTitleAttribute) ?? ""
                let help: String = attribute(element, kAXDescriptionAttribute) ?? attribute(element, kAXHelpAttribute) ?? ""
                return Item(title: title.isEmpty ? help : title, frame: frame(element), element: element, app: app)
            }
        }
    }
}

/// Status items macOS cannot show on a notched display: the ones that fall behind the notch, and the ones the
/// frontmost app's long menus run over. Damla's own menu bar menu lists them; picking one opens its menu.
final class MenuBarOverflow {
    /// Called on the main thread whenever the hidden set changes (count for the badge).
    var onChange: ((Int) -> Void)?
    private(set) var hidden: [MenuBarItems.Item] = []
    private var cached: [MenuBarItems.Item] = []
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private let queue = DispatchQueue(label: "app.local.damla.menubar", qos: .utility)
    private var scanning = false

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        // A new app may bring a status item; another app in front has other menus to collide with.
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.refresh(rescan: true) }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh(rescan: false)
        })
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh(rescan: true) }
        timer?.tolerance = 5
        refresh(rescan: true)
    }

    /// `rescan` asks every app for its status items again; otherwise only their positions against the new
    /// frontmost app's menus are checked.
    func refresh(rescan: Bool) {
        guard AXIsProcessTrusted(), let band = Self.notchBand(), !scanning else { return }
        scanning = true
        let front = NSWorkspace.shared.frontmostApplication
        queue.async { [weak self] in
            guard let self else { return }
            let items = rescan || self.cached.isEmpty ? MenuBarItems.statusItems() : self.cached.map {
                MenuBarItems.Item(title: $0.title, frame: MenuBarItems.frame($0.element), element: $0.element, app: $0.app)
            }
            let menus = front.map(MenuBarItems.appMenus) ?? []
            let hidden = Self.hidden(items, notch: band.notch, bar: band.bar, menus: menus.map(\.frame))
            DispatchQueue.main.async {
                self.cached = items
                self.scanning = false
                let changed = hidden.map(\.frame) != self.hidden.map(\.frame)
                self.hidden = hidden
                if changed { self.onChange?(hidden.count) }
            }
        }
    }

    /// The notch and the menu bar strip of the notched display, in Accessibility coordinates.
    static func notchBand() -> (notch: CGRect, bar: CGRect)? {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
              let mainHeight = NSScreen.screens.first?.frame.height else { return nil }
        let top = mainHeight - screen.frame.maxY
        let height = screen.safeAreaInsets.top
        return (CGRect(x: left.maxX, y: top, width: right.minX - left.maxX, height: height),
                CGRect(x: screen.frame.minX, y: top, width: screen.frame.width, height: height))
    }

    /// On the notched display's menu bar, behind the notch or under one of the app's menus.
    static func hidden(_ items: [MenuBarItems.Item], notch: CGRect, bar: CGRect, menus: [CGRect]) -> [MenuBarItems.Item] {
        items.filter { item in
            let frame = item.frame
            guard frame.width > 0, frame.midY >= bar.minY, frame.midY <= bar.maxY, frame.midX >= bar.minX, frame.midX <= bar.maxX else { return false }
            return frame.intersects(notch.insetBy(dx: 2, dy: 0)) || menus.contains { $0.intersects(frame.insetBy(dx: 2, dy: 0)) }
        }
        .sorted { $0.frame.minX < $1.frame.minX }
    }

    /// Opens the item's own menu, as a click on it would.
    static func open(_ item: MenuBarItems.Item) {
        if AXUIElementPerformAction(item.element, kAXPressAction as CFString) != .success {
            AXUIElementPerformAction(item.element, "AXShowMenu" as CFString)
        }
    }

    /// Debug: what is hidden right now, to /tmp/damla-menubar.txt.
    func dump() {
        let lines = ["trusted: \(AXIsProcessTrusted())", "band: \(String(describing: Self.notchBand()))", "known: \(cached.count)"]
            + hidden.map { "hidden: \($0.app.localizedName ?? "?") \($0.title) \($0.frame)" }
        try? lines.joined(separator: "\n").write(toFile: "/tmp/damla-menubar.txt", atomically: true, encoding: .utf8)
    }
}
