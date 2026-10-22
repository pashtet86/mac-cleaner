import AppKit
import SwiftUI

/// One page per rule section: App Caches, Xcode, IDEs, Packages & Toolchains.
struct RulesPage: View {
    @Environment(CleanupStore.self) private var store
    let section: AppSection
    @State private var expanded: Set<String> = []
    @State private var isReviewing = false

    private var ruleSection: RuleSection { section.ruleSection ?? .apps }

    var body: some View {
        // Only what exists on this Mac is listed; the rest is named in a footnote.
        let rules = store.rules(in: ruleSection)
        let found = rules.filter { !store.items(for: $0).isEmpty }
        let missing = rules.filter { store.items(for: $0).isEmpty }
        let largest = found.map(store.size(of:)).max() ?? 0

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(
                    title: section.pageTitle, subtitle: section.summary,
                    symbol: section.symbol, tint: section.tint
                ) {
                    Button {
                        Task { await store.scan() }
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.quiet)
                    .disabled(store.isBusy)
                }

                if let last = store.lastReport, last.section == ruleSection {
                    ReportBanner(report: last.report) { store.dismissReport() }
                }

                if store.scannedAt == nil {
                    Card {
                        VStack(spacing: 12) {
                            ProgressView().controlSize(.small)
                            Text("Looking for \(section.title.lowercased()) data…")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    }
                } else if found.isEmpty {
                    Card {
                        EmptyNote(
                            symbol: "checkmark.circle", title: "Nothing to clean",
                            message: "None of the supported tools left anything here.")
                    }
                } else {
                    summary
                }

                if !found.isEmpty {
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(found.enumerated()), id: \.element.id) { index, rule in
                                if index > 0 { Divider().overlay(Theme.hairline).padding(.leading, 104) }
                                RuleRow(
                                    rule: rule, tint: section.tint, largest: largest,
                                    isExpanded: expanded.contains(rule.id)
                                ) {
                                    withAnimation(.snappy(duration: 0.25)) {
                                        if expanded.contains(rule.id) {
                                            expanded.remove(rule.id)
                                        } else {
                                            expanded.insert(rule.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if store.scannedAt != nil, !missing.isEmpty {
                    AlsoSupported(names: missing.map(\.title))
                }
            }
            .padding(Theme.gutter)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas)
        .sheet(isPresented: $isReviewing) { CleanupReviewSheet(section: ruleSection) }
        .task { await store.scanIfNeeded() }
    }

    private var summary: some View {
        let found = store.total(in: ruleSection)
        return Card(padding: 24) {
            VStack(alignment: .leading, spacing: 22) {
                SummaryLayout {
                    // The selection figure appears only once something is selected.
                    if !store.selectedItems(in: ruleSection).isEmpty {
                        Stat(
                            label: "To clean", value: store.selectedBytes(in: ruleSection).formattedBytes,
                            caption: "\(store.selectedItems(in: ruleSection).count) items", large: true)
                    }
                    Stat(
                        label: "Cleanable", value: found.formattedBytes,
                        caption: store.scannedAt.map { "Scanned \($0.formatted(.relative(presentation: .named)))" },
                        large: store.selectedItems(in: ruleSection).isEmpty)
                } action: {
                    VStack(alignment: .trailing, spacing: 10) {
                        if store.isBusy {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(store.phase == .scanning ? "Scanning…" : "Moving to Trash…")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        Button("Clean Selected…") { isReviewing = true }
                            .buttonStyle(.primary)
                            .disabled(store.selectedItems(in: ruleSection).isEmpty || store.phase != .ready)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    CapacityBar(
                        segments: Risk.allCases.map {
                            .init(
                                fraction: Double(store.total(for: $0, in: ruleSection)) / Double(max(found, 1)),
                                color: $0.tone)
                        })
                    FlowLayout {
                        ForEach(Risk.allCases.filter { store.total(for: $0, in: ruleSection) > 0 }, id: \.self) {
                            risk in
                            LegendDot(
                                color: risk.tone, label: risk.label,
                                value: store.total(for: risk, in: ruleSection).formattedBytes)
                        }
                    }
                }
            }
        }
    }
}

private struct RuleRow: View {
    @Environment(CleanupStore.self) private var store
    let rule: CleanupRule
    let tint: Color
    let largest: Int64
    let isExpanded: Bool
    let onExpand: () -> Void

    private let visibleItemLimit = 12

    var body: some View {
        let items = store.items(for: rule)
        let size = store.size(of: rule)
        let isScanning = store.phase == .scanning && store.results[rule.id] == nil

        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button {
                    store.toggle(rule)
                } label: {
                    SelectionMark(state: store.selectionState(of: rule))
                }
                .buttonStyle(.plain)
                .disabled(items.isEmpty)

                Glyph(symbol: rule.symbol, tint: items.isEmpty ? .secondary : tint, size: 32)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(rule.title).font(.system(size: 13, weight: .medium))
                        RiskTag(risk: rule.risk)
                    }
                    Text(rule.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    // Share of the section's largest rule, in the section's hue.
                    CapacityBar(
                        segments: [.init(fraction: Double(size) / Double(max(largest, 1)), color: tint)], height: 3
                    )
                    .frame(maxWidth: 280)
                    .padding(.top, 3)
                    .opacity(items.isEmpty ? 0 : 1)
                }

                Spacer(minLength: 16)

                Text(isScanning ? "—" : (items.isEmpty ? "Empty" : size.formattedBytes))
                    .font(.system(size: 13, weight: .regular).monospacedDigit())
                    .foregroundStyle(items.isEmpty ? .tertiary : .primary)

                Button(action: onExpand) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.icon)
                .disabled(items.isEmpty)
                .opacity(items.isEmpty ? 0 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .hoverRow()
            .contentShape(Rectangle())
            .onTapGesture { if !items.isEmpty { onExpand() } }

            if isExpanded, !items.isEmpty {
                VStack(spacing: 0) {
                    ForEach(items.prefix(visibleItemLimit)) { item in
                        ItemRow(item: item)
                    }
                    if items.count > visibleItemLimit {
                        let rest = items.dropFirst(visibleItemLimit)
                        Text("and \(rest.count) more · \(rest.reduce(0) { $0 + $1.size }.formattedBytes)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 88)
                            .padding(.vertical, 8)
                    }
                }
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
    }
}

private struct ItemRow: View {
    @Environment(CleanupStore.self) private var store
    let item: CleanupItem

    var body: some View {
        HStack(spacing: 12) {
            Button {
                store.toggle(item)
            } label: {
                SelectionMark(state: store.selection.contains(item.url) ? .on : .off)
            }
            .buttonStyle(.plain)

            Text(item.name)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 11))
            }
            .buttonStyle(.icon)
            .help("Show in Finder")

            Spacer()

            Text(item.size.formattedBytes)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 60)
        .padding(.trailing, 52)
        .padding(.vertical, 5)
        .hoverRow()
    }
}

struct RiskTag: View {
    let risk: Risk

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(risk.tone).frame(width: 6, height: 6)
            Text(risk.label)
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(risk.tone)
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(risk.tone.opacity(0.1), in: Capsule())
    }
}

struct ReportBanner: View {
    let report: TrashReport
    let onDismiss: () -> Void
    @State private var showFailures = false

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(Theme.sage)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            "Cleaned \(report.movedCount) items · \(report.movedBytes.formattedBytes) moved to the Trash"
                        )
                        .font(.system(size: 13, weight: .medium))
                        Text("Space is reclaimed once you empty the Trash.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !report.failures.isEmpty {
                        Button("\(report.failures.count) skipped") { showFailures.toggle() }
                            .buttonStyle(.quiet)
                    }
                    Button("Open Trash") {
                        let trash = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash")
                        NSWorkspace.shared.open(trash)
                    }
                    .buttonStyle(.quiet)
                    Button(action: onDismiss) {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.icon)
                }
                if showFailures {
                    ScrollView {
                        Text(report.failures.joined(separator: "\n"))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 120)
                }
            }
        }
    }
}
