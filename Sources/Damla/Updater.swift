import AppKit
import Combine
import Sparkle

/// Sparkle-backed updates: a daily background check against the appcast on GitHub, a notch notice when a
/// new version is found, and Sparkle's own window for the download and install. No server of ours is
/// involved; the appcast and the disk images are static files on GitHub, and every download is
/// verified against the EdDSA public key in Info.plist plus Apple's notarization.
final class UpdateService: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    @Published var automaticChecks = true { didSet { controller?.updater.automaticallyChecksForUpdates = automaticChecks } }
    @Published private(set) var availableVersion: String?
    @Published private(set) var lastCheck: Date?
    var onUpdateFound: ((String) -> Void)?
    private var controller: SPUStandardUpdaterController?

    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    var isConfigured: Bool { Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil }

    func start() {
        guard isConfigured, controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        automaticChecks = controller.updater.automaticallyChecksForUpdates
        lastCheck = controller.updater.lastUpdateCheckDate
        do { try controller.updater.start() } catch { NSLog("Damla: updater failed to start: %@", error.localizedDescription) }
    }

    /// Opens Sparkle's window (checking, or straight to the found update).
    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    // MARK: SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableVersion = item.displayVersionString
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        availableVersion = nil
        lastCheck = Date()
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        lastCheck = Date()
    }

    // MARK: SPUStandardUserDriverDelegate (gentle reminders for a background app)

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        // If Damla is already in front, let Sparkle show its window; otherwise we point to it from the notch.
        immediateFocus
    }
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        availableVersion = update.displayVersionString
        if !handleShowingUpdate { onUpdateFound?(update.displayVersionString) }
    }
    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {}
    func standardUserDriverWillFinishUpdateSession() { availableVersion = nil }
}
