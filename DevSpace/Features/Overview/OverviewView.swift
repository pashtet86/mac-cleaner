import SwiftUI

struct OverviewView: View {
    @Environment(CleanupStore.self) private var cleanup
    @Environment(SimulatorsStore.self) private var simulators
    @Environment(DockerStore.self) private var docker
    @Environment(AppsStore.self) private var apps
    @Binding var selection: AppSection?
    @State private var volume = DiskUsage.bootVolume()

    private var availability: SectionAvailability {
        SectionAvailability(cleanup: cleanup, simulators: simulators, docker: docker, apps: apps)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(
                    title: "Overview",
                    subtitle: "Developer disk cleaner · \(Host.current().localizedName ?? "This Mac")")

                if let volume { diskCard(volume) }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                    ForEach(
                        availability.visible([AppSection.apps] + AppSection.developer, keeping: nil), id: \.self,
                        content: moduleCard)
                }

                if !availability.notFound.isEmpty {
                    AlsoSupported(names: availability.notFound.map(\.title))
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
            await availability.detectAll()
            volume = DiskUsage.bootVolume()
        }
    }

    // MARK: - Disk

    /// Categories of used space, in fixed palette order.
    private var categories: [(section: AppSection, bytes: Int64)] {
        let all: [(section: AppSection, bytes: Int64)] = [
            (.xcode, cleanup.total(in: .xcode)),
            (.apps, cleanup.total(in: .apps)),
            (.packages, cleanup.total(in: .packages)),
            (.ides, cleanup.total(in: .ides)),
            (.simulators, simulators.runtimesBytes + simulators.devicesBytes),
        ]
        return all.filter { $0.bytes > 0 }
    }

    private func diskCard(_ volume: DiskUsage.Volume) -> some View {
        let total = Double(max(volume.total, 1))
        let known = categories.reduce(0) { $0 + $1.bytes }
        let other = max(volume.used - known, 0)
        let reclaimable = [RuleSection.xcode, .ides, .packages, .apps].reduce(0) { $0 + cleanup.safeTotal(in: $1) }

        return Card(padding: 24) {
            VStack(alignment: .leading, spacing: 22) {
                SummaryLayout {
                    Stat(
                        label: "Available", value: volume.available.formattedBytes,
                        caption: "of \(volume.total.formattedBytes) on Macintosh HD", large: true)
                    Stat(label: "Used", value: volume.used.formattedBytes)
                } action: {
                    SafeToCleanPanel(bytes: reclaimable, sections: sectionsWithSafeBytes)
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
                            .overlay(alignment: .topTrailing) {
                                if let attention = availability.attention(for: section) {
                                    // Badge on the icon corner, ringed in the card color.
                                    AttentionDot()
                                        .padding(2)
                                        .background(Theme.card, in: Circle())
                                        .offset(x: 4, y: -4)
                                        .help("\(attention.formattedBytes) safe to clean")
                                }
                            }
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    Stat(
                        label: section.title, value: value, caption: caption,
                        captionTint: hasSafeBytes(section) ? Theme.sage : nil)
                }
            }
            .hoverLift()
            .contentShape(.rect(cornerRadius: Theme.radius))
        }
        .buttonStyle(.plain)
    }

    private func hasSafeBytes(_ section: AppSection) -> Bool {
        switch section {
        case .docker: docker.state == .running && docker.totalReclaimable > 0
        default: section.ruleSection.map { cleanup.safeTotal(in: $0) > 0 } ?? false
        }
    }

    private var sectionsWithSafeBytes: Int {
        [RuleSection.xcode, .ides, .packages, .apps].filter { cleanup.safeTotal(in: $0) > 0 }.count
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

/// The headline of the Overview: how much can go right now, without review.
private struct SafeToCleanPanel: View {
    let bytes: Int64
    let sections: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 11, weight: .semibold))
                Text("SAFE TO CLEAN").font(.eyebrow).tracking(1.1)
            }
            .foregroundStyle(Theme.sage)
            Text(bytes.formattedBytes)
                .font(.figure)
                .foregroundStyle(Theme.sage)
                .contentTransition(.numericText())
            Text(
                sections == 0
                    ? "Nothing to clean right now"
                    : "in \(sections) section\(sections == 1 ? "" : "s") · rebuilds by itself"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Theme.sage.opacity(0.09), in: .rect(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.sage.opacity(0.22))
        }
    }
}
