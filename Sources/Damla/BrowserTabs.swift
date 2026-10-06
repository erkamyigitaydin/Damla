import AppKit
import ApplicationServices

/// One browser tab playing sound, found over Apple Events: the page's media elements and their volume.
struct BrowserTab: Identifiable, Equatable {
    let id: String          // browser|window|tab
    let browser: String     // bundle id
    /// The tab inside the browser: "tab id 7 of window id 2" (Chromium), "tab 3 of window id 2" (Safari).
    let ref: String
    let title: String
    let host: String
    var volume: Double      // 0–100: the loudest playing element
}

/// Per-tab volume for browsers. macOS mixes every tab of a browser into one audio process, so a tab cannot be
/// tapped like an app; instead the page's own <video>/<audio> elements are asked, over Apple Events, for their
/// volume and given a new one. Chromium browsers take `execute javascript`, Safari `do JavaScript`, each with its
/// "Allow JavaScript from Apple Events" switch on. Media inside iframes and Web Audio players are out of reach, so
/// a tab with sound can still be missing here. Scans run only while the Ses page shows a browser that plays.
final class BrowserTabVolumes: ObservableObject {
    /// Playing tabs by browser bundle id.
    @Published private(set) var tabs: [String: [BrowserTab]] = [:]
    /// Browsers that refused JavaScript over Apple Events (their menu switch is off).
    @Published private(set) var javaScriptOff: Set<String> = []
    /// Browsers macOS will not let Damla control (System Settings → Privacy → Automation).
    @Published private(set) var automationDenied: Set<String> = []

    static let chromium: Set<String> = VideoNotch.browsers.union(["company.thebrowser.Browser"])
    static let safari: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
    static func supports(_ bundleID: String) -> Bool { chromium.contains(bundleID) || safari.contains(bundleID) }
    /// Where the switch sits, in the browser's own menus.
    static func menuPath(_ bundleID: String) -> String {
        safari.contains(bundleID) ? String(localized: "Geliştirici → Apple Events’ten JavaScript’e İzin Ver")
            : String(localized: "Görünüm → Geliştirici → Apple Events’ten JavaScript’e izin ver")
    }

    private var browsers: [String] = []
    private var watching = false
    private var timer: Timer?
    private var scanning: Set<String> = []
    private var setWork: [String: DispatchWorkItem] = [:]
    /// Tabs whose level was just set: a scan already under way may still report the old value.
    private var recentlySet: [String: Date] = [:]
    private var beforeMute: [String: Double] = [:]
    private let queue = DispatchQueue(label: "app.damla.tabs", qos: .utility)

