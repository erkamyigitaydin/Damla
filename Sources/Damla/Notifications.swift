import AppKit
import ApplicationServices
import Combine
import SwiftUI

/// A system notification as the notch shows it, read from the banner Notification Center put on screen.
struct MirroredNotification: Identifiable, Equatable {
    let id: String          // the banner's AXIdentifier (a UUID per notification)
    var app: String
    var bundleID: String?
    var title: String
    var subtitle: String
    var body: String
    /// The banner's own buttons once its details are open (Reply, Accept, Mark as Read…), in order.
    var actions: [String] = []
    var arrived = Date()
}

/// Pure pieces of the banner reading, kept apart from Accessibility so the self-tests can check them.
enum BannerText {
    /// The banner's description is "App, title, subtitle, body"; the app is what comes before the title.
    static func appName(description: String, title: String) -> String {
        if !title.isEmpty, let range = description.range(of: ", " + title) { return String(description[..<range.lowerBound]) }
        return description.components(separatedBy: ", ").first ?? description
    }
    /// Messaging apps pad names with invisible direction marks (WhatsApp's U+200E); drop them.
    static func clean(_ text: String) -> String {
        String(text.unicodeScalars.filter { !$0.properties.isDefaultIgnorableCodePoint }).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// Custom actions arrive as "Name:Kapat\nTarget:0x0\nSelector:(null)"; the name is localized.
    static func actionName(_ raw: String) -> String? {
        guard raw.hasPrefix("Name:") else { return nil }
        return String(raw.dropFirst(5).prefix { $0 != "\n" })
    }
    static let showDetails: Set<String> = ["Ayrıntıları Göster", "Show Details"]
    static let hideDetails: Set<String> = ["Ayrıntıları Gizle", "Hide Details"]
    static let close: Set<String> = ["Kapat", "Close", "Temizle", "Clear"]
    /// Picks a banner action by its name in Turkish or English; otherwise by where macOS puts it
    /// (details first, close last), so another system language still works.
    static func pick(_ names: [String], _ wanted: Set<String>, fallbackFirst: Bool) -> String? {
        let custom = names.filter { actionName($0) != nil }
        return custom.first { wanted.contains(actionName($0)!) } ?? (fallbackFirst ? custom.first : custom.last)
    }
}

/// Shows other apps' notifications in the notch. Reads Notification Center's banners through Accessibility
/// (no other permission), moves the system banner off screen while the notch shows it, and passes clicks,
/// buttons and replies back to the banner so the app gets them exactly as if the banner had been used.
final class NotificationMirror: ObservableObject {
    static let centerBundleID = "com.apple.notificationcenterui"
    static let showFor: TimeInterval = 6

