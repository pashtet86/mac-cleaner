import SwiftUI

/// Disk Cleaner → Settings… (⌘,).
struct SettingsView: View {
    private let telemetry = Telemetry.shared

    var body: some View {
        Form {
            Section("Privacy") {
                if telemetry.isAvailable {
                    Toggle(
                        "Share anonymous usage statistics",
                        isOn: Binding(
                            get: { telemetry.consent == .granted },
                            set: { telemetry.setSharing($0) }))
                    Text(TelemetryConsentCard.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("This build sends nothing anywhere — it has no statistics endpoint.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
    }
}

/// Asked once on Overview, only in builds that have a statistics endpoint.
struct TelemetryConsentCard: View {
    static let explanation =
        "A random ID, Disk Cleaner and macOS versions, Mac type, and how much space each section cleaned. Never file names, paths, or your Mac's or your name. Change it any time in Settings."

    private let telemetry = Telemetry.shared

    var body: some View {
        Card(padding: 18) {
            HStack(alignment: .top, spacing: 14) {
                Glyph(symbol: "chart.bar.xaxis", tint: Theme.accent, size: 34)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Help improve Disk Cleaner?").font(.system(size: 13, weight: .semibold))
                    Text(Self.explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button("Share Anonymous Stats") { telemetry.setSharing(true) }
                            .buttonStyle(.primary)
                        Button("No Thanks") { telemetry.setSharing(false) }
                            .buttonStyle(.quiet)
                    }
                    .padding(.top, 6)
                }
            }
        }
    }
}
