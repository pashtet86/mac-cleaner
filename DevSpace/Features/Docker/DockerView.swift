import SwiftUI

struct DockerView: View {
    @Environment(DockerStore.self) private var store
    @State private var pending: DockerAction?

    private let section = AppSection.docker

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(
                    title: section.pageTitle, subtitle: section.summary,
                    symbol: section.symbol, tint: section.tint
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

                switch store.state {
                case .unknown:
                    Card { EmptyNote(symbol: "shippingbox", title: "Checking Docker…", message: "") }
                case .notInstalled:
                    Card {
                        EmptyNote(
                            symbol: "shippingbox", title: "Docker isn't installed",
                            message: "Install Docker Desktop to manage images and build cache here.")
                    }
                case .notRunning:
                    Card {
                        VStack(spacing: 4) {
                            EmptyNote(
                                symbol: "moon.zzz", title: "Docker isn't running",
                                message: "Start Docker Desktop, then refresh to see what it's using.")
                            Button("Start Docker") { store.startDocker() }
                                .buttonStyle(.primary)
                                .padding(.bottom, 24)
                        }
                        .frame(maxWidth: .infinity)
                    }
                case .running:
                    summary
                    actions
                }
            }
            .padding(Theme.gutter)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas)
        .task { await store.refreshIfNeeded() }
        .confirmationDialog(
            pending.map { "Clean \($0.title.lowercased())?" } ?? "",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            presenting: pending
        ) { action in
            Button("Clean", role: .destructive) { Task { await store.perform(action) } }
        } message: { action in
            Text(action.detail + (store.reclaimable(for: action).map { " Frees about \($0.formattedBytes)." } ?? ""))
        }
        .alert(
            "Docker operation failed",
            isPresented: Binding(
                get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private static let typeColors: [String: Color] = [
        "Images": Theme.indigo, "Containers": Theme.teal,
        "Local Volumes": Theme.ochre, "Build Cache": Theme.rose,
    ]

    private var summary: some View {
        let total = Double(max(store.totalSize, 1))
        return Card(padding: 24) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 48) {
                    Stat(label: "In use", value: store.totalSize.formattedBytes, large: true)
                    Stat(
                        label: "Reclaimable", value: store.totalReclaimable.formattedBytes,
                        caption: "volumes are never removed")
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 10) {
                    CapacityBar(
                        segments: store.usage.map {
                            .init(fraction: Double($0.size) / total, color: Self.typeColors[$0.type] ?? Theme.dataOther)
                        }, height: 8)
                    FlowLayout {
                        ForEach(store.usage) { row in
                            LegendDot(
                                color: Self.typeColors[row.type] ?? Theme.dataOther,
                                label: "\(row.type) (\(row.totalCount))", value: row.size.formattedBytes)
                        }
                    }
                }
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Clean up")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(DockerAction.allCases.enumerated()), id: \.element) { index, action in
                        if index > 0 { Divider().overlay(Theme.hairline).padding(.leading, 62) }
                        HStack(spacing: 14) {
                            Glyph(symbol: action.symbol, tint: section.tint, size: 32)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(action.title).font(.system(size: 13, weight: .medium))
                                Text(action.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let bytes = store.reclaimable(for: action), bytes > 0 {
                                Text(bytes.formattedBytes)
                                    .font(.system(size: 13).monospacedDigit())
                            }
                            if store.busy.contains(action) {
                                ProgressView().controlSize(.small).frame(width: 70)
                            } else {
                                Button("Clean…") { pending = action }
                                    .buttonStyle(.quiet)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .hoverRow()
                    }
                }
            }
        }
    }
}