    /// While the Ses page is open, the browsers on it are asked every few seconds. Opening the page asks again
    /// even a browser that refused last time: the user may have flipped its switch meanwhile.
    func setWatching(_ on: Bool) {
        watching = on
        timer?.invalidate(); timer = nil
        guard on else { return }
        javaScriptOff.removeAll(); automationDenied.removeAll()
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in self?.scan() }
    }

    /// The browsers the page lists right now (those playing sound); others are dropped with their tabs.
    func watch(_ apps: [String]) {
        let wanted = apps.filter(Self.supports)
        guard wanted != browsers else { return }
        browsers = wanted
        for gone in tabs.keys where !wanted.contains(gone) { tabs.removeValue(forKey: gone) }
        if watching { scan() }
    }

    /// Slider moves arrive many times a second; the page gets the last one after a short pause.
    func setVolume(_ tab: BrowserTab, _ value: Double) {
        let level = min(100, max(0, value.rounded()))
        if let index = tabs[tab.browser]?.firstIndex(where: { $0.id == tab.id }) { tabs[tab.browser]?[index].volume = level }
        recentlySet[tab.id] = Date()
        setWork[tab.id]?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.queue.async { Self.apply(tab, level) } }
        setWork[tab.id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    /// A tap on the tab's icon: down to 0, and back to where it was.
    func toggleMute(_ tab: BrowserTab) {
        if tab.volume > 0 { beforeMute[tab.id] = tab.volume; setVolume(tab, 0) }
        else { setVolume(tab, beforeMute.removeValue(forKey: tab.id) ?? 100) }
    }

    /// Flips the browser's "Allow JavaScript from Apple Events" item through Accessibility (a press on the menu
    /// item, as System Events would do it); without Accessibility, or if the press does not take, the browser
    /// comes forward so the user can click it.
    func enableJavaScript(_ browser: String) {
        guard AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: browser).first else {
            Self.openBrowser(browser); return
        }
        let pid = app.processIdentifier
        queue.async {
            if let found = VideoSetup.findMenuItem(pid: pid), !VideoSetup.checked(found.item),
               AXUIElementPerformAction(found.item, kAXPressAction as CFString) == .success {
                Thread.sleep(forTimeInterval: 0.3)
                if VideoSetup.checked(found.item) {
                    MediaService.trace("tabs: JavaScript switched on in \(browser)")
                    DispatchQueue.main.async { self.javaScriptOff.remove(browser); self.scan() }
                    return
                }
            }
            DispatchQueue.main.async { Self.openBrowser(browser) }
        }
    }

    static func openBrowser(_ browser: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") { NSWorkspace.shared.open(url) }
    }

    // MARK: Scanning

    private func scan() {
        for browser in browsers where !scanning.contains(browser) && !javaScriptOff.contains(browser) && !automationDenied.contains(browser) {
            scanning.insert(browser)
            queue.async {
                let result = VideoNotch.appleScript(Self.scanScript(browser))
                DispatchQueue.main.async { self.finish(browser, result) }
            }
        }
    }

    private func finish(_ browser: String, _ result: (value: String?, error: String?, code: Int?)) {
        scanning.remove(browser)
        guard watching, browsers.contains(browser) else { return }
        if result.code == -1743 {
            MediaService.trace("tabs: automation denied for \(browser)")
            automationDenied.insert(browser); return
        }
        let parsed = Self.parse(result.value ?? "", browser: browser)
        let problem = (parsed.error ?? "") + (result.error ?? "")
        if problem.localizedCaseInsensitiveContains("JavaScript") {
            MediaService.trace("tabs: JavaScript off in \(browser): \(problem)")
            javaScriptOff.insert(browser)
            if tabs[browser] != nil { tabs.removeValue(forKey: browser) }
            return
        }
        if let error = result.error { MediaService.trace("tabs: \(browser) scan failed: \(error)") }
        MediaService.trace("tabs: \(browser) \(parsed.tabs.count) playing tab(s)")
        var found = parsed.tabs
        // A level set a moment ago wins over what the scan read before it landed.
        for index in found.indices {
            guard let at = recentlySet[found[index].id], Date().timeIntervalSince(at) < 1.5,
                  let shown = tabs[browser]?.first(where: { $0.id == found[index].id }) else { continue }
            found[index].volume = shown.volume
        }
        if tabs[browser] != found { tabs[browser] = found }
    }

    /// Rows of "window ␟ tab ␟ volume ␟ host ␟ title", one per playing tab; a first line starting with "!" is the
    /// browser's error when no tab answered (its JavaScript switch is off).
    static func parse(_ output: String, browser: String) -> (tabs: [BrowserTab], error: String?) {
        var lines = output.split(whereSeparator: \.isNewline).map(String.init)
        var error: String?
        if let first = lines.first, first.hasPrefix("!") { error = String(first.dropFirst()); lines.removeFirst() }
        var tabs: [BrowserTab] = []
        for line in lines {
            let parts = line.split(separator: "\u{1F}", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 5, let volume = Double(parts[2]) else { continue }
            let (window, tab) = (parts[0], parts[1])
            let ref = safari.contains(browser) ? "tab \(tab) of window id \(window)" : "tab id \(tab) of window id \(window)"
            tabs.append(BrowserTab(id: "\(browser)|\(window)|\(tab)", browser: browser, ref: ref,
                                   title: parts[4].trimmingCharacters(in: .whitespaces), host: parts[3], volume: min(100, max(0, volume))))
        }
        return (tabs, error)
    }

    /// Runs in each page: the playing, unmuted media elements and the loudest one's volume. Muted autoplay
    /// videos (news sites) are not sound and are left out. A "(17) " unread count in the title is dropped.
    private static let probe = "(()=>{const s=String.fromCharCode(31),m=[...document.querySelectorAll('video,audio')].filter(e=>!e.paused&&!e.ended&&!e.muted);"
        + "if(!m.length)return '';const v=Math.round(Math.max(...m.map(e=>e.volume))*100);"
        + "return v+s+location.hostname.replace(/^www\\./,'')+s+document.title.replace(/[\\x00-\\x1f]/g,' ').replace(/^\\(\\d+\\)\\s*/,'').slice(0,80)})()"

    /// Every http tab of every window is probed inside one script, so the browser does the walking.
    private static func scanScript(_ browser: String) -> String {
        let js = VideoNotch.escaped(probe)
        let safari = safari.contains(browser)
        let run = safari ? "do JavaScript \"\(js)\" in t" : "execute t javascript \"\(js)\""
        let tabID = safari ? "i" : "(id of t)"
        return """
        with timeout of 8 seconds
        tell application id "\(browser)"
            set sep to character id 31
            set out to ""
            set err to ""
            repeat with w in windows
                set wid to id of w
                set i to 0
                repeat with t in tabs of w
                    set i to i + 1
                    try
                        set u to URL of t
                        if u starts with "http" then
                            set r to \(run)
                            if r is not missing value then
                                set r to r as text
                                if r is not "" then set out to out & wid & sep & \(tabID) & sep & r & linefeed
                            end if
                        end if
                    on error msg
                        set err to msg
                    end try
                end repeat
            end repeat
            if err is not "" and out is "" then return "!" & err & linefeed
            return out
        end tell
        end timeout
        """
    }

    private static func apply(_ tab: BrowserTab, _ level: Double) {
        let js = VideoNotch.escaped("(()=>{const v=\(level / 100);document.querySelectorAll('video,audio').forEach(e=>{e.volume=v});return 'ok'})()")
        let body = safari.contains(tab.browser) ? "do JavaScript \"\(js)\" in (\(tab.ref))" : "execute (\(tab.ref)) javascript \"\(js)\""
        let result = VideoNotch.appleScript("with timeout of 4 seconds\ntell application id \"\(tab.browser)\"\n\(body)\nend tell\nend timeout")
        MediaService.trace("tabs: \(tab.host) → \(Int(level)) \(result.value ?? result.error ?? "")")
    }
}
