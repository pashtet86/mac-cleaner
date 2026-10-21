import SwiftUI

struct OverviewView: View {
    @Environment(CleanupStore.self) private var cleanup
    @Environment(SimulatorsStore.self) private var simulators
    @Environment(DockerStore.self) private var docker
    @Binding var selection: AppSection?
    @State private var volume = DiskUsage.bootVolume()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(title: "Overview", subtitle: Host.current().localizedName ?? "This Mac")

                if let volume { diskCard(volume) }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                    ForEach([AppSection.apps] + AppSection.developer, id: \.self, content: moduleCard)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow("Coming next")
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(AppSection.upcoming.enumerated()), id: \.element) { index, section in
                                if index > 0 { Divider().overlay(Theme.hairline).padding(.leading, 62) }
                                HStack(spacing: 14) {
                                    Glyph(symbol: section.symbol, size: 32)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(section.title).font(.system(size: 13, weight: .medium))
                                        Text(section.summary).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
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
        .task {
            volume = DiskUsage.bootVolume()
            async let scan: Void = cleanup.scanIfNeeded()
            async let sims: Void = simulators.refreshIfNeeded()
            async let dock: Void = docker.refreshIfNeeded()
            _ = await (scan, sims, dock)
            volume = DiskUsage.bootVolume()
        }
    }

    // MARK: - Disk

    /// Categories of used space, in fixed palette order.
    private var categories: [(section: AppSection, bytes: Int64)] {
        [
            (.xcode, cleanup.total(in: .xcode)),
            (.apps, cleanup.total(in: .apps)),
            (.packages, cleanup.total(in: .packages)),
            (.ides, cleanup.total(in: .ides)),
            (.simulators, simulators.runtimesBytes + simulators.devicesBytes),
        ]
    }

    private func diskCard(_ volume: DiskUsage.Volume) -> some View {
        let total = Double(max(volume.total, 1))
        let known = categories.reduce(0) { $0 + $1.bytes }
        let other = max(volume.used - known, 0)
        let reclaimable = [RuleSection.xcode, .ides, .packages, .apps].reduce(0) { $0 + cleanup.safeTotal(in: $1) }

        return Card(padding: 24) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 48) {
                    Stat(
                        label: "Available", value: volume.available.formattedBytes,
                        caption: "of \(volume.total.formattedBytes) on Macintosh HD", large: true)
                    Stat(label: "Used", value: volume.used.formattedBytes)
                    Stat(label: "Safe to clean", value: reclaimable.formattedBytes)
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 12) {
                    CapacityBar(
                        segments: categories.map {
                            .init(fraction: Double($0.bytes) / total, color: $0.section.tint)
                        } + [.init(fraction: Double(other) / total, color: Theme.dataOther)], height: 10)
                    FlowLayout {
                        ForEach(categories, id: \.section) { category in
                            LegendDot(
                                color: category.section.tint, label: category.section.title,
                                value: category.bytes.formattedBytes)
                        }
                        LegendDot(color: Theme.dataOther, label: "Other", value: other.formattedBytes)
                        LegendDot(color: Theme.track, label: "Free")
                    }
                }
            }
        }
    }

    // MARK: - Modules

    private func moduleCard(_ section: AppSection) -> some View {
        let (value, caption) = figures(for: section)
        return Button {
            selection = section
        } label: {
            Card(padding: 20) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Glyph(symbol: section.symbol, tint: section.tint, size: 34)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    Stat(label: section.title, value: value, caption: caption)
                }
            }
            .contentShape(.rect(cornerRadius: Theme.radius))
        }
        .buttonStyle(.plain)
    }

    private func figures(for section: AppSection) -> (String, String) {
        switch section {
        case .simulators:
            guard simulators.hasLoaded else { return ("—", "Loading…") }
            return (
                (simulators.runtimesBytes + simulators.devicesBytes).formattedBytes,
                "\(simulators.runtimes.count) runtimes · \(simulators.devices.count) devices"
            )
        case .docker:
            switch docker.state {
            case .running:
                return (docker.totalSize.formattedBytes, "\(docker.totalReclaimable.formattedBytes) reclaimable")
            case .notRunning: return ("—", "Docker isn't running")
            case .notInstalled: return ("—", "Not installed")
            case .unknown: return ("—", "Checking…")
            }
        default:
            guard let rules = section.ruleSection else { return ("—", "") }
            if cleanup.phase == .idle || (cleanup.phase == .scanning && cleanup.scannedAt == nil) {
                return ("—", "Scanning…")
            }
            return (
                cleanup.total(in: rules).formattedBytes, "\(cleanup.safeTotal(in: rules).formattedBytes) safe to clean"
            )
        }
    }
}
