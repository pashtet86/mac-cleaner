import AppKit
import SwiftUI

struct InspectorView: View {
    @Environment(InspectorStore.self) private var store
    @State private var isReviewing = false

    private let section = AppSection.inspector
    private let listLimit = 40

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    title: section.pageTitle, subtitle: section.summary, symbol: section.symbol, tint: section.tint
                ) {
                    HStack(spacing: 10) {
                        Button {
                            store.chooseRoot()
                        } label: {
                            Label("Choose Folder…", systemImage: "folder")
                        }
                        .buttonStyle(.quiet)
                        .disabled(store.isScanning)
                        if store.isScanning {
                            Button("Cancel") { store.cancel() }.buttonStyle(.quiet)
                        } else {
                            Button {
                                store.scan()
                            } label: {
                                Label(store.tree == nil ? "Scan" : "Rescan", systemImage: "magnifyingglass")
                            }
                            .buttonStyle(.primary)
                            .disabled(store.phase == .cleaning)
                        }
                    }
                }

                if let report = store.lastReport {
                    ReportBanner(report: report) { store.dismissReport() }
                }

                if store.isScanning {
                    progress
                } else if let current = store.current, let tree = store.tree {
                    summary(current)
                    map(current)
                    contents(current)
                    footnote(tree)
                } else {
                    intro
                }
            }
            .padding(Theme.gutter)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas)
        .sheet(isPresented: $isReviewing) { InspectorReviewSheet() }
        .alert(
            "Can't inspect folder",
            isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    // MARK: - States

    private var intro: some View {
        Card(padding: 24) {
            VStack(alignment: .leading, spacing: 18) {
                Text(
                    "See everything in \(store.root.lastPathComponent) as a map, open folders to go deeper, and pick what to remove. Every tile says how safe it is to delete."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                SafetyLegend(values: nil)
                Text(
                    "macOS may ask for access to Desktop, Documents and Downloads. Folders macOS protects — Mail, Messages, app containers, media libraries — are never read."
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
    }

    private var progress: some View {
        Card(padding: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Stat(label: "Mapping", value: store.scannedFiles.formatted(), caption: "files measured", large: true)
                ProgressView().progressViewStyle(.linear).tint(section.tint)
                Text(store.currentFolder.isEmpty ? " " : "In \(store.currentFolder)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func summary(_ current: InspectorNode) -> some View {
        let breakdown = current.breakdown
        let total = Double(max(current.size, 1))
        return Card(padding: 24) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 48) {
                    Stat(
                        label: "To clean", value: store.selectedBytes.formattedBytes,
                        caption: "\(store.selected.count) items", large: true)
                    Stat(
                        label: current.name, value: current.size.formattedBytes,
                        caption: "\(current.children.count + current.smallCount) items inside")
                    Spacer()
                    Button("Clean Selected…") { isReviewing = true }
                        .buttonStyle(.primary)
                        .disabled(store.selected.isEmpty || store.phase != .ready)
                }
                VStack(alignment: .leading, spacing: 10) {
                    CapacityBar(
                        segments: Safety.allCases.map {
                            .init(fraction: Double(breakdown[$0] ?? 0) / total, color: $0.tone)
                        }, height: 8)
                    SafetyLegend(values: breakdown)
                }
            }
        }
    }

    // MARK: - Map

    private func map(_ current: InspectorNode) -> some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                breadcrumbs
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                Divider().overlay(Theme.hairline)
                TreemapView(
                    node: current,
                    isSelected: store.isSelected,
                    focused: store.focused,
                    onFocus: { store.focused = $0 },
                    onOpen: { store.open($0) }
                )
                .id(ObjectIdentifier(current))
                .frame(height: 460)
                .padding(6)
                Divider().overlay(Theme.hairline)
                detail(store.focused ?? current, isFolderShown: store.focused == nil)
                    .padding(14)
            }
        }
    }

    private var breadcrumbs: some View {
        HStack(spacing: 6) {
            Button {
                store.goUp()
            } label: {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.icon)
            .disabled(store.path.count < 2)
            .keyboardShortcut("[", modifiers: .command)
            .help("Back (⌘[)")

            ForEach(Array(store.path.enumerated()), id: \.offset) { index, node in
                if index > 0 {
                    Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary)
                }
                Button(index == 0 && node.rootURL?.path == NSHomeDirectory() ? "Home" : node.name) {
                    store.goTo(depth: index)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: index == store.path.count - 1 ? .semibold : .regular))
                .foregroundStyle(index == store.path.count - 1 ? .primary : .secondary)
            }
            Spacer()
            Text("Click to inspect · double-click to open")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func detail(_ node: InspectorNode, isFolderShown: Bool) -> some View {
        let parentSize = Double(max(node.parent?.size ?? node.size, 1))
        return HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: node.url.path))
                .resizable()
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(node.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    SafetyTag(safety: node.safety)
                    if !isFolderShown, node.parent != nil {
                        Text("\(Int((Double(node.size) / parentSize * 100).rounded()))% of \(node.parent?.name ?? "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(node.verdict.reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(displayPath(node.url))
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 12)
            Text(node.size.formattedBytes)
                .font(.figureSmall)
            VStack(alignment: .trailing, spacing: 6) {
                if !isFolderShown, node.canOpen {
                    Button("Open") { store.open(node) }.buttonStyle(.quiet)
                }
                if !isFolderShown, node.safety.isSelectable {
                    Button(store.isSelected(node) ? "Deselect" : "Select") { store.toggle(node) }
                        .buttonStyle(.quiet)
                        .disabled(store.isCoveredByAncestor(node))
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([node.url])
                } label: {
                    Label("Finder", systemImage: "arrow.up.forward.square")
                }
                .buttonStyle(.quiet)
            }
        }
    }

    // MARK: - Contents

    private func contents(_ current: InspectorNode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Inside \(current.name)")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(current.children.prefix(listLimit).enumerated()), id: \.element.id) { index, node in
                        if index > 0 { Divider().overlay(Theme.hairline).padding(.leading, 58) }
                        InspectorRow(node: node, share: Double(node.size) / Double(max(current.size, 1)))
                    }
                    if current.smallCount > 0 || current.children.count > listLimit {
                        let hidden = current.children.dropFirst(listLimit)
                        let bytes = current.smallBytes + hidden.reduce(0) { $0 + $1.size }
                        Text("and \(current.smallCount + hidden.count) smaller items · \(bytes.formattedBytes)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 58)
                            .padding(.vertical, 10)
                    }
                }
            }
        }
    }

    private func footnote(_ tree: InspectorNode) -> some View {
        Group {
            if !tree.notScanned.isEmpty {
                Text(
                    "\(tree.notScanned.count) protected folders were not read (app containers, Mail, Messages, media libraries), so their size is not shown."
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
                .help(tree.notScanned.map(displayPath).joined(separator: "\n"))
            }
        }
    }
}

