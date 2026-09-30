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
    @Published private(set) var trusted = AXIsProcessTrusted()
    /// A reply is being written in the notch (the banner's own text field waits off screen): the card stays.
    @Published private(set) var replying = false
    /// The banner came with its reply field already open (WhatsApp): the notch shows a field straight away,
    /// which holds the card only once it is clicked into.
    @Published private(set) var inlineReply = false
    @Published var replyText = ""
    /// The pointer is on the card: it stays until the pointer leaves, and the banner's buttons come out.
    var hovering = false {
        didSet {
            guard hovering != oldValue else { return }
            scheduleEnd(after: hovering ? nil : 2.5)
            if hovering { revealActions() }
        }
    }
    /// Whether the notch can take a notification now (not open, not hidden by a full-screen app).
    var canTakeOver: () -> Bool = { true }
    var onShow: (() -> Void)?

    private var observer: AXObserver?
    private var centerApp: AXUIElement?
    private var centerPID: pid_t = 0
    private var banner: AXUIElement?      // the system banner behind `current`
    private var window: AXUIElement?      // Notification Center's window holding it
    private var detailsOpen = false       // the banner's details were opened by us (it then never times out)
    private var leftoverWork: DispatchWorkItem?
    private var watchdog: Timer?
    private var replyField: AXUIElement?
    private var buttonsBeforeReply: Set<String> = []
    private var seen: [String] = []        // banner ids already handled, newest last
    private var endWork: DispatchWorkItem?
    private var trustTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    var cardHeight: CGFloat {
        guard let current else { return 0 }
        return 86 + (replying || inlineReply || (!current.actions.isEmpty && banner != nil) ? 38 : 0)
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
    }

    /// Quitting or switching off: Notification Center keeps reusing its window, so it must not stay off screen.
    /// Moved back even with a banner in it (its glass then shows a stale backdrop until it goes).
    func restoreWindows() {
        guard let centerApp else { return }
        for window in Self.children(centerApp, kAXWindowsAttribute) { Self.restore(window) }
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
            seen.append(id); if seen.count > 50 { seen.removeFirst(seen.count - 50) }
            // The notch is busy (open, hidden by full screen, or a reply is being written): the system banner
            // shows as usual. Unless its window is already off screen for an earlier one: moving it back leaves
            // the banners' glass showing a stale backdrop, so the notch takes this one too.
            let hidden = Self.isOffScreen(window)
            MediaService.trace("notifications: banner \(id) takeOver=\(canTakeOver()) replying=\(replying) hidden=\(hidden)")
            guard hidden || (canTakeOver() && !replying) else { continue }
            show(newest, id: id, window: window)
        }
    }

    private func show(_ element: AXUIElement, id: String, window: AXUIElement) {
        var text: [String: String] = [:]
        for child in Self.children(element, kAXChildrenAttribute) {
            if let key = Self.string(child, "AXIdentifier"), let value = Self.string(child, kAXValueAttribute) { text[key] = BannerText.clean(value) }
        }
        let title = text["title"] ?? ""
        let app = BannerText.clean(BannerText.appName(description: Self.string(element, kAXDescriptionAttribute) ?? "", title: title))
        guard !title.isEmpty || !(text["body"] ?? "").isEmpty else { return }
        let bundleID = NSWorkspace.shared.runningApplications.first { $0.localizedName == app }?.bundleIdentifier ?? Self.installed[app]
        if current != nil { finish(collapsing: true) }   // the older one goes back to timing out
        banner = element
        self.window = window
        current = MirroredNotification(id: id, app: app, bundleID: bundleID, title: title, subtitle: text["subtitle"] ?? "", body: text["body"] ?? "")
        // Alerts (calendar, reminders) never time out; they stay on screen, where they wait for an answer.
        let alert = Self.windowHasAlert(window)
        if hideBanners && !alert { Self.moveOffScreen(window) }
        onShow?()
        scheduleEnd(after: Self.showFor)
    }

    // MARK: What the notch does with it

    /// The pointer came onto the card: open the banner's details off screen to find its buttons or reply field.
    /// Only now, since an opened banner no longer times out by itself.
    private func revealActions() {
        guard hideBanners, !detailsOpen, let current, let banner, let window, Self.isOffScreen(window),
              Self.alive(banner, id: current.id),
              let action = BannerText.pick(Self.actions(banner), BannerText.showDetails, fallbackFirst: true),
              !BannerText.hideDetails.contains(BannerText.actionName(action) ?? "") else { return }
        detailsOpen = AXUIElementPerformAction(banner, action as CFString) == .success
        let id = current.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.current?.id == id else { return }
            if let field = Self.textField(in: banner) {
                // Its button is the send button; the notch's field and its arrow stand in for both.
                self.replyField = field
                self.buttonsBeforeReply = []
                self.inlineReply = true
            } else {
                self.current?.actions = Self.buttons(in: banner).map(\.label)
            }
            MediaService.trace("notifications: \(self.current?.app ?? "") buttons=\(Self.buttons(in: banner).map(\.label)) inline=\(self.inlineReply)")
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
            // One that still hangs on off screen well after its lifetime (a reply field keeps some banners open)
            // is dismissed: it was seen in the notch, and a window stuck off screen would hide the next ones.
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.current?.id != id, Self.alive(banner, id: id),
                      let action = BannerText.pick(Self.actions(banner), BannerText.close, fallbackFirst: false) else { return }
                MediaService.trace("notifications: dismissing leftover \(id)")
                AXUIElementPerformAction(banner, action as CFString)
            }
            leftoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
        }
        endReply()
        detailsOpen = false
        banner = nil
        window = nil
        current = nil
        hovering = false
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
                .onTapGesture { mirror.open() }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(Text("Tıkla: \(note.app) içinde aç"))
                if mirror.replying || mirror.inlineReply { replyRow } else if !note.actions.isEmpty { actionRow(note) }
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
        }
        .padding(.leading, 45)
        .frame(height: 28)
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
        }
        .padding(.leading, 45)
        .onAppear {
            // After a Reply button the keyboard comes here at once; a field that came with the banner waits for a click.
            guard mirror.replying else { return }
            model.requestKeyFocus?()
            DispatchQueue.main.async { fieldFocused = true }
        }
        .onChange(of: fieldFocused) { _, focused in if focused { mirror.beginReply() } }
        .onChange(of: mirror.replyText) { _, text in if !text.isEmpty { mirror.beginReply() } }
    }
}
