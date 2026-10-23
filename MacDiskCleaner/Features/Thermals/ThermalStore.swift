import Foundation
import Observation
import SwiftUI

@Observable
final class ThermalStore {
    private(set) var cpu: Double?
    private(set) var ssd: Double?
    private(set) var state: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    /// Startup disk, refreshed with the sensors so cleaning shows up within seconds.
    private(set) var volume: DiskUsage.Volume? = DiskUsage.bootVolume()
    /// RPM per fan; empty until the first reading.
    private(set) var fans: [Double] = []

    /// Nil when the private sensor API is unavailable; the thermal state still works.
    private let sensors = ThermalSensors()
    /// Nil on Macs without fans — the fan line is hidden then.
    private let fanReader = FanReader()
    private var polling: Task<Void, Never>?

    var hasSensors: Bool { sensors != nil }
    var hasFans: Bool { fanReader != nil }

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
        volume = DiskUsage.bootVolume()
        let sensors = sensors
        let fanReader = fanReader
        let (reading, speeds) = await Task.detached(priority: .utility) {
            (sensors?.reading(), fanReader?.speeds() ?? [])
        }.value
        cpu = reading?.cpu
        ssd = reading?.ssd
        fans = speeds
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
