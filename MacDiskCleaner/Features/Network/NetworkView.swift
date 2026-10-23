import AppKit
import SwiftUI

struct NetworkView: View {
    @Environment(NetworkStore.self) private var store
    @State private var showsLocal = false

    private let section = AppSection.network

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

                    if !store.findings.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Eyebrow(store.issues.isEmpty ? "Firewall" : "Needs a look")
                            FindingsCard(findings: store.findings)
                        }
                    }

                    listenerSection(
                        title: "Open to your network · \(store.exposed.count)", listeners: store.exposed,
                        empty: "No app accepts connections from other devices.")

                    if !store.local.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                withAnimation(.snappy) { showsLocal.toggle() }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .semibold))
                                        .rotationEffect(.degrees(showsLocal ? 90 : 0))
                                    Eyebrow("Only this Mac · \(store.local.count)")
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            if showsLocal { listenerCard(store.local) }
                        }
                    }

                    Text("Listening TCP ports on this Mac, checked locally. Nothing is sent anywhere.")
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
    }

    private var summary: some View {
        Card(padding: 24) {
            SummaryLayout {
                Stat(
                    label: "Firewall", value: store.firewall.enabled.map { $0 ? "On" : "Off" } ?? "—",
                    caption: store.firewall.enabled == false ? "connections aren't filtered" : nil, large: true,
                    captionTint: store.firewall.enabled == false ? Theme.attention : nil)
                Stat(label: "Stealth mode", value: store.firewall.stealth.map { $0 ? "On" : "Off" } ?? "—")
                Stat(label: "Open to network", value: "\(store.exposed.count)")
                Stat(label: "Only this Mac", value: "\(store.local.count)")
            }
        }
    }

    @ViewBuilder
    private func listenerSection(title: String, listeners: [Listener], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(title)
                Spacer()
                Button("Sharing Settings") { NSWorkspace.shared.open(NetworkScanner.sharingSettings) }
                    .buttonStyle(.quiet)
            }
            if listeners.isEmpty {
                Card(padding: 16) {
                    Text(empty).font(.callout).foregroundStyle(.secondary)
                }
            } else {
                listenerCard(listeners)
            }
        }
    }

    private func listenerCard(_ listeners: [Listener]) -> some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(listeners.enumerated()), id: \.element.id) { index, listener in
                    if index > 0 { Divider().overlay(Theme.hairline).padding(.leading, 16) }
                    ListenerRow(listener: listener)
                }
            }
        }
    }
}

private struct ListenerRow: View {
    let listener: Listener

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: String(listener.port))
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .frame(width: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(listener.process)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let service = listener.service, service.name != listener.process {
                    Text(service.name).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            Text(listener.addresses.map(display).joined(separator: ", "))
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            if listener.isExposed, listener.service?.kind == .remoteAccess {
                StatusTag(text: "Remote access", tone: Theme.sand)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .hoverRow()
    }

    private func display(_ address: String) -> String {
        address == "*" ? "all interfaces" : address
    }
}
