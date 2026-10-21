import AppKit
import SwiftUI

/// Mandatory preview of everything that will be moved to the Trash.
struct CleanupReviewSheet: View {
    @Environment(CleanupStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let section: RuleSection

    var body: some View {
        let selected = store.selectedItems(in: section)
        let byRule = Dictionary(grouping: selected, by: \.rule.id)
        let rules = store.rules.filter { byRule[$0.id] != nil }
        let apps = store.appsToQuit(in: section)

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Eyebrow("Review")
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.selectedBytes(in: section).formattedBytes).font(.figure)
                    Text("\(selected.count) items will be moved to the Trash. Nothing is deleted permanently.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if !apps.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(Theme.sand)
                        Text(
                            "Quit \(apps.compactMap(\.localizedName).joined(separator: ", ")) first — running apps may keep files open or recreate them immediately."
                        )
                        .font(.callout)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.sand.opacity(0.1), in: .rect(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(28)

            Divider().overlay(Theme.hairline)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(rules) { rule in
                        let entries = byRule[rule.id] ?? []
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(rule.title).font(.system(size: 13, weight: .medium))
                                RiskTag(risk: rule.risk)
                                Spacer()
                                Text(entries.reduce(0) { $0 + $1.item.size }.formattedBytes)
                                    .font(.callout.monospacedDigit())
                            }
                            ForEach(entries.prefix(6), id: \.item.id) { entry in
                                HStack {
                                    Text(
                                        entry.item.url.path(percentEncoded: false).replacingOccurrences(
                                            of: NSHomeDirectory(), with: "~")
                                    )
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    Spacer()
                                    Text(entry.item.size.formattedBytes).monospacedDigit()
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            if entries.count > 6 {
                                Text("and \(entries.count - 6) more")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .padding(28)
            }
            .frame(minHeight: 180, maxHeight: 340)

            Divider().overlay(Theme.hairline)

            HStack {
                Text("Space is reclaimed once you empty the Trash.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.quiet)
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash") {
                    dismiss()
                    Task { await store.cleanSelected(in: section) }
                }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .frame(width: 560)
        .background(Theme.canvas)
    }
}
