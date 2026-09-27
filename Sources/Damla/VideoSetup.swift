import AppKit
import ApplicationServices
import SwiftUI

/// What the video in the notch needs, once, and where each thing is switched on. Shown as a card in Özet when
/// the ⧉ button is pressed with something missing; it rechecks every second and a half while it is open, so a
/// switch flipped in System Settings turns green without closing it.
final class VideoSetup: ObservableObject {
    enum Automation: Equatable { case granted, denied, unasked, notRunning }

    @Published private(set) var accessibility = AXIsProcessTrusted()
    @Published private(set) var screenRecording = CGPreflightScreenCaptureAccess()
    @Published private(set) var automation = Automation.unasked
    /// The browser's "Allow JavaScript from Apple Events" menu item: nil until found (needs Accessibility and a
    /// running browser), then its checkmark.
    @Published private(set) var javaScript: Bool?
    /// That item's name and the menus it sits in, in the browser's own language.
    @Published private(set) var menuItemTitle: String?
    @Published private(set) var menuPlace: String?
    /// Screen Recording was asked for in this run: macOS often reports it only after a relaunch.
    @Published private(set) var askedScreenRecording = false
    private(set) var bundleID = "com.google.Chrome"

    private var menuItem: AXUIElement?
    private var menuItemPID: pid_t = 0
    private var timer: Timer?
    private var scanning = false
    private let queue = DispatchQueue(label: "damla.video.setup", qos: .userInitiated)

    var ready: Bool { accessibility && screenRecording && automation == .granted && javaScript == true }
    /// The checks that answer at once; the menu item is looked up separately.
    var quickReady: Bool {
        refreshQuick()
        return accessibility && screenRecording && automation == .granted && javaScript != false
    }
    /// "Chrome" rather than "Google Chrome": it has to fit a row.
    var browserName: String {
        let name = MediaService.appName(for: bundleID)
        return name.hasPrefix("Google ") ? String(name.dropFirst(7)) : name.hasPrefix("Microsoft ") ? String(name.dropFirst(10)) : name
    }

    func use(_ bundleID: String) {
        guard bundleID != self.bundleID else { return }
        self.bundleID = bundleID
        menuItem = nil; menuItemTitle = nil; menuPlace = nil; javaScript = nil
    }

    func startWatching() {
        refresh()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    func stopWatching() { timer?.invalidate(); timer = nil }

    /// Debug: how the card looks halfway through (the live checks take over on the next refresh).
    func debugHalfway() {
        stopWatching()
        automation = .unasked; javaScript = false
    }

    /// The browser said its JavaScript setting is off (the start failed on it).
    func javaScriptTurnedOff() { if javaScript != false { javaScript = false } }

    func refresh() {
        refreshQuick()
        refreshMenuItem()
    }

    private func refreshQuick() {
        let ax = AXIsProcessTrusted(), screen = CGPreflightScreenCaptureAccess()
        if accessibility != ax { accessibility = ax }
        if screenRecording != screen { screenRecording = screen }
        let state = Self.automation(bundleID, ask: false)
        if automation != state { automation = state }
    }

    // MARK: Actions

    func requestAccessibility() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        Self.openSettings("Privacy_Accessibility")
    }

    func requestScreenRecording() {
        askedScreenRecording = true
        if !CGRequestScreenCaptureAccess() { Self.openSettings("Privacy_ScreenCapture") }
    }

    /// Asks macOS for control of the browser (its own prompt the first time); once refused, only Settings can change it.
    func requestAutomation() {
        if automation == .notRunning || automation == .denied {
            if automation == .denied { Self.openSettings("Privacy_Automation") } else { openBrowser() }
            return
        }
        let bundleID = self.bundleID
        queue.async {
            let state = Self.automation(bundleID, ask: true)
            DispatchQueue.main.async { self.automation = state }
        }
    }

    /// The browser comes forward; the card shows the menu path to click.
    func openBrowser() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: Checks

