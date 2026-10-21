import Foundation
import Observation

@Observable
final class SimulatorsStore {
    private(set) var runtimes: [SimRuntime] = []
    private(set) var devices: [SimDevice] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var busy: Set<String> = []
    var errorMessage: String?

    static let unavailableKey = "unavailable"

    var runtimesBytes: Int64 { runtimes.reduce(0) { $0 + ($1.sizeBytes ?? 0) } }
    var devicesBytes: Int64 { devices.reduce(0) { $0 + ($1.dataPathSize ?? 0) } }
    var unavailableDevices: [SimDevice] { devices.filter { !$0.isAvailable } }
    var unavailableBytes: Int64 { unavailableDevices.reduce(0) { $0 + ($1.dataPathSize ?? 0) } }

    func devices(on runtime: SimRuntime) -> [SimDevice] {
        devices.filter { $0.runtimeIdentifier == runtime.runtimeIdentifier }
    }

    /// Devices grouped by runtime, newest first, unavailable groups last.
    var deviceGroups: [(name: String, devices: [SimDevice])] {
        Dictionary(grouping: devices, by: \.runtimeIdentifier)
            .map { (name: $0.value.first?.runtimeName ?? $0.key, devices: $0.value.sorted { $0.name < $1.name }) }
            .sorted { lhs, rhs in
                let lAvail = lhs.devices.contains(where: \.isAvailable)
                let rAvail = rhs.devices.contains(where: \.isAvailable)
                if lAvail != rAvail { return lAvail }
                return lhs.name.compare(rhs.name, options: .numeric) == .orderedDescending
            }
    }

    func refreshIfNeeded() async {
        if !hasLoaded { await refresh() }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        // No Xcode: nothing to show and nothing to report as an error.
        guard await Simctl.isAvailable() else {
            runtimes = []
            devices = []
            return
        }
        do {
            async let runtimes = Simctl.runtimes()
            async let devices = Simctl.devices()
            (self.runtimes, self.devices) = try await (runtimes, devices)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ runtime: SimRuntime) async {
        await perform(runtime.id) { try await Simctl.deleteRuntime(runtime.identifier) }
    }

    func delete(_ device: SimDevice) async {
        await perform(device.id) { try await Simctl.deleteDevice(device.udid) }
    }

    func deleteUnavailable() async {
        await perform(Self.unavailableKey) { try await Simctl.deleteUnavailableDevices() }
    }

    private func perform(_ key: String, _ operation: () async throws -> Void) async {
        busy.insert(key)
        defer { busy.remove(key) }
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()
    }
}
