import Foundation
import SwiftUI

/// How much a Security or Network finding needs you.
nonisolated enum Severity: Int, Comparable, CaseIterable, Sendable {
    case critical, warning, info, ok

    static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .critical: "Fix now"
        case .warning: "Review"
        case .info: "Tidy up"
        case .ok: "OK"
        }
    }

    /// Worth a red dot and an Overview alert.
    var needsAttention: Bool { self <= .warning }
}

extension Severity {
    var tone: Color {
        switch self {
        case .critical: Theme.attention
        case .warning: Theme.sand
        case .info: Theme.slate
        case .ok: Theme.sage
        }
    }
}

/// One line on the Security or Network page.
nonisolated struct HealthFinding: Identifiable, Sendable {
    let id: String
    let severity: Severity
    let title: String
    let detail: String
    var symbol: String = "checkmark.shield"
    /// Shown under the detail (a plist path, a port).
    var subtitle: String? = nil
    /// A command to copy — never run for you.
    var command: String? = nil
    /// A user LaunchAgent plist that can go to the Trash from the app.
    var trashablePlist: URL? = nil
    /// The System Settings pane where you fix it yourself.
    var settingsURL: URL? = nil
}

/// What Overview shows for a Mac Health section that needs you.
struct HealthAlert: Identifiable {
    let section: AppSection
    let severity: Severity
    let title: String
    let detail: String
    var id: AppSection { section }
}
