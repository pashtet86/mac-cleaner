import AppKit
import SwiftUI

struct SecurityView: View {
    @Environment(SecurityStore.self) private var store
    @State private var showsAllItems = false
    @State private var pendingTrash: HealthFinding?

    private let section = AppSection.security

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    title: section.pageTitle, subtitle: section.summary, symbol: section.symbol, tint: section.tint
                ) {
                    HStack(spacing: 10) {
                        if store.phase == .scanning { ProgressView().controlSize(.small) }
                        Button {
                            Task { await store.scan() }
                        } label: {
                            Label("Check Again", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.quiet)
                        .disabled(store.phase == .scanning)
                    }
                }

                if !store.hasLoaded {
                    Card { EmptyNote(symbol: section.symbol, title: "Checking this Mac", message: "") }
                } else {
                    summary

                    if store.issues.isEmpty {
                        allClear
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Eyebrow("Needs a look")
                            FindingsCard(findings: store.issues) { pendingTrash = $0 }
                        }
                    }

                    if let error = store.lastError {
                        Text(error).font(.caption).foregroundStyle(Theme.attention)
                    }

                    if !store.passed.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Eyebrow("Protections")
                            FindingsCard(findings: store.passed)
                        }
                    }

                    if !store.items.isEmpty { launchItems }

                    Text(
                        "Everything here is read-only. Fixes that need an administrator are commands you copy into Terminal — the app never runs them for you."
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
        .task { await store.scanIfNeeded() }
        .confirmationDialog(
            "Move this launch agent to the Trash?", isPresented: .constant(pendingTrash != nil),
            presenting: pendingTrash
        ) { finding in
            Button("Move to Trash", role: .destructive) {
                pendingTrash = nil
                Task { await store.trash(finding) }
            }
            Button("Cancel", role: .cancel) { pendingTrash = nil }
        } message: { finding in
            Text(
                "\(finding.trashablePlist?.lastPathComponent ?? "") stops now and won't start at your next login. You can put it back from the Trash."
            )
        }
    }

    private var summary: some View {
        Card(padding: 24) {
            SummaryLayout {
                Stat(
                    label: Severity.critical.label, value: "\(store.count(.critical))",
                    caption: store.count(.critical) > 0 ? "can put this Mac at risk" : nil, large: true,
                    captionTint: store.count(.critical) > 0 ? Theme.attention : nil)
                Stat(label: Severity.warning.label, value: "\(store.count(.warning))")
                Stat(label: Severity.info.label, value: "\(store.count(.info))")
                Stat(label: "Start automatically", value: "\(store.items.count)")
            }
        }
    }

    private var allClear: some View {
        Card(padding: 18) {
            HStack(spacing: 14) {
                Glyph(symbol: "checkmark.shield", tint: Theme.sage, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nothing needs your attention").font(.system(size: 13, weight: .semibold))
                    Text("macOS protections are on and every background item points to a signed program.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var launchItems: some View {
        let items = showsAllItems ? store.items : Array(store.items.prefix(8))
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow("Starts automatically · \(store.items.count)")
                Spacer()
                Button("Login Items Settings") { NSWorkspace.shared.open(SecurityScanner.loginItemsSettings) }
                    .buttonStyle(.quiet)
            }
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().overlay(Theme.hairline).padding(.leading, 16) }
                        LaunchItemRow(item: item)
                    }
                    if store.items.count > 8 {
                        Button(showsAllItems ? "Show fewer" : "Show all \(store.items.count)") {
                            withAnimation(.snappy) { showsAllItems.toggle() }
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

private struct LaunchItemRow: View {
    let item: LaunchItem

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text((item.program ?? item.plist.path).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            Text(item.domain.rawValue).font(.caption).foregroundStyle(.secondary)
            StatusTag(text: signerText, tone: signerTone)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .hoverRow()
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.plist]) }
        }
    }

    private var signerText: String {
        switch item.signer {
        case let .developer(name):
            // "Developer ID Application: Docker Inc (9BNSXJN65R)" → "Docker Inc"
            name.replacingOccurrences(of: "Developer ID Application: ", with: "")
                .replacingOccurrences(of: #"\s*\([A-Z0-9]{10}\)$"#, with: "", options: .regularExpression)
        case .adHoc: "Ad-hoc"
        default: item.signer.label
        }
    }

    private var signerTone: Color {
        switch item.signer {
        case .apple, .developer: Theme.sage
        case .script, .adHoc: Theme.slate
        case .missing: Color.secondary
        case .unsigned, .invalid: Theme.sand
        }
    }
}
