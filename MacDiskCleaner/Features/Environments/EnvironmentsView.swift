import AppKit
import SwiftUI

struct EnvironmentsView: View {
    @Environment(EnvironmentsStore.self) private var store
    @State private var showsAllBrew = false

    private let section = AppSection.environments

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    title: section.pageTitle, subtitle: section.summary, symbol: section.symbol, tint: section.tint
                ) {
                    HStack(spacing: 10) {
                        if store.isBusy { ProgressView().controlSize(.small) }
                        Button {
                            Task { await store.scan() }
                        } label: {
                            Label("Rescan", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.quiet)
                        .disabled(store.isBusy)
                        Button(store.checkedAt == nil ? "Check Online" : "Check Again") {
                            Task { await store.checkOnline() }
                        }
                        .buttonStyle(.primary)
                        .disabled(store.isBusy)
                    }
                }

                if store.checkedAt == nil && store.phase == .checking {
                    Card(padding: 18) {
                        HStack(spacing: 14) {
                            ProgressView().controlSize(.small).frame(width: 34)
                            Text("Comparing with the latest releases")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                } else if store.checkedAt == nil {
                    Card(padding: 18) {
                        HStack(alignment: .top, spacing: 14) {
                            Glyph(symbol: "network", tint: Theme.accent, size: 34)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Compare with the latest releases")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(
                                    "Check Online downloads public release schedules from nodejs.org and endoflife.date and compares them here. Your installed versions are never sent."
                                )
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                } else {
                    summary
                }

                if store.phase == .scanning && store.installs.isEmpty {
                    Card { EmptyNote(symbol: section.symbol, title: "Looking for installed tools", message: "") }
                } else if store.installs.isEmpty {
                    Card {
                        EmptyNote(
                            symbol: section.symbol, title: "No developer tools found",
                            message: "Node, Java, Python, Ruby, Homebrew and others show up here once installed.")
                    }
                } else {
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(store.sorted.enumerated()), id: \.element.id) { index, install in
                                if index > 0 { Divider().overlay(Theme.hairline).padding(.leading, 62) }
                                InstallRow(install: install)
                            }
                        }
                    }
                }

                if !store.brewOutdated.isEmpty { brewCard }

                if !store.failedProducts.isEmpty {
                    Text(
                        "Couldn't load release schedules for \(store.failedProducts.joined(separator: ", ")). Try again later."
                    )
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(Theme.gutter)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas)
        .task { await store.prepare() }
    }

    private var summary: some View {
        Card(padding: 24) {
            SummaryLayout {
                ForEach([Urgency.updateNow, .soon, .convenient, .upToDate], id: \.self) { urgency in
                    Stat(
                        label: urgency.label, value: "\(store.count(urgency))",
                        caption: urgency == .updateNow && store.count(.updateNow) > 0
                            ? "end of life or security fix" : nil,
                        large: urgency == .updateNow,
                        captionTint: urgency == .updateNow && store.count(.updateNow) > 0 ? Theme.attention : nil)
                }
            }
        }
    }

    private var brewCard: some View {
        let items = showsAllBrew ? store.brewOutdated : Array(store.brewOutdated.prefix(6))
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Homebrew packages with updates · \(store.brewOutdated.count)")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                CopyButton(command: "brew upgrade", title: "Copy brew upgrade")
            }
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().overlay(Theme.hairline).padding(.leading, 16) }
                        HStack(spacing: 10) {
                            Text(item.name).font(.system(size: 13, weight: .medium))
                            if item.isCask { StatusTag(text: "App", tone: Theme.slate) }
                            Spacer()
                            Text("\(item.installed) → \(item.current)")
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(.secondary)
                            CopyButton(command: item.command)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .hoverRow()
                    }
                    if store.brewOutdated.count > 6 {
                        Button(showsAllBrew ? "Show fewer" : "Show all \(store.brewOutdated.count)") {
                            withAnimation(.snappy) { showsAllBrew.toggle() }
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(10)
                    }
                }
            }
        }
    }
}

private struct InstallRow: View {
    @Environment(EnvironmentsStore.self) private var store
    let install: Installation

    var body: some View {
        let spec = ToolSpec.spec(install.toolID)
        let assessment = store.assessments[install.id]
        let urgency = assessment?.urgency ?? .unknown

        HStack(alignment: .top, spacing: 14) {
            Glyph(symbol: spec?.symbol ?? "terminal", tint: urgency.tone, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("\(spec?.name ?? install.toolID) \(install.version.description)")
                        .font(.system(size: 13, weight: .medium))
                    Text(sourceText).font(.caption).foregroundStyle(.tertiary)
                    if assessment != nil { UrgencyTag(urgency: urgency) }
                }
                if let assessment {
                    Text(assessment.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let latest = assessment.latestInLine ?? assessment.latest, latest != install.version.description
                    {
                        Text(
                            "Latest: \(latest)"
                                + (assessment.latest.map { $0 != latest ? " · newest \($0)" : "" } ?? "")
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    }
                } else {
                    Text(install.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 12)
            if let command = assessment?.command {
                CopyButton(command: command, title: command)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .hoverRow()
    }

    private var sourceText: String {
        var parts = [install.source.rawValue]
        if let note = install.note { parts.append(note) }
        if install.isActive { parts.append("in use") }
        return parts.joined(separator: ", ")
    }
}

/// Shows a command and copies it; nothing is ever run for you.
struct CopyButton: View {
    let command: String
    var title: String? = nil
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            withAnimation(.hover) { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.hover) { copied = false }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: copied ? "checkmark" : "doc.on.clipboard")
                if let title {
                    Text(copied ? "Copied" : title)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.quiet)
        .help("Copy “\(command)” — paste it into Terminal to run it")
    }
}

private struct UrgencyTag: View {
    let urgency: Urgency
    var body: some View { StatusTag(text: urgency.label, tone: urgency.tone) }
}

extension Urgency {
    var tone: Color {
        switch self {
        case .updateNow: Theme.attention
        case .soon: Theme.sand
        case .convenient: Theme.slate
        case .optional: Color.secondary
        case .upToDate: Theme.sage
        case .unknown: Theme.dataOther
        }
    }
}
