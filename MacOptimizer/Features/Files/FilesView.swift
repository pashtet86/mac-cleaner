import AppKit
import SwiftUI

struct FilesView: View {
    @Environment(FilesStore.self) private var store
    @State private var tab: Tab = .large
    @State private var isReviewing = false

    enum Tab: Hashable { case large, duplicates }

    private let section = AppSection.largeFiles
    private let visibleLimit = 200

    static let kindColors: [FileKind: Color] = [
        .video: Theme.indigo, .diskImage: Theme.ochre, .archive: Theme.teal, .other: Theme.lavender,
    ]

    var body: some View {
        @Bindable var store = store

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(
                    title: section.title, subtitle: section.summary,
                    symbol: section.symbol, tint: section.tint
                ) {
                    if store.isScanning {
                        Button("Cancel") { store.cancel() }.buttonStyle(.quiet)
                    } else {
                        Button {
                            store.scan()
                        } label: {
                            Label(store.scannedAt == nil ? "Scan" : "Rescan", systemImage: "magnifyingglass")
                        }
                        .buttonStyle(.primary)
                        .disabled(store.roots.isEmpty || store.phase == .cleaning)
                    }
                }

                scope

                if let report = store.lastReport {
                    ReportBanner(report: report) { store.dismissReport() }
                }

                if store.isScanning {
                    progress
                } else if store.scannedAt != nil {
                    summary
                    Picker("", selection: $tab) {
                        Text("Large files · \(store.largeFiles.count)").tag(Tab.large)
                        Text("Duplicates · \(store.duplicateGroups.count)").tag(Tab.duplicates)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()

                    switch tab {
                    case .large: largeList
                    case .duplicates: duplicatesList
                    }
                } else {
                    Card {
                        EmptyNote(
                            symbol: "doc.text.magnifyingglass", title: "Find what takes the space",
                            message:
                                "Scan to list files over \(store.threshold.label) and byte-identical copies. macOS may ask for access to Desktop, Documents and Downloads."
                        )
                    }
                }
            }
            .padding(Theme.gutter)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas)
        .sheet(isPresented: $isReviewing) { FilesReviewSheet() }
        .alert(
            "Can't add folder",
            isPresented: Binding(
                get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    // MARK: - Scope

    private var scope: some View {
        @Bindable var store = store
        return Card(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Eyebrow("Scan in")
                    Spacer()
                    Text("Large files from").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $store.threshold) {
                        ForEach(FilesStore.Threshold.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                    .disabled(store.isScanning)
                }
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(store.roots, id: \.self) { root in
                        HStack(spacing: 6) {
                            Image(systemName: "folder").foregroundStyle(.secondary)
                            Text(root.path == NSHomeDirectory() ? "Home" : root.lastPathComponent)
                            Button {
                                store.removeRoot(root)
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tertiary)
                        }
                        .font(.callout)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.track, in: Capsule())
                        .help(root.path)
                    }
                    Button {
                        store.addRoot()
                    } label: {
                        Label("Add Folder…", systemImage: "plus")
                    }
                    .buttonStyle(.quiet)
                    if store.roots != [FileManager.default.homeDirectoryForCurrentUser] {
                        Button("Reset") { store.resetRoots() }.buttonStyle(.quiet)
                    }
                }
                .disabled(store.isScanning)
                Text("Skipped: hidden folders, app bundles, ~/Library, node_modules, Pods and cloud folders.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Progress & summary

    private var progress: some View {
        Card(padding: 24) {
            VStack(alignment: .leading, spacing: 14) {
                switch store.phase {
                case let .scanning(files):
                    Stat(label: "Scanning", value: files.formatted(), caption: "files looked at", large: true)
                    ProgressView().progressViewStyle(.linear).tint(section.tint)
                case let .hashing(done, total):
                    Stat(
                        label: "Comparing contents", value: "\(done.formatted()) / \(total.formatted())",
                        caption: "groups of same-size files", large: true)
                    ProgressView(value: Double(done), total: Double(max(total, 1))).tint(section.tint)
                default:
                    EmptyView()
                }
            }
        }
    }

    private var summary: some View {
        let total = Double(max(store.largeBytes, 1))
        let kinds = FileKind.allCases.filter { store.bytes(of: $0) > 0 }
        return Card(padding: 24) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 48) {
                    Stat(
                        label: "Selected", value: store.selectedBytes.formattedBytes,
                        caption: "\(store.selection.count) files", large: true)
                    Stat(
                        label: "Large files", value: store.largeBytes.formattedBytes,
                        caption: "\(store.largeFiles.count) over \(store.threshold.label)")
                    Stat(
                        label: "Duplicates", value: store.wastedBytes.formattedBytes,
                        caption: "wasted in \(store.duplicateGroups.count) groups")
                    Spacer()
                    Button("Review & Move to Trash…") { isReviewing = true }
                        .buttonStyle(.primary)
                        .disabled(store.selection.isEmpty || store.phase != .ready)
                }
                if !kinds.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        CapacityBar(
                            segments: kinds.map {
                                .init(
                                    fraction: Double(store.bytes(of: $0)) / total,
                                    color: Self.kindColors[$0] ?? Theme.dataOther)
                            }, height: 8)
                        FlowLayout {
                            ForEach(kinds, id: \.self) { kind in
                                LegendDot(
                                    color: Self.kindColors[kind] ?? Theme.dataOther, label: kind.label,
                                    value: store.bytes(of: kind).formattedBytes)
                            }
                        }
                    }
                }
                Text(
                    "Scanned \(store.scannedFiles.formatted()) files \(store.scannedAt.map { $0.formatted(.relative(presentation: .named)) } ?? "")"
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Lists

    private var largeList: some View {
        Card(padding: 0) {
            if store.largeFiles.isEmpty {
                EmptyNote(symbol: "checkmark.circle", title: "No files over \(store.threshold.label)", message: "")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.largeFiles.prefix(visibleLimit).enumerated()), id: \.element.id) {
                        index, entry in
                        if index > 0 { Divider().overlay(Theme.hairline).padding(.leading, 90) }
                        FileRow(entry: entry, tint: Self.kindColors[entry.kind] ?? Theme.dataOther, showKind: true)
                    }
                    if store.largeFiles.count > visibleLimit {
                        Text("Showing the largest \(visibleLimit) of \(store.largeFiles.count)")
                            .font(.caption).foregroundStyle(.tertiary).padding(12)
                    }
                }
            }
        }
    }

    private var duplicatesList: some View {
        VStack(alignment: .leading, spacing: 14) {
            if store.duplicateGroups.isEmpty {
                Card { EmptyNote(symbol: "checkmark.circle", title: "No duplicates over 1 MB", message: "") }
            } else {
                HStack {
                    Text("The oldest copy in each group is listed first.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Select All but Oldest") { store.selectAllButOldest() }.buttonStyle(.quiet)
                }
                ForEach(store.duplicateGroups.prefix(visibleLimit)) { group in
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            HStack {
                                Text("\(group.files.count) copies · \(group.size.formattedBytes) each")
                                    .font(.system(size: 13, weight: .medium))
                                Spacer()
                                Text("\(group.wasted.formattedBytes) wasted")
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            Divider().overlay(Theme.hairline)
                            ForEach(group.files) { entry in
                                FileRow(entry: entry, tint: section.tint, showKind: false)
                            }
                        }
                    }
                }
                Text("APFS clones share storage, so removing a cloned copy may free less than shown.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}

private struct FileRow: View {
    @Environment(FilesStore.self) private var store
    let entry: FileEntry
    let tint: Color
    let showKind: Bool

    var body: some View {
        HStack(spacing: 14) {
            Button {
                store.toggle(entry)
            } label: {
                SelectionMark(state: store.selection.contains(entry.url) ? .on : .off)
            }
            .buttonStyle(.plain)

            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                .resizable()
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(entry.url.lastPathComponent)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if showKind, entry.kind != .other {
                        StatusTag(text: entry.kind.label, tone: tint)
                    }
                }
                Text(
                    entry.displayPath
                        + (entry.modified.map { " · modified \($0.formatted(date: .abbreviated, time: .omitted))" }
                            ?? "")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            }

            Spacer(minLength: 16)

            Text(entry.size.formattedBytes)
                .font(.system(size: 13).monospacedDigit())

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([entry.url])
            } label: {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// Mandatory preview before user files go to the Trash.
private struct FilesReviewSheet: View {
    @Environment(FilesStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let entries = store.selectedEntries
        let unsafeGroups = store.fullySelectedGroups

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Eyebrow("Review")
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.selectedBytes.formattedBytes).font(.figure)
                    Text("\(entries.count) files will be moved to the Trash. You can put them back from there.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if !unsafeGroups.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.clay)
                        Text(
                            "Every copy is selected in \(unsafeGroups.count) duplicate group\(unsafeGroups.count == 1 ? "" : "s") — keep at least one copy of each."
                        )
                        .font(.callout)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.clay.opacity(0.1), in: .rect(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(28)

            Divider().overlay(Theme.hairline)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entries) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.url.lastPathComponent).font(.callout).lineLimit(1).truncationMode(.middle)
                                Text(entry.displayPath).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Text(entry.size.formattedBytes).font(.callout.monospacedDigit())
                        }
                    }
                }
                .padding(28)
            }
            .frame(minHeight: 180, maxHeight: 340)

            Divider().overlay(Theme.hairline)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.quiet)
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash") {
                    dismiss()
                    Task { await store.trashSelected() }
                }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
                .disabled(entries.isEmpty || !unsafeGroups.isEmpty)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .frame(width: 600)
        .background(Theme.canvas)
    }
}
