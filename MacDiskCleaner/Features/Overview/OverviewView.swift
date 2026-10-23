import SwiftUI

struct OverviewView: View {
    @Environment(CleanupStore.self) private var cleanup
    @Environment(SimulatorsStore.self) private var simulators
    @Environment(DockerStore.self) private var docker
    @Environment(AppsStore.self) private var apps
    @Environment(EnvironmentsStore.self) private var environments
    @Environment(SecurityStore.self) private var security
    @Environment(NetworkStore.self) private var network
    @Binding var selection: AppSection?
    @State private var volume = DiskUsage.bootVolume()

    private var availability: SectionAvailability {
        SectionAvailability(
            cleanup: cleanup, simulators: simulators, docker: docker, apps: apps, environments: environments,
            security: security, network: network)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(
                    title: "Overview",
                    subtitle: "Developer disk cleaner · \(Host.current().localizedName ?? "This Mac")")

                if Telemetry.shared.shouldAsk {
                    TelemetryConsentCard().transition(.opacity)
                }

                if !healthAlerts.isEmpty || environments.urgentSummary != nil {
                    VStack(spacing: 10) {
                        ForEach(healthAlerts) { alert in
                            HealthAlertBanner(
                                symbol: alert.section.symbol, tone: alert.severity.tone, title: alert.title,
                                detail: alert.detail, help: "See \(alert.section.title)"
                            ) { selection = alert.section }
                        }
                        if let urgent = environments.urgentSummary { environmentsAlert(urgent) }
                    }
                }

                if let volume { diskCard(volume) }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                    ForEach(
                        availability.visible(AppSection.clean, keeping: nil), id: \.self,
                        content: moduleCard)
                }

                if !availability.notFound.isEmpty {
                    AlsoSupported(names: availability.notFound.map(\.title))
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

        return Card(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                SummaryLayout {
                    Stat(
                        label: "Available", value: volume.available.formattedBytes,
                        caption: "of \(volume.total.formattedBytes)")
                    Stat(label: "Used", value: volume.used.formattedBytes)
                } action: {
                    SafeToCleanPanel(bytes: reclaimable, sections: sectionsWithSafeBytes)
                }
                VStack(alignment: .leading, spacing: 10) {
                    CapacityBar(
                        segments: categories.map {
                            .init(fraction: Double($0.bytes) / total, color: $0.section.tint)
                        } + [.init(fraction: Double(other) / total, color: Theme.dataOther)], height: 8)
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

    // MARK: - Environments alert

    private func environmentsAlert(_ urgent: EnvironmentsStore.UrgentSummary) -> some View {
        let count = urgent.names.count
        return HealthAlertBanner(
            symbol: AppSection.environments.symbol, tone: Theme.attention,
            title: "\(count) developer tool\(count == 1 ? "" : "s") need\(count == 1 ? "s" : "") updating now",
            detail: urgent.names.prefix(3).joined(separator: ", ")
                + (count > 3 ? " and \(count - 3) more" : ""),
            help: "End of life or a security release — see Environments"
        ) { selection = .environments }
    }

    /// Security and Network findings worth a look, worst first.
    private var healthAlerts: [HealthAlert] {
        [AppSection.security, .network].compactMap(availability.healthAlert(for:))
            .sorted { $0.severity < $1.severity }
    }

    // MARK: - Modules

    private func moduleCard(_ section: AppSection) -> some View {
        let (value, caption) = figures(for: section)
        return Button {
            selection = section
        } label: {
            // Compact: icon on the left, figures beside it, arrow at the far edge.
            Card(padding: 16) {
                HStack(alignment: .center, spacing: 14) {
                    Glyph(symbol: section.symbol, tint: section.tint, size: 40)
                        .overlay(alignment: .topTrailing) {
                            if let attention = availability.attentionMessage(for: section) {
                                // Badge on the icon corner, ringed in the card color.
                                AttentionDot()
                                    .padding(2)
                                    .background(Theme.card, in: Circle())
                                    .offset(x: 4, y: -4)
                                    .help(attention)
                            }
                        }
                    VStack(alignment: .leading, spacing: 3) {
                        Eyebrow(section.title)
                        Text(value)
                            .font(.system(size: 22, weight: .light).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .contentTransition(.numericText())
                        Text(caption)
                            .font(.system(size: 12, weight: hasSafeBytes(section) ? .semibold : .regular))
                            .foregroundStyle(
                                hasSafeBytes(section) ? AnyShapeStyle(Theme.cleanable) : AnyShapeStyle(.secondary)
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
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
            guard simulators.hasLoaded else { return ("—", "Loading") }
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
            case .unknown: return ("—", "Checking")
            }
        default:
            guard let rules = section.ruleSection else { return ("—", "") }
            if cleanup.phase == .idle || (cleanup.phase == .scanning && cleanup.scannedAt == nil) {
                return ("—", "Scanning")
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
        VStack(alignment: .leading, spacing: 4) {
            Text("SAFE TO CLEAN")
                .font(.eyebrow)
                .tracking(1.1)
                .foregroundStyle(Theme.cleanable)
            Text(bytes.formattedBytes)
                .font(.figureSmall)
                .foregroundStyle(Theme.cleanable)
                .contentTransition(.numericText())
            Text(
                sections == 0
                    ? "Nothing to clean right now"
                    : "in \(sections) section\(sections == 1 ? "" : "s") · rebuilds by itself"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.cleanable.opacity(0.09), in: .rect(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cleanable.opacity(0.22))
        }
    }
}
