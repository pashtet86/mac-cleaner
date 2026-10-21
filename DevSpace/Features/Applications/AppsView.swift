import AppKit
import SwiftUI

struct AppsView: View {
    @Environment(AppsStore.self) private var store
    @State private var pending: AppEntry?

    private let section = AppSection.applications

    var body: some View {
        @Bindable var store = store

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    title: section.pageTitle, subtitle: section.summary, symbol: section.symbol, tint: section.tint
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

                HStack(spacing: 12) {
                    TextField("Search apps", text: $store.query)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                    Spacer()
                    Text("Sort by").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $store.sort) {
                        ForEach(AppsStore.Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                Card(padding: 0) {
                    let apps = store.visibleApps
                    if apps.isEmpty {
                        EmptyNote(
                            symbol: section.symbol, title: store.hasLoaded ? "No apps found" : "Looking for apps…",
                            message: "")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                                if index > 0 { Divider().overlay(Theme.hairline).padding(.leading, 66) }
                                row(app)
                            }
                        }
                    }
                }

                Text(
                    "Removing an app moves it to the Trash. Its settings and caches in ~/Library stay — App Caches cleans the caches."
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            .padding(Theme.gutter)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas)
        .task { await store.refreshIfNeeded() }
        .confirmationDialog(
            pending.map { "Move \($0.name) to the Trash?" } ?? "",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            presenting: pending
        ) { app in
            Button("Remove \(app.name)", role: .destructive) { Task { await store.remove(app) } }
        } message: { app in
            Text(
                "Frees \((app.size ?? 0).formattedBytes). You can put it back from the Trash."
                    + (app.isFromAppStore ? " App Store apps may ask for your password." : ""))
        }
        .alert(
            "Couldn't remove app",
            isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var summary: some View {
        Card(padding: 24) {
            HStack(alignment: .top, spacing: 48) {
                Stat(
                    label: "Applications", value: store.totalBytes.formattedBytes,
                    caption: "\(store.apps.count) apps" + (store.isMeasuring ? " · measuring…" : ""), large: true)
                // Shown only when there is something unused to point at.
                if !store.unusedApps.isEmpty {
                    Stat(
                        label: "Not used for 6 months", value: store.unusedBytes.formattedBytes,
                        caption: "\(store.unusedApps.count) apps",
                        captionTint: Theme.sand)
                }
                Spacer()
            }
        }
    }

    private func row(_ app: AppEntry) -> some View {
        let running = store.isRunning(app)
        let unused = !app.isSystem && app.isUnused(after: store.unusedCutoff)
        return HStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(app.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if let version = app.version {
                        Text(version).font(.caption).foregroundStyle(.tertiary)
                    }
                    if app.isSystem { StatusTag(text: "System", tone: .secondary) }
                    if app.isFromAppStore { StatusTag(text: "App Store", tone: Theme.slate) }
                    if running { StatusTag(text: "Running", tone: Theme.sage) }
                    if unused { StatusTag(text: "Unused", tone: Theme.sand) }
                }
                Text(lastUsedText(app))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Group {
                if let size = app.size {
                    Text(size.formattedBytes)
                } else {
                    ProgressView().controlSize(.mini)
                }
            }
            .font(.system(size: 13).monospacedDigit())
            .frame(width: 80, alignment: .trailing)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([app.url])
            } label: {
                Image(systemName: "arrow.up.forward.square").font(.system(size: 12)).frame(width: 16, height: 16)
            }
            .buttonStyle(.icon)
            .help("Show in Finder")

            if store.removing.contains(app.url) {
                ProgressView().controlSize(.small).frame(width: 78)
            } else {
                Button("Remove…") { pending = app }
                    .buttonStyle(.quiet)
                    .disabled(app.isSystem || running)
                    .help(
                        app.isSystem
                            ? "Part of macOS — can't be removed"
                            : (running ? "Quit the app to remove it" : "Move to the Trash"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .hoverRow()
    }

    private func lastUsedText(_ app: AppEntry) -> String {
        guard let date = app.lastUsed else { return "No record of use" }
        return "Last used \(date.formatted(.relative(presentation: .named)))"
    }
}
