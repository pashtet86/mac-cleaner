import Foundation
import Observation
import SwiftUI

@Observable
final class ThermalStore {
    private(set) var cpu: Double?
    private(set) var ssd: Double?
    private(set) var state: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

    /// Nil when the private sensor API is unavailable; the thermal state still works.
    private let sensors = ThermalSensors()
    private var polling: Task<Void, Never>?

    var hasSensors: Bool { sensors != nil }

    func start(every interval: Duration = .seconds(3)) {
        guard polling == nil else { return }
        polling = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        polling?.cancel()
        polling = nil
    }

    private func refresh() async {
        state = ProcessInfo.processInfo.thermalState
        guard let sensors else { return }
        let reading = await Task.detached(priority: .utility) { sensors.reading() }.value
        cpu = reading?.cpu
        ssd = reading?.ssd
    }
}

extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal: "Normal"
        case .fair: "Warm"
        case .serious: "Hot"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }

    var tone: Color {
        switch self {
        case .nominal: Theme.sage
        case .fair: Theme.sand
        case .serious, .critical: Theme.attention
        @unknown default: Theme.dataOther
        }
    }
}
