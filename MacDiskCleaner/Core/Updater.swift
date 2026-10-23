import Foundation
import Observation
@preconcurrency import Sparkle

/// App updates through Sparkle: a signed appcast on downloads.machealthapps.com, checked in the
/// background once a day (`SUScheduledCheckInterval`). Every update is verified against the EdDSA
/// public key in Info.plist and must be signed by the same Developer ID before it is installed.
@Observable
final class Updater: NSObject {
    static let shared = Updater()

    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"

    /// Release builds with a feed and a public key; Debug builds never update themselves.
    let isAvailable: Bool
    private(set) var canCheck = false
    /// A version found by a background check that the user hasn't looked at yet.
    private(set) var pendingVersion: String?
    private(set) var lastCheck: Date?

    var automaticallyChecks: Bool {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }
    var automaticallyDownloads: Bool {
        didSet { controller?.updater.automaticallyDownloadsUpdates = automaticallyDownloads }
    }

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    private override init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        #if DEBUG
        isAvailable = false
        #else
        isAvailable = !key.isEmpty && feed.hasPrefix("https://")
        #endif
        automaticallyChecks = false
        automaticallyDownloads = false
        super.init()
        guard isAvailable else { return }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        automaticallyDownloads = controller.updater.automaticallyDownloadsUpdates
        lastCheck = controller.updater.lastUpdateCheckDate
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) {
            [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            let date = updater.lastUpdateCheckDate
            Task { @MainActor in
                self?.canCheck = value
                self?.lastCheck = date
            }
        }
    }

    /// Shows Sparkle's window: "You're up to date" or the new version with its release notes.
    func checkForUpdates() {
        pendingVersion = nil
        controller?.checkForUpdates(nil)
    }
}

// Background checks don't pop a window over your work: the sidebar shows a quiet
// "Update available" line instead, and Sparkle's window opens when you click it.
extension Updater: SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Right at launch it's fine to show the window; later, only the sidebar line.
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        if !handleShowingUpdate { pendingVersion = update.displayVersionString }
        lastCheck = controller?.updater.lastUpdateCheckDate
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        pendingVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        pendingVersion = nil
        lastCheck = controller?.updater.lastUpdateCheckDate
    }
}