private func displayPath(_ url: URL) -> String { displayPath(url.path) }

private func displayPath(_ path: String) -> String {
    let home = NSHomeDirectory()
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}

private struct InspectorRow: View {
    @Environment(InspectorStore.self) private var store
    let node: InspectorNode
    let share: Double

    var body: some View {
        let covered = store.isCoveredByAncestor(node)
        HStack(spacing: 12) {
            Button {
                store.toggle(node)
            } label: {
                SelectionMark(state: store.isSelected(node) ? .on : .off)
            }
            .buttonStyle(.plain)
            .disabled(!node.safety.isSelectable || covered)
            .opacity(node.safety.isSelectable ? 1 : 0.25)

            RoundedRectangle(cornerRadius: 2).fill(node.safety.tone).frame(width: 4, height: 24)

            Image(systemName: node.isDirectory ? "folder" : "doc")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(node.name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    SafetyTag(safety: node.safety)
                }
                Text(node.verdict.reason).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer(minLength: 12)

            CapacityBar(segments: [.init(fraction: share, color: node.safety.tone)], height: 4)
                .frame(width: 90)
            Text(node.size.formattedBytes)
                .font(.system(size: 13).monospacedDigit())
                .frame(width: 80, alignment: .trailing)

            Button {
                store.open(node)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.icon)
            .opacity(node.canOpen ? 1 : 0)
            .disabled(!node.canOpen)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .hoverRow(isActive: store.focused === node)
        .onTapGesture(count: 2) { store.open(node) }
        .onTapGesture { store.focused = node }
    }
}

struct SafetyTag: View {
    let safety: Safety

    var body: some View {
        HStack(spacing: 4) {
            if safety == .protected { Image(systemName: "lock.fill").font(.system(size: 8)) }
            Text(safety.label)
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(safety == .protected ? Color.secondary : safety.tone)
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(safety.tone.opacity(0.12), in: Capsule())
    }
}

struct SafetyLegend: View {
    /// Bytes per level; `nil` shows the levels with short explanations instead.
    let values: [Safety: Int64]?

    private static let explanations: [Safety: String] = [
        .rebuildable: "recreated automatically",
        .likelySafe: "installers, build output",
        .review: "archives, debug symbols",
        .personal: "check before deleting",
        .protected: "can't be selected",
    ]

    var body: some View {
        FlowLayout {
            ForEach(Safety.allCases.filter { values == nil || (values?[$0] ?? 0) > 0 }, id: \.self) { safety in
                LegendDot(
                    color: safety.tone, label: safety.label,
                    value: values.map { ($0[safety] ?? 0).formattedBytes } ?? Self.explanations[safety])
            }
        }
    }
}

/// Mandatory preview; calls out anything not marked as rebuildable.
private struct InspectorReviewSheet: View {
    @Environment(InspectorStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let nodes = store.selectedNodes
        let personal = nodes.filter { $0.safety == .personal || $0.safety == .review }

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Eyebrow("Ready to clean")
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.selectedBytes.formattedBytes).font(.figure)
                    Text("\(nodes.count) items will be moved to the Trash. You can put them back from there.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if !personal.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.clay)
                        Text(
                            "\(personal.count) of them are your files or need review — they won't come back by themselves."
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
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(nodes) { node in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text(node.name).font(.callout).lineLimit(1).truncationMode(.middle)
                                    SafetyTag(safety: node.safety)
                                }
                                Text(displayPath(node.url)).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Text(node.size.formattedBytes).font(.callout.monospacedDigit())
                        }
                    }
                }
                .padding(28)
            }
            .frame(minHeight: 160, maxHeight: 320)

            Divider().overlay(Theme.hairline)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.quiet)
                    .keyboardShortcut(.cancelAction)
                Button("Clean") {
                    dismiss()
                    Task { await store.trashSelected() }
                }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
                .disabled(nodes.isEmpty)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .frame(width: 600)
        .background(Theme.canvas)
    }
}
