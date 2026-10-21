import SwiftUI

/// Temperatures, fans and thermal state pinned to the bottom of the sidebar.
struct ThermalFooter: View {
    @Environment(ThermalStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                icon("thermometer.medium")
                if store.hasSensors {
                    reading("CPU", store.cpu.map(Self.format))
                    reading("SSD", store.ssd.map(Self.format))
                }
                Spacer(minLength: 4)
                HStack(spacing: 5) {
                    Circle().fill(store.state.tone).frame(width: 6, height: 6)
                    Text(store.state.label)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            }
            // Only Macs with fans get this line.
            if store.hasFans {
                HStack(spacing: 10) {
                    icon(fansSpinning ? "fan.fill" : "fan")
                    reading(store.fans.count == 1 ? "Fan" : "\(store.fans.count) fans", fanText)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .help(
            store.hasSensors
                ? "Hottest CPU core and SSD temperature, fan speed and the thermal state reported by macOS."
                : "Thermal state as reported by macOS. Temperature sensors aren't available on this Mac."
        )
        .task { store.start() }
        .onDisappear { store.stop() }
    }

    private var fansSpinning: Bool { store.fans.contains { $0 > 0 } }

    /// "Off" while the fans are stopped (normal on Apple silicon at low load), else the fastest fan.
    private var fanText: String? {
        guard !store.fans.isEmpty else { return nil }
        guard let fastest = store.fans.max(), fastest > 0 else { return "Off" }
        return "\(Int(fastest.rounded()).formatted()) rpm"
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(width: 14)
    }

    private func reading(_ label: String, _ value: String?) -> some View {
        HStack(spacing: 3) {
            Text(label).foregroundStyle(.tertiary)
            Text(value ?? "—")
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText())
                .animation(.hover, value: value)
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
