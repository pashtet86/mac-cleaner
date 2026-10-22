import SwiftUI

struct SimulatorsView: View {
    @Environment(SimulatorsStore.self) private var store
    @State private var pendingRuntime: SimRuntime?
    @State private var pendingDevice: SimDevice?
    @State private var confirmUnavailable = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(
                    title: AppSection.simulators.pageTitle, subtitle: AppSection.simulators.summary,
                    symbol: AppSection.simulators.symbol, tint: AppSection.simulators.tint
                ) {
                    HStack(spacing: 10) {
                        if store.isLoading { ProgressView().controlSize(.small) }
                        Button {
                            Task { await store.refresh() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.quiet)
                        .disabled(store.isLoading)
                    }
                }

                summary

                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow("Runtimes")
                    Card(padding: 0) {
                        if store.runtimes.isEmpty {
                            EmptyNote(
                                symbol: "iphone.slash", title: store.hasLoaded ? "No runtimes" : "Loading…",
                                message: "Simulator runtimes downloaded through Xcode appear here.")
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(store.runtimes.enumerated()), id: \.element.id) { index, runtime in
                                    if index > 0 { Divider().overlay(Theme.hairline).padding(.leading, 62) }
                                    runtimeRow(runtime)
                                }
                            }
                        }
                    }
                }

                ForEach(store.deviceGroups, id: \.name) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow("Devices · \(group.name)")
                        Card(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(group.devices.enumerated()), id: \.element.id) { index, device in
                                    if index > 0 { Divider().overlay(Theme.hairline).padding(.leading, 62) }
                                    deviceRow(device)
                                }
                            }
                        }
                    }
                }
            }
            .padding(Theme.gutter)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas)
        .task { if !store.hasLoaded { await store.refresh() } }
        .confirmationDialog(
            pendingRuntime.map { "Delete \($0.title)?" } ?? "",
            isPresented: Binding(get: { pendingRuntime != nil }, set: { if !$0 { pendingRuntime = nil } }),
            presenting: pendingRuntime
        ) { runtime in
            Button("Delete Runtime", role: .destructive) { Task { await store.delete(runtime) } }
        } message: { runtime in
            let count = store.devices(on: runtime).count
            Text(
                "Frees \((runtime.sizeBytes ?? 0).formattedBytes). \(count) device\(count == 1 ? "" : "s") on this runtime will become unavailable. Xcode can download it again later."
            )
        }
        .confirmationDialog(
            pendingDevice.map { "Delete \($0.name)?" } ?? "",
            isPresented: Binding(get: { pendingDevice != nil }, set: { if !$0 { pendingDevice = nil } }),
            presenting: pendingDevice
        ) { device in
            Button("Delete Device", role: .destructive) { Task { await store.delete(device) } }
        } message: { device in
            Text("Removes the simulator and its \((device.dataPathSize ?? 0).formattedBytes) of apps and data.")
        }
        .confirmationDialog("Remove unavailable devices?", isPresented: $confirmUnavailable) {
            Button("Remove \(store.unavailableDevices.count) Devices", role: .destructive) {
                Task { await store.deleteUnavailable() }
            }
        } message: {
            Text(
                "These devices belong to runtimes that are no longer installed. Frees \(store.unavailableBytes.formattedBytes)."
            )
        }
        .alert(
            "Simulator operation failed",
            isPresented: Binding(
                get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var summary: some View {
        let available = store.devicesBytes - store.unavailableBytes
        let total = Double(max(store.runtimesBytes + store.devicesBytes, 1))
        return Card(padding: 24) {
            VStack(alignment: .leading, spacing: 22) {
                SummaryLayout {
                    Stat(
                        label: "Runtimes", value: store.runtimesBytes.formattedBytes,
                        caption: "\(store.runtimes.count) installed", large: true)
                    Stat(
                        label: "Device data", value: store.devicesBytes.formattedBytes,
                        caption: "\(store.devices.count) devices")
                    Stat(
                        label: "Unavailable", value: store.unavailableBytes.formattedBytes,
                        caption: "\(store.unavailableDevices.count) orphaned devices")
                } action: {
                    Button("Clean Unavailable…") { confirmUnavailable = true }
                        .buttonStyle(.primary)
                        .disabled(
                            store.unavailableDevices.isEmpty || store.busy.contains(SimulatorsStore.unavailableKey))
                }
                VStack(alignment: .leading, spacing: 10) {
                    CapacityBar(
                        segments: [
                            .init(fraction: Double(store.runtimesBytes) / total, color: Theme.rose),
                            .init(fraction: Double(available) / total, color: Theme.rose.opacity(0.5)),
                            .init(fraction: Double(store.unavailableBytes) / total, color: Theme.sand),
                        ], height: 8)
                    FlowLayout {
                        LegendDot(color: Theme.rose, label: "Runtimes", value: store.runtimesBytes.formattedBytes)
                        LegendDot(color: Theme.rose.opacity(0.5), label: "Devices", value: available.formattedBytes)
                        LegendDot(color: Theme.sand, label: "Unavailable", value: store.unavailableBytes.formattedBytes)
                    }
                }
            }
        }
    }

    private func runtimeRow(_ runtime: SimRuntime) -> some View {
        let deviceCount = store.devices(on: runtime).count
        return HStack(spacing: 14) {
            Glyph(symbol: runtime.symbol, tint: Theme.rose, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(runtime.title).font(.system(size: 13, weight: .medium))
                Text(runtimeCaption(runtime, deviceCount: deviceCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text((runtime.sizeBytes ?? 0).formattedBytes)
                .font(.system(size: 13).monospacedDigit())
            deleteButton(busy: store.busy.contains(runtime.id), enabled: runtime.deletable ?? true) {
                pendingRuntime = runtime
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .hoverRow()
    }

    private func deviceRow(_ device: SimDevice) -> some View {
        HStack(spacing: 14) {
            Glyph(symbol: "iphone", tint: device.isAvailable ? Theme.rose : Theme.sand, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(device.name).font(.system(size: 13, weight: .medium))
                    if device.isBooted { StatusTag(text: "Booted", tone: Theme.sage) }
                    if !device.isAvailable { StatusTag(text: "Unavailable", tone: Theme.sand) }
                }
                Text(
                    device.lastUsedAt.map { "Last used \($0.formatted(.relative(presentation: .named)))" }
                        ?? "Never used"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text((device.dataPathSize ?? 0).formattedBytes)
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(.secondary)
            deleteButton(busy: store.busy.contains(device.id), enabled: !device.isBooted) {
                pendingDevice = device
            }
            .help(device.isBooted ? "Shut down the simulator before deleting it" : "Delete device")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .hoverRow()
    }

    private func runtimeCaption(_ runtime: SimRuntime, deviceCount: Int) -> String {
        var parts = ["Build \(runtime.build)", "\(deviceCount) device\(deviceCount == 1 ? "" : "s")"]
        if let used = runtime.lastUsedAt {
            parts.append("used \(used.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }

    private func deleteButton(busy: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Group {
            if busy {
                ProgressView().controlSize(.small).frame(width: 28, height: 28)
            } else {
                Button(action: action) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.icon)
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.3)
            }
        }
    }
}

struct StatusTag: View {
    let text: String
    let tone: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(tone)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(tone.opacity(0.1), in: Capsule())
    }
}