    @Published var enabled = UserDefaults.standard.object(forKey: "notificationsInNotch") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "notificationsInNotch"); restart() }
    }
    /// Hide the system banner while the notch shows its copy. Buttons and replies need it (the banner is
    /// opened off screen when the pointer comes onto the card); without it the notch shows the text and opens the app.
    @Published var hideBanners = UserDefaults.standard.object(forKey: "hideSystemBanners") as? Bool ?? true {
        didSet { UserDefaults.standard.set(hideBanners, forKey: "hideSystemBanners") }
    }
    @Published private(set) var current: MirroredNotification?
    /// Everything read this session, newest first. Kept in memory only: message texts never touch the disk.
    @Published private(set) var history: [MirroredNotification] = []
    @Published private(set) var unread = 0
    static let historyLimit = 60
    var isViewing: () -> Bool = { false }
    @Published private(set) var trusted = AXIsProcessTrusted()
    /// A reply is being written in the notch (the banner's own text field waits off screen): the card stays.
    @Published private(set) var replying = false
    /// The banner came with its reply field already open (WhatsApp): the notch shows a field straight away,
    /// which holds the card only once it is clicked into.
    @Published private(set) var inlineReply = false
    @Published var replyText = ""
    /// The pointer is on the card: it stays until the pointer has been gone a few seconds.
    var hovering = false {
        didSet {
            guard hovering != oldValue else { return }
            scheduleEnd(after: hovering ? nil : 4)
        }
    }
    /// The card was clicked open: the banner's buttons or reply field show under the text, with "Aç" beside them.
    @Published private(set) var revealed = false
    /// Whether the notch can take a notification now (not open, not hidden by a full-screen app).
    var canTakeOver: () -> Bool = { true }
    var onShow: (() -> Void)?

    private var observer: AXObserver?
    private var centerApp: AXUIElement?
    private var centerPID: pid_t = 0
    private var banner: AXUIElement?      // the system banner behind `current`
    private var window: AXUIElement?      // Notification Center's window holding it
    private var detailsOpen = false       // the banner's details were opened by us (it then never times out)
    private var watchdog: Timer?
    private var replyField: AXUIElement?
    private var buttonsBeforeReply: Set<String> = []
    private var seen: [String] = []        // banner ids already handled, newest last
    private var endWork: DispatchWorkItem?
    private var trustTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    var cardHeight: CGFloat {
        guard let current else { return 0 }
        return 86 + (revealed || replying ? 38 : 0)
    }

    func start() {
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .filter { $0.bundleIdentifier == Self.centerBundleID }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.restart() }   // Notification Center restarted: follow the new process
            .store(in: &cancellables)
        Self.indexApplications()
        restart()
    }

    private func restart() {
        restoreWindows()
        detach()
        trustTimer?.invalidate(); trustTimer = nil
        watchdog?.invalidate(); watchdog = nil
        guard enabled else { return }
        trusted = AXIsProcessTrusted()
        MediaService.trace("notifications: trusted=\(trusted)")
        guard trusted else {
            // Granted later in System Settings: pick it up without a relaunch.
            let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
                guard let self, AXIsProcessTrusted() else { return }
                self.restart()
            }
            RunLoop.main.add(timer, forMode: .common)
            trustTimer = timer
            return
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.centerBundleID).first else { return }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.4)
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, context in
            guard let context else { return }
            Unmanaged<NotificationMirror>.fromOpaque(context).takeUnretainedValue().sweep()
        }
        guard AXObserverCreate(app.processIdentifier, callback, &created) == .success, let created else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        // A banner arriving creates the window (the first one) or changes the layout (the next ones); one
        // leaving changes the layout and destroys its element.
        for name in [kAXWindowCreatedNotification, kAXLayoutChangedNotification, kAXUIElementDestroyedNotification] {
            AXObserverAddNotification(created, element, name as CFString, context)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created; centerApp = element; centerPID = app.processIdentifier
        MediaService.trace("notifications: watching pid \(app.processIdentifier)")
        // Notification Center is a background agent: its relaunch posts no workspace notification. Follow it.
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            guard let self else { return }
            let pid = NSRunningApplication.runningApplications(withBundleIdentifier: Self.centerBundleID).first?.processIdentifier ?? 0
            if pid != self.centerPID { self.restart() }
        }
        timer.tolerance = 3
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
        adoptLeftovers()
    }

    /// Quitting or switching off: Notification Center keeps reusing its window, so it must not stay off screen.
    /// Moved back even with a banner in it (its glass then shows a stale backdrop until it goes).
    func restoreWindows() {
        guard let centerApp else { return }
        for window in Self.children(centerApp, kAXWindowsAttribute) where Self.isOffScreen(window) {
            Self.banners(in: window).forEach(collapse)   // opened ones would never time out on their own
            Self.restore(window)
        }
    }

    private func detach() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil; centerApp = nil
    }

    // MARK: Reading banners

    private func sweep() {
        guard enabled, let centerApp else { return }
        for window in Self.children(centerApp, kAXWindowsAttribute) {
            let banners = Self.banners(in: window)
            // Emptied: back where it was, ready to show the next banner itself if the notch cannot.
            if banners.isEmpty { Self.restoreIfEmpty(window); continue }
            guard let newest = banners.first, let id = Self.string(newest, "AXIdentifier"), !seen.contains(id) else { continue }
            if let banner, CFEqual(banner, newest) { seen.append(id); continue }   // the shown one, relabelled on opening
            seen.append(id); if seen.count > 50 { seen.removeFirst(seen.count - 50) }
            // The notch is busy (open, hidden by full screen, or a reply is being written): the system banner
            // shows as usual. Unless its window is already off screen for an earlier one: moving it back leaves
            // the banners' glass showing a stale backdrop, so the notch takes this one too.
            guard let note = Self.read(newest, id: id) else { continue }
            record(note)   // on the page whether or not the notch shows it
            let hidden = Self.isOffScreen(window)
            MediaService.trace("notifications: banner \(id) takeOver=\(canTakeOver()) replying=\(replying) hidden=\(hidden)")
            guard hidden || (canTakeOver() && !replying) else { continue }
            show(note, element: newest, window: window)
        }
    }

    /// The banner's text as the notch shows it; nil for an empty one.
    private static func read(_ element: AXUIElement, id: String) -> MirroredNotification? {
        var text: [String: String] = [:]
        for child in children(element, kAXChildrenAttribute) {
            if let key = string(child, "AXIdentifier"), let value = string(child, kAXValueAttribute) { text[key] = BannerText.clean(value) }
        }
        let title = text["title"] ?? ""
        let app = BannerText.clean(BannerText.appName(description: string(element, kAXDescriptionAttribute) ?? "", title: title))
        guard !title.isEmpty || !(text["body"] ?? "").isEmpty else { return nil }
        let bundleID = NSWorkspace.shared.runningApplications.first { $0.localizedName == app }?.bundleIdentifier ?? installed[app]
        return MirroredNotification(id: id, app: app, bundleID: bundleID, title: title, subtitle: text["subtitle"] ?? "", body: text["body"] ?? "")
    }

    private func record(_ note: MirroredNotification) {
        history.insert(note, at: 0)
        if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
        if !isViewing() { unread += 1 }
    }

    func markRead() { if unread != 0 { unread = 0 } }
    func remove(_ note: MirroredNotification) { history.removeAll { $0.id == note.id } }
    func clearHistory() { history.removeAll(); unread = 0 }

    /// An entry on the page: the live banner still answers (the right conversation); an older one opens its app.
    func open(_ note: MirroredNotification) {
        if current?.id == note.id { open(); return }
        guard let id = note.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func show(_ note: MirroredNotification, element: AXUIElement, window: AXUIElement) {
        if current != nil { finish(collapsing: true) }   // the older one goes back to timing out
        banner = element
        self.window = window
        current = note
        // Alerts (calendar, reminders) never time out; they stay on screen, where they wait for an answer.
        let alert = Self.windowHasAlert(window)
        if hideBanners && !alert { Self.moveOffScreen(window) }
        onShow?()
        scheduleEnd(after: Self.showFor)
    }

    // MARK: What the notch does with it

    /// A click on the card, the same for every app: the first one opens the banner's details off screen and
    /// brings its buttons (or its reply field, ready to type in) under the text; the card then holds until used
    /// or the pointer leaves. With nothing to reveal (no buttons, banner gone, system banner not hidden), it opens.
    func tapCard() {
        guard !revealed else { open(); return }
        guard hideBanners, !detailsOpen, let current, let banner, let window, Self.isOffScreen(window),
              Self.alive(banner, id: current.id),
              let action = BannerText.pick(Self.actions(banner), BannerText.showDetails, fallbackFirst: true),
              !BannerText.hideDetails.contains(BannerText.actionName(action) ?? "") else { open(); return }
        detailsOpen = AXUIElementPerformAction(banner, action as CFString) == .success
        scheduleEnd(after: hovering ? nil : 4)
        let id = current.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.current?.id == id else { return }
            let buttons = Self.buttons(in: banner)
            MediaService.trace("notifications: \(current.app) buttons=\(buttons.map(\.label)) field=\(Self.textField(in: banner) != nil)")
            if let field = Self.textField(in: banner) {
                // Its button is the send button; the notch's field and its arrow stand in for both. The click
                // was the intent to answer: the field takes the keyboard at once.
                self.replyField = field
                self.buttonsBeforeReply = []
                self.inlineReply = true
                self.replying = true
                self.scheduleEnd(after: nil)
            } else if !buttons.isEmpty {
                self.current?.actions = buttons.map(\.label)
            }
            self.revealed = true
        }
    }

    /// The card itself: the banner's default action, which opens the app at the right conversation.
    func open() {
        guard let current else { return }
        if let banner, Self.alive(banner, id: current.id) { AXUIElementPerformAction(banner, kAXPressAction as CFString) }
        else if let bundleID = current.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
        finish(collapsing: false)
    }

    /// One of the banner's buttons. A reply button opens a text field in the banner; the notch then shows its own.
    func perform(_ index: Int) {
        guard let current, let banner, Self.alive(banner, id: current.id) else { finish(collapsing: false); return }
        let buttons = Self.buttons(in: banner)
        guard index < buttons.count else { return }
        buttonsBeforeReply = Set(buttons.map(\.label))
        AXUIElementPerformAction(buttons[index].element, kAXPressAction as CFString)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.current?.id == current.id else { return }
            let field = Self.textField(in: banner)
            MediaService.trace("notifications: pressed button \(index), field=\(field != nil) buttons=\(Self.buttons(in: banner).map(\.label))")
            if let field {
                self.replyField = field
                self.replyText = ""
                self.replying = true
                self.scheduleEnd(after: nil)   // a reply is being written: stay
            } else {
                self.finish(collapsing: false)
            }
        }
    }

    /// Writes the reply into the banner's field and sends it the way the banner would.
    func sendReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let banner, let field = replyField, !text.isEmpty else { return }
        AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, text as CFTypeRef)
        // The send button is the one that came with the field; Return (AXConfirm) where there is none.
        if let send = Self.buttons(in: banner).last(where: { !buttonsBeforeReply.contains($0.label) }) {
            AXUIElementPerformAction(send.element, kAXPressAction as CFString)
        } else {
            AXUIElementPerformAction(field, kAXConfirmAction as CFString)
        }
        finish(collapsing: false)
    }

    /// The pointer went into the reply field or typing began: hold the card until it is sent or dropped.
    func beginReply() {
        guard replyField != nil, !replying else { return }
        replying = true
        scheduleEnd(after: nil)
    }

    func cancelReply() {
        endReply()
        scheduleEnd(after: 2.5)
    }

    /// The notch's ✕: the notification goes away for good, as with the banner's own close button.
    func close() {
        if let current, let banner, Self.alive(banner, id: current.id),
           let action = BannerText.pick(Self.actions(banner), BannerText.close, fallbackFirst: false) {
            AXUIElementPerformAction(banner, action as CFString)
        }
        finish(collapsing: false)
    }

    private func endReply() {
        replying = false; inlineReply = false; replyField = nil; replyText = ""; buttonsBeforeReply = []
        if current?.actions.isEmpty ?? true { revealed = false }
    }

    private func scheduleEnd(after delay: TimeInterval?) {
        endWork?.cancel(); endWork = nil
        guard let delay, current != nil, !replying else { return }
        let work = DispatchWorkItem { [weak self] in self?.finish(collapsing: true) }
        endWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Time is up (or the notification was used). A banner we opened is closed up again so it times out into
    /// Notification Center's list like any other.
    private func finish(collapsing: Bool) {
        endWork?.cancel(); endWork = nil
        if collapsing, detailsOpen, let banner, let id = current?.id, Self.alive(banner, id: id) {
            collapse(banner)
            dismissLater(banner, id: id)
        }
        endReply()
        revealed = false
        detailsOpen = false
        banner = nil
        window = nil
        current = nil
        hovering = false
    }

    /// A banner that still hangs on off screen well after its lifetime (a reply field keeps some open) is
    /// dismissed: it was seen in the notch, and an opened banner holds back every notification after it.
    private func dismissLater(_ banner: AXUIElement, id: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.current?.id != id, Self.alive(banner, id: id),
                  !(Self.string(banner, kAXSubroleAttribute)?.hasPrefix("AXNotificationCenterAlert") ?? false),
                  let action = BannerText.pick(Self.actions(banner), BannerText.close, fallbackFirst: false) else { return }
            MediaService.trace("notifications: dismissing leftover \(id)")
            AXUIElementPerformAction(banner, action as CFString)
        }
    }

    /// Banners an earlier run hid (or left open) are closed up to time out as usual; their window comes back
    /// once it is empty.
    private func adoptLeftovers() {
        guard let centerApp else { return }
        for window in Self.children(centerApp, kAXWindowsAttribute) where Self.isOffScreen(window) {
            let banners = Self.banners(in: window)
            if banners.isEmpty { Self.restore(window); continue }
            for banner in banners {
                guard let id = Self.string(banner, "AXIdentifier") else { continue }
                seen.append(id)
                collapse(banner)
                dismissLater(banner, id: id)
            }
        }
    }

    private func collapse(_ element: AXUIElement) {
        guard let action = Self.actions(element).first(where: { BannerText.hideDetails.contains(BannerText.actionName($0) ?? "") }) else { return }
        AXUIElementPerformAction(element, action as CFString)
    }

    /// Installed apps by the name the banner shows (localized: "Betik Düzenleyici"), for apps that post while not
    /// running. Built once in the background at start.
    private static var installed: [String: String] = [:]
    private static func indexApplications() {
        DispatchQueue.global(qos: .utility).async {
            var names: [String: String] = [:]
            let roots = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
            for root in roots {
                for item in (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [] where item.hasSuffix(".app") {
                    let path = root + "/" + item
                    guard let id = Bundle(path: path)?.bundleIdentifier else { continue }
                    let shown = (FileManager.default.displayName(atPath: path) as NSString).deletingPathExtension
                    names[shown] = names[shown] ?? id
                    names[(item as NSString).deletingPathExtension] = names[(item as NSString).deletingPathExtension] ?? id
                }
            }
            DispatchQueue.main.async { installed = names }
        }
    }

    // MARK: Accessibility helpers

    private static func value(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    private static func string(_ element: AXUIElement, _ name: String) -> String? { value(element, name) as? String }
    private static func children(_ element: AXUIElement, _ name: String) -> [AXUIElement] { value(element, name) as? [AXUIElement] ?? [] }
    private static func actions(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        AXUIElementCopyActionNames(element, &names)
        return names as? [String] ?? []
    }
    private static func alive(_ element: AXUIElement, id: String) -> Bool { string(element, "AXIdentifier") == id }

    /// Banners in a window, the newest (top) first.
    private static func banners(in element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 6 else { return [] }
        if let sub = string(element, kAXSubroleAttribute), sub.hasPrefix("AXNotificationCenterBanner") || sub.hasPrefix("AXNotificationCenterAlert") {
            // A stack holds its banners as children; take them, else the element itself.
            let inner = children(element, kAXChildrenAttribute).flatMap { banners(in: $0, depth: depth + 1) }
            return inner.isEmpty ? [element] : inner
        }
        return children(element, kAXChildrenAttribute).flatMap { banners(in: $0, depth: depth + 1) }
    }

    /// The app's buttons in an opened banner: not the chevron, not the "more actions" menu.
    private static func buttons(in element: AXUIElement) -> [(label: String, element: AXUIElement)] {
        var found: [(String, AXUIElement)] = []
        func walk(_ node: AXUIElement, _ depth: Int) {
            guard depth < 5 else { return }
            for child in children(node, kAXChildrenAttribute) {
                if string(child, kAXRoleAttribute) == kAXButtonRole as String,
                   !(string(child, "AXIdentifier") ?? "").hasPrefix("chevron") {
                    let label = [string(child, kAXTitleAttribute), string(child, kAXDescriptionAttribute)].compactMap { $0 }.first { !$0.isEmpty }
                    if let label { found.append((BannerText.clean(label), child)) }
                }
                walk(child, depth + 1)
            }
        }
        walk(element, 0)
        return found
    }

    private static func textField(in element: AXUIElement) -> AXUIElement? {
        for child in children(element, kAXChildrenAttribute) {
            let role = string(child, kAXRoleAttribute)
            if role == kAXTextFieldRole as String || role == kAXTextAreaRole as String { return child }
            if let inner = textField(in: child) { return inner }
        }
        return nil
    }

    /// Notification Center draws every banner in one screen-sized window; pushing it far above the screens
    /// hides the banners while they keep working. The window is made anew for the next notification.
    private static let offScreen = CGPoint(x: 0, y: -20_000)
    /// Where each window sat before it was moved (Notification Center reuses its window for later banners).
    private static var homes: [CFHashCode: CGPoint] = [:]
    /// Banners drawn off screen keep a stale glass backdrop if their window comes back while they show, so the
    /// window goes back only once it is empty (or when Damla lets go of it).
    private static func moveOffScreen(_ window: AXUIElement) {
        guard !isOffScreen(window) else { return }
        homes[CFHash(window)] = position(window) ?? .zero
        setPosition(window, offScreen)
    }
    private static func restoreIfEmpty(_ window: AXUIElement) {
        guard isOffScreen(window), banners(in: window).isEmpty else { return }
        restore(window)
    }
    private static func restore(_ window: AXUIElement) {
        guard isOffScreen(window) else { return }
        setPosition(window, homes.removeValue(forKey: CFHash(window)) ?? .zero)
    }
    private static func position(_ window: AXUIElement) -> CGPoint? {
        var point = CGPoint.zero
        guard let value = value(window, kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }
    static func isOffScreen(_ window: AXUIElement) -> Bool { (position(window)?.y ?? 0) <= offScreen.y / 2 }
    private static func windowHasAlert(_ window: AXUIElement) -> Bool {
        banners(in: window).contains { string($0, kAXSubroleAttribute)?.hasPrefix("AXNotificationCenterAlert") ?? false }
    }
    private static func setPosition(_ window: AXUIElement, _ point: CGPoint) {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }
}

// MARK: - The card

/// Another app's notification in the notch: its icon, app, title and text; a click opens it where it belongs,
/// the app's own buttons sit underneath, and a reply button turns the row into a text field.
struct NotificationCard: View {
    @ObservedObject var model: AppState
    @ObservedObject var mirror: NotificationMirror
    @FocusState private var fieldFocused: Bool

    var body: some View {
        if let note = mirror.current {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 11) {
                    icon(note).frame(width: 34, height: 34).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 1.5) {
                        HStack(spacing: 6) {
                            Text(verbatim: note.app).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.dim).lineLimit(1)
                            Spacer(minLength: 4)
                            Button { mirror.close() } label: {
                                Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold)).foregroundStyle(Theme.dim)
                                    .frame(width: 16, height: 16).background(Theme.fill, in: Circle()).contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help("Bildirimi kapat")
                        }
                        if !note.title.isEmpty {
                            Text(verbatim: note.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                        }
                        if !note.subtitle.isEmpty {
                            Text(verbatim: note.subtitle).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                        }
                        if !note.body.isEmpty {
                            Text(verbatim: note.body).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.78))
                                .lineLimit(note.subtitle.isEmpty ? 2 : 1)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { mirror.tapCard() }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(Text("Tıkla: yanıtla ya da düğmeleri göster"))
                if mirror.replying || mirror.inlineReply { replyRow } else if mirror.revealed { actionRow(note) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .id(note.id)
        }
    }

    @ViewBuilder private func icon(_ note: MirroredNotification) -> some View {
        if let id = note.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().interpolation(.high)
        } else {
            Image(systemName: "bell.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 34, height: 34).background(Theme.fillStrong, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private func actionRow(_ note: MirroredNotification) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(note.actions.prefix(3).enumerated()), id: \.offset) { index, label in
                Button { mirror.perform(index) } label: {
                    Text(verbatim: label).font(.system(size: 11, weight: .medium)).lineLimit(1)
                }
                .buttonStyle(PillStyle(accent: index == 0))
            }
            Spacer(minLength: 0)
            openButton
        }
        .padding(.leading, 45)
        .frame(height: 28)
    }

    /// Opens the notification where it belongs (the conversation, the event), as a click on the banner would.
    private var openButton: some View {
        Button { mirror.open() } label: {
            Label("Aç", systemImage: "arrow.up.forward.app").font(.system(size: 11, weight: .medium)).lineLimit(1)
        }
        .buttonStyle(PillStyle())
        .help("Uygulamada aç")
    }

    private var replyRow: some View {
        HStack(spacing: 8) {
            TextField("Yanıtla…", text: $mirror.replyText)
                .textFieldStyle(.plain).font(.system(size: 12))
                .focused($fieldFocused)
                // The notch window does not take the keyboard by itself; a click in the field asks for it.
                .simultaneousGesture(TapGesture().onEnded { model.requestKeyFocus?(); fieldFocused = true })
                .onSubmit { mirror.sendReply() }
                .padding(.horizontal, 11).frame(height: 28)
                .background(Theme.fill, in: Capsule())
            Button { mirror.sendReply() } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(mirror.replyText.trimmingCharacters(in: .whitespaces).isEmpty)
            .help("Gönder")
            openButton
        }
        .padding(.leading, 45)
        .onAppear {
            // The click that brought the field up (or a Reply button) was the intent to answer: type straight away.
            guard mirror.replying else { return }
            model.requestKeyFocus?()
            DispatchQueue.main.async { fieldFocused = true }
        }
        .onChange(of: fieldFocused) { _, focused in if focused { mirror.beginReply() } }
        .onChange(of: mirror.replyText) { _, text in if !text.isEmpty { mirror.beginReply() } }
    }
}

