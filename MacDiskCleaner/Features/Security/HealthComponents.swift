import AppKit
import SwiftUI

struct SeverityTag: View {
    let severity: Severity
    var body: some View { StatusTag(text: severity.label, tone: severity.tone) }
}

/// One finding: what's wrong, why it matters, and how to fix it yourself.
struct FindingRow: View {
    let finding: HealthFinding
    /// Offered only for your own leftover launch agents.
    var onTrash: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Glyph(symbol: finding.symbol, tint: finding.severity.tone, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(finding.title)
                        .font(.system(size: 13, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    if finding.severity != .ok { SeverityTag(severity: finding.severity) }
                }
                if !finding.detail.isEmpty {
                    Text(finding.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let subtitle = finding.subtitle {
                    Text(subtitle.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                if let url = finding.settingsURL {
                    Button("Open Settings") { NSWorkspace.shared.open(url) }
                        .buttonStyle(.quiet)
                }
                if let onTrash {
                    Button("Move to Trash", action: onTrash).buttonStyle(.quiet)
                }
                if let command = finding.command {
                    CopyButton(command: command)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .hoverRow()
    }
}

/// A list of findings in one card.
struct FindingsCard: View {
    let findings: [HealthFinding]
    var onTrash: ((HealthFinding) -> Void)? = nil

    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(findings.enumerated()), id: \.element.id) { index, finding in
                    if index > 0 { Divider().overlay(Theme.hairline).padding(.leading, 62) }
                    FindingRow(
                        finding: finding,
                        onTrash: finding.trashablePlist != nil ? onTrash.map { trash in { trash(finding) } } : nil)
                }
            }
        }
    }
}

/// The Overview banner for a Mac Health section that needs you.
struct HealthAlertBanner: View {
    let symbol: String
    let tone: Color
    let title: String
    let detail: String
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Glyph(symbol: symbol, tint: tone, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 12)
                Text("Review")
                    .font(.system(size: 13, weight: .medium))
                    .pill()
            }
            .padding(14)
            .background(tone.opacity(0.08), in: .rect(cornerRadius: Theme.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(tone.opacity(0.25))
            }
            .contentShape(.rect(cornerRadius: Theme.radius))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
