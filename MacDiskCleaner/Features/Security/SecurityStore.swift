import Foundation
import Observation

@Observable
final class SecurityStore {
    enum Phase: Equatable { case idle, scanning, ready }

    private(set) var phase: Phase = .idle
    private(set) var protections = SecurityScanner.Protections()
    private(set) var items: [LaunchItem] = []
    private(set) var findings: [HealthFinding] = []
    private(set) var lastError: String?

    var hasLoaded: Bool { phase == .ready }

    /// Findings that are not "all good".
    var issues: [HealthFinding] { findings.filter { $0.severity != .ok } }
    var passed: [HealthFinding] { findings.filter { $0.severity == .ok } }
    var needsAttention: [HealthFinding] { findings.filter(\.severity.needsAttention) }

    func count(_ severity: Severity) -> Int { findings.filter { $0.severity == severity }.count }

    var alert: HealthAlert? {
        let urgent = needsAttention
        guard let worst = urgent.first else { return nil }
        let count = urgent.count
        return HealthAlert(
            section: .security, severity: worst.severity,
            title: count == 1 ? worst.title : "\(count) security issues need a look",
            detail: count == 1 ? worst.detail : urgent.prefix(2).map(\.title).joined(separator: " · "))
    }

    func scanIfNeeded() async {
        if phase == .idle { await scan() }
    }

    func scan() async {
        phase = .scanning
        async let protections = SecurityScanner.protections()
        let items = await Task.detached(priority: .userInitiated) { SecurityScanner.launchItems() }.value
        self.protections = await protections
        self.items = items.sorted { ($0.domain.rawValue, $0.label) < ($1.domain.rawValue, $1.label) }
        findings = SecurityScanner.findings(protections: self.protections, items: items)
        phase = .ready
    }

    /// Stops a leftover agent of yours and moves its plist to the Trash.
    func trash(_ finding: HealthFinding) async {
        guard let plist = finding.trashablePlist else { return }
        lastError = nil
        _ = try? await ProcessRunner.run("/bin/launchctl", ["bootout", "gui/\(getuid())", plist.path], timeout: 10)
        let report = await SafeTrash.trash([(plist, 0)])
        if let failure = report.failures.first { lastError = failure }
        await scan()
    }
}
