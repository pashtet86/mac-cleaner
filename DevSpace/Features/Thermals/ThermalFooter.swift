import SwiftUI

/// Compact temperature line pinned to the bottom of the sidebar.
struct ThermalFooter: View {
    @Environment(ThermalStore.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "thermometer.medium")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if store.hasSensors {
                reading("CPU", store.cpu)
                reading("SSD", store.ssd)
            }

            Spacer(minLength: 4)

            HStack(spacing: 5) {
                Circle().fill(store.state.tone).frame(width: 6, height: 6)
                Text(store.state.label)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .help(
            store.hasSensors
                ? "Hottest CPU core and SSD temperature. Thermal state as reported by macOS."
                : "Thermal state as reported by macOS. Temperature sensors aren't available on this Mac."
        )
        .task { store.start() }
        .onDisappear { store.stop() }
    }

    private func reading(_ label: String, _ value: Double?) -> some View {
        HStack(spacing: 3) {
            Text(label).foregroundStyle(.tertiary)
            Text(value.map(Self.format) ?? "—")
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText())
                .animation(.hover, value: value.map { Int($0) })
        }
        .font(.system(size: 11, weight: .medium))
        .fixedSize()
    }

    /// "38°" in the locale's scale (°F where the locale uses Fahrenheit); the scale letter is
    /// dropped to fit the sidebar.
    private static func format(_ celsius: Double) -> String {
        let unit: UnitTemperature = Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
        let value = Measurement(value: celsius, unit: UnitTemperature.celsius).converted(to: unit).value
        return "\(Int(value.rounded()))°"
    }
}