// MARK: - The page

/// Bildirimler: what came in this session, grouped by app (the app with the newest one first). A click opens it,
/// the ✕ drops it. Nothing here is written to disk; it is gone when Damla quits.
struct NotificationsView: View {
    @ObservedObject var model: AppState
    @ObservedObject var mirror: NotificationMirror

    private struct AppGroup: Identifiable {
        let app: String
        let bundleID: String?
        var notes: [MirroredNotification]
        var id: String { app }
    }
    private var groups: [AppGroup] {
        var order: [String] = [], byApp: [String: AppGroup] = [:]
        for note in mirror.history {
            if byApp[note.app] == nil { order.append(note.app); byApp[note.app] = AppGroup(app: note.app, bundleID: note.bundleID, notes: []) }
            byApp[note.app]?.notes.append(note)
        }
        return order.compactMap { byApp[$0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if mirror.history.isEmpty {
                empty
            } else {
                HStack {
                    Text("\(mirror.history.count) bildirim").font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.dim)
                    Spacer()
                    Button("Temizle") { withAnimation(Theme.quick) { mirror.clearHistory() } }
                        .font(.system(size: 10.5, weight: .medium)).buttonStyle(PillStyle())
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    appIcon(group.bundleID).frame(width: 15, height: 15)
                                    Text(verbatim: group.app).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.dim)
                                }
                                ForEach(group.notes) { note in HistoryRow(note: note, mirror: mirror) }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: mirror.enabled && mirror.trusted ? "bell" : "bell.slash").font(.system(size: 22, weight: .light)).foregroundStyle(Theme.faint)
            if !mirror.enabled {
                Text("Bildirimler çentikte kapalı").font(.system(size: 11)).foregroundStyle(Theme.faint)
                Button("Aç") { mirror.enabled = true }.font(.system(size: 10.5, weight: .medium)).buttonStyle(PillStyle())
            } else if !mirror.trusted {
                Text("Erişilebilirlik izni gerekli").font(.system(size: 11)).foregroundStyle(Theme.faint)
                Button("Ayarları aç") { MediaKeyInterceptor.openAccessibilitySettings() }.font(.system(size: 10.5, weight: .medium)).buttonStyle(PillStyle())
            } else {
                Text("Henüz bildirim yok").font(.system(size: 11)).foregroundStyle(Theme.faint)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func appIcon(_ bundleID: String?) -> some View {
        if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().interpolation(.high)
        } else {
            Image(systemName: "bell.fill").font(.system(size: 9)).foregroundStyle(Theme.dim)
        }
    }
}

private struct HistoryRow: View {
    let note: MirroredNotification
    @ObservedObject var mirror: NotificationMirror
    @State private var hovering = false
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(verbatim: note.title.isEmpty ? note.app : note.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    TimelineView(.everyMinute) { _ in
                        Text(verbatim: Self.age(note.arrived)).font(.system(size: 10, design: .rounded)).monospacedDigit().foregroundStyle(Theme.faint)
                    }
                }
                let text = [note.subtitle, note.body].filter { !$0.isEmpty }.joined(separator: " · ")
                if !text.isEmpty {
                    Text(verbatim: text).font(.system(size: 11)).foregroundStyle(.white.opacity(0.72)).lineLimit(2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { mirror.open(note) }
            Button { withAnimation(Theme.quick) { mirror.remove(note) } } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.dim)
                    .frame(width: 16, height: 16).background(Theme.fill, in: Circle()).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .help("Listeden kaldır")
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(Theme.fill.opacity(hovering ? 1.6 : 1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering = $0 }
        .help(note.bundleID == nil ? "" : String(localized: "Tıkla: \(note.app) uygulamasını aç"))
    }

    /// "şimdi", "5 dk", "2 sa"
    static func age(_ date: Date) -> String {
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 1 { return String(localized: "şimdi") }
        if minutes < 60 { return String(localized: "\(minutes) dk") }
        return String(localized: "\(minutes / 60) sa")
    }
}
