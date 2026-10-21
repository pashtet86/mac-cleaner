import SwiftUI

struct LargeFilesView: View {
    let store: FilesStore
    @State private var isReviewing = false

    private let section = AppSection.largeFiles
    private let visibleLimit = 200

    static let kindColors: [FileKind: Color] = [
        .video: Theme.indigo, .diskImage: Theme.ochre, .archive: Theme.teal, .other: Theme.lavender,
    ]

    var body: some View {
        FileScanPage(
            section: section, store: store, optionsLabel: "Files from",
            emptyMessage:
                "Scan to list files over \(store.minimumSize.label). macOS may ask for access to Desktop, Documents and Downloads."
        ) {
            summary
        } results: {
            list
        }
        .sheet(isPresented: $isReviewing) { FilesReviewSheet(store: store) }
    }

    private var summary: some View {
        let total = Double(max(store.largeBytes, 1))
        let kinds = FileKind.allCases.filter { store.bytes(of: $0) > 0 }
        return Card(padding: 24) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 48) {
                    // The selection figure appears only once something is selected.
                    if !store.selection.isEmpty {
                        Stat(
                            label: "To clean", value: store.selectedBytes.formattedBytes,
                            caption: "\(store.selection.count) files", large: true)
                    }
                    Stat(
                        label: "Large files", value: store.largeBytes.formattedBytes,
                        caption: "\(store.largeFiles.count) over \(store.minimumSize.label)",
                        large: store.selection.isEmpty)
                    Spacer()
                    Button("Clean Selected…") { isReviewing = true }
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
                ScanFootnote(store: store)
            }
        }
    }

    private var list: some View {
        Card(padding: 0) {
            if store.largeFiles.isEmpty {
                EmptyNote(symbol: "checkmark.circle", title: "No files over \(store.minimumSize.label)", message: "")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.largeFiles.prefix(visibleLimit).enumerated()), id: \.element.id) {
                        index, entry in
                        if index > 0 { Divider().overlay(Theme.hairline).padding(.leading, 90) }
                        FileRow(
                            store: store, entry: entry, tint: Self.kindColors[entry.kind] ?? Theme.dataOther,
                            showKind: true)
                    }
                    if store.largeFiles.count > visibleLimit {
                        Text("Showing the largest \(visibleLimit) of \(store.largeFiles.count)")
                            .font(.caption).foregroundStyle(.tertiary).padding(12)
                    }
                }
            }
        }
    }
}
