import Foundation
import Observation

@Observable
final class NetworkStore {
    enum Phase: Equatable { case idle, scanning, ready }

    private(set) var phase: Phase = .idle
    private(set) var firewall = NetworkScanner.Firewall()
    private(set) var listeners: [Listener] = []
    private(set) var proxy = NetworkScanner.Proxy()
    private(set) var findings: [HealthFinding] = []

    var hasLoaded: Bool { phase == .ready }
    var exposed: [Listener] { listeners.filter(\.isExposed) }
    var local: [Listener] { listeners.filter { !$0.isExposed } }
    var issues: [HealthFinding] { findings.filter { $0.severity != .ok } }
    var needsAttention: [HealthFinding] { findings.filter(\.severity.needsAttention) }

    var alert: HealthAlert? {
        let urgent = needsAttention
        guard let worst = urgent.first else { return nil }
        return HealthAlert(
            section: .network, severity: worst.severity,
            title: urgent.count == 1 ? worst.title : "\(urgent.count) network settings need a look",
            detail: urgent.count == 1 ? worst.detail : urgent.prefix(2).map(\.title).joined(separator: " · "))
    }

    func scanIfNeeded() async {
        if phase == .idle { await scan() }
    }

    func scan() async {
        phase = .scanning
        async let firewall = NetworkScanner.firewall()
        async let listeners = NetworkScanner.listeners()
        async let proxy = NetworkScanner.proxy()
        (self.firewall, self.listeners, self.proxy) = await (firewall, listeners, proxy)
        findings = NetworkScanner.findings(firewall: self.firewall, listeners: self.listeners, proxy: self.proxy)
        phase = .ready
    }
}
