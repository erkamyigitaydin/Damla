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
        NSLog("Damla updater: found %@ (%@)", item.displayVersionString, item.versionString)
        availableVersion = item.displayVersionString
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        NSLog("Damla updater: no update: %@", error.localizedDescription)
        availableVersion = nil
        lastCheck = Date()
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        NSLog("Damla updater: cycle finished (%d) error=%@", updateCheck.rawValue, error?.localizedDescription ?? "none")
        lastCheck = Date()
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        NSLog("Damla updater: aborted: %@", error.localizedDescription)
    }
    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        NSLog("Damla updater: download failed: %@", error.localizedDescription)
    }
    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) { NSLog("Damla updater: downloaded %@", item.displayVersionString) }
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) { NSLog("Damla updater: will install %@", item.displayVersionString) }

    // MARK: SPUStandardUserDriverDelegate (gentle reminders for a background app)

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        // If Damla is already in front, let Sparkle show its window; otherwise we point to it from the notch.
        immediateFocus
    }
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        NSLog("Damla updater: will show %@ handledBySparkle=%d stage=%d userInitiated=%d", update.displayVersionString, handleShowingUpdate ? 1 : 0, state.stage.rawValue, state.userInitiated ? 1 : 0)
        availableVersion = update.displayVersionString
        if !handleShowingUpdate { onUpdateFound?(update.displayVersionString) }
    }
    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {}
    func standardUserDriverWillFinishUpdateSession() { availableVersion = nil }
}
