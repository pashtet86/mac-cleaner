import Foundation

/// Decides which sections exist on this Mac: a section appears only once
/// detection found something for it (Xcode data, Docker installed, …).
struct SectionAvailability {
    let cleanup: CleanupStore
    let simulators: SimulatorsStore
    let docker: DockerStore
    let apps: AppsStore

    /// `true` found, `false` nothing on this Mac, `nil` still detecting.
    func state(of section: AppSection) -> Bool? {
        switch section {
        case .overview, .inspector, .applications, .largeFiles, .duplicates:
            return true
        case .apps, .xcode, .ides, .packages:
            guard cleanup.scannedAt != nil, let rules = section.ruleSection else { return nil }
            return cleanup.total(in: rules) > 0
        case .simulators:
            guard simulators.hasLoaded else { return nil }
            return !simulators.runtimes.isEmpty || !simulators.devices.isEmpty
        case .docker:
            switch docker.state {
            case .unknown: return nil
            case .notInstalled: return false
            case .notRunning, .running: return true
            }
        case .security, .network:
            return false
        }
    }

    /// Below this, a section isn't worth flagging.
    static let attentionThreshold: Int64 = 100_000_000
    static let unusedAppsThreshold: Int64 = 1_000_000_000

    /// Bytes that can be cleaned right away without review, when that is worth a red dot.
    func attention(for section: AppSection) -> Int64? {
        let bytes: Int64
        switch section {
        case .apps, .xcode, .ides, .packages:
            guard cleanup.scannedAt != nil, let rules = section.ruleSection else { return nil }
            bytes = cleanup.safeTotal(in: rules)
        case .simulators:
            bytes = simulators.unavailableBytes
        case .docker:
            guard docker.state == .running else { return nil }
            bytes = docker.totalReclaimable
        case .applications:
            // Unused apps are worth a look only once they add up.
            guard apps.unusedBytes >= Self.unusedAppsThreshold else { return nil }
            bytes = apps.unusedBytes
        default:
            return nil
        }
        return bytes >= Self.attentionThreshold ? bytes : nil
    }

    func visible(_ sections: [AppSection], keeping selected: AppSection?) -> [AppSection] {
        sections.filter { state(of: $0) == true || $0 == selected }
    }

    /// Supported sections with nothing on this Mac.
    var notFound: [AppSection] { (AppSection.mac + AppSection.developer).filter { state(of: $0) == false } }

    var isDetecting: Bool { (AppSection.mac + AppSection.developer).contains { state(of: $0) == nil } }

    /// Starts every detection in parallel; each store skips work it already did.
    func detectAll() async {
        async let scan: Void = cleanup.scanIfNeeded()
        async let sims: Void = simulators.refreshIfNeeded()
        async let dock: Void = docker.refreshIfNeeded()
        async let installed: Void = apps.refreshIfNeeded()
        _ = await (scan, sims, dock, installed)
    }
}