    static func automation(_ bundleID: String, ask: Bool) -> Automation {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { return .notRunning }
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        switch AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask) {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(procNotFound): return .notRunning
        default: return .unasked
        }
    }

    /// Reads the menu item's checkmark. The first look walks the browser's menus (about a second); after that the
    /// item itself is read.
    private func refreshMenuItem() {
        guard accessibility, let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        if let menuItem, menuItemPID == app.processIdentifier {
            let on = Self.checked(menuItem)
            if javaScript != on { javaScript = on }
            return
        }
        guard !scanning else { return }
        scanning = true
        let pid = app.processIdentifier
        queue.async {
            let found = Self.findMenuItem(pid: pid)
            DispatchQueue.main.async {
                self.scanning = false
                guard let found else { return }
                self.menuItem = found.item
                self.menuItemPID = pid
                self.menuItemTitle = found.path.last
                self.menuPlace = found.path.dropLast().joined(separator: " → ")
                self.javaScript = Self.checked(found.item)
            }
        }
    }

    private static func checked(_ item: AXUIElement) -> Bool {
        var mark: AnyObject?
        AXUIElementCopyAttributeValue(item, "AXMenuItemMarkChar" as CFString, &mark)
        return !((mark as? String) ?? "").isEmpty
    }

    /// The menu item whose title names both JavaScript and Apple Events: brand names, kept in every language.
    private static func findMenuItem(pid: pid_t) -> (item: AXUIElement, path: [String])? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        func attr(_ e: AXUIElement, _ name: String) -> AnyObject? { var v: AnyObject?; AXUIElementCopyAttributeValue(e, name as CFString, &v); return v }
        func walk(_ e: AXUIElement, depth: Int, path: [String]) -> (AXUIElement, [String])? {
            let title = attr(e, kAXTitleAttribute) as? String ?? ""
            if title.contains("JavaScript") && title.contains("Apple") { return (e, path + [title]) }
            guard depth < 5 else { return nil }
            let next = title.isEmpty ? path : path + [title]
            for kid in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
                if let hit = walk(kid, depth: depth + 1, path: next) { return hit }
            }
            return nil
        }
        guard let bar = attr(app, kAXMenuBarAttribute) else { return nil }
        return walk(bar as! AXUIElement, depth: 0, path: []).map { (item: $0.0, path: $0.1) }
    }

    private static func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
}

// MARK: - Card

/// The one-time setup for the video in the notch, as a pane of Özet.
struct VideoSetupView: View {
    @ObservedObject var model: AppState
    @ObservedObject var setup: VideoSetup
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Çentikte video").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Spacer()
                if setup.ready {
                    Button("Başlat") {
                        withAnimation(Theme.quick) { model.homePane = .player }
                        model.startVideo()
                    }
                    .font(.system(size: 11, weight: .semibold)).buttonStyle(PillStyle(accent: true))
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                IconButton(icon: "xmark", label: "Kapat", size: 24) { withAnimation(Theme.quick) { model.homePane = .player } }
            }
            .animation(Theme.quick, value: setup.ready)
            VStack(spacing: 4) {
                row(icon: "accessibility", title: Text("Erişilebilirlik"), detail: Text("Videoya dokunur, pencereyi çentiğe yerleştirir"),
                    done: setup.accessibility, action: Text("İzin ver")) { setup.requestAccessibility() }
                if setup.askedScreenRecording && !setup.screenRecording {
                    row(icon: "record.circle", title: Text("Ekran Kaydı"), detail: Text("İzin verdiysen Damla’yı yeniden başlat"),
                        done: false, action: Text("Yeniden başlat")) { setup.relaunch() }
                } else {
                    row(icon: "record.circle", title: Text("Ekran Kaydı"), detail: Text("Yalnızca videonun penceresi yakalanır"),
                        done: setup.screenRecording, action: Text("İzin ver")) { setup.requestScreenRecording() }
                }
                row(icon: "hand.tap", title: Text("\(setup.browserName) denetimi"), detail: automationDetail,
                    done: setup.automation == .granted, action: automationAction) { setup.requestAutomation() }
                row(icon: "curlybraces", title: Text(setup.menuItemTitle ?? String(localized: "Apple Events’ten JavaScript’e izin ver")),
                    detail: Text("\(setup.browserName) · \(setup.menuPlace ?? String(localized: "Görünüm → Geliştirici")) menüsünde"),
                    done: setup.javaScript == true, action: Text("Aç")) { setup.openBrowser() }
                    .help("Damla videoyu bulup resim içinde resme almak için sekmede küçük bir komut çalıştırır. Bu ayar açıkken, \(setup.browserName) için denetim izni verdiğin uygulamalar sekmelerde JavaScript çalıştırabilir.")
            }
        }
        .onAppear { setup.startWatching() }
        .onDisappear { setup.stopWatching() }
    }

    private var automationDetail: Text {
        switch setup.automation {
        case .notRunning: return Text("\(setup.browserName) açık olmalı")
        case .denied: return Text("Reddedilmiş; Ayarlar → Otomasyon’dan aç")
        default: return Text("Sekmedeki videoyu bulmak için")
        }
    }
    private var automationAction: Text {
        switch setup.automation {
        case .notRunning: return Text("Aç")
        case .denied: return Text("Ayarlar")
        default: return Text("İzin ver")
        }
    }

    private func row(icon: String, title: Text, detail: Text, done: Bool, action: Text, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(done ? Theme.green : Theme.dim)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                title.font(.system(size: 11, weight: .semibold)).lineLimit(1)
                detail.font(.system(size: 9.5)).foregroundStyle(Theme.dim).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 6)
            if done {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(Theme.green)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button(action: perform) { action.font(.system(size: 10, weight: .semibold)).lineLimit(1) }
                    .buttonStyle(PillStyle())
            }
        }
        .padding(.horizontal, 9).frame(height: 33)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .animation(Theme.quick, value: done)
    }
}
