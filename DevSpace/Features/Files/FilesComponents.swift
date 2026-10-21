import AppKit
import SwiftUI

/// Page skeleton shared by Large Files and Duplicates: header with scan control,
/// scope, progress, then the page's own summary and list once a scan finished.
struct FileScanPage<Summary: View, Results: View>: View {
    let section: AppSection
    let store: FilesStore
    let optionsLabel: String
    let emptyMessage: String
    @ViewBuilder var summary: Summary
    @ViewBuilder var results: Results

    var body: some View {
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

                FileScanScope(store: store, optionsLabel: optionsLabel)

                if let report = store.lastReport {
                    ReportBanner(report: report) { store.dismissReport() }
                }

                if store.isScanning {
                    FileScanProgress(store: store, tint: section.tint)
                } else if store.scannedAt != nil {
                    summary
                    results
                } else {
                    Card {
                        EmptyNote(symbol: section.symbol, title: section.title, message: emptyMessage)
                    }
                }
            }
            .padding(Theme.gutter)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas)
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
}

struct FileScanScope: View {
    @Bindable var store: FilesStore
    let optionsLabel: String

    var body: some View {
        Card(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Eyebrow("Scan in")
                    Spacer()
                    Text(optionsLabel).font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $store.minimumSize) {
                        ForEach(store.sizeOptions) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .disabled(store.isScanning)
                }
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(store.roots, id: \.self) { root in
                        Label {
                            HStack(spacing: 8) {
                                Text(root.path == NSHomeDirectory() ? "Home" : root.lastPathComponent)
                                Button {
                                    store.removeRoot(root)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.tertiary)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("Remove from scan")
                            }
                        } icon: {
                            Image(systemName: "folder")
                        }
                        .pill()
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
                Text(
                    "Skipped: hidden folders, app bundles, ~/Library, Music and TV libraries, node_modules, Pods and cloud folders."
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
    }
}

struct FileScanProgress: View {
    let store: FilesStore
    let tint: Color

    var body: some View {
        Card(padding: 24) {
            VStack(alignment: .leading, spacing: 14) {
                switch store.phase {
                case let .scanning(files):
                    Stat(label: "Scanning", value: files.formatted(), caption: "files looked at", large: true)
                    ProgressView().progressViewStyle(.linear).tint(tint)
                case let .hashing(done, total):
                    Stat(
                        label: "Comparing contents", value: "\(done.formatted()) / \(total.formatted())",
                        caption: "groups of same-size files", large: true)
                    ProgressView(value: Double(done), total: Double(max(total, 1))).tint(tint)
                default:
                    EmptyView()
                }
            }
        }
    }
}

/// Footer line under a summary: how many files the last scan looked at.
struct ScanFootnote: View {
    let store: FilesStore

    var body: some View {
        let when = store.scannedAt.map { $0.formatted(.relative(presentation: .named)) } ?? ""
        Text("Scanned \(store.scannedFiles.formatted()) files \(when)")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }
}

struct FileRow: View {
    let store: FilesStore
    let entry: FileEntry
    let tint: Color
    var showKind = false

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
struct FilesReviewSheet: View {
    let store: FilesStore
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
