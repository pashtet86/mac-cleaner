import SwiftUI

/// Large Files, Duplicates and the Files Inspector under one sidebar item, switched by tabs in
/// the window toolbar. Each tab keeps its own page, scan and selection.
struct FilesHubView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case largeFiles, duplicates, inspector
        var id: String { rawValue }

        var title: String {
            switch self {
            case .largeFiles: "Large Files"
            case .duplicates: "Duplicates"
            case .inspector: "Inspector"
            }
        }
    }

    @Environment(FileScans.self) private var files
    @AppStorage("files.tab") private var tab: Tab = .largeFiles

    var body: some View {
        Group {
            switch tab {
            case .largeFiles: LargeFilesView(store: files.large)
            case .duplicates: DuplicatesView(store: files.duplicates)
            case .inspector: InspectorView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }
}
