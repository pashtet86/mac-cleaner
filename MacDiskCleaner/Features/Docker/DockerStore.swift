import AppKit
import Foundation
import Observation

@Observable
final class DockerStore {
    enum State: Equatable { case unknown, notInstalled, notRunning, running }

    private(set) var state: State = .unknown
    private(set) var usage: [DockerUsage] = []
    private(set) var isLoading = false
    private(set) var busy: Set<DockerAction> = []
    var errorMessage: String?

    var totalSize: Int64 { usage.reduce(0) { $0 + $1.size } }
    var totalReclaimable: Int64 { usage.reduce(0) { $0 + $1.reclaimable } }

    func reclaimable(for action: DockerAction) -> Int64? {
        guard let type = action.usageType else { return nil }
        return usage.first { $0.type == type }?.reclaimable
    }

    func refreshIfNeeded() async {
        if state == .unknown { await refresh() }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        switch await Docker.status() {
        case .notInstalled:
            state = .notInstalled
            usage = []
        case .notRunning:
            state = .notRunning
            usage = []
        case let .running(rows):
            state = .running
            usage = rows
        }
    }

    func startDocker() {
        NSWorkspace.shared.openApplication(at: Docker.appURL, configuration: .init())
    }

    func perform(_ action: DockerAction) async {
        busy.insert(action)
        defer { busy.remove(action) }
        let estimate = reclaimable(for: action) ?? 0
        do {
            try await Docker.perform(action)
            Telemetry.shared.cleaned(estimate, in: .docker)
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()
    }
}
