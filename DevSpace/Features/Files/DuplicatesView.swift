import SwiftUI

struct DuplicatesView: View {
    let store: FilesStore
    @State private var isReviewing = false

    private let section = AppSection.duplicates
    private let visibleLimit = 200

    var body: some View {
        FileScanPage(
            section: section, store: store, optionsLabel: "Files from",
            emptyMessage:
                "Scan to find byte-identical copies over \(store.minimumSize.label). Files are compared by size, then by SHA-256 of their contents."
        ) {
            summary
        } results: {
            list
        }
        .sheet(isPresented: $isReviewing) { FilesReviewSheet(store: store) }
    }

    private var summary: some View {
        let copies = store.duplicateGroups.reduce(0) { $0 + $1.files.count }
        return Card(padding: 24) {
            VStack(alignment: .leading, spacing: 22) {
                SummaryLayout {
                    // The selection figure appears only once something is selected.
                    if !store.selection.isEmpty {
                        Stat(
                            label: "To clean", value: store.selectedBytes.formattedBytes,
                            caption: "\(store.selection.count) files", large: true)
                    }
                    Stat(
                        label: "Wasted", value: store.wastedBytes.formattedBytes,
                        caption: "\(copies) copies in \(store.duplicateGroups.count) groups",
                        large: store.selection.isEmpty)
                } action: {
                    Button("Clean Selected…") { isReviewing = true }
                        .buttonStyle(.primary)
                        .disabled(store.selection.isEmpty || store.phase != .ready)
                }
                ScanFootnote(store: store)
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 14) {
            if store.duplicateGroups.isEmpty {
                Card {
                    EmptyNote(
                        symbol: "checkmark.circle", title: "No duplicates over \(store.minimumSize.label)", message: "")
                }
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
                                FileRow(store: store, entry: entry, tint: section.tint)
                            }
                        }
                    }
                }
                if store.duplicateGroups.count > visibleLimit {
                    Text("Showing \(visibleLimit) of \(store.duplicateGroups.count) groups, most wasted first")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                Text("APFS clones share storage, so removing a cloned copy may free less than shown.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}
